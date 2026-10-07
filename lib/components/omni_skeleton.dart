import 'dart:async';

import 'package:flutter/material.dart';

import '../flutter_flow/flutter_flow_theme.dart';

/// Theme-aware skeleton primitive shared by data-backed screens.
///
/// Geometry stays with each screen so placeholders mirror its real content;
/// this widget owns the accessible, reduced-motion-aware shine treatment.
class OmniSkeleton extends StatefulWidget {
  const OmniSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.circle = false,
    this.baseTint,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;
  final bool circle;
  final Color? baseTint;

  @override
  State<OmniSkeleton> createState() => _OmniSkeletonState();
}

class _OmniSkeletonState extends State<OmniSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Slow, calm sweep: a soft band of light, never a sharp line.
    duration: const Duration(milliseconds: 1600),
  );
  var _reduceMotion = true;
  var _loopRunning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop(canceled: true);
      _controller.value = 0;
    } else if (!_loopRunning) {
      unawaited(_runShimmer());
    }
  }

  Future<void> _runShimmer() async {
    if (_loopRunning || _reduceMotion || !mounted) return;
    _loopRunning = true;
    try {
      while (mounted && !_reduceMotion) {
        await _controller.forward(from: 0).orCancel;
        if (!mounted || _reduceMotion) break;
        // Keep a short rest between sweeps. Besides feeling calmer, the idle
        // window avoids keeping widget tests' frame loop perpetually active.
        await Future<void>.delayed(const Duration(milliseconds: 380));
      }
    } on TickerCanceled {
      // Expected when reduced-motion is enabled or the skeleton is disposed.
    } finally {
      _loopRunning = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark =
        ThemeData.estimateBrightnessForColor(theme.primaryBackground) ==
            Brightness.dark;
    final themeBase = Color.lerp(
      theme.secondaryBackground,
      theme.alternate,
      isDark ? .78 : .62,
    )!;
    final base = widget.baseTint == null
        ? themeBase
        : Color.lerp(themeBase, widget.baseTint, .18)!;
    final highlight = Color.lerp(
      base,
      isDark ? theme.primaryText : theme.primaryBackground,
      isDark ? .24 : .78,
    )!;
    // Feathered mid-stop so the band fades softly instead of drawing a hard
    // bright line across the placeholder.
    final midFeather = Color.lerp(base, highlight, .45)!;
    final radius = widget.circle
        ? BorderRadius.circular(
            widget.width > widget.height ? widget.width / 2 : widget.height / 2)
        : widget.borderRadius;
    final shape = SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(color: base),
      ),
    );

    return ExcludeSemantics(
      child: _reduceMotion
          ? shape
          : AnimatedBuilder(
              animation: _controller,
              child: shape,
              builder: (context, child) => ShaderMask(
                blendMode: BlendMode.srcATop,
                // Wide, soft-feathered band (base → mid → highlight → mid →
                // base) so the sweep reads as a diffuse shine rather than a
                // narrow moving line, even on small placeholders.
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment(-1.6 + 3.2 * _controller.value, -.2),
                  end: Alignment(-.4 + 3.2 * _controller.value, .2),
                  colors: [base, midFeather, highlight, midFeather, base],
                  stops: const [.0, .32, .5, .68, 1.0],
                ).createShader(bounds),
                child: child,
              ),
            ),
    );
  }
}
