import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_controller.g.dart';

class OnboardingState {
  const OnboardingState({required this.initialized, required this.completed});
  final bool initialized;
  final bool completed;
}

@Riverpod(keepAlive: true)
class OnboardingController extends _$OnboardingController {
  @override
  OnboardingState build() =>
      const OnboardingState(initialized: true, completed: false);

  Future<void> complete() async {
    state = const OnboardingState(initialized: true, completed: true);
  }
}
