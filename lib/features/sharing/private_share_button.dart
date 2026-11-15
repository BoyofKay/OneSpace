import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import 'package:onespace/l10n/phrases.dart';

/// A private object's owner can grant or revoke a temporary viewing right.
/// The server RPC validates ownership, relationship, privacy and membership.
class PrivateShareButton extends StatefulWidget {
  const PrivateShareButton({
    super.key,
    required this.objectType,
    required this.objectId,
    this.onChanged,
  });

  final String objectType;
  final String objectId;
  final VoidCallback? onChanged;

  @override
  State<PrivateShareButton> createState() => _PrivateShareButtonState();
}

class _PrivateShareButtonState extends State<PrivateShareButton> {
  bool _loading = true;
  bool _busy = false;
  bool _shared = false;

  @override
  void initState() {
    super.initState();
    _readGrant();
  }

  Future<void> _readGrant() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('object_shares')
          .select('id')
          .eq('object_type', widget.objectType)
          .eq('object_id', widget.objectId)
          .eq('shared_by', userId)
          .isFilter('revoked_at', null)
          .limit(1);
      if (mounted) {
        setState(() {
          _shared = rows.isNotEmpty;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggle() async {
    if (_loading || _busy) return;
    final enable = !_shared;
    if (enable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(context, 'shareViewOnly')),
          content: Text(tr(context, 'shareExplanation')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr(context, 'shareViewOnly')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('set_object_share', params: {
        'p_type': widget.objectType,
        'p_object': widget.objectId,
        'p_active': enable,
      });
      if (!mounted) return;
      setState(() => _shared = enable);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, enable ? 'shareEnabled' : 'shareRevoked')),
      ));
      widget.onChanged?.call();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tt(e.message))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'saveFailed'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: Key('share-${widget.objectType}-${widget.objectId}'),
    icon: Icon(_shared ? Icons.visibility_off_outlined : Icons.visibility_outlined),
    tooltip: tr(context, _shared ? 'stopSharing' : 'shareViewOnly'),
    onPressed: _loading || _busy ? null : _toggle,
  );
}
