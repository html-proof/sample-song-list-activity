import 'package:music_hub_app/shared/models/music_item.dart';

/// A Home row. [id] identifies the row, [contentType] says what kind of card
/// belongs in it. The two are separate on purpose: several rows ("Trending",
/// "New releases", "Made for you") all hold songs.
class HomeSection {
  const HomeSection({
    required this.id,
    required this.title,
    required this.contentType,
    required this.items,
  });

  final String id;
  final String title;
  final MusicItemType contentType;
  final List<MusicItem> items;

  HomeSection copyWith({List<MusicItem>? items}) => HomeSection(
    id: id,
    title: title,
    contentType: contentType,
    items: items ?? this.items,
  );

  /// Builds a section, dropping any item that is not what the row claims to
  /// hold, then removing duplicates. A "Trending songs" row can therefore
  /// never surface an artist, whatever the provider mixed into the payload.
  factory HomeSection.build({
    required String id,
    required String title,
    required MusicItemType contentType,
    required List<MusicItem> items,
  }) {
    final resolvedType = contentType == MusicItemType.unknown
        ? _dominantType(items)
        : contentType;
    final matching = resolvedType == MusicItemType.unknown
        ? items
        : items.where((item) => item.type == resolvedType).toList();
    return HomeSection(
      id: id,
      title: title,
      contentType: resolvedType,
      items: dedupeItems(matching),
    );
  }

  /// The content type a known section id is defined to hold. Sections the
  /// backend adds later fall through to whatever their items declare.
  static MusicItemType contentTypeFor(String id) => switch (id) {
    'continue_listening' ||
    'recommended_for_you' ||
    'because_you_like' ||
    'trending' ||
    'trending_songs' ||
    'language_mix' ||
    'recently_played' ||
    'more_for_you' ||
    'popular_around_you' => MusicItemType.song,
    'recommended_artists' || 'artists_for_you' => MusicItemType.artist,
    'recommended_albums' || 'new_albums' => MusicItemType.album,
    'recommended_playlists' || 'playlists_for_you' => MusicItemType.playlist,
    // New releases legitimately mixes songs and albums, so it keeps whatever
    // the payload declares rather than being forced to one type.
    _ => MusicItemType.unknown,
  };

  static MusicItemType _dominantType(List<MusicItem> items) {
    final counts = <MusicItemType, int>{};
    for (final item in items) {
      if (item.type == MusicItemType.unknown) continue;
      counts[item.type] = (counts[item.type] ?? 0) + 1;
    }
    if (counts.isEmpty) return MusicItemType.unknown;
    var best = counts.entries.first;
    for (final entry in counts.entries) {
      if (entry.value > best.value) best = entry;
    }
    return best.key;
  }
}

/// Removes repeats within one row, keeping the first occurrence.
List<MusicItem> dedupeItems(Iterable<MusicItem> items) {
  final seen = <String>{};
  final output = <MusicItem>[];
  for (final item in items) {
    if (seen.add(item.dedupKey)) output.add(item);
  }
  return List.unmodifiable(output);
}

/// Soft diversity pass across the whole feed.
///
/// A song may legitimately appear in both "Continue listening" and "Made for
/// you" — different rows mean different things. What this prevents is the same
/// song filling five rows of one screen: after [maxAppearances] rows have shown
/// it, later rows drop it in favour of something the user has not seen yet.
List<HomeSection> diversifySections(
  List<HomeSection> sections, {
  int maxAppearances = 2,
  int minimumItems = 4,
}) {
  final appearances = <String, int>{};
  return sections
      .map((section) {
        final kept = <MusicItem>[];
        final overflow = <MusicItem>[];
        for (final item in section.items) {
          final seen = appearances[item.dedupKey] ?? 0;
          if (seen < maxAppearances) {
            kept.add(item);
          } else {
            overflow.add(item);
          }
        }
        // Never thin a row down to nothing: a short row is worse than a repeat.
        if (kept.length < minimumItems) {
          kept.addAll(overflow.take(minimumItems - kept.length));
        }
        for (final item in kept) {
          appearances[item.dedupKey] = (appearances[item.dedupKey] ?? 0) + 1;
        }
        return section.copyWith(items: List.unmodifiable(kept));
      })
      .toList(growable: false);
}

class HomeFeed {
  const HomeFeed({required this.sections, this.nextCursor});

  final List<HomeSection> sections;
  final String? nextCursor;

  static const empty = HomeFeed(sections: []);

  HomeSection? sectionById(String id) {
    for (final section in sections) {
      if (section.id == id) return section;
    }
    return null;
  }

  factory HomeFeed.fromJson(Map<String, dynamic> json) {
    final sections = json['sections'] is List
        ? _sectioned(json['sections'] as List)
        : _legacy(json);
    return HomeFeed(
      sections: diversifySections(
        sections.where((section) => section.items.isNotEmpty).toList(),
      ),
      nextCursor: json['next_cursor']?.toString(),
    );
  }

  /// The shape every new endpoint should return: each row names its id, its
  /// title and the content type it holds.
  static List<HomeSection> _sectioned(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((section) {
          final value = section.cast<String, dynamic>();
          final id = (value['id'] ?? value['type'] ?? 'unknown').toString();
          final declared = musicItemTypeFrom(
            value['type'] ?? value['content_type'],
          );
          return HomeSection.build(
            id: id,
            title: value['title']?.toString() ?? 'Music',
            contentType: declared == MusicItemType.unknown
                ? HomeSection.contentTypeFor(id)
                : declared,
            items: _items(value['items']),
          );
        })
        .toList(growable: false);
  }

  /// The current backend still answers with one key per row.
  static List<HomeSection> _legacy(Map<String, dynamic> json) {
    const titles = <String, String>{
      'continue_listening': 'Continue listening',
      'recommended_for_you': 'Made for you',
      'recommended_artists': 'Artists to discover',
      'recommended_playlists': 'Playlists for you',
      'recommended_albums': 'Albums for you',
      'trending': 'Trending now',
      'new_releases': 'New releases',
      'because_you_like': 'Because you like',
      'language_mix': 'Your language mix',
      'recently_played': 'Recently played',
    };
    return titles.entries
        .map(
          (entry) => HomeSection.build(
            id: entry.key,
            title: entry.value,
            contentType: HomeSection.contentTypeFor(entry.key),
            items: _items(json[entry.key]),
          ),
        )
        .toList(growable: false);
  }

  static List<MusicItem> _items(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false)
      : const [];
}
