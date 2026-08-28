import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_session_controller.dart';

part 'api_service.g.dart';

@Riverpod(keepAlive: true)
ApiService apiService(Ref ref) => ApiService(
      baseUrl: dotenv.env['API_BASE_URL'] ?? '',
      readAccessToken: () =>
          ref.read(authSessionControllerProvider).accessToken,
      onUnauthorized: () =>
          ref.read(authSessionControllerProvider.notifier).invalidateSession(),
    );

class ApiService {
  ApiService({
    required this.baseUrl,
    required String? Function() readAccessToken,
    required Future<void> Function() onUnauthorized,
    Dio? dio,
  })  : _readAccessToken = readAccessToken,
        _onUnauthorized = onUnauthorized,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {
                'Accept': 'application/json',
                'Content-Type': 'application/json'
              },
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.extra['_startedAt'] = Stopwatch()..start();
        if (options.extra['skipAuth'] != true) {
          final token = _readAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        if (_diagnosticsEnabled) {
          developer.log(_formatRequest(options), name: 'ApiService');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (_diagnosticsEnabled) {
          developer.log(_formatResponse(response), name: 'ApiService');
        }
        handler.next(response);
      },
      onError: (error, handler) async {
        if (_diagnosticsEnabled) {
          developer.log(_formatError(error), name: 'ApiService', error: error);
        }
        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra['skipAuth'] != true &&
            error.requestOptions.extra['sessionInvalidated'] != true) {
          error.requestOptions.extra['sessionInvalidated'] = true;
          await _onUnauthorized();
        }
        handler.next(error);
      },
    ));
  }

  final Dio _dio;
  final String baseUrl;
  final String? Function() _readAccessToken;
  final Future<void> Function() _onUnauthorized;

  static bool get _diagnosticsEnabled => kDebugMode || kProfileMode;

  @visibleForTesting
  static dynamic redactForDiagnostics(dynamic value) => _redactPayload(value);

  String _formatRequest(RequestOptions options) =>
      'REQUEST ${options.method} ${options.uri}\n'
      'Headers: ${_stringify(_redactHeaders(options.headers))}\n'
      'Body: ${_stringify(_redactPayload(options.data))}';

  String _formatResponse(Response<dynamic> response) {
    final elapsed = _elapsed(response.requestOptions);
    return 'RESPONSE ${response.statusCode} '
        '${response.requestOptions.method} ${response.requestOptions.uri} '
        '(${elapsed}ms)\n'
        'Headers: ${_stringify(_redactHeaders(response.headers.map))}\n'
        'Body: ${_stringify(_redactPayload(response.data))}';
  }

  String _formatError(DioException error) {
    final response = error.response;
    final elapsed = _elapsed(error.requestOptions);
    return 'ERROR ${error.requestOptions.method} '
        '${error.requestOptions.uri} (${elapsed}ms)\n'
        'Type: ${error.type}\n'
        'Status: ${response?.statusCode}\n'
        'Request headers: '
        '${_stringify(_redactHeaders(error.requestOptions.headers))}\n'
        'Request body: '
        '${_stringify(_redactPayload(error.requestOptions.data))}\n'
        'Response headers: '
        '${_stringify(response == null ? null : _redactHeaders(response.headers.map))}\n'
        'Response body: '
        '${_stringify(_redactPayload(response?.data))}\n'
        'Message: ${error.message}';
  }

  int _elapsed(RequestOptions options) {
    final stopwatch = options.extra['_startedAt'];
    if (stopwatch is Stopwatch) {
      if (stopwatch.isRunning) stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    }
    return 0;
  }

  Future<dynamic> get(String path,
          {Map<String, dynamic>? queryParameters, bool requiresAuth = true}) =>
      _request(() => _dio.get(path,
          queryParameters: queryParameters, options: _options(requiresAuth)));
  Future<dynamic> post(String path, Map<String, dynamic> body,
          {bool requiresAuth = true, Map<String, String>? headers}) =>
      _request(() => _dio.post(path,
          data: body, options: _options(requiresAuth, headers)));
  Future<dynamic> put(String path, Map<String, dynamic> body,
          {bool requiresAuth = true}) =>
      _request(
          () => _dio.put(path, data: body, options: _options(requiresAuth)));
  Future<dynamic> patch(String path, Map<String, dynamic> body,
          {bool requiresAuth = true}) =>
      _request(
          () => _dio.patch(path, data: body, options: _options(requiresAuth)));
  Future<dynamic> delete(String path,
          {Map<String, dynamic>? body, bool requiresAuth = true}) =>
      _request(
          () => _dio.delete(path, data: body, options: _options(requiresAuth)));

  Options _options(bool requiresAuth, [Map<String, String>? headers]) =>
      Options(headers: headers, extra: {'skipAuth': !requiresAuth});
  Future<dynamic> _request(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (error) {
      throw ApiClientException.fromDio(error);
    }
  }

  static Map<String, dynamic> _redactHeaders(Map<String, dynamic>? headers) {
    if (headers == null) return <String, dynamic>{};
    return headers.map(
      (key, value) => MapEntry(
        key,
        _isSensitiveKey(key) ? '[REDACTED]' : _redactPayload(value),
      ),
    );
  }

  static dynamic _redactPayload(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, nestedValue) => MapEntry(
          key,
          _isSensitiveKey(key.toString())
              ? '[REDACTED]'
              : _redactPayload(nestedValue),
        ),
      );
    }
    if (value is Iterable) {
      return value.map(_redactPayload).toList(growable: false);
    }
    return value;
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[-_]'), '');
    return normalized == 'authorization' ||
        normalized == 'cookie' ||
        normalized == 'setcookie' ||
        normalized.contains('password') ||
        normalized.contains('secret') ||
        normalized.contains('token') ||
        normalized.contains('apikey');
  }

  static String _stringify(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return value;
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}

class ApiClientException implements Exception {
  const ApiClientException(
      {required this.message,
      this.statusCode,
      this.code,
      this.data,
      this.isNetworkError = false});
  final String message;
  final int? statusCode;
  final String? code;
  final dynamic data;
  final bool isNetworkError;
  factory ApiClientException.fromDio(DioException error) {
    final data = error.response?.data;
    final map = data is Map ? data : null;
    return ApiClientException(
      message: (map?['message'] ??
              map?['error'] ??
              map?['detail'] ??
              error.message ??
              'Request failed')
          .toString(),
      statusCode: error.response?.statusCode,
      code: (map?['code'] ?? map?['error_code'])?.toString(),
      data: data,
      isNetworkError: const {
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.unknown
      }.contains(error.type),
    );
  }
}
