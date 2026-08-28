import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth/auth_models.dart';
import 'api_service.dart';
import 'app_runtime_config.dart';
import 'device_metadata_service.dart';

part 'auth_repository.g.dart';

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) => AuthRepository(
      api: uiOnlyMode ? null : ref.watch(apiServiceProvider),
      deviceMetadata:
          uiOnlyMode ? null : ref.watch(deviceMetadataServiceProvider),
    );

class AuthRepository {
  AuthRepository({ApiService? api, DeviceMetadataService? deviceMetadata})
      : _api = api,
        _deviceMetadata = deviceMetadata ?? DeviceMetadataService();
  final ApiService? _api;
  final DeviceMetadataService _deviceMetadata;

  Future<AuthResult<AuthSession>> login(
          {required String email, required String password}) =>
      uiOnlyMode
          ? Future<AuthResult<AuthSession>>.value(
              AuthSuccess(_demoSession(email)))
          : _run(() async {
              final response = await _api!.post(
                  '/auth/login', {'email': email, 'password': password},
                  requiresAuth: false,
                  headers: await _deviceMetadata.buildHeaders());
              if (response is! Map) {
                throw const FormatException('Invalid login response.');
              }
              return AuthSession.fromLoginJson(response
                  .map((key, value) => MapEntry(key.toString(), value)));
            });

  Future<AuthResult<AuthUser>> fetchMe() => uiOnlyMode
      ? Future<AuthResult<AuthUser>>.value(const AuthSuccess(_demoUser))
      : _run(() async {
          final response = await _api!.get('/auth/me');
          if (response is! Map) {
            throw const FormatException('Invalid user response.');
          }
          return AuthUser.fromJson(
              response.map((key, value) => MapEntry(key.toString(), value)));
        });

  Future<AuthResult<void>> logout({bool everywhere = false}) => uiOnlyMode
      ? Future<AuthResult<void>>.value(const AuthSuccess<void>(null))
      : _run(() async {
          await _api!
              .post(everywhere ? '/auth/logout-all' : '/auth/logout', const {});
        });

  Future<AuthResult<void>> forgotPassword(String email) => uiOnlyMode
      ? Future<AuthResult<void>>.value(const AuthSuccess<void>(null))
      : _run(() async {
          await _api!.post('/auth/forgot-password', {'email': email},
              requiresAuth: false);
        });

  Future<AuthResult<void>> resetPassword(
          {required String email,
          required String token,
          required String password}) =>
      uiOnlyMode
          ? Future<AuthResult<void>>.value(const AuthSuccess<void>(null))
          : _run(() async {
              await _api!.post(
                  '/auth/reset-password',
                  {
                    'email': email,
                    'token': token,
                    'password': password,
                    'password_confirmation': password
                  },
                  requiresAuth: false);
            });

  Future<AuthResult<void>> changePassword(
          {required String currentPassword, required String newPassword}) =>
      uiOnlyMode
          ? Future<AuthResult<void>>.value(const AuthSuccess<void>(null))
          : _run(() async {
              await _api!.post('/auth/change-password', {
                'current_password': currentPassword,
                'new_password': newPassword,
                'new_password_confirmation': newPassword
              });
            });

  static const _demoUser = AuthUser(
    id: 'demo-user',
    name: 'Demo Agent',
    email: 'demo@omnidesk.local',
    role: 'agent',
    isSuperAdmin: false,
    status: 'active',
  );

  static AuthSession _demoSession(String email) => AuthSession(
        accessToken: 'ui-only-demo-token',
        tokenType: 'Bearer',
        user: AuthUser(
          id: _demoUser.id,
          name: _demoUser.name,
          email: email.isEmpty ? _demoUser.email : email,
          role: _demoUser.role,
          isSuperAdmin: _demoUser.isSuperAdmin,
          status: _demoUser.status,
        ),
      );

  Future<AuthResult<T>> _run<T>(Future<T> Function() operation) async {
    try {
      return AuthSuccess(await operation());
    } catch (error) {
      return AuthFailureResult(_toFailure(error));
    }
  }

  AuthFailure _toFailure(Object error) {
    if (error is FormatException) {
      return AuthFailure(
          type: AuthFailureType.protocol, message: error.message);
    }
    if (error is! ApiClientException) {
      return AuthFailure(type: AuthFailureType.unknown);
    }
    if (error.isNetworkError) {
      return AuthFailure(
          type: AuthFailureType.network,
          message: error.message,
          statusCode: error.statusCode);
    }
    return switch (error.statusCode) {
      401 => AuthFailure(
          type: AuthFailureType.invalidCredentials,
          message: error.message,
          statusCode: 401),
      403 => AuthFailure(
          type: AuthFailureType.accountInactive,
          message: error.message,
          statusCode: 403),
      _ => AuthFailure(
          type: AuthFailureType.unknown,
          message: error.message,
          statusCode: error.statusCode),
    };
  }
}
