// Reads a meter's barcode or QR code with the phone camera (Android and iOS only; a PC
// has no scan button). The number goes into the field, so nothing is typed by hand.
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart' hide Actions;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/scope.dart';

bool get canScanCodes => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Opens the camera and returns the first code it reads, or null if the person closes it.
Future<String?> scanCode(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _ScanPage()));

class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(s.t('scan.title'))),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().where((v) => v.trim().isNotEmpty).firstOrNull;
            if (code == null) return;
            _done = true;
            Navigator.of(context).pop(code.trim());
          },
          errorBuilder: (context, error, child) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(s.t('scan.noCamera'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)))),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(padding: const EdgeInsets.all(24), child: Text(s.t('scan.hint'), style: const TextStyle(color: Colors.white70))),
        ),
      ]),
    );
  }
}
