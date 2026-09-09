import '../models.dart';

/// Handles multi-source deduplication of tracks, albums, artists, and playlists.
class SearchDeduplicator {
  SearchDeduplicator._();
  static final SearchDeduplicator instance = SearchDeduplicator._();

  /// Generates a semantic fingerprint for a track to detect duplicates
  /// across different providers (e.g. Gaana vs JioSaavn).
  String trackFingerprint(Track track) {
    final title = normalizeSearchText(track.title);
    final artist = normalizeSearchText(track.artist).split(' ').first;
    final album = normalizeSearchText(track.album).split(' ').first;
    // Round duration to nearest 8-second bucket to tolerate minor provider differences
    final durationBucket = track.durationSeconds > 0 ? (track.durationSeconds ~/ 8) : 0;
    return '${title}_${artist}_${album}_$durationBucket';
  }

  /// Deduplicates tracks, retaining richer metadata (stream URL, artwork, duration).
  List<Track> deduplicateTracks(Iterable<Track> tracks) {
    final seenFingerprints = <String, Track>{};
    final seenIds = <String>{};
    final result = <Track>[];

    for (final track in tracks) {
      final id = track.id.trim().toLowerCase();
      if (id.isNotEmpty && seenIds.contains(id)) {
        continue;
      }

      final fp = trackFingerprint(track);
      if (seenFingerprints.containsKey(fp)) {
        final existing = seenFingerprints[fp]!;
        // Merge richer metadata into existing entry
        final merged = _mergeTracks(existing, track);
        seenFingerprints[fp] = merged;
        final idx = result.indexOf(existing);
        if (idx != -1) {
          result[idx] = merged;
        }
      } else {
        seenFingerprints[fp] = track;
        if (id.isNotEmpty) seenIds.add(id);
        result.add(track);
      }
    }

    return result;
  }

  Track _mergeTracks(Track a, Track b) {
    return a.copyWith(
      streamUrl: a.streamUrl.isNotEmpty ? a.streamUrl : b.streamUrl,
      imageUrl: a.imageUrl.isNotEmpty ? a.imageUrl : b.imageUrl,
      durationSeconds: a.durationSeconds > 0 ? a.durationSeconds : b.durationSeconds,
      album: a.album.isNotEmpty ? a.album : b.album,
      albumId: a.albumId.isNotEmpty ? a.albumId : b.albumId,
      albumSeokey: a.albumSeokey.isNotEmpty ? a.albumSeokey : b.albumSeokey,
      language: a.language.isNotEmpty ? a.language : b.language,
    );
  }

  /// Deduplicates albums by normalized title and primary artist.
  List<Album> deduplicateAlbums(Iterable<Album> albums) {
    final seen = <String, Album>{};
    final result = <Album>[];

    for (final a in albums) {
      final key = '${normalizeSearchText(a.title)}_${normalizeSearchText(a.artist).split(' ').first}';
      if (key.trim().isEmpty) continue;

      if (!seen.containsKey(key)) {
        seen[key] = a;
        result.add(a);
      } else {
        final existing = seen[key]!;
        if (existing.imageUrl.isEmpty && a.imageUrl.isNotEmpty) {
          final merged = existing.copyWith(imageUrl: a.imageUrl);
          seen[key] = merged;
          final idx = result.indexOf(existing);
          if (idx != -1) result[idx] = merged;
        }
      }
    }

    return result;
  }

  /// Deduplicates artists by normalized name.
  List<Artist> deduplicateArtists(Iterable<Artist> artists) {
    final seen = <String, Artist>{};
    final result = <Artist>[];

    for (final a in artists) {
      final key = normalizeSearchText(a.name);
      if (key.isEmpty) continue;

      if (!seen.containsKey(key)) {
        seen[key] = a;
        result.add(a);
      } else {
        final existing = seen[key]!;
        if (existing.imageUrl.isEmpty && a.imageUrl.isNotEmpty) {
          final merged = Artist(
            seokey: existing.seokey.isNotEmpty ? existing.seokey : a.seokey,
            artistId: existing.artistId.isNotEmpty ? existing.artistId : a.artistId,
            name: existing.name,
            imageUrl: a.imageUrl,
          );
          seen[key] = merged;
          final idx = result.indexOf(existing);
          if (idx != -1) result[idx] = merged;
        }
      }
    }

    return result;
  }

  /// Deduplicates playlists by normalized title.
  List<Map<String, dynamic>> deduplicatePlaylists(Iterable<Map<String, dynamic>> playlists) {
    final seen = <String, Map<String, dynamic>>{};
    final result = <Map<String, dynamic>>[];

    for (final p in playlists) {
      final name = normalizeSearchText('${p['name'] ?? p['title'] ?? ''}');
      if (name.isEmpty) continue;

      if (!seen.containsKey(name)) {
        seen[name] = p;
        result.add(p);
      }
    }

    return result;
  }
}
