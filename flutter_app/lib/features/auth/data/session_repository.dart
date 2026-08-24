import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/shared/models/app_user.dart';

class SessionRepository {
  SessionRepository(this._api);

  final ApiClient _api;
  AppUser? _currentUser;
  Future<AppUser>? _pending;

  AppUser? get currentUser => _currentUser;

  Future<AppUser> synchronize({bool force = false}) {
    if (!force && _currentUser != null) {
      return Future.value(_currentUser);
    }
    if (!force && _pending != null) return _pending!;
    final request = _synchronize();
    _pending = request;
    return request.whenComplete(() {
      if (identical(_pending, request)) _pending = null;
    });
  }

  Future<AppUser> _synchronize() async {
    final result = await _api.post(ApiEndpoints.session);
    if (result is! Map) throw StateError('Invalid session response');
    final user = AppUser.fromJson(result.cast<String, dynamic>());
    _currentUser = user;
    return user;
  }

  void clear() {
    _currentUser = null;
    _pending = null;
  }
}
