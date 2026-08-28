import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart'
    as smooth_page_indicator;

import '../../flutter_flow/flutter_flow_theme.dart';
import 'on_boarding_screen_model.dart';

export 'on_boarding_screen_model.dart';

class OnBoardingScreenWidget extends ConsumerStatefulWidget {
  const OnBoardingScreenWidget({super.key});
  static const routeName = 'OnBoardingScreen';
  static const routePath = '/onboarding';
  @override
  ConsumerState<OnBoardingScreenWidget> createState() =>
      _OnBoardingScreenWidgetState();
}

class _OnBoardingScreenWidgetState
    extends ConsumerState<OnBoardingScreenWidget> {
  final _pageController = PageController();
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final state = ref.watch(onBoardingScreenProvider);
    final notifier = ref.read(onBoardingScreenProvider.notifier);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${state.pageIndex + 1}/${onboardingItems.length}',
                    style: theme.bodyMedium),
                TextButton(onPressed: _complete, child: const Text('Skip')),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: onboardingItems.length,
              onPageChanged: notifier.setPageIndex,
              itemBuilder: (_, index) =>
                  _OnboardingPageBody(item: onboardingItems[index]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: state.isFirstPage ? null : _previous,
                  child: const Text('Previous'),
                ),
                smooth_page_indicator.SmoothPageIndicator(
                  controller: _pageController,
                  count: onboardingItems.length,
                  onDotClicked: _jumpTo,
                  effect: smooth_page_indicator.ExpandingDotsEffect(
                    activeDotColor: theme.primary,
                    dotColor: theme.alternate,
                    dotHeight: 8,
                    dotWidth: 8,
                  ),
                ),
                FilledButton(
                  onPressed: state.isCompleting
                      ? null
                      : (state.isLastPage ? _complete : _next),
                  child: Text(state.isLastPage ? 'Get started' : 'Next'),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _complete() async {
    await ref.read(onBoardingScreenProvider.notifier).complete();
    if (mounted) context.go('/login');
  }

  Future<void> _next() => _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );

  Future<void> _previous() => _pageController.previousPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );

  Future<void> _jumpTo(int index) => _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
}

class _OnboardingPageBody extends StatelessWidget {
  const _OnboardingPageBody({required this.item});
  final OnboardingItem item;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(children: [
        Expanded(
          flex: 55,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: theme.alternate),
            ),
            child: Center(
              child: CircleAvatar(
                radius: 62,
                backgroundColor: theme.primary,
                child:
                    Icon(item.icon, size: 68, color: theme.primaryBackground),
              ),
            ),
          ),
        ),
        Text(
          item.title,
          textAlign: TextAlign.center,
          style: theme.headlineSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Text(
          item.description,
          textAlign: TextAlign.center,
          style: theme.bodyMedium
              .copyWith(color: theme.secondaryText, height: 1.5),
        ),
        const Spacer(flex: 8),
      ]),
    );
  }
}
