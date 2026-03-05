import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class RecetarioShareService {
  Future<Directory> _resolveTempDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Web no utiliza filesystem temporal local.');
    }
    try {
      return await getTemporaryDirectory();
    } on MissingPluginException {
      final fallbackDir = await Directory.systemTemp.createTemp('agripy_');
      return fallbackDir;
    }
  }

  Future<XFile> savePdfTemp(Uint8List bytes, String filename) async {
    final normalizedFileName = filename.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );

    if (kIsWeb) {
      return XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: normalizedFileName,
      );
    }

    final tmpDir = await _resolveTempDirectory();
    final file = File('${tmpDir.path}/$normalizedFileName');
    await file.writeAsBytes(bytes, flush: true);
    return XFile(file.path, mimeType: 'application/pdf', name: normalizedFileName);
  }

  Future<void> sharePdf(XFile file, String text) async {
    await SharePlus.instance.share(
      ShareParams(text: text, files: [file]),
    );
  }
}
