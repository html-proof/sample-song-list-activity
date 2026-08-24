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
    final partialPath = '$path.part';
    await _dio.download(
      url,
      partialPath,
      deleteOnError: false,
      onReceiveProgress: (received, total) {
        if (total > 0) progress(received / total);
      },
    );
    final partial = File(partialPath);
    if (!await partial.exists() || await partial.length() == 0) {
      throw const FileSystemException('Downloaded audio is empty');
    }
    final completed = File(path);
    if (await completed.exists()) await completed.delete();
    await partial.rename(path);
    return path;
  }

  Future<void> remove(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
