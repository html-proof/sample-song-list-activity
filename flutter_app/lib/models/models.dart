class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final Duration duration;
  final String? previewUrl;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.duration,
    this.previewUrl,
  });
}

class Playlist {
  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;
  final int trackCount;
  final String genre;
  final List<Track> tracks;

  const Playlist({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.trackCount,
    required this.genre,
    this.tracks = const [],
  });
}

class Artist {
  final String id;
  final String name;
  final String role;
  final String imageUrl;
  final String followers;
  final int following;
  final bool isVerified;

  const Artist({
    required this.id,
    required this.name,
    required this.role,
    required this.imageUrl,
    required this.followers,
    required this.following,
    this.isVerified = false,
  });
}

class MockData {
  static const List<Track> tracks = [
    Track(
      id: '1',
      title: 'Your Mirror Voice',
      artist: 'Velour Hours',
      album: 'Soul Sensual Mix',
      coverUrl: 'https://picsum.photos/seed/track1/400/400',
      duration: Duration(minutes: 3, seconds: 34),
    ),
    Track(
      id: '2',
      title: 'Night Circuits and Lights',
      artist: 'Mono Sleep',
      album: 'Soul Sensual Mix',
      coverUrl: 'https://picsum.photos/seed/track2/400/400',
      duration: Duration(minutes: 2, seconds: 48),
    ),
    Track(
      id: '3',
      title: 'Silence Begins Here',
      artist: 'Betty & Bob D.',
      album: 'Soul Sensual Mix',
      coverUrl: 'https://picsum.photos/seed/track3/400/400',
      duration: Duration(minutes: 3, seconds: 34),
    ),
    Track(
      id: '4',
      title: 'Electric Air Into You',
      artist: 'Pale 911',
      album: 'Neon Afterglow',
      coverUrl: 'https://picsum.photos/seed/track4/400/400',
      duration: Duration(minutes: 4, seconds: 12),
    ),
    Track(
      id: '5',
      title: 'Between Two Breaths',
      artist: 'Lune Archive',
      album: 'Midnight Cassette',
      coverUrl: 'https://picsum.photos/seed/track5/400/400',
      duration: Duration(minutes: 3, seconds: 58),
    ),
    Track(
      id: '6',
      title: 'Static Youth',
      artist: 'Nova Glass',
      album: 'Analog Dreams',
      coverUrl: 'https://picsum.photos/seed/track6/400/400',
      duration: Duration(minutes: 3, seconds: 21),
    ),
  ];

  static const List<Playlist> playlists = [
    Playlist(
      id: '1',
      title: 'Midnight Cassette',
      subtitle: '28 tracks',
      coverUrl: 'https://picsum.photos/seed/pl1/400/400',
      trackCount: 28,
      genre: 'Synthpop',
    ),
    Playlist(
      id: '2',
      title: 'Analog Dreams',
      subtitle: '34 tracks',
      coverUrl: 'https://picsum.photos/seed/pl2/400/400',
      trackCount: 34,
      genre: 'Indie',
    ),
    Playlist(
      id: '3',
      title: 'Static Romance',
      subtitle: '31 tracks',
      coverUrl: 'https://picsum.photos/seed/pl3/400/400',
      trackCount: 31,
      genre: 'Soft Rock',
    ),
    Playlist(
      id: '4',
      title: 'Neon Afterglow',
      subtitle: '16 tracks',
      coverUrl: 'https://picsum.photos/seed/pl4/400/400',
      trackCount: 16,
      genre: 'New Wave',
    ),
    Playlist(
      id: '5',
      title: 'Velvet Frequency',
      subtitle: '23 tracks',
      coverUrl: 'https://picsum.photos/seed/pl5/400/400',
      trackCount: 23,
      genre: 'Synthpop',
    ),
    Playlist(
      id: '6',
      title: 'Tape Echo Stories',
      subtitle: '31 tracks',
      coverUrl: 'https://picsum.photos/seed/pl6/400/400',
      trackCount: 31,
      genre: 'Indie',
    ),
  ];

  static const List<Artist> artists = [
    Artist(
      id: '1',
      name: 'Nova Glass',
      role: 'Singer, Producer',
      imageUrl: 'https://picsum.photos/seed/artist1/400/400',
      followers: '2.4M',
      following: 14,
      isVerified: true,
    ),
    Artist(
      id: '2',
      name: 'Lune Archive',
      role: 'Singer, Song Writer',
      imageUrl: 'https://picsum.photos/seed/artist2/400/400',
      followers: '8.1M',
      following: 7,
      isVerified: true,
    ),
    Artist(
      id: '3',
      name: 'Velour Hours',
      role: 'Band',
      imageUrl: 'https://picsum.photos/seed/artist3/400/400',
      followers: '1.2M',
      following: 32,
    ),
    Artist(
      id: '4',
      name: 'Mono Sleep',
      role: 'Composer',
      imageUrl: 'https://picsum.photos/seed/artist4/400/400',
      followers: '540K',
      following: 5,
    ),
    Artist(
      id: '5',
      name: 'Pale 911',
      role: 'DJ, Producer',
      imageUrl: 'https://picsum.photos/seed/artist5/400/400',
      followers: '3.7M',
      following: 11,
      isVerified: true,
    ),
    Artist(
      id: '6',
      name: 'Betty & Bob D.',
      role: 'Duo',
      imageUrl: 'https://picsum.photos/seed/artist6/400/400',
      followers: '920K',
      following: 23,
    ),
    Artist(
      id: '7',
      name: 'Echo Bloom',
      role: 'Singer',
      imageUrl: 'https://picsum.photos/seed/artist7/400/400',
      followers: '650K',
      following: 18,
    ),
    Artist(
      id: '8',
      name: 'Silk Distance',
      role: 'Producer',
      imageUrl: 'https://picsum.photos/seed/artist8/400/400',
      followers: '4.2M',
      following: 9,
      isVerified: true,
    ),
  ];
}
