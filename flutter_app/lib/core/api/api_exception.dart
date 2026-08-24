import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  factory ApiException.fromDio(DioException error) {
    final data = error.response?.data;
    final errorBody = data is Map ? data['error'] : null;
    final detail = data is Map ? data['detail'] : null;
    return ApiException(
      errorBody is Map
          ? (errorBody['message']?.toString() ?? 'Request failed')
          : detail?.toString() ??
                (error.type == DioExceptionType.connectionError
                    ? 'Unable to reach Music Hub'
                    : 'Request failed'),
      statusCode: error.response?.statusCode,
      code: errorBody is Map ? errorBody['code']?.toString() : null,
    );
  }

  @override
  String toString() => message;
}
