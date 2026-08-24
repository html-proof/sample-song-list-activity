import 'package:dio/dio.dart';
import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/features/lyrics/domain/entities/lyrics.dart';

class LyricsRemoteDataSource {
  LyricsRemoteDataSource(this._api);

  final ApiClient _api;

  Future<Lyrics> fetch(String songId, {CancelToken? cancelToken}) async {
    final encoded = Uri.encodeComponent(songId);
    final json = await _api.getMap(
      '${ApiEndpoints.songs}/$encoded/lyrics',
      cancelToken: cancelToken,
    );
    return Lyrics.fromJson(json);
  }
}
