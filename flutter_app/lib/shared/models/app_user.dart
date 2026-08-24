class AppUser {
  const AppUser({
    required this.id,
    required this.onboardingCompleted,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  final String id;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final bool onboardingCompleted;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final body = json['user'] is Map
        ? (json['user'] as Map).cast<String, dynamic>()
        : json;
    return AppUser(
      id: body['id']?.toString() ?? '',
      displayName: (body['display_name'] ?? body['name'])?.toString(),
      email: body['email']?.toString(),
      photoUrl: body['photo_url']?.toString(),
      onboardingCompleted: body['onboarding_completed'] == true,
    );
  }
}
