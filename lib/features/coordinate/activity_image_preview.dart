import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_image_rules.dart';
import 'package:onespace/l10n/phrases.dart';

/// Private Activity image preview. Each access obtains a short-lived URL
/// through the viewer's authenticated RLS permissions, never a public URL.
class ActivityImagePreview extends StatefulWidget {
  const ActivityImagePreview({
    super.key,
    required this.objectPath,
    required this.label,
  });

  final String objectPath;
  final String label;

  @override
  State<ActivityImagePreview> createState() => _ActivityImagePreviewState();
}

class _ActivityImagePreviewState extends State<ActivityImagePreview> {
  late Future<String> signedUrl;

  Future<String> sign() => Supabase.instance.client.storage
      .from(ActivityImageRules.bucket)
      .createSignedUrl(widget.objectPath, 120);

  @override
  void initState() {
    super.initState();
    signedUrl = sign();
  }

  @override
  void didUpdateWidget(covariant ActivityImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.objectPath != widget.objectPath) {
      signedUrl = sign();
    }
  }

  Future<void> openFullSize() async {
    try {
      final freshUrl = await sign();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Stack(children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Image.network(freshUrl,
                fit: BoxFit.contain,
                errorBuilder: (ctx, error, stack) => Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(tt('Unable to open this private image.')),
                )),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: tt('Close photo'),
                onPressed: () => Navigator.of(ctx).pop(),
              )),
          ]),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            tt('Unable to open the photo. Check your connection or access.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: signedUrl,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton.icon(
          onPressed: () => setState(() => signedUrl = sign()),
          icon: const Icon(Icons.refresh),
          label: Text(tt('Retry private photo')),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 110,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return InkWell(
        onTap: openFullSize,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            snapshot.data!,
            width: double.infinity,
            height: 145,
            fit: BoxFit.cover,
            semanticLabel: widget.label,
            errorBuilder: (ctx, error, stack) => SizedBox(
              height: 110,
              child: Center(child: Text(tt('Photo unavailable. Tap to retry.'))),
            ),
          ),
        ),
      );
    },
  );
}
