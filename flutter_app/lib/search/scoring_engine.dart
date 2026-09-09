import 'dart:math';
import '../models.dart';

/// Standard list of recognizable language identifiers and terms.
const Set<String> kSupportedSearchLanguages = {
  'malayalam',
  'tamil',
  'hindi',
  'telugu',
  'kannada',
  'english',
  'punjabi',
  'bengali',
  'marathi',
  'gujarati',
};

/// Common phonetic transliteration substitutions for Indian and English titles.
const Map<String, String> _phoneticSubstitutions = {
  'aa': 'a',
  'ee': 'i',
  'oo': 'u',
  'th': 't',
  'dh': 'd',
  'zh': 'l',
  'sh': 's',
  'ch': 'c',
  'bh': 'b',
  'ph': 'p',
  'kh': 'k',
  'gh': 'g',
};

/// Cleans and normalizes search text:
/// - Lowercase
/// - Replaces punctuation, parentheses, brackets, hyphens with spaces
/// - Collapses multiple spaces
/// - Strips leading/trailing whitespace
String normalizeSearchText(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[\(\)\[\]\{\}"' "'" r'.,:;!/?\\|_~@#$%^&*+=<>`-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Applies phonetic transliteration normalization to handle spelling variants
/// like "Gilli" <-> "Ghilli", "Anirud" <-> "Anirudh", "Arijit" <-> "Arjit".
String toPhoneticKey(String text) {
  var s = normalizeSearchText(text).replaceAll(' ', '');
  _phoneticSubstitutions.forEach((key, val) {
    s = s.replaceAll(key, val);
  });
  return s;
}

/// Levenshtein edit distance for high-quality typo matching.
int levenshteinDistance(String s, String t) {
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;

  List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(t.length + 1, 0);

  for (int i = 0; i < s.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < t.length; j++) {
      int cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
      v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
    }
    for (int j = 0; j <= t.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v1[t.length];
}

/// Identifies if target is a high-quality typo match of query.
bool isHighQualityTypo(String query, String target) {
  if (query.length < 4 || target.length < 4) return false;
  final dist = levenshteinDistance(query, target);
  if (dist <= 1 && query.length >= 4) return true;
  if (dist <= 2 && query.length >= 6) return true;
  return false;
}

/// Extracts any explicit language keywords present in the search query.
/// E.g. "premam malayalam" -> query: "premam", detectedLanguage: "malayalam".
class ParsedSearchQuery {
  const ParsedSearchQuery({
    required this.rawQuery,
    required this.cleanQuery,
    this.detectedLanguage,
    required this.tokens,
  });

  final String rawQuery;
  final String cleanQuery;
  final String? detectedLanguage;
  final List<String> tokens;

  factory ParsedSearchQuery.parse(String raw) {
    final normalized = normalizeSearchText(raw);
    if (normalized.isEmpty) {
      return const ParsedSearchQuery(
        rawQuery: '',
        cleanQuery: '',
        tokens: [],
      );
    }

    final rawTokens = normalized.split(' ').where((w) => w.isNotEmpty).toList();
    String? foundLang;
    final remaining = <String>[];

    for (final token in rawTokens) {
      if (foundLang == null && kSupportedSearchLanguages.contains(token)) {
        foundLang = token;
      } else {
        remaining.add(token);
      }
    }

    // If query was only the language name itself (e.g. "malayalam"), keep it as query
    final clean = remaining.isEmpty ? normalized : remaining.join(' ');
    final cleanTokens = clean.split(' ').where((w) => w.isNotEmpty).toList();

    return ParsedSearchQuery(
      rawQuery: raw,
      cleanQuery: clean,
      detectedLanguage: foundLang,
      tokens: cleanTokens,
    );
  }
}

/// RegEx to identify unofficial noise: covers, karaoke, 8D audio, slowed reverb, etc.
final RegExp _noiseRegex = RegExp(
  r'\b(?:cover|karaoke|instrumental|reverb|lo-?fi|slowed|ringtone|status|dj remix|tribute|dialogue promo|whatsapp status)\b',
  caseSensitive: false,
);

final RegExp _ostKeywordsRegex = RegExp(
  r'\b(?:original motion picture soundtrack|original soundtrack|ost|soundtrack)\b',
  caseSensitive: false,
);

/// Central Spotify-Style Relevance Scoring for Tracks.
///
/// Conceptual 1000-point scale:
/// - Exact song/title match:            +1000
/// - Exact movie/album title:           +950
/// - Title starts with query:           +850
/// - Title word starts with query:      +750
/// - Exact artist:                      +700
/// - Song title contains query:         +600
/// - Album/movie contains query:        +500
/// - Artist starts with query:          +450
/// - Artist contains query:             +350
/// - Correct language:                  +250
/// - Transliteration match:             +220
/// - High-quality typo match:           +150
/// - User-preferred artist:             +80
/// - User-preferred language:           +70
/// - Popularity:                        +30
/// - Weak fuzzy similarity:             +10
/// - Noise penalty:                     -400
int scoreTrack(
  Track track,
  String query, {
  List<String>? userLanguages,
  List<String>? userArtists,
}) {
  final parsed = ParsedSearchQuery.parse(query);
  final q = parsed.cleanQuery;
  if (q.isEmpty) return 0;

  final title = normalizeSearchText(track.title);
  final artist = normalizeSearchText(track.artist);
  final album = normalizeSearchText(track.album);
  final cleanAlbum = album.replaceAll(_ostKeywordsRegex, '').trim();
  final trackLang = track.language.toLowerCase().trim();

  final titleTokens = title.split(' ').where((w) => w.isNotEmpty).toList();
  final artistTokens = artist.split(' ').where((w) => w.isNotEmpty).toList();
  final queryTokens = parsed.tokens;

  int score = 0;

  // 1. Exact song title match (+1000)
  if (title == q) {
    score = 1000;
  }
  // 2. Exact movie/album title match (+950)
  else if (cleanAlbum.isNotEmpty && cleanAlbum == q) {
    score = 950;
  }
  // 3. Title starts with query (+850)
  else if (title.startsWith('$q ') || (title.startsWith(q) && !isHighQualityTypo(q, title))) {
    score = 850;
  }
  // 4. Title individual word starts with query (+750)
  else if (titleTokens.any((t) => t == q || t.startsWith('$q ') || (t.startsWith(q) && !isHighQualityTypo(q, t)))) {
    score = 750;
  }
  // 5. Exact artist match (+700)
  else if (artist == q || artistTokens.any((t) => t == q)) {
    score = 700;
  }
  // 6. Song title contains query (+600)
  else if (title.contains(q) && !isHighQualityTypo(q, title)) {
    score = 600;
  }
  // 7. Album/movie contains query (+500)
  else if (album.contains(q) || cleanAlbum.contains(q)) {
    score = 500;
  }
  // 8. Artist starts with query (+450)
  else if (artist.startsWith(q) || artistTokens.any((t) => t.startsWith(q))) {
    score = 450;
  }
  // 9. Artist contains query (+350)
  else if (artist.contains(q)) {
    score = 350;
  }
  // 10. Multi-word query cross-field match (+400)
  // E.g. "Vijay Ghilli" or "Believer Imagine Dragons"
  else if (queryTokens.length > 1 &&
      queryTokens.every((qt) =>
          title.contains(qt) || artist.contains(qt) || album.contains(qt))) {
    score = 400;
  }
  // 11. Transliteration match (+220)
  else if (toPhoneticKey(title) == toPhoneticKey(q) ||
      titleTokens.any((t) => toPhoneticKey(t) == toPhoneticKey(q))) {
    score = 220;
  }
  // 12. High-quality typo match (+150)
  else if (isHighQualityTypo(q, title) ||
      titleTokens.any((t) => isHighQualityTypo(q, t))) {
    score = 150;
  }
  // 13. Weak fuzzy / contains (+10)
  else {
    score = 10;
  }

  // Language Intent Boost:
  // If the query explicitly specified a language (e.g. "premam malayalam"), award +250
  if (parsed.detectedLanguage != null && trackLang.isNotEmpty) {
    if (trackLang == parsed.detectedLanguage ||
        trackLang.startsWith(parsed.detectedLanguage!) ||
        parsed.detectedLanguage!.startsWith(trackLang)) {
      score += 250;
    }
  }

  // User personalization tie-breakers:
  // Text relevance dominates! User preferences are strictly tie-breakers (+70 / +80).
  if (userLanguages != null && trackLang.isNotEmpty) {
    if (userLanguages.any((l) => l.toLowerCase() == trackLang)) {
      score += 70;
    }
  }
  if (userArtists != null && artist.isNotEmpty) {
    if (userArtists.any((a) => normalizeSearchText(a) == artist || artist.contains(normalizeSearchText(a)))) {
      score += 80;
    }
  }

  // Popularity (+30)
  // Text relevance dominates popularity (+1000 vs +30).
  // Popularity helps break ties between non-exact matches without beating exact matches.
  if (title != q && track.popularityScore > 0) {
    score += (track.popularityScore * 30).round();
  }

  // Noise Penalty:
  // Covers, karaoke, ringtones, slowed reverb receive a -400 penalty unless user asked for it
  final isLookingForNoise = _noiseRegex.hasMatch(q);
  if (!isLookingForNoise && (_noiseRegex.hasMatch(title) || _noiseRegex.hasMatch(album))) {
    score -= 400;
  }

  // Exact match rule: non-exact matches cannot outscore an exact match
  if (title != q && score >= 1000) {
    score = 999;
  }

  return score;
}

/// Central Spotify-Style Relevance Scoring for Albums.
int scoreAlbum(
  Album album,
  String query, {
  List<String>? userLanguages,
  List<String>? userArtists,
}) {
  final parsed = ParsedSearchQuery.parse(query);
  final q = parsed.cleanQuery;
  if (q.isEmpty) return 0;

  final title = normalizeSearchText(album.title);
  final artist = normalizeSearchText(album.artist);
  final cleanTitle = title.replaceAll(_ostKeywordsRegex, '').trim();
  final albumLang = album.language.toLowerCase().trim();

  final titleTokens = cleanTitle.split(' ').where((w) => w.isNotEmpty).toList();

  int score = 0;

  // 1. Exact album/movie title match (+1000)
  if (title == q || cleanTitle == q) {
    score = 1000;
  }
  // 2. Title starts with query (+850)
  else if (title.startsWith(q) || cleanTitle.startsWith(q)) {
    score = 850;
  }
  // 3. Word starts with query (+750)
  else if (titleTokens.any((t) => t.startsWith(q))) {
    score = 750;
  }
  // 4. Exact artist (+700)
  else if (artist == q) {
    score = 700;
  }
  // 5. Title contains query (+600)
  else if (title.contains(q) || cleanTitle.contains(q)) {
    score = 600;
  }
  // 6. Artist starts with query (+450)
  else if (artist.startsWith(q) || artist.split(' ').any((t) => t.startsWith(q))) {
    score = 450;
  }
  // 7. Artist contains query (+350)
  else if (artist.contains(q)) {
    score = 350;
  }
  // 8. Transliteration match (+220)
  else if (toPhoneticKey(cleanTitle) == toPhoneticKey(q) ||
      titleTokens.any((t) => toPhoneticKey(t) == toPhoneticKey(q))) {
    score = 220;
  }
  // 9. High-quality typo (+150)
  else if (isHighQualityTypo(q, cleanTitle) ||
      titleTokens.any((t) => isHighQualityTypo(q, t))) {
    score = 150;
  }
  // 10. Weak fuzzy (+10)
  else {
    score = 10;
  }

  // Language Intent Boost (+250)
  if (parsed.detectedLanguage != null && albumLang.isNotEmpty) {
    if (albumLang == parsed.detectedLanguage ||
        albumLang.startsWith(parsed.detectedLanguage!) ||
        parsed.detectedLanguage!.startsWith(albumLang)) {
      score += 250;
    }
  }

  // Personalization tie-breakers (+70 / +80)
  if (userLanguages != null && albumLang.isNotEmpty) {
    if (userLanguages.any((l) => l.toLowerCase() == albumLang)) {
      score += 70;
    }
  }
  if (userArtists != null && artist.isNotEmpty) {
    if (userArtists.any((a) => normalizeSearchText(a) == artist)) {
      score += 80;
    }
  }

  return score;
}

/// Central Spotify-Style Relevance Scoring for Artists.
int scoreArtist(
  Artist artist,
  String query, {
  List<String>? userArtists,
}) {
  final parsed = ParsedSearchQuery.parse(query);
  final q = parsed.cleanQuery;
  if (q.isEmpty) return 0;

  final name = normalizeSearchText(artist.name);
  final nameTokens = name.split(' ').where((w) => w.isNotEmpty).toList();

  int score = 0;

  // 1. Exact artist match (+1000)
  if (name == q) {
    score = 1000;
  }
  // 2. Artist starts with query (+850)
  else if (name.startsWith(q)) {
    score = 850;
  }
  // 3. Name word starts with query (+750)
  else if (nameTokens.any((t) => t.startsWith(q))) {
    score = 750;
  }
  // 4. Artist contains query (+450)
  else if (name.contains(q)) {
    score = 450;
  }
  // 5. Transliteration match (+220)
  else if (toPhoneticKey(name) == toPhoneticKey(q) ||
      nameTokens.any((t) => toPhoneticKey(t) == toPhoneticKey(q))) {
    score = 220;
  }
  // 6. High-quality typo (+150)
  else if (isHighQualityTypo(q, name) ||
      nameTokens.any((t) => isHighQualityTypo(q, t))) {
    score = 150;
  }
  // 7. Weak fuzzy (+10)
  else {
    score = 10;
  }

  if (userArtists != null && name.isNotEmpty) {
    if (userArtists.any((a) => normalizeSearchText(a) == name)) {
      score += 80;
    }
  }

  return score;
}

/// Deterministically rank tracks for a query.
List<Track> rankTracksForQuery(
  List<Track> list,
  String query, {
  List<String>? userLanguages,
  List<String>? userArtists,
}) {
  final q = normalizeSearchText(query);
  if (q.isEmpty || list.isEmpty) return list;

  final scored = list
      .map((track) => MapEntry(
            scoreTrack(
              track,
              query,
              userLanguages: userLanguages,
              userArtists: userArtists,
            ),
            track,
          ))
      .toList();

  // Deterministic multi-tier sort:
  // 1. Score descending
  // 2. StartsWith query descending
  // 3. Length ascending (shorter more exact title wins)
  // 4. Id string comparison for perfect stability
  scored.sort((a, b) {
    final cmpScore = b.key.compareTo(a.key);
    if (cmpScore != 0) return cmpScore;

    final aTitle = normalizeSearchText(a.value.title);
    final bTitle = normalizeSearchText(b.value.title);
    final aStarts = aTitle.startsWith(q);
    final bStarts = bTitle.startsWith(q);
    if (aStarts && !bStarts) return -1;
    if (!aStarts && bStarts) return 1;

    final cmpLen = aTitle.length.compareTo(bTitle.length);
    if (cmpLen != 0) return cmpLen;

    return a.value.id.compareTo(b.value.id);
  });

  return scored.map((e) => e.value).toList();
}

/// Deterministically rank albums for a query.
List<Album> rankAlbumsForQuery(
  List<Album> list,
  String query, {
  int limit = 20,
  List<String>? userLanguages,
  List<String>? userArtists,
}) {
  final q = normalizeSearchText(query);
  if (q.isEmpty || list.isEmpty) return list.take(limit).toList();

  final scored = list
      .map((album) => MapEntry(
            scoreAlbum(
              album,
              query,
              userLanguages: userLanguages,
              userArtists: userArtists,
            ),
            album,
          ))
      .toList();

  scored.sort((a, b) {
    final cmpScore = b.key.compareTo(a.key);
    if (cmpScore != 0) return cmpScore;

    final aTitle = normalizeSearchText(a.value.title);
    final bTitle = normalizeSearchText(b.value.title);
    final aStarts = aTitle.startsWith(q);
    final bStarts = bTitle.startsWith(q);
    if (aStarts && !bStarts) return -1;
    if (!aStarts && bStarts) return 1;

    return a.value.id.compareTo(b.value.id);
  });

  return scored.map((e) => e.value).take(limit).toList();
}

/// Deterministically rank artists for a query.
List<Artist> rankArtistsForQuery(
  List<Artist> list,
  String query, {
  List<String>? userArtists,
}) {
  final q = normalizeSearchText(query);
  if (q.isEmpty || list.isEmpty) return list;

  final scored = list
      .map((artist) => MapEntry(
            scoreArtist(
              artist,
              query,
              userArtists: userArtists,
            ),
            artist,
          ))
      .toList();

  scored.sort((a, b) {
    final cmpScore = b.key.compareTo(a.key);
    if (cmpScore != 0) return cmpScore;

    final aName = normalizeSearchText(a.value.name);
    final bName = normalizeSearchText(b.value.name);
    final aStarts = aName.startsWith(q);
    final bStarts = bName.startsWith(q);
    if (aStarts && !bStarts) return -1;
    if (!aStarts && bStarts) return 1;

    return a.value.id.compareTo(b.value.id);
  });

  return scored.map((e) => e.value).toList();
}

/// Computes the Top Result representing the strongest interpretation of the query.
///
/// Rules:
/// - Exact song match -> Song intent wins.
/// - Exact artist match -> Artist intent wins.
/// - Exact movie/album match -> Album intent wins.
/// - Never rank popularity over exact text match.
SearchTopResult? computeTopResult(
  String query, {
  List<Track>? tracks,
  List<Album>? albums,
  List<Artist>? artists,
}) {
  final parsed = ParsedSearchQuery.parse(query);
  final q = parsed.cleanQuery;
  if (q.isEmpty) return null;

  int bestScore = 0;
  SearchTopResult? best;

  // 1. Check Artist candidate
  if (artists != null && artists.isNotEmpty) {
    final topArtist = artists.first;
    final s = scoreArtist(topArtist, query);
    if (s > bestScore) {
      bestScore = s;
      best = SearchTopResult(
        type: 'artist',
        confidence: s / 1000.0,
        artist: topArtist,
      );
    }
  }

  // 2. Check Album candidate
  if (albums != null && albums.isNotEmpty) {
    final topAlbum = albums.first;
    final s = scoreAlbum(topAlbum, query);
    // Album with exact title (e.g. "Ghilli") beats weaker artist matches
    if (s > bestScore) {
      bestScore = s;
      best = SearchTopResult(
        type: 'album',
        confidence: s / 1000.0,
        album: topAlbum,
      );
    }
  }

  // 3. Check Track candidate
  if (tracks != null && tracks.isNotEmpty) {
    final topTrack = tracks.first;
    final s = scoreTrack(topTrack, query);
    // If track is exact match (score >= 1000) or stronger than album/artist, song intent wins
    if (s >= bestScore && s >= 500) {
      bestScore = s;
      best = SearchTopResult(
        type: 'song',
        confidence: s / 1000.0,
        track: topTrack,
      );
    }
  }

  return bestScore >= 350 ? best : null;
}
