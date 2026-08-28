import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/auth_session_controller.dart';

part 'home_page_model.g.dart';

class HomePageState {
  const HomePageState({required this.greeting, required this.subtitle});

  final String greeting;
  final String subtitle;
}

@riverpod
HomePageState homePage(Ref ref) {
  final user = ref.watch(authSessionControllerProvider).session?.user;
  if (user == null) {
    return const HomePageState(greeting: 'Welcome', subtitle: 'Omnidesk Agent');
  }
  return HomePageState(
    greeting: 'Welcome, ${user.displayName}',
    subtitle: user.role.isEmpty ? 'Your Omnidesk home' : '${user.role} account',
  );
}
