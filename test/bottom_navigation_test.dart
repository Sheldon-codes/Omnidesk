import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omnidesk_agent/components/digistem_bottom_nav/digistem_bottom_nav.dart';

void main() {
  testWidgets('renders all Home navigation affordances', (tester) async {
    final semantics = tester.ensureSemantics();
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const _TestPage()),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Home',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('all items keep the current route on Home', (tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const _TestPage()),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    for (final label in ['Home', 'Phone', 'Chats', 'Email', 'Tickets']) {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/home');
    }
  });
}

class _TestPage extends StatelessWidget {
  const _TestPage();

  static const items = <DigiStemBottomNavItem>[
    DigiStemBottomNavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    DigiStemBottomNavItem(
      label: 'Phone',
      icon: Icons.phone_outlined,
      selectedIcon: Icons.phone,
    ),
    DigiStemBottomNavItem(
      label: 'Chats',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    DigiStemBottomNavItem(
      label: 'Email',
      icon: Icons.mail_outline_rounded,
      selectedIcon: Icons.mail_rounded,
    ),
    DigiStemBottomNavItem(
      label: 'Tickets',
      icon: Icons.confirmation_number_outlined,
      selectedIcon: Icons.confirmation_number_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) => DigiStemBottomNav(
        items: items,
        onSelected: (_) => context.go('/home'),
        body: const SizedBox.shrink(),
      );
}
