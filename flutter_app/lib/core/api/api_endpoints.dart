class ApiEndpoints {
  static const session = '/api/v1/auth/session';
  static const me = '/api/v1/users/me';
  static const account = '/api/v1/account';
  static const onboarding = '/api/v1/onboarding';
  static const onboardingLanguages = '/api/v1/onboarding/languages';
  static const onboardingArtists = '/api/v1/onboarding/artists';
  static const onboardingSuggestedArtists =
      '/api/v1/onboarding/artists/suggested';
  static const home = '/api/v1/home';
  static const search = '/api/v1/search';
  static const searchEvents = '/api/v1/search/events';
  static const songs = '/api/v1/songs';
  static const artists = '/api/v1/artists';
  static const albums = '/api/v1/albums';
  static const libraryLikes = '/api/v1/library/likes';
  static const libraryArtists = '/api/v1/library/artists';
  static const playlists = '/api/v1/playlists';
  static const historyListens = '/api/v1/history/listens';
  static const historyEvents = '/api/v1/history/events';
  static const historyRecent = '/api/v1/history/recent';
  static const recommendations = '/api/v1/recommendations';
  static const preferences = '/api/v1/preferences';
  static const preferenceLanguages = '/api/v1/preferences/languages';
  static const preferenceArtists = '/api/v1/preferences/artists';
  static const settings = '/api/v1/settings';
  static const settingsGeneral = '/api/v1/settings/general';
  static const settingsPlayback = '/api/v1/settings/playback';
  static const settingsDownloads = '/api/v1/settings/downloads';
  static const settingsRecommendations = '/api/v1/settings/recommendations';
  static const settingsNotifications = '/api/v1/settings/notifications';
  static const settingsPrivacy = '/api/v1/settings/privacy';
  static const settingsReset = '/api/v1/settings/reset';
  static const clearListeningHistory =
      '/api/v1/settings/history/listening/clear';
  static const clearSearchHistory = '/api/v1/settings/history/search/clear';
  static const resetRecommendations = '/api/v1/settings/recommendations/reset';
  static const devices = '/api/v1/devices';
}
