import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n.dart';

/// Camera QR scanner (Android/iOS/macOS) + decoding QR from an image file.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  /// Picks an image and decodes the first QR code in it.
  static Future<String?> fromImage(BuildContext context) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.single.path;
    if (path == null) return null;
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Распознавание QR из файла доступно на Android/iOS/macOS. Скопируйте ссылку в буфер.')),
        );
      }
      return null;
    }
    final ctrl = MobileScannerController();
    try {
      final capture = await ctrl.analyzeImage(path);
      return capture?.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    } finally {
      await ctrl.dispose();
    }
  }

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _ctrl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('scanQr'))),
        body: MobileScanner(
          controller: _ctrl,
          onDetect: (capture) {
            if (_done) return;
            final v = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (v != null) {
              _done = true;
              Navigator.pop(context, v);
            }
          },
        ),
      );
}
