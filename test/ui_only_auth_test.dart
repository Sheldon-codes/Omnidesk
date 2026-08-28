import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/models/auth/auth_models.dart';
import 'package:omnidesk_agent/services/auth_repository.dart';

void main() {
  test('UI-only auth repository completes locally without an API client',
      () async {
    final repository = AuthRepository();

    final login = await repository.login(
      email: 'agent@example.com',
      password: 'valid-password',
    );
    final currentUser = await repository.fetchMe();
    final forgot = await repository.forgotPassword('agent@example.com');
    final reset = await repository.resetPassword(
      email: 'agent@example.com',
      token: 'demo-code',
      password: 'valid-password',
    );
    final change = await repository.changePassword(
      currentPassword: 'old-password',
      newPassword: 'valid-password',
    );
    final logout = await repository.logout();

    expect(login, isA<AuthSuccess<AuthSession>>());
    expect(currentUser, isA<AuthSuccess<AuthUser>>());
    expect(forgot, isA<AuthSuccess<void>>());
    expect(reset, isA<AuthSuccess<void>>());
    expect(change, isA<AuthSuccess<void>>());
    expect(logout, isA<AuthSuccess<void>>());
  });
}
