enum StartupDestination { splash, login, onboarding, home }

extension StartupDestinationRoute on StartupDestination {
  String get location => switch (this) {
    StartupDestination.splash => '/splash',
    StartupDestination.login => '/login',
    StartupDestination.onboarding => '/onboarding/languages',
    StartupDestination.home => '/home',
  };
}
