class DownloadWriter {
  Future<String> save(String id, String url, void Function(double) progress) {
    throw UnsupportedError(
      'Offline audio downloads are available on mobile only',
    );
  }

  Future<void> remove(String path) async {}
}
