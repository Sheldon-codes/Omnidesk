import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth/auth_models.dart';
import 'auth_repository.dart';
import 'auth_token_store.dart';

part 'auth_session_controller.g.dart';

enum AuthStatus {
  bootstrapping,
  unauthenticated,
  authenticated,
  loading,
  error
}

class AuthState {
  const AuthState({
    this.status = AuthStatus.bootstrapping,
    this.session,
    this.failure,
    this.bootstrapComplete = false,
    this.isOffline = false,
  });

  final AuthStatus status;
  final AuthSession? session;
  final AuthFailure? failure;
  final bool bootstrapComplete;
  final bool isOffline;

  String? get accessToken => session?.accessToken;
  bool get isAuthenticated =>
      status == AuthStatus.authenticated && session != null;

  AuthState copyWith({
    AuthStatus? status,
    AuthSession? session,
    AuthFailure? failure,
    bool clearSession = false,
    bool clearFailure = false,
    bool? bootstrapComplete,
    bool? isOffline,
  }) =>
      AuthState(
        status: status ?? this.status,
        session: clearSession ? null : (session ?? this.session),
        failure: clearFailure ? null : (failure ?? this.failure),
        bootstrapComplete: bootstrapComplete ?? this.bootstrapComplete,
        isOffline: isOffline ?? this.isOffline,
      );
}

@Riverpod(keepAlive: true)
class AuthSessionController extends _$AuthSessionController {
  Future<void>? _bootstrapFuture;
  Future<void>? _refreshFuture;
  Future<void>? _invalidationFuture;

  @override
  AuthState build() {
    Future.microtask(bootstrap);
    return const AuthState();
  }

  Future<void> bootstrap() {
    final existing = _bootstrapFuture;
    if (existing != null) return existing;
    final task = _bootstrap();
    _bootstrapFuture = task;
    task.whenComplete(() {
      if (identical(_bootstrapFuture, task)) _bootstrapFuture = null;
    });
    return task;
  }

  Future<void> _bootstrap() async {
    state = const AuthState(status: AuthStatus.bootstrapping);
    try {
      final store = ref.read(authTokenStoreProvider);
      final cachedSession = await store.readSession();
      final token = cachedSession?.accessToken ?? await store.readAccessToken();
      if (token == null || token.isEmpty) {
        state = const AuthState(
          status: AuthStatus.unauthenticated,
          bootstrapComplete: true,
        );
        return;
      }

      final provisionalSession = cachedSession ?? _placeholderSession(token);
      state =
          AuthState(status: AuthStatus.loading, session: provisionalSession);
      final result = await ref.read(authRepositoryProvider).fetchMe();
      switch (result) {
        case AuthSuccess<AuthUser>(value: final user):
          final verifiedSession = provisionalSession.withUser(user);
          await store.saveSession(verifiedSession);
          state = AuthState(
            status: AuthStatus.authenticated,
            session: verifiedSession,
            bootstrapComplete: true,
          );
        case AuthFailureResult<AuthUser>(failure: final failure):
          await _applyBootstrapFailure(failure, cachedSession);
      }
    } catch (_) {
      state = const AuthState(
        status: AuthStatus.error,
        failure: AuthFailure(
          type: AuthFailureType.unknown,
          message: 'Unable to restore your saved session.',
        ),
        bootstrapComplete: true,
      );
    }
  }

  Future<void> _applyBootstrapFailure(
    AuthFailure failure,
    AuthSession? cachedSession,
  ) async {
    if (failure.statusCode == 401 || failure.statusCode == 403) {
      await _clearLocalSession();
      return;
    }
    if (failure.type == AuthFailureType.network && cachedSession != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        session: cachedSession,
        failure: failure,
        bootstrapComplete: true,
        isOffline: true,
      );
      return;
    }
    state = AuthState(
      status: AuthStatus.error,
      failure: failure,
      bootstrapComplete: true,
    );
  }

  Future<AuthFailure?> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(
      status: AuthStatus.loading,
      clearSession: true,
      clearFailure: true,
      bootstrapComplete: true,
      isOffline: false,
    );
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
    try {
      await ref.read(authTokenStoreProvider).saveSession(session);
      state = AuthState(
        status: AuthStatus.authenticated,
        session: session,
        bootstrapComplete: true,
      );
      return null;
    } catch (_) {
      return _fail(const AuthFailure(
        type: AuthFailureType.unknown,
        message: 'Unable to securely save your session. Please try again.',
      ));
    }
  }

  AuthFailure _fail(AuthFailure failure) {
    state = AuthState(
      status: AuthStatus.error,
      failure: failure,
      bootstrapComplete: true,
    );
    return failure;
  }

  Future<void> refreshSession() {
    final currentSession = state.session;
    if (!state.isAuthenticated || currentSession == null) {
      return Future.value();
    }
    final existing = _refreshFuture;
    if (existing != null) return existing;
    final task = _refresh(currentSession);
    _refreshFuture = task;
    task.whenComplete(() {
      if (identical(_refreshFuture, task)) _refreshFuture = null;
    });
    return task;
  }

  Future<void> _refresh(AuthSession currentSession) async {
    final result = await ref.read(authRepositoryProvider).fetchMe();
    switch (result) {
      case AuthSuccess<AuthUser>(value: final user):
        final verifiedSession = currentSession.withUser(user);
        try {
          await ref.read(authTokenStoreProvider).saveSession(verifiedSession);
          state = state.copyWith(
            status: AuthStatus.authenticated,
            session: verifiedSession,
            clearFailure: true,
            isOffline: false,
          );
        } catch (_) {
          state = state.copyWith(
            failure: const AuthFailure(
              type: AuthFailureType.unknown,
              message: 'Unable to securely update your session.',
            ),
          );
        }
      case AuthFailureResult<AuthUser>(failure: final failure):
        if (failure.statusCode == 401 || failure.statusCode == 403) {
          await invalidateSession();
        } else {
          state = state.copyWith(
            failure: failure,
            isOffline: failure.type == AuthFailureType.network,
          );
        }
    }
  }

  Future<void> logout({bool everywhere = false}) async {
    try {
      await ref.read(authRepositoryProvider).logout(everywhere: everywhere);
    } finally {
      await invalidateSession();
    }
  }

  Future<void> setActiveWorkspace(WorkspaceMembership workspace) async {
    final current = state.session;
    if (current == null) return;
    final updated = current.withActiveWorkspace(workspace);
    await ref.read(authTokenStoreProvider).saveSession(updated);
    state = state.copyWith(session: updated, clearFailure: true);
  }

  Future<void> invalidateSession() {
    final existing = _invalidationFuture;
    if (existing != null) return existing;
    final task = _clearLocalSession();
    _invalidationFuture = task;
    task.whenComplete(() {
      if (identical(_invalidationFuture, task)) _invalidationFuture = null;
    });
    return task;
  }

  Future<void> _clearLocalSession() async {
    try {
      await ref.read(authTokenStoreProvider).clear();
    } catch (_) {
      // The in-memory auth state must still be invalidated if secure storage
      // is temporarily unavailable. A later login can repair persistence.
    } finally {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        bootstrapComplete: true,
      );
    }
  }

  AuthSession _placeholderSession(String token) => AuthSession(
        accessToken: token,
        tokenType: 'Bearer',
        user: const AuthUser(
          id: '',
          name: '',
          email: '',
          role: 'agent',
          isSuperAdmin: false,
          status: 'active',
        ),
      );
}
