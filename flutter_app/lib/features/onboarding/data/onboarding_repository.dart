import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

class OnboardingRepository {
  OnboardingRepository(this._api);

  final ApiClient _api;

  Future<List<String>> languages() async {
    final response = await _api.getMap(ApiEndpoints.onboardingLanguages);
    final data = response['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => (item['name'] ?? item['code']).toString())
        .toList(growable: false);
  }

  Future<List<MusicItem>> artists(String query) async {
    final response = await _api.getMap(
      ApiEndpoints.onboardingArtists,
      query: {'q': query, 'limit': 20},
    );
    final data = response['data'];
    return data is List
        ? data
              .whereType<Map>()
              .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false)
        : const [];
  }

  Future<Map<String, dynamic>> currentPreferences() =>
      _api.getMap(ApiEndpoints.onboarding);

  Future<void> updateLanguages(List<String> languages) async {
    await _api.put(
      ApiEndpoints.preferenceLanguages,
      data: {
        'languages': [
          for (var i = 0; i < languages.length; i++)
            {'language_code': languages[i], 'priority': languages.length - i},
        ],
      },
    );
  }

  Future<void> updateArtists(List<MusicItem> artists) async {
    await _api.put(
      ApiEndpoints.preferenceArtists,
      data: {
        'artists': [
          for (final artist in artists)
            {
              'provider': 'gaana',
              'provider_artist_id': artist.id,
              'artist_name': artist.title,
              'artist_image': artist.imageUrl,
              'preference_score': 1.0,
            },
        ],
      },
    );
  }

  Future<void> complete({
    required List<String> languages,
    required List<MusicItem> artists,
  }) async {
    await _api.put(
      ApiEndpoints.onboarding,
      data: {
        'languages': [
          for (var i = 0; i < languages.length; i++)
            {'language_code': languages[i], 'priority': languages.length - i},
        ],
        'artists': [
          for (final artist in artists)
            {
              'provider': 'gaana',
              'provider_artist_id': artist.id,
              'artist_name': artist.title,
              'artist_image': artist.imageUrl,
              'preference_score': 1.0,
            },
        ],
      },
    );
  }
}
