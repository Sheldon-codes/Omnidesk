import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

part 'auth_token_store.g.dart';

@Riverpod(keepAlive: true)
AuthTokenStore authTokenStore(Ref ref) => AuthTokenStore();

class AuthTokenStore {
  AuthTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  static const _accessTokenKey = 'omnidesk_access_token';
  final FlutterSecureStorage _storage;
  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);
  Future<void> clear() => _storage.delete(key: _accessTokenKey);
}
