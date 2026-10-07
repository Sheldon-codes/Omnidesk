import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/components/omni_skeleton.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('skeleton base is visible in $brightness mode', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Scaffold(
              body: Center(
                child: OmniSkeleton(width: 120, height: 16),
              ),
            ),
          ),
        ),
      );

      final fill = tester.widget<ColoredBox>(find.descendant(
        of: find.byType(OmniSkeleton),
        matching: find.byType(ColoredBox),
      ));
      expect(fill.color.a, 1);
      expect(
          fill.color,
          isNot(Theme.of(tester.element(find.byType(Scaffold)))
              .scaffoldBackgroundColor));
    });
  }
}
