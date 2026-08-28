import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth/auth_models.dart';
import 'auth_repository.dart';
import 'auth_token_store.dart';
import 'app_runtime_config.dart';

part 'auth_session_controller.g.dart';

enum AuthStatus {
  bootstrapping,
  unauthenticated,
  authenticated,
  loading,
  error
}

class AuthState {
  const AuthState(
      {this.status = AuthStatus.bootstrapping, this.session, this.failure});
  final AuthStatus status;
  final AuthSession? session;
  final AuthFailure? failure;
  String? get accessToken => session?.accessToken;
  bool get isAuthenticated =>
      status == AuthStatus.authenticated && session != null;
  AuthState copyWith(
          {AuthStatus? status,
          AuthSession? session,
          AuthFailure? failure,
          bool clearSession = false,
          bool clearFailure = false}) =>
      AuthState(
        status: status ?? this.status,
        session: clearSession ? null : (session ?? this.session),
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

@Riverpod(keepAlive: true)
class AuthSessionController extends _$AuthSessionController {
  static const _demoAccessToken = 'ui-only-demo-token';

  @override
  AuthState build() {
    Future.microtask(bootstrap);
    return const AuthState();
  }

  Future<void> bootstrap() async {
    state = const AuthState(status: AuthStatus.bootstrapping);
    final token = await ref.read(authTokenStoreProvider).readAccessToken();
    if (token == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    if (uiOnlyMode) {
      state = AuthState(
        status: AuthStatus.authenticated,
        session: _demoSession,
      );
      return;
    }
    state = AuthState(
        status: AuthStatus.loading,
        session: AuthSession(
            accessToken: token,
            tokenType: 'Bearer',
            user: const AuthUser(
                id: '',
                name: '',
                email: '',
                role: 'agent',
                isSuperAdmin: false,
                status: 'active')));
    final result = await ref.read(authRepositoryProvider).fetchMe();
    switch (result) {
      case AuthSuccess<AuthUser>(value: final user):
        state = AuthState(
            status: AuthStatus.authenticated,
            session: state.session!.withUser(user));
      case AuthFailureResult<AuthUser>(failure: final failure):
        if (failure.statusCode == 401 || failure.statusCode == 403) {
          await ref.read(authTokenStoreProvider).clear();
          state = const AuthState(status: AuthStatus.unauthenticated);
        } else {
          state = AuthState(status: AuthStatus.error, failure: failure);
        }
    }
  }

  Future<AuthFailure?> login(
      {required String email, required String password}) async {
    state = const AuthState(status: AuthStatus.loading);
    if (uiOnlyMode) {
      await ref.read(authTokenStoreProvider).saveAccessToken(_demoAccessToken);
      state =
          AuthState(status: AuthStatus.authenticated, session: _demoSession);
      return null;
    }
    final result = await ref
        .read(authRepositoryProvider)
        .login(email: email, password: password);
    return switch (result) {
      AuthSuccess<AuthSession>(value: final session) =>
        await _completeLogin(session),
      AuthFailureResult<AuthSession>(failure: final failure) => _fail(failure),
    };
  }

  Future<AuthFailure?> _completeLogin(AuthSession session) async {
    await ref.read(authTokenStoreProvider).saveAccessToken(session.accessToken);
    state = AuthState(status: AuthStatus.authenticated, session: session);
    return null;
  }

  AuthFailure _fail(AuthFailure failure) {
    state = AuthState(status: AuthStatus.error, failure: failure);
    return failure;
  }

  static final _demoSession = AuthSession(
    accessToken: _demoAccessToken,
    tokenType: 'Bearer',
    user: const AuthUser(
      id: 'demo-user',
      name: 'Demo Agent',
      email: 'demo@omnidesk.local',
      role: 'agent',
      isSuperAdmin: false,
      status: 'active',
    ),
  );

  Future<void> logout({bool everywhere = false}) async {
    if (!uiOnlyMode) {
      await ref.read(authRepositoryProvider).logout(everywhere: everywhere);
    }
    await ref.read(authTokenStoreProvider).clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> invalidateSession() async {
    if (state.status == AuthStatus.unauthenticated) return;
    await ref.read(authTokenStoreProvider).clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}
