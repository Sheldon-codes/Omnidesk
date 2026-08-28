import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/onboarding_controller.dart';

part 'on_boarding_screen_model.g.dart';

class OnBoardingScreenState {
  const OnBoardingScreenState({this.pageIndex = 0, this.isCompleting = false});

  final int pageIndex;
  final bool isCompleting;

  bool get isFirstPage => pageIndex == 0;
  bool get isLastPage => pageIndex == onboardingItems.length - 1;
}

@riverpod
class OnBoardingScreenNotifier extends _$OnBoardingScreenNotifier {
  @override
  OnBoardingScreenState build() => const OnBoardingScreenState();

  void setPageIndex(int index) {
    if (index != state.pageIndex) {
      state = OnBoardingScreenState(pageIndex: index);
    }
  }

  Future<void> complete() async {
    if (state.isCompleting) return;
    state =
        OnBoardingScreenState(pageIndex: state.pageIndex, isCompleting: true);
    await ref.read(onboardingControllerProvider.notifier).complete();
    state = OnBoardingScreenState(pageIndex: state.pageIndex);
  }
}

class OnboardingItem {
  const OnboardingItem({
    required this.title,
    required this.description,
    required this.icon,
  });
  final String title;
  final String description;
  final IconData icon;
}

const onboardingItems = [
  OnboardingItem(
    title: 'Every customer conversation, in one place.',
    description:
        'Stay on top of WhatsApp, email, Instagram, and web messages without switching tools.',
    icon: Icons.forum_rounded,
  ),
  OnboardingItem(
    title: 'Focus on the work that needs you now.',
    description:
        'See your assigned conversations, priorities, and response targets at a glance.',
    icon: Icons.bolt_rounded,
  ),
  OnboardingItem(
    title: 'Deliver a better customer experience.',
    description:
        'Use complete customer context to resolve issues quickly and confidently.',
    icon: Icons.favorite_rounded,
  ),
];
