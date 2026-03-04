import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class RecetarioShareService {
  Future<File> savePdfTemp(Uint8List bytes, String filename) async {
    final tmpDir = await getTemporaryDirectory();
    final normalizedFileName = filename.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final file = File('${tmpDir.path}/$normalizedFileName');
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<void> sharePdf(File file, String text) async {
    await SharePlus.instance.share(
      ShareParams(text: text, files: [XFile(file.path)]),
    );
  }
}
