import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omnidesk_agent/services/onboarding_controller.dart';

void main() {
  test('onboarding starts incomplete for every new app session', () async {
    final firstContainer = ProviderContainer();
    addTearDown(firstContainer.dispose);

    final first = firstContainer.read(onboardingControllerProvider);
    expect(first.initialized, isTrue);
    expect(first.completed, isFalse);

    await firstContainer.read(onboardingControllerProvider.notifier).complete();
    expect(
      firstContainer.read(onboardingControllerProvider).completed,
      isTrue,
    );

    final secondContainer = ProviderContainer();
    addTearDown(secondContainer.dispose);
    final second = secondContainer.read(onboardingControllerProvider);
    expect(second.initialized, isTrue);
    expect(second.completed, isFalse);
  });
}
