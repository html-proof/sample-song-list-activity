import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'album_details_screen.dart';
import 'player_screen.dart';

class ArtistProfileScreen extends StatefulWidget {
  const ArtistProfileScreen({super.key, this.artist, this.state});

  final Artist? artist;
  final AppState? state;

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  bool _following = false;
  late Future<List<Track>> _tracksFuture;
  late Future<List<Album>> _albumsFuture;
  String _imageUrl = '';
  Map<String, dynamic>? _artistDetails;
  late final MusicApi _api = widget.state?.api ?? MusicApi(widget.state?.auth ?? AuthService());

  @override
  void initState() {
    super.initState();
    final artist = widget.artist;
    if (artist != null) {
      _imageUrl = artist.imageUrl;
      final state = widget.state;
      if (state != null) {
        _following = state.selectedArtists.contains(artist.seokey) ||
            (state.profile['favorite_artists'] as List? ?? const [])
                .contains(artist.name);
      }
      final detailsFuture = _getOrFetchDetails(artist);
      _tracksFuture = _fetchArtistTracks(artist, detailsFuture);
      _albumsFuture = _fetchArtistAlbums(artist, detailsFuture);
      if (_imageUrl.isEmpty) {
        unawaited(_resolveArtistImage(artist.name, artist.seokey));
      }
    } else {
      _tracksFuture = Future.value(const <Track>[]);
      _albumsFuture = Future.value(const <Album>[]);
    }
  }

  Future<Map<String, dynamic>> _getOrFetchDetails(Artist artist) async {
    if (_artistDetails != null && _artistDetails!.isNotEmpty) return _artistDetails!;

    // Step 1: Fast direct lookup using primary key
    final primaryKey = artist.seokey.isNotEmpty
        ? artist.seokey
        : (artist.artistId.isNotEmpty ? artist.artistId : artist.name);
    if (primaryKey.isNotEmpty) {
      try {
        final details = await _api.artistDetails(primaryKey);
        final rawSongs = details['popular_songs'] as List? ?? details['songs'] as List? ?? details['top_tracks'] as List?;
        final rawAlbums = details['albums'] as List? ?? details['singles'] as List?;
        if ((rawSongs != null && rawSongs.isNotEmpty) || (rawAlbums != null && rawAlbums.isNotEmpty)) {
          _artistDetails = details;
          final rawArt = details['artist'] as Map?;
          final img = rawArt?['imageUrl'] ?? rawArt?['image_url'] ?? rawArt?['artist_image'];
          if (img != null && img.toString().isNotEmpty && _imageUrl.isEmpty && mounted) {
            setState(() => _imageUrl = img.toString());
          }
          return details;
        }
      } catch (_) {}
    }

    // Step 2: Parallel candidate lookup
    final cleanSlug = artist.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final nameWithoutInitials = artist.name
        .replaceAll(RegExp(r'^[a-zA-Z][\.\s]+'), '')
        .trim();

    final candidateKeys = <String>[
      if (cleanSlug.isNotEmpty && cleanSlug != primaryKey) cleanSlug,
      if (nameWithoutInitials.isNotEmpty && nameWithoutInitials != artist.name) nameWithoutInitials,
    ];

    if (candidateKeys.isNotEmpty) {
      try {
        final results = await Future.wait(
          candidateKeys.map((k) => _api.artistDetails(k).catchError((_) => <String, dynamic>{})),
        );
        for (final details in results) {
          final rawSongs = details['popular_songs'] as List? ?? details['songs'] as List? ?? details['top_tracks'] as List?;
          final rawAlbums = details['albums'] as List? ?? details['singles'] as List?;
          if ((rawSongs != null && rawSongs.isNotEmpty) || (rawAlbums != null && rawAlbums.isNotEmpty)) {
            _artistDetails = details;
            final rawArt = details['artist'] as Map?;
            final img = rawArt?['imageUrl'] ?? rawArt?['image_url'] ?? rawArt?['artist_image'];
            if (img != null && img.toString().isNotEmpty && _imageUrl.isEmpty && mounted) {
              setState(() => _imageUrl = img.toString());
            }
            return details;
          }
        }
      } catch (_) {}
    }

    return const <String, dynamic>{};
  }

  Future<List<Track>> _fetchArtistTracks(Artist artist, Future<Map<String, dynamic>> detailsFuture) async {
    // 1. Try artistDetails catalog endpoint
    final details = await detailsFuture;
    final rawSongs = details['popular_songs'] as List? ?? details['songs'] as List? ?? details['top_tracks'] as List?;
    if (rawSongs != null && rawSongs.isNotEmpty) {
      final tracks = Track.list(rawSongs);
      if (tracks.isNotEmpty) return tracks;
    }

    // 2. Search artist directly via searchArtists to find true seokey/id
    try {
      final matchedArtists = await _api.searchArtists(artist.name, limit: 3);
      for (final a in matchedArtists) {
        if (a.id.isNotEmpty && a.id != artist.seokey) {
          final fallbackDetails = await _api.artistDetails(a.id);
          final fallbackSongs = fallbackDetails['popular_songs'] as List? ?? fallbackDetails['songs'] as List? ?? fallbackDetails['top_tracks'] as List?;
          if (fallbackSongs != null && fallbackSongs.isNotEmpty) {
            final tracks = Track.list(fallbackSongs);
            if (tracks.isNotEmpty) return tracks;
          }
        }
      }
    } catch (_) {}

    // 3. Search categorized songs
    try {
      final cat = await _api.categorizedSearch(artist.name);
      final catSongs = Track.list(cat['songs']);
      if (catSongs.isNotEmpty) return catSongs;
    } catch (_) {}

    // 4. Search tracks directly with full artist name
    try {
      final songs = await _api.searchTracks(artist.name, limit: 20);
      if (songs.isNotEmpty) return songs;
    } catch (_) {}

    return const [];
  }

  Future<List<Album>> _fetchArtistAlbums(Artist artist, Future<Map<String, dynamic>> detailsFuture) async {
    // 1. Try artistDetails catalog endpoint
    final details = await detailsFuture;
    final rawAlbums = details['albums'] as List? ?? details['singles'] as List?;
    if (rawAlbums != null && rawAlbums.isNotEmpty) {
      final albums = Album.list(rawAlbums);
      if (albums.isNotEmpty) return albums;
    }

    // 2. Search albums directly with full artist name
    try {
      final albums = await _api.searchAlbums(artist.name, limit: 10);
      if (albums.isNotEmpty) return albums;
    } catch (_) {}

    // 3. Query categorizedSearch and extract albums
    try {
      final cat = await _api.categorizedSearch(artist.name);
      final catAlbums = Album.list(cat['albums']);
      if (catAlbums.isNotEmpty) return catAlbums;
    } catch (_) {}

    return const [];
  }

  Future<void> _resolveArtistImage(String name, [String? seokey]) async {
    try {
      final photo = await ArtistPhotoResolver.resolve(name);
      if (photo != null && photo.isNotEmpty && mounted) {
        setState(() => _imageUrl = photo);
        return;
      }
      final query = name.isNotEmpty ? name : (seokey ?? '');
      if (query.isEmpty) return;
      final results = await _api.searchArtists(query, limit: 5);
      if (results.isNotEmpty) {
        final match = results.firstWhere(
          (a) => a.imageUrl.isNotEmpty,
          orElse: () => results.first,
        );
        if (match.imageUrl.isNotEmpty && mounted) {
          setState(() => _imageUrl = match.imageUrl);
        }
      }
    } catch (_) {}
  }

  void _toggleFollow() {
    final artist = widget.artist;
    if (artist == null) return;
    setState(() => _following = !_following);
    final state = widget.state;
    if (state != null) {
      state.toggleArtist(artist.seokey);
      unawaited(state.saveArtistPreferences());
    }
  }

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    if (artist == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Tap an artist to view their profile.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.hubColors.textSecondary),
              ),
            ),
          ),
        ),
      );
    }

    final avatarUrl = _imageUrl.isNotEmpty ? _imageUrl : artist.imageUrl;

    return Scaffold(
      bottomNavigationBar: (widget.state != null && widget.state!.player.current != null)
          ? SafeArea(
              top: false,
              child: MiniPlayer(
                state: widget.state!,
                onOpen: () => unawaited(openFullPlayer(context, widget.state!)),
              ),
            )
          : null,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
          children: [
            Center(
              child: SizedBox.square(
                dimension: 184,
                child: ClipOval(
                  child: Artwork(
                    url: avatarUrl,
                    label: artist.name,
                    radius: 999,
                    cacheKey: 'artist-${artist.seokey}',
                    debugKind: 'Artist',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              artist.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Artist',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.hubColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: _toggleFollow,
                icon: Icon(_following ? Icons.check : Icons.add),
                label: Text(_following ? 'Following' : 'Follow'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _following
                      ? context.hubColors.textPrimary
                      : context.hubColors.accentColor,
                  side: BorderSide(
                    color: _following
                        ? context.hubColors.dividerColor
                        : context.hubColors.accentColor,
                  ),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 36),
            Text(
              'Popular Songs',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Track>>(
              future: _tracksFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final songs = snapshot.data ?? const [];
                if (songs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No songs found for this artist.',
                      style: TextStyle(color: context.hubColors.textSecondary),
                    ),
                  );
                }
                return Column(
                  children: songs.take(8).map((track) {
                    final isPlayingCurrent =
                        widget.state?.player.current?.id == track.id &&
                            widget.state?.player.playing == true;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox.square(
                        dimension: 48,
                        child: Artwork(
                          url: track.imageUrl,
                          label: track.title,
                          radius: 10,
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isPlayingCurrent
                              ? context.hubColors.accentColor
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        track.album.isNotEmpty ? track.album : track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.hubColors.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        isPlayingCurrent
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_filled_rounded,
                        size: 32,
                        color: context.hubColors.accentColor,
                      ),
                      onTap: () {
                        if (widget.state != null) {
                          if (isPlayingCurrent) {
                            widget.state!.player.toggle();
                          } else {
                            widget.state!.player.play(
                              track,
                              fromQueue: songs,
                            );
                          }
                        }
                      },
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              'Albums & Singles',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<Album>>(
              future: _albumsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final rawAlbums = snapshot.data ?? const [];
                final albums = Album.list(rawAlbums.map((a) => {
                  'id': a.id,
                  'title': a.title,
                  'artist': a.artist,
                  'artistIds': a.artistIds,
                  'imageUrl': a.imageUrl,
                  'trackCount': a.trackCount,
                  'releaseDate': a.releaseDate,
                  'language': a.language,
                  'label': a.label,
                }).toList());
                if (albums.isEmpty) {
                  return Text(
                    'No albums found for this artist.',
                    style: TextStyle(color: context.hubColors.textSecondary),
                  );
                }
                return SizedBox(
                  height: 180,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: albums.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return SizedBox(
                        width: 130,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            if (widget.state != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AlbumDetailsScreen(
                                    state: widget.state!,
                                    albumId: album.id,
                                    preview: album,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Artwork(
                                    url: album.imageUrl,
                                    label: album.title,
                                    radius: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                album.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                album.releaseDate.length >= 4
                                    ? album.releaseDate.substring(0, 4)
                                    : 'Album',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.hubColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
