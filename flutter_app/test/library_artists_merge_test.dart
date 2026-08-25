import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/features/library/data/library_repository.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

MusicItem followed(String id, String name) =>
    MusicItem.fromJson({'artist_id': id, 'artist_name': name});

MusicItem preferred(String id, String name) =>
    MusicItem.fromJson({'provider_artist_id': id, 'artist_name': name});

void main() {
  test('onboarding favourites join the followed artists', () {
    final merged = LibraryRepository.mergeArtists(
      [followed('1', 'Followed')],
      [preferred('2', 'Favourite')],
    );

    expect(merged.map((item) => item.title), ['Followed', 'Favourite']);
  });

  test('an artist that is both followed and favourited appears once', () {
    final merged = LibraryRepository.mergeArtists(
      [followed('1', 'Followed')],
      [preferred('1', 'Same artist'), preferred('2', 'Favourite')],
    );

    expect(merged.map((item) => item.id), ['1', '2']);
    expect(merged.first.title, 'Followed');
  });

  test('favourites alone still populate the tab', () {
    final merged = LibraryRepository.mergeArtists(const [], [
      preferred('7', 'Only a favourite'),
    ]);

    expect(merged.single.title, 'Only a favourite');
  });

  test('an artist without an id is skipped rather than shown blank', () {
    final merged = LibraryRepository.mergeArtists(const [], [
      MusicItem.fromJson({'artist_name': 'No id'}),
    ]);

    expect(merged, isEmpty);
  });
}
