import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_env.dart';
import 'archive_retention_rules.dart';
import 'package:onespace/l10n/phrases.dart';

/// All archive objects are encrypted on the server before they can become
/// ready. Local app-private copies disappear when the app is uninstalled.
/// Automatic app-private copies NEVER confirm an external user download.
class MyArchivesScreen extends StatefulWidget {
  const MyArchivesScreen({super.key});
  @override
  State<MyArchivesScreen> createState() => _MyArchivesScreenState();
}

class _MyArchivesScreenState extends State<MyArchivesScreen> {
  static const _export = MethodChannel('onespace/data_export');
  final _db = Supabase.instance.client;
  List<Map<String,dynamic>> _archives = [];
  final Set<String> _inProgress = {};
  final Set<String> _cached = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  bool _isReady(Map<String,dynamic> archive) =>
      archive['status'] == 'ready' &&
      DateTime.tryParse(archive['expires_at']?.toString() ?? '')
        ?.isAfter(DateTime.now()) == true;

  Future<Directory> _privateFolder() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/onespace_archives');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _localFile(String id) async =>
      File('${(await _privateFolder()).path}/$id.onespace');

  bool _validHash(String? digest, Uint8List bytes) =>
    digest != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) &&
    sha256.convert(bytes).toString() == digest;

  Future<Uint8List> _downloadVerified(Map<String,dynamic> archive) async {
    final session = _db.auth.currentSession;
    if (session == null) throw StateError('Sign in required');
    final id = archive['id']?.toString();
    if (id == null || !_isReady(archive)) {
      throw StateError('This archive is no longer available');
    }
    final response = await http.post(
      Uri.parse('${OneSpaceEnv.supabaseUrl}/functions/v1/onespace-download-archive'),
      headers: {
        'authorization': 'Bearer ${session.accessToken}',
        'apikey': OneSpaceEnv.publishableKey,
        'content-type': 'application/json',
      },
      body: '{"archive_id":"$id"}',
    ).timeout(const Duration(minutes: 3));
    if (response.statusCode != 200) {
      throw StateError('Unable to download this archive');
    }
    final expected = archive['ciphertext_sha256']?.toString();
    final bytes = response.bodyBytes;
    if (!_validHash(expected, bytes) ||
        (archive['byte_length'] as num?)?.toInt() != bytes.length) {
      throw StateError('Downloaded archive failed integrity verification');
    }
    return bytes;
  }

  Future<void> _load() async {
    try {
      final me = _db.auth.currentUser?.id;
      if (me == null) throw StateError('Sign in required');
      final data = await _db.from('space_archives')
        .select('id,archive_kind,status,created_at,expires_at,ciphertext_sha256,byte_length,explicit_download_confirmed_at')
        .eq('recipient_id',me)
        .order('created_at',ascending:false).limit(50);
      if (!mounted) return;
      setState(() { _archives = List<Map<String,dynamic>>.from(data);
        _loading = false; _error = null; });
      for (final a in _archives) {
        if (_isReady(a)) { unawaited(_cacheInApp(a)); }
      }
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = tt('Unable to load archives.');
      });
    }
  }

  Future<void> _cacheInApp(Map<String,dynamic> a) async {
    final id = a['id'].toString();
    if (_inProgress.contains(id)) return;
    _inProgress.add(id);
    try {
      final file = await _localFile(id);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (_validHash(a['ciphertext_sha256']?.toString(),bytes)) {
          if (mounted) setState(() => _cached.add(id));
          return;
        }
      }
      final bytes = await _downloadVerified(a);
      await file.writeAsBytes(bytes,flush:true);
      if (!await file.exists() ||
          !_validHash(a['ciphertext_sha256']?.toString(),
            await file.readAsBytes())) {
        throw StateError('Device copy verification failed');
      }
      if (mounted) setState(() => _cached.add(id));
      // Deliberately NO confirm_external_archive_save here.
    } catch (_) {
      // An unavailable automatic copy never deletes its server backup.
    } finally {
      _inProgress.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveOutsideApp(Map<String,dynamic> a) async {
    // Native Android saveToDownloads creates a durable MediaStore item.
    // iOS share sheet completion does not guarantee Files was selected.
    if (!Platform.isAndroid || !_isReady(a)) return;
    final id = a['id'].toString();
    if (_inProgress.contains(id)) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tt('Save archive outside OneSpace?')),
        content: Text(tt('After the file is saved and verified in your phone’s '
          'Downloads folder, this temporary server archive will be scheduled '
          'for deletion. Keep the downloaded file somewhere safe.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx,false),
            child: Text(tt('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx,true),
            child: Text(tt('Save archive'))),
        ],
      ));
    if (approved != true || !mounted) return;
    setState(() { _inProgress.add(id); _error = null; });
    try {
      final bytes = await _downloadVerified(a);
      final name = 'OneSpace-${a['archive_kind']}-$id.onespace';
      final location = await _export.invokeMethod<String>('saveToDownloads',{
        'name':name,'bytes':bytes,
        'verifySha256':sha256.convert(bytes).toString(),
        'requireDurable':true,
      });
      if (location == null || location.isEmpty) {
        throw StateError('External archive save was not confirmed');
      }
      // The native Android plugin reads the external MediaStore file back and
      // checks its SHA-256 before returning. Never acknowledge an automatic
      // app-private download or an unverified/cancelled save.
      if (!ArchiveRetentionRules.mayConfirmExternalSave(
        userInitiated: true, savedOutsideApp: true, verifiedAfterWrite: true)) {
        throw StateError('External download was not verified');
      }
      final confirmed = await _db.rpc('confirm_external_archive_save',params:{
        'p_archive_id':id,
        'p_sha256':sha256.convert(bytes).toString(),
      });
      if (confirmed != true) throw StateError('Download recorded but server acknowledgment failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tt('Saved to $location. Server copy scheduled for deletion.'))));
        await _load();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = tt(
          'Could not confirm the external save. Your server archive has not '
          'been marked downloaded. Try again before it expires.'));
      }
    } finally {
      if (mounted) setState(() => _inProgress.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tt('My Archives'))),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh:_load,child:ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(tt('Your OneSpace archives'),
              style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(tt('An automatic encrypted copy stays inside the installed '
              'OneSpace app and disappears if you uninstall it. Only tapping '
              'Save archive below creates a separate copy in Downloads. '
              'Server archives expire after 30 days or after a verified '
              'user-initiated external save, whichever comes first.')),
            const SizedBox(height: 16),
            if (_archives.isEmpty) Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tt('No separation archives are available yet. '
                'Your personal data and current shared space are unchanged.')),
            )),
            for(final archive in _archives)...[
              Card(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment:CrossAxisAlignment.start,
                  children:[
                    Row(children:[
                      const Icon(Icons.folder_zip_outlined),
                      const SizedBox(width:10),
                      Expanded(child: Text(tt(archive['archive_kind']=='private'
                        ? 'My private archive' : 'Shared history archive'),
                        style:theme.textTheme.titleMedium)),
                    ]),
                    const SizedBox(height:8),
                    Text(tt(archive['status']=='ready'
                      ? 'Ready for download'
                      : archive['status']=='purged'
                        ? 'Temporary server copy removed'
                        : archive['status']=='purge_due'
                          ? 'Download complete; cleaning up server copy'
                          : 'Preparing archive')),
                    if (archive['expires_at'] != null)
                      Text('${tt('Server expiry')}: ${archive['expires_at']}'),
                    if (_cached.contains(archive['id']))
                      Text(tt('Encrypted copy stored privately in this app.')),
                    if (_inProgress.contains(archive['id']))
                      const LinearProgressIndicator(),
                    if (_isReady(archive))
                      FilledButton.tonalIcon(
                        onPressed: _inProgress.contains(archive['id'])
                          || !Platform.isAndroid ? null
                          : () => _saveOutsideApp(archive),
                        icon: const Icon(Icons.download_outlined),
                        label: Text(tt('Save archive to Downloads')),
                      ),
                  ],
                ),
              )),
              const SizedBox(height:10),
            ],
            if (_error != null) Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, style:TextStyle(color:theme.colorScheme.error)),
            ),
            const SizedBox(height:60),
          ],
        ))),
    );
  }
}
