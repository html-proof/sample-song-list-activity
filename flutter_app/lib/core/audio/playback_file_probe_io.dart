import 'dart:io';

Future<bool> isUsablePlaybackFile(Uri uri) async {
  if (uri.scheme != 'file') return false;
  try {
    final file = File.fromUri(uri);
    return await file.exists() && await file.length() > 0;
  } catch (_) {
    return false;
  }
}
