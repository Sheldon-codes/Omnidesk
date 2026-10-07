import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/onboarding_controller.dart';

part 'on_boarding_screen_model.g.dart';

/// Which layout a slide uses.
///  - [converge]    : channel icons snap into the logo on a pink glow (page 1)
///  - [queue]       : mini queue preview + arriving conversation cards (page 2)
///  - [sla]         : needs-attention card + availability toggle (page 3)
///  - [permissions] : microphone / push primer with inline Allow buttons
enum OnBoardingPageKind { converge, queue, sla, permissions }

/// Holds all content for a single onboarding slide.
class OnboardingItem {
  const OnboardingItem({
    required this.title,
    required this.description,
    required this.kind,
    this.icon = Icons.star_rounded,
  });
  final String title;
  final String description;
  final OnBoardingPageKind kind;
  final IconData icon;
}

class OnBoardingScreenState {
  OnBoardingScreenState({
    required this.pageViewController,
    this.items = onboardingItems,
    this.currentPageIndex = 0,
    this.isCompleting = false,
  });

  final PageController pageViewController;
  final List<OnboardingItem> items;
  final int currentPageIndex;
  final bool isCompleting;

  int get totalPages => items.length;
  bool get isFirstPage => currentPageIndex == 0;
  bool get isLastPage => currentPageIndex == totalPages - 1;

  /// Backwards-compatible 0-based page index for the top counter.
  int get pageIndex => currentPageIndex;

  OnBoardingScreenState copyWith({
    int? currentPageIndex,
    List<OnboardingItem>? items,
    bool? isCompleting,
  }) =>
      OnBoardingScreenState(
        pageViewController: pageViewController,
        currentPageIndex: currentPageIndex ?? this.currentPageIndex,
        items: items ?? this.items,
        isCompleting: isCompleting ?? this.isCompleting,
      );
}

@riverpod
class OnBoardingScreenNotifier extends _$OnBoardingScreenNotifier {
  @override
  OnBoardingScreenState build() {
    final controller = PageController(initialPage: 0);
    ref.onDispose(controller.dispose);
    return OnBoardingScreenState(pageViewController: controller);
  }

  void setPageIndex(int index) {
    if (index != state.currentPageIndex) {
      state = state.copyWith(currentPageIndex: index);
    }
  }

  void updatePageIndex(int index) => setPageIndex(index);

  Future<void> nextPage() async {
    if (state.pageViewController.hasClients) {
      await state.pageViewController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> previousPage() async {
    if (state.pageViewController.hasClients) {
      await state.pageViewController.previousPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> jumpToPage(int index) async {
    if (state.pageViewController.hasClients) {
      await state.pageViewController.animateToPage(
        index,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> complete() async {
    if (state.isCompleting) return;
    state = state.copyWith(isCompleting: true);
    await ref.read(onboardingControllerProvider.notifier).complete();
    state = state.copyWith(isCompleting: false);
  }
}

// ── OmniDesk slides ─────────────────────────────────────────────────────────
// Agents are invited, not persuaded: each slide teaches the model in seconds —
// every channel lands in one queue, and nothing misses its SLA.

const onboardingItems = [
  OnboardingItem(
    title: 'Every channel. One OmniDesk.',
    description:
        'Calls, WhatsApp, email and web chat orbit one home — nothing lives in a separate app anymore.',
    kind: OnBoardingPageKind.converge,
    icon: Icons.hub_rounded,
  ),
  OnboardingItem(
    title: 'Every conversation, one queue.',
    description:
        'New messages, calls and emails arrive here live, each carrying its channel — just pick up the next one.',
    kind: OnBoardingPageKind.queue,
    icon: Icons.inbox_rounded,
  ),
  OnboardingItem(
    title: 'Never miss an SLA.',
    description:
        'Escalated and overdue work surfaces itself with a live timer. Flip yourself Available and work the queue.',
    kind: OnBoardingPageKind.sla,
    icon: Icons.timer_rounded,
  ),
  OnboardingItem(
    title: 'Stay reachable for the queue.',
    description:
        'Allow the microphone for calls and push for new tickets — you can change either later in Settings.',
    kind: OnBoardingPageKind.permissions,
    icon: Icons.notifications_active_rounded,
  ),
];
