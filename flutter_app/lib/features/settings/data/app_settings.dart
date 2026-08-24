class AppSettings {
  const AppSettings({
    required this.general,
    required this.playback,
    required this.downloads,
    required this.recommendations,
    required this.notifications,
    required this.privacy,
  });

  factory AppSettings.defaults() => const AppSettings(
    general: {
      'app_language': 'en',
      'theme_mode': 'system',
      'dynamic_artwork_colors': true,
      'animations_enabled': true,
    },
    playback: {
      'streaming_quality': 'auto',
      'mobile_streaming_quality': 'medium',
      'wifi_streaming_quality': 'high',
      'autoplay': true,
      'normalize_volume': true,
      'gapless_playback': true,
      'crossfade_seconds': 0,
      'explicit_content': true,
      'auto_resume': true,
      'repeat_mode': 'off',
    },
    downloads: {
      'quality': 'high',
      'wifi_only': true,
      'auto_download_liked': false,
      'auto_download_playlists': false,
      'delete_played_after_days': null,
    },
    recommendations: {
      'enabled': true,
      'use_listening_history': true,
      'use_search_history': true,
      'use_likes': true,
      'cross_language_discovery': true,
      'discover_new_artists': true,
      'exploration_level': 20,
      'diversity_level': 50,
    },
    notifications: {
      'enabled': true,
      'artist_releases': true,
      'new_music': true,
      'recommendations': true,
      'playlist_updates': true,
      'download_complete': true,
      'headphone_health': true,
    },
    privacy: {
      'save_listening_history': true,
      'save_search_history': true,
      'personalized_recommendations': true,
      'analytics_enabled': true,
    },
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    return AppSettings(
      general: _merged(defaults.general, json['general']),
      playback: _merged(defaults.playback, json['playback']),
      downloads: _merged(defaults.downloads, json['downloads']),
      recommendations: _merged(
        defaults.recommendations,
        json['recommendations'],
      ),
      notifications: _merged(defaults.notifications, json['notifications']),
      privacy: _merged(defaults.privacy, json['privacy']),
    );
  }

  final Map<String, dynamic> general;
  final Map<String, dynamic> playback;
  final Map<String, dynamic> downloads;
  final Map<String, dynamic> recommendations;
  final Map<String, dynamic> notifications;
  final Map<String, dynamic> privacy;

  Map<String, dynamic> group(String name) => switch (name) {
    'general' => general,
    'playback' => playback,
    'downloads' => downloads,
    'recommendations' => recommendations,
    'notifications' => notifications,
    'privacy' => privacy,
    _ => throw ArgumentError.value(name, 'name', 'Unknown settings group'),
  };

  AppSettings mergeGroup(String name, Map<String, dynamic> changes) {
    final next = {...group(name), ...changes};
    return AppSettings(
      general: name == 'general' ? next : general,
      playback: name == 'playback' ? next : playback,
      downloads: name == 'downloads' ? next : downloads,
      recommendations: name == 'recommendations' ? next : recommendations,
      notifications: name == 'notifications' ? next : notifications,
      privacy: name == 'privacy' ? next : privacy,
    );
  }

  Map<String, dynamic> toJson() => {
    'general': general,
    'playback': playback,
    'downloads': downloads,
    'recommendations': recommendations,
    'notifications': notifications,
    'privacy': privacy,
  };

  static Map<String, dynamic> _merged(
    Map<String, dynamic> defaults,
    Object? value,
  ) {
    if (value is! Map) return {...defaults};
    return {
      ...defaults,
      ...value.map((key, item) => MapEntry(key.toString(), item)),
    };
  }
}
