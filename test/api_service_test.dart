import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/services/api_service.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('Dio attaches auth and custom headers through ApiService', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final api = ApiService(
      baseUrl: 'https://api.example.test',
      dio: dio,
      readAccessToken: () => 'access-token',
      onUnauthorized: () async {},
    );

    await api.get('/private');
    await api.post(
      '/public',
      {'email': 'agent@example.com'},
      requiresAuth: false,
      headers: {'X-Device-OS': 'test'},
    );

    expect(adapter.requests[0].headers['Authorization'], 'Bearer access-token');
    expect(adapter.requests[1].headers['Authorization'], isNull);
    expect(adapter.requests[1].headers['X-Device-OS'], 'test');
  });

  test('diagnostic redaction protects sensitive headers and payload fields',
      () {
    final redacted = ApiService.redactForDiagnostics({
      'Authorization': 'Bearer secret',
      'nested': {
        'password': 'hunter2',
        'safe': 'visible',
      },
    }) as Map;

    expect(redacted['Authorization'], '[REDACTED]');
    expect((redacted['nested'] as Map)['password'], '[REDACTED]');
    expect((redacted['nested'] as Map)['safe'], 'visible');
  });

  test('Dio failures map to ApiClientException', () {
    final exception = ApiClientException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/private'),
        type: DioExceptionType.connectionTimeout,
        message: 'timed out',
      ),
    );

    expect(exception.isNetworkError, isTrue);
    expect(exception.message, 'timed out');
  });
}
