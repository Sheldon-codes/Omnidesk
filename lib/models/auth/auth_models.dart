enum AuthFailureType {
  invalidCredentials,
  accountInactive,
  network,
  unauthorized,
  protocol,
  unknown,
}

class AuthFailure {
  const AuthFailure({
    required this.type,
    this.message,
    this.statusCode,
  });

  final AuthFailureType type;
  final String? message;
  final int? statusCode;

  String get displayMessage {
    if (message != null && message!.trim().isNotEmpty) return message!;
    return switch (type) {
      AuthFailureType.invalidCredentials => 'Invalid email or password.',
      AuthFailureType.accountInactive =>
        'Your account is inactive. Please contact your administrator.',
      AuthFailureType.network =>
        'We could not reach Omnidesk. Check your connection and try again.',
      AuthFailureType.unauthorized =>
        'Your session has expired. Please sign in again.',
      AuthFailureType.protocol ||
      AuthFailureType.unknown =>
        'Something went wrong. Please try again.',
    };
  }
}

sealed class AuthResult<T> {
  const AuthResult();
}

final class AuthSuccess<T> extends AuthResult<T> {
  const AuthSuccess(this.value);
  final T value;
}

final class AuthFailureResult<T> extends AuthResult<T> {
  const AuthFailureResult(this.failure);
  final AuthFailure failure;
}

class WorkspaceMembership {
  const WorkspaceMembership({
    required this.id,
    required this.name,
    required this.slug,
    required this.role,
  });

  final String id;
  final String name;
  final String slug;
  final String role;

  factory WorkspaceMembership.fromJson(Map<String, dynamic> json) =>
      WorkspaceMembership(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        slug: (json['slug'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
      );
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isSuperAdmin,
    required this.status,
    this.phone,
    this.activeWorkspace,
    this.workspaces = const [],
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final bool isSuperAdmin;
  final String status;
  final WorkspaceMembership? activeWorkspace;
  final List<WorkspaceMembership> workspaces;

  bool get isActive => status.toLowerCase() == 'active';
  String get displayName => name.trim().isEmpty ? email : name;
  String get initials {
    final words = displayName.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words.first[0]}${words.last[0]}'.toUpperCase();
    }
    return displayName
        .substring(0, displayName.length.clamp(0, 2))
        .toUpperCase();
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? mapValue(dynamic value) => value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : null;
    final workspaceJson = mapValue(json['activeWorkspace']);
    final rawWorkspaces = json['workspaces'];
    return AuthUser(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: json['phone']?.toString(),
      role: (json['role'] ?? 'agent').toString(),
      isSuperAdmin: json['isSuperAdmin'] == true,
      status: (json['status'] ?? 'active').toString(),
      activeWorkspace: workspaceJson == null
          ? null
          : WorkspaceMembership.fromJson(workspaceJson),
      workspaces: rawWorkspaces is List
          ? rawWorkspaces
              .whereType<Map>()
              .map((item) => WorkspaceMembership.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value))))
              .toList(growable: false)
          : const [],
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  final String accessToken;
  final String tokenType;
  final AuthUser user;

  factory AuthSession.fromLoginJson(Map<String, dynamic> json) {
    final token = json['accessToken']?.toString() ?? '';
    final user = json['user'];
    if (token.isEmpty || user is! Map) {
      throw const FormatException('Invalid login response.');
    }
    return AuthSession(
      accessToken: token,
      tokenType: (json['tokenType'] ?? 'Bearer').toString(),
      user: AuthUser.fromJson(
          user.map((key, value) => MapEntry(key.toString(), value))),
    );
  }

  AuthSession withUser(AuthUser value) => AuthSession(
        accessToken: accessToken,
        tokenType: tokenType,
        user: value,
      );
}
