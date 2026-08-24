import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._auth);

  final FirebaseAuth _auth;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final user = _auth.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    options.headers['Accept'] = 'application/json';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final user = _auth.currentUser;
    if (err.response?.statusCode != 401 ||
        request.extra['firebase_token_refreshed'] == true ||
        user == null) {
      handler.next(err);
      return;
    }
    try {
      final token = await user.getIdToken(true);
      if (token == null) {
        handler.next(err);
        return;
      }
      request.extra['firebase_token_refreshed'] = true;
      request.headers['Authorization'] = 'Bearer $token';
      final response = await Dio().fetch<dynamic>(request);
      handler.resolve(response);
    } catch (_) {
      handler.next(err);
    }
  }
}
