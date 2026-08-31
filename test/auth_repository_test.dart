import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/models/auth/auth_models.dart';
import 'package:omnidesk_agent/services/api_service.dart';
import 'package:omnidesk_agent/services/auth_repository.dart';
import 'package:omnidesk_agent/services/device_metadata_service.dart';

class _AuthAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = switch (options.path) {
      '/auth/login' => {
          'accessToken': 'token-123',
          'tokenType': 'Bearer',
          'user': _userJson,
        },
      '/auth/me' => _userJson,
      _ => {'message': 'OK'},
    };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

class _FixedDeviceMetadataService extends DeviceMetadataService {
  @override
  Future<Map<String, String>> buildHeaders() async => const {
        'X-Device-Name': 'Test device',
        'X-Device-OS': 'test',
        'X-App-Version': '1.0.0',
        'X-App-Build': '1',
      };
}

const _userJson = <String, dynamic>{
  'id': 14,
  'name': 'John Doe',
  'email': 'agent@example.com',
  'phone': '+254712345678',
  'role': 'agent',
  'isSuperAdmin': false,
  'status': 'active',
  'activeWorkspace': {
    'id': 1,
    'name': 'CRM System',
    'slug': 'crm-system',
    'role': 'agent',
  },
  'workspaces': [
    {
      'id': 1,
      'name': 'CRM System',
      'slug': 'crm-system',
      'role': 'agent',
    },
  ],
};

void main() {
  test('auth repository uses every documented live endpoint', () async {
    final adapter = _AuthAdapter();
    final api = ApiService(
      baseUrl: 'https://api.example.test/api/v1',
      dio: Dio()..httpClientAdapter = adapter,
      readAccessToken: () => 'access-token',
      onUnauthorized: () async {},
    );
    final repository = AuthRepository(
      api: api,
      deviceMetadata: _FixedDeviceMetadataService(),
    );

    final login = await repository.login(
      email: 'agent@example.com',
      password: 'strong-password',
    );
    expect(login, isA<AuthSuccess<AuthSession>>());
    expect(adapter.requests[0].path, '/auth/login');
    expect(adapter.requests[0].data,
        {'email': 'agent@example.com', 'password': 'strong-password'});
    expect(adapter.requests[0].headers['Authorization'], isNull);
    expect(adapter.requests[0].headers['X-Device-Name'], 'Test device');

    expect(await repository.fetchMe(), isA<AuthSuccess<AuthUser>>());
    expect(adapter.requests[1].path, '/auth/me');
    expect(adapter.requests[1].headers['Authorization'], 'Bearer access-token');

    expect(await repository.forgotPassword('agent@example.com'),
        isA<AuthSuccess<void>>());
    expect(adapter.requests[2].path, '/auth/forgot-password');
    expect(adapter.requests[2].headers['Authorization'], isNull);

    expect(
      await repository.resetPassword(
        email: 'agent@example.com',
        token: 'reset-token',
        password: 'new-password',
      ),
      isA<AuthSuccess<void>>(),
    );
    expect(adapter.requests[3].path, '/auth/reset-password');
    expect(adapter.requests[3].data, {
      'email': 'agent@example.com',
      'token': 'reset-token',
      'password': 'new-password',
      'password_confirmation': 'new-password',
    });

    expect(
      await repository.changePassword(
        currentPassword: 'old-password',
        newPassword: 'new-password',
      ),
      isA<AuthSuccess<void>>(),
    );
    expect(adapter.requests[4].path, '/auth/change-password');
    expect(adapter.requests[4].headers['Authorization'], 'Bearer access-token');

    expect(await repository.logout(), isA<AuthSuccess<void>>());
    expect(adapter.requests[5].path, '/auth/logout');
    expect(await repository.logout(everywhere: true), isA<AuthSuccess<void>>());
    expect(adapter.requests[6].path, '/auth/logout-all');
  });
}
