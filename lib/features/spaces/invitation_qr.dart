import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

import 'invitation_code.dart';

/// R73 (Ahmed): the invitation as a QR code your partner scans in OneSpace.
class InvitationQr extends StatelessWidget {
  const InvitationQr({super.key, required this.code});
  final String code;
  @override
  Widget build(BuildContext context) => Center(child: Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
    child: QrImageView(data: 'onespace-invite:$code', size: 200, backgroundColor: Colors.white)));
}

/// Opens the camera and returns the invitation code found in a QR code.
Future<String?> scanInvitation(BuildContext context) => Navigator.of(context).push<String>(
  MaterialPageRoute(builder: (_) => const _ScanScreen()));

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();
  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool done = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tt('Scan the invitation'))),
    body: Stack(children: [
      MobileScanner(controller: controller, onDetect: (capture) {
        if (done) return;
        for (final b in capture.barcodes) {
          final code = normalizedInvitationCode(b.rawValue ?? '');
          if (code != null) {
            done = true;
            Navigator.of(context).pop(code);
            return;
          }
        }
      }),
      Align(alignment: Alignment.bottomCenter, child: Container(
        margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
        child: Text(tt('Point the camera at the QR code on your partner’s phone.'),
          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)))),
    ]));
}
