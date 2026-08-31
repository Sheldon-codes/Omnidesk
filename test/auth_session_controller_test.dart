import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omnidesk_agent/models/auth/auth_models.dart';
import 'package:omnidesk_agent/services/api_service.dart';
import 'package:omnidesk_agent/services/auth_repository.dart';
import 'package:omnidesk_agent/services/auth_session_controller.dart';
import 'package:omnidesk_agent/services/auth_token_store.dart';

const _storedSession = AuthSession(
  accessToken: 'stored-token',
  tokenType: 'Bearer',
  user: AuthUser(
    id: '14',
    name: 'Stored Agent',
    email: 'stored@example.com',
    role: 'agent',
    isSuperAdmin: false,
    status: 'active',
    workspaces: [
      WorkspaceMembership(
        id: '1',
        name: 'CRM System',
        slug: 'crm-system',
        role: 'agent',
      ),
    ],
  ),
);

const _verifiedUser = AuthUser(
  id: '14',
  name: 'Verified Agent',
  email: 'verified@example.com',
  role: 'agent',
  isSuperAdmin: false,
  status: 'active',
);

class _MemoryTokenStore extends AuthTokenStore {
  _MemoryTokenStore({this.session});

  AuthSession? session;
  var clearCount = 0;

  @override
  Future<String?> readAccessToken() async => session?.accessToken;

  @override
  Future<AuthSession?> readSession() async => session;

  @override
  Future<void> saveSession(AuthSession value) async {
    session = value;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    session = null;
  }
}

class _StubAuthRepository extends AuthRepository {
  _StubAuthRepository({
    required this.fetchMeResult,
    this.loginResult,
  }) : super(
          api: ApiService(
            baseUrl: 'https://api.example.test/api/v1',
            dio: Dio(),
            readAccessToken: () => null,
            onUnauthorized: () async {},
          ),
        );

  AuthResult<AuthUser> fetchMeResult;
  AuthResult<AuthSession>? loginResult;

  @override
  Future<AuthResult<AuthUser>> fetchMe() async => fetchMeResult;

  @override
  Future<AuthResult<AuthSession>> login({
    required String email,
    required String password,
  }) async =>
      loginResult ??
      const AuthFailureResult(
        AuthFailure(type: AuthFailureType.unknown),
      );

  @override
  Future<AuthResult<void>> logout({bool everywhere = false}) async {
    return const AuthSuccess<void>(null);
  }
}

void main() {
  ProviderContainer containerFor({
    required _MemoryTokenStore store,
    required _StubAuthRepository repository,
  }) =>
      ProviderContainer(overrides: [
        authTokenStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(repository),
      ]);

  test('verified bootstrap refreshes identity and preserves login workspaces',
      () async {
    final store = _MemoryTokenStore(session: _storedSession);
    final container = containerFor(
      store: store,
      repository: _StubAuthRepository(
        fetchMeResult: const AuthSuccess(_verifiedUser),
      ),
    );
    addTearDown(container.dispose);

    await container.read(authSessionControllerProvider.notifier).bootstrap();
    final state = container.read(authSessionControllerProvider);

    expect(state.status, AuthStatus.authenticated);
    expect(state.isOffline, isFalse);
    expect(state.session!.user.name, 'Verified Agent');
    expect(state.session!.user.workspaces, hasLength(1));
    expect(store.session!.user.email, 'verified@example.com');
  });

  test('network bootstrap restores a previously verified cached session',
      () async {
    final store = _MemoryTokenStore(session: _storedSession);
    final container = containerFor(
      store: store,
      repository: _StubAuthRepository(
        fetchMeResult: const AuthFailureResult(
          AuthFailure(type: AuthFailureType.network, message: 'offline'),
        ),
      ),
    );
    addTearDown(container.dispose);

    await container.read(authSessionControllerProvider.notifier).bootstrap();
    final state = container.read(authSessionControllerProvider);

    expect(state.status, AuthStatus.authenticated);
    expect(state.isOffline, isTrue);
    expect(state.session, _storedSession);
  });

  test('expired bootstrap clears local credentials and becomes unauthenticated',
      () async {
    final store = _MemoryTokenStore(session: _storedSession);
    final container = containerFor(
      store: store,
      repository: _StubAuthRepository(
        fetchMeResult: const AuthFailureResult(
          AuthFailure(
            type: AuthFailureType.invalidCredentials,
            statusCode: 401,
          ),
        ),
      ),
    );
    addTearDown(container.dispose);

    await container.read(authSessionControllerProvider.notifier).bootstrap();

    expect(container.read(authSessionControllerProvider).status,
        AuthStatus.unauthenticated);
    expect(store.session, isNull);
    expect(store.clearCount, 1);
  });

  test('login persists the complete server session and invalidation is deduped',
      () async {
    final store = _MemoryTokenStore();
    final container = containerFor(
      store: store,
      repository: _StubAuthRepository(
        fetchMeResult: const AuthFailureResult(
          AuthFailure(type: AuthFailureType.network),
        ),
        loginResult: const AuthSuccess(_storedSession),
      ),
    );
    addTearDown(container.dispose);

    final controller = container.read(authSessionControllerProvider.notifier);
    expect(
      await controller.login(email: 'agent@example.com', password: 'password'),
      isNull,
    );
    expect(store.session, _storedSession);

    await Future.wait([
      controller.invalidateSession(),
      controller.invalidateSession(),
    ]);
    expect(store.clearCount, 1);
    expect(container.read(authSessionControllerProvider).status,
        AuthStatus.unauthenticated);
  });
}
