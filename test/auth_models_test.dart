import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/models/auth/auth_models.dart';

void main() {
  const user = {
    'id': 14,
    'name': 'John Doe',
    'email': 'agent@example.com',
    'phone': '+254712345678',
    'role': 'agent',
    'isSuperAdmin': false,
    'status': 'active',
    'activeWorkspace': {'id': 1, 'name': 'CRM System', 'slug': 'crm-system'},
    'workspaces': [
      {'id': 1, 'name': 'CRM System', 'slug': 'crm-system', 'role': 'agent'},
    ],
  };

  test('parses the documented login session', () {
    final session = AuthSession.fromLoginJson({
      'accessToken': '1|token',
      'tokenType': 'Bearer',
      'user': user,
    });

    expect(session.accessToken, '1|token');
    expect(session.user.id, '14');
    expect(session.user.activeWorkspace?.slug, 'crm-system');
    expect(session.user.workspaces.single.role, 'agent');
  });

  test('marks inactive agents as inactive', () {
    final agent = AuthUser.fromJson({...user, 'status': 'inactive'});

    expect(agent.isActive, isFalse);
  });
}
