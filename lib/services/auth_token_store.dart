import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth/auth_models.dart';

part 'auth_token_store.g.dart';

@Riverpod(keepAlive: true)
AuthTokenStore authTokenStore(Ref ref) => AuthTokenStore();

class AuthTokenStore {
  AuthTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  static const _accessTokenKey = 'omnidesk_access_token';
  static const _sessionKey = 'omnidesk_authenticated_session';
  final FlutterSecureStorage _storage;

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  Future<void> saveSession(AuthSession session) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));
    await saveAccessToken(session.accessToken);
  }

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<AuthSession?> readSession() async {
    final values = await Future.wait([
      readAccessToken(),
      _storage.read(key: _sessionKey),
    ]);
    final token = values[0];
    final rawSession = values[1];
    if (token == null || token.isEmpty || rawSession == null) return null;
    try {
      final decoded = jsonDecode(rawSession);
      if (decoded is! Map) return null;
      final stored = AuthSession.fromStoredJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      return AuthSession(
        accessToken: token,
        tokenType: stored.tokenType,
        user: stored.user,
      );
    } on FormatException {
      return null;
    } on Object {
      return null;
    }
  }

  Future<void> clear() => Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _sessionKey),
      ]);
}
