import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class DownloadWriter {
  final Dio _dio = Dio();

  Future<String> save(
    String id,
    String url,
    void Function(double) progress,
  ) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}music');
    await directory.create(recursive: true);
    final path = '${directory.path}${Platform.pathSeparator}$id.audio';
    await _dio.download(
      url,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0) progress(received / total);
      },
    );
    return path;
  }

  Future<void> remove(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
