import 'package:music_hub_app/shared/models/music_item.dart';

class HomeSection {
  const HomeSection({
    required this.type,
    required this.title,
    required this.items,
  });

  final String type;
  final String title;
  final List<MusicItem> items;
}

class HomeFeed {
  const HomeFeed({required this.sections, this.nextCursor});

  final List<HomeSection> sections;
  final String? nextCursor;

  factory HomeFeed.fromJson(Map<String, dynamic> json) {
    if (json['sections'] is List) {
      return HomeFeed(
        sections: (json['sections'] as List)
            .whereType<Map>()
            .map((section) {
              final value = section.cast<String, dynamic>();
              return HomeSection(
                type: value['type']?.toString() ?? 'unknown',
                title: value['title']?.toString() ?? 'Music',
                items: _items(value['items']),
              );
            })
            .toList(growable: false),
        nextCursor: json['next_cursor']?.toString(),
      );
    }
    const titles = <String, String>{
      'continue_listening': 'Continue listening',
      'recommended_for_you': 'Made for you',
      'because_you_like': 'Because you like',
      'new_releases': 'New releases',
      'trending': 'Trending now',
      'language_mix': 'Your language mix',
      'recently_played': 'Recently played',
      'recommended_artists': 'Artists to discover',
    };
    return HomeFeed(
      sections: titles.entries
          .map(
            (entry) => HomeSection(
              type: entry.key,
              title: entry.value,
              items: _items(json[entry.key]),
            ),
          )
          .where((section) => section.items.isNotEmpty)
          .toList(growable: false),
      nextCursor: json['next_cursor']?.toString(),
    );
  }

  static List<MusicItem> _items(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false)
      : const [];
}
