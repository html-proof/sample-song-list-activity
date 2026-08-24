import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:music_hub_app/core/api/api_exception.dart';
import 'package:music_hub_app/core/api/auth_interceptor.dart';
import 'package:music_hub_app/core/config/app_config.dart';

class ApiClient {
  ApiClient(FirebaseAuth auth)
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 15),
          contentType: Headers.jsonContentType,
        ),
      )..interceptors.add(AuthInterceptor(auth));

  final Dio dio;

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    try {
      return (await dio.get<dynamic>(
        path,
        queryParameters: query,
        cancelToken: cancelToken,
      )).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    try {
      return _asMap(await get(path, query: query, cancelToken: cancelToken));
    } on ApiException {
      rethrow;
    }
  }

  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    try {
      return (await dio.post<dynamic>(
        path,
        data: data,
        options: Options(headers: headers),
      )).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<dynamic> put(String path, {Object? data}) async {
    try {
      return (await dio.put<dynamic>(path, data: data)).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<dynamic> patch(String path, {Object? data}) async {
    try {
      return (await dio.patch<dynamic>(path, data: data)).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> delete(String path, {Map<String, dynamic>? query}) async {
    try {
      await dio.delete<dynamic>(path, queryParameters: query);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    throw const ApiException('The server returned an unexpected response');
  }
}
