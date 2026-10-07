import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart'
    as smooth_page_indicator;

import '../../flutter_flow/flutter_flow_theme.dart';
import 'on_boarding_screen_model.dart';
import 'onboarding_agent_preview.dart';

export 'on_boarding_screen_model.dart';

const String _kLogoAsset = 'assets/images/Omnidesk-logo.png';

// ─────────────────────────────────────────────────────────────────────────────
// Widget — animation architecture (entrance controllers, scroll-driven rise,
// staggered floaters, parallax) mirrors the proven onboarding technique; only
// the mock widgets and choreography are OmniDesk-specific.
// ─────────────────────────────────────────────────────────────────────────────

class OnBoardingScreenWidget extends ConsumerStatefulWidget {
  const OnBoardingScreenWidget({super.key});
  static const routeName = 'OnBoardingScreen';
  static const routePath = '/onboarding';
  @override
  ConsumerState<OnBoardingScreenWidget> createState() =>
      _OnBoardingScreenWidgetState();
}

class _OnBoardingScreenWidgetState extends ConsumerState<OnBoardingScreenWidget>
    with TickerProviderStateMixin {
  // Text enter animation (shared by all pages).
  late AnimationController _enterCtrl;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;

  // Per-page entrances (time based, staggered by intervals downstream).
  late AnimationController _convergeCtrl;
  late AnimationController _queueCtrl;
  late AnimationController _slaCtrl;
  late AnimationController _permCtrl;
  // One looping clock for idle drift, Answer pulse and the SLA timer.
  late AnimationController _idleCtrl;

  late final PageController _pc;
  int _convergeIndex = -1;
  int _queueIndex = -1;
  int _slaIndex = -1;
  int _permIndex = -1;
  bool _convergeArmed = false;
  bool _queueArmed = false;
  bool _slaArmed = false;
  bool _permArmed = false;

  int _lastAnimatedPage = -1;

  // Permissions primer state (page 4). Best-effort: a denial never blocks.
  bool _micGranted = false;
  bool _pushGranted = false;

  @override
  void initState() {
    super.initState();

    final initial = ref.read(onBoardingScreenProvider);
    _pc = initial.pageViewController;
    _convergeIndex = initial.items
        .indexWhere((i) => i.kind == OnBoardingPageKind.converge);
    _queueIndex =
        initial.items.indexWhere((i) => i.kind == OnBoardingPageKind.queue);
    _slaIndex =
        initial.items.indexWhere((i) => i.kind == OnBoardingPageKind.sla);
    _permIndex = initial.items
        .indexWhere((i) => i.kind == OnBoardingPageKind.permissions);

    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _convergeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _queueCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _slaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _permCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    _textFade = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _enterCtrl,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _enterCtrl.forward();
    _lastAnimatedPage = 0;

    // Page 1 is on screen at launch. MediaQuery isn't available in initState,
    // so start its entrance after the first frame.
    _convergeArmed = _convergeIndex == 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _convergeArmed) _play(_convergeCtrl);
    });

    // Start/reset page entrances from the scroll position, so they begin as
    // soon as a page starts sliding in (not after the swipe settles).
    _pc.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pc.removeListener(_onScroll);
    _enterCtrl.dispose();
    _convergeCtrl.dispose();
    _queueCtrl.dispose();
    _slaCtrl.dispose();
    _permCtrl.dispose();
    _idleCtrl.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  void _play(AnimationController c) {
    if (_reduceMotion) {
      c.value = 1;
    } else {
      c.forward(from: 0);
    }
  }

  void _onScroll() {
    if (!mounted || !_pc.hasClients || !_pc.position.haveDimensions) return;
    _convergeArmed = _syncEntrance(_convergeIndex, _convergeArmed, _convergeCtrl);
    _queueArmed = _syncEntrance(_queueIndex, _queueArmed, _queueCtrl);
    _slaArmed = _syncEntrance(_slaIndex, _slaArmed, _slaCtrl);
    _permArmed = _syncEntrance(_permIndex, _permArmed, _permCtrl);
  }

  /// Starts [ctrl] once page [index] is ~25% into view, and resets it once the
  /// page is fully off screen so the entrance replays next time.
  bool _syncEntrance(int index, bool armed, AnimationController ctrl) {
    if (index < 0) return armed;
    final enter = 1 - _pageDelta(_pc, index).abs();
    if (!armed && enter > 0.25) {
      _play(ctrl);
      return true;
    }
    if (armed && enter < 0.02) {
      ctrl.value = 0;
      return false;
    }
    return armed;
  }

  /// Brief 0..1 "tap" pulse once per idle cycle (Answer button).
  double _pressPulse() {
    final k = (_idleCtrl.value + 0.5) % 1.0;
    return k < 0.10 ? math.sin(k / 0.10 * math.pi) : 0.0;
  }

  /// SLA countdown text ticking down a 2:30 loop from the idle clock.
  String _slaTick() {
    const total = 150;
    final elapsed = (_idleCtrl.value * total).floor() % total;
    final left = total - elapsed;
    final m = left ~/ 60;
    final s = (left % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Maps v from [begin, end] to 0..1 and applies [curve].
  double _seg(double v, double begin, double end, Curve curve) {
    final t = ((v - begin) / (end - begin)).clamp(0.0, 1.0).toDouble();
    return curve.transform(t);
  }

  /// (page - index) clamped to -1..1. Negative = page sits to the right of
  /// the viewport, positive = it has been swiped off to the left.
  double _pageDelta(PageController c, int index) {
    if (!c.hasClients || !c.position.haveDimensions) {
      return (c.initialPage - index).toDouble().clamp(-1.0, 1.0).toDouble();
    }
    final page = c.page ?? c.initialPage.toDouble();
    return (page - index).clamp(-1.0, 1.0).toDouble();
  }

  // ── Shared title + description (with scroll parallax) ─────────────────────
  Widget _buildTextBlock(OnboardingItem item, int index, PageController pc) {
    final theme = FlutterFlowTheme.of(context);

    final block = Column(
      children: [
        FadeTransition(
          opacity: _textFade,
          child: SlideTransition(
            position: _textSlide,
            child: Padding(
              padding: const EdgeInsets.only(top: 28.0, bottom: 12.0),
              child: Text(
                item.title,
                textAlign: TextAlign.center,
                style: theme.headlineSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 26,
                ),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: _textFade,
          child: SlideTransition(
            position: _textSlide,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Text(
                item.description,
                textAlign: TextAlign.center,
                style: theme.bodyMedium.copyWith(
                  fontSize: 15,
                  height: 1.55,
                  color: theme.secondaryText,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    // Text sits one layer closer than the page: it travels slightly faster
    // than the swipe and cross-fades, so it never fights the visuals.
    return AnimatedBuilder(
      animation: pc,
      child: block,
      builder: (context, child) {
        final delta = _pageDelta(pc, index);
        final width = MediaQuery.of(context).size.width;
        final fade = (1 - delta.abs() * 1.5).clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(-delta * width * 0.18, 0),
            child: child,
          ),
        );
      },
    );
  }

  // ── Page 1: channels orbit the logo ─────────────────────────────────────
  // Choreography: everything starts hidden → the logo pops in on a
  // pink-to-violet glow → the four channel icons fade in on their ring →
  // once revealed they circle the logo continuously (static ring when
  // reduced motion is on).
  Widget _buildConvergePage(
      OnboardingItem item, int index, PageController pc) {
    final theme = FlutterFlowTheme.of(context);

    // Ring slots for the four channel icons (radians, 0 = east).
    const orbits = [
      _Orbit(icon: Icons.call_rounded, angle: -math.pi / 2),
      _Orbit(
          icon: Icons.chat_bubble_rounded,
          color: Color(0xFF22C55E),
          angle: 0),
      _Orbit(
          icon: Icons.email_rounded,
          color: Color(0xFF3B82F6),
          angle: math.pi / 2),
      _Orbit(icon: Icons.forum_rounded, angle: math.pi),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          Expanded(
            flex: 55,
            child: Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([pc, _idleCtrl, _convergeCtrl]),
                builder: (context, _) {
                  final calm = _reduceMotion;
                  final width = MediaQuery.of(context).size.width;
                  final delta = _pageDelta(pc, index);
                  final away = delta.abs();
                  final v = _convergeCtrl.value;

                  final logoIn = _seg(v, 0.05, 0.55, Curves.easeOutBack);
                  final logoFade = _seg(v, 0.0, 0.35, Curves.easeOut);
                  final glowIn = _seg(v, 0.45, 1.0, Curves.easeOut);
                  // 0 until every icon is revealed, then eases to 1 so the
                  // ring spins up smoothly instead of jumping.
                  final spinGate = _seg(v, 0.55, 1.0, Curves.easeOut);
                  // One full revolution per 10s (idle loop is 5s).
                  final orbitAngle =
                      _idleCtrl.value * 2 * math.pi * 0.5 * spinGate;
                  final wave = math.sin(_idleCtrl.value * 2 * math.pi);
                  final bob = calm ? 0.0 : wave * 6;

                  final exitFade = (1 - away * 1.4).clamp(0.0, 1.0).toDouble();

                  return Transform.translate(
                    offset: Offset(-delta * width * 0.35, 0),
                    child: Opacity(
                      opacity: exitFade,
                      child: Transform.scale(
                        scale: 1 - 0.25 * away,
                        child: SizedBox(
                          width: 300,
                          height: 300,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Pink-to-violet glow, strongest once revealed.
                              Opacity(
                                opacity: glowIn,
                                child: Container(
                                  width: 300,
                                  height: 300,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        theme.secondary.withValues(
                                            alpha: calm ? 0.22 : 0.22 + 0.06 * wave),
                                        theme.primary
                                            .withValues(alpha: 0.16 * glowIn),
                                        theme.primary.withValues(alpha: 0.0),
                                      ],
                                      stops: const [0.0, 0.55, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                              // Channel icons: hidden → fade in on the ring →
                              // circle the logo.
                              for (var i = 0; i < orbits.length; i++)
                                _orbitingIcon(
                                  theme,
                                  orbits[i],
                                  slot: i,
                                  v: v,
                                  orbitAngle: orbitAngle,
                                ),
                              // The logo itself.
                              Transform.translate(
                                offset: Offset(0, bob),
                                child: Transform.scale(
                                  scale: 0.6 + 0.4 * logoIn,
                                  child: Opacity(
                                    opacity: logoFade,
                                    child: Container(
                                      width: 112,
                                      height: 112,
                                      decoration: BoxDecoration(
                                        color: theme.secondaryBackground,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: theme.alternate,
                                          width: 1,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(20),
                                      child: Image.asset(
                                        _kLogoAsset,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => Icon(
                                          item.icon,
                                          size: 56,
                                          color: theme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          _buildTextBlock(item, index, pc),
          const Spacer(flex: 5),
        ],
      ),
    );
  }

  /// One channel icon: starts hidden, fades/scales in on its ring slot, then
  /// circles the logo. Icons stay upright — only their position orbits.
  Widget _orbitingIcon(
    FlutterFlowTheme theme,
    _Orbit orbit, {
    required int slot,
    required double v,
    required double orbitAngle,
  }) {
    const radius = 108.0;
    final appear =
        _seg(v, 0.25 + slot * 0.08, 0.55 + slot * 0.08, Curves.easeOut);
    final angle = orbit.angle + orbitAngle;

    final color = orbit.color ?? theme.primary;
    return Opacity(
      opacity: appear,
      child: Transform.translate(
        offset: Offset(
          math.cos(angle) * radius,
          math.sin(angle) * radius,
        ),
        child: Transform.scale(
          scale: 0.6 + 0.4 * appear,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              shape: BoxShape.circle,
              border: Border.all(color: theme.alternate, width: 1),
            ),
            child: Icon(orbit.icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }

  // ── Pages 2 & 3: mini queue + arriving floaters ────────────────────────────
  Widget _buildPreviewPage(
    OnboardingItem item,
    int index,
    PageController pc, {
    required AnimationController ctrl,
    required Widget backdrop,
    required List<Widget> Function(_FloaterFrame f) floaters,
  }) {
    return Column(
      children: [
        Expanded(
          flex: 66,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              return AnimatedBuilder(
                animation: Listenable.merge([pc, _idleCtrl, ctrl]),
                // Built once; reused every frame.
                child: backdrop,
                builder: (context, child) {
                  final delta = _pageDelta(pc, index);

                  // Scroll-driven: 0 = page fully off screen, 1 = centred.
                  final enter = 1 - delta.abs();
                  // The mini queue RISES from the bottom while the page slides
                  // in (and sinks again as it leaves).
                  final rise = Curves.easeOutCubic.transform(enter);
                  final bgFade = (enter * 1.6).clamp(0.0, 1.0).toDouble();

                  final frame = _FloaterFrame(
                    w: w,
                    h: h,
                    v: ctrl.value,
                    delta: delta,
                    calm: _reduceMotion,
                  );

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: w * 0.13,
                        right: w * 0.13,
                        top: 0,
                        bottom: 0,
                        child: Transform.translate(
                          // x: slightly slower than the page (depth)
                          // y: rises from the bottom
                          offset:
                              Offset(delta * w * 0.10, (1 - rise) * h * 0.65),
                          child: Opacity(opacity: bgFade, child: child),
                        ),
                      ),
                      ...floaters(frame),
                    ],
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: _buildTextBlock(item, index, pc),
        ),
        const Spacer(flex: 3),
      ],
    );
  }

  // Page 2 floaters: items ARRIVE one after another — WhatsApp, call, email.
  List<Widget> _queueFloaters(_FloaterFrame f) {
    return [
      _floater(
        width: f.w * 0.62,
        left: -f.w * 0.03,
        top: f.h * 0.08,
        v: f.v,
        begin: 0.30,
        end: 0.62,
        from: const Offset(-70, 0),
        phase: 0.0,
        amp: 4,
        parallax: 0.30,
        delta: f.delta,
        screenW: f.w,
        calm: f.calm,
        builder: (t) => PreviewWhatsAppBubble(reveal: t),
      ),
      _floater(
        width: f.w * 0.66,
        right: -f.w * 0.05,
        top: f.h * 0.44,
        v: f.v,
        begin: 0.45,
        end: 0.78,
        from: const Offset(70, 0),
        phase: 0.33,
        amp: 5,
        parallax: 0.45,
        delta: f.delta,
        screenW: f.w,
        calm: f.calm,
        builder: (t) => PreviewIncomingCallCard(
          reveal: t,
          press: f.calm ? 0 : _pressPulse(),
        ),
      ),
      _floater(
        width: f.w * 0.62,
        left: 0,
        bottom: f.h * 0.02,
        v: f.v,
        begin: 0.60,
        end: 0.93,
        from: const Offset(0, 50),
        phase: 0.66,
        amp: 4,
        parallax: 0.60,
        delta: f.delta,
        screenW: f.w,
        calm: f.calm,
        builder: (t) => PreviewEmailCard(reveal: t),
      ),
    ];
  }

  // Page 3 floaters: needs-attention card, then the availability toggle.
  List<Widget> _slaFloaters(_FloaterFrame f) {
    final available = f.v > 0.7;
    return [
      _floater(
        width: f.w * 0.72,
        left: f.w * 0.02,
        top: f.h * 0.10,
        v: f.v,
        begin: 0.30,
        end: 0.65,
        from: const Offset(-70, 0),
        phase: 0.0,
        amp: 4,
        parallax: 0.30,
        delta: f.delta,
        screenW: f.w,
        calm: f.calm,
        builder: (t) => PreviewSlaCard(reveal: t, tick: _slaTick()),
      ),
      _floater(
        width: f.w * 0.66,
        right: -f.w * 0.02,
        bottom: f.h * 0.06,
        v: f.v,
        begin: 0.55,
        end: 0.90,
        from: const Offset(0, 50),
        phase: 0.5,
        amp: 4,
        parallax: 0.55,
        delta: f.delta,
        screenW: f.w,
        calm: f.calm,
        builder: (_) => PreviewAvailabilityRow(available: available),
      ),
    ];
  }

  /// One floating component: staggered entrance + gentle idle drift +
  /// parallax. Flat editorial style — no tilt, no heavy shadows; hairline
  /// borders live inside the mock widgets themselves.
  Widget _floater({
    required double width,
    double? left,
    double? right,
    double? top,
    double? bottom,
    required double v,
    required double begin,
    required double end,
    required Offset from,
    required double phase,
    required double amp,
    required double parallax,
    required double delta,
    required double screenW,
    required bool calm,
    required Widget Function(double reveal) builder,
  }) {
    final pop = _seg(v, begin, end, Curves.easeOutBack);
    final fade = _seg(v, begin, end, Curves.easeOut);
    final reveal = _seg(v, begin + 0.05, end + 0.05, Curves.easeOutCubic);
    final drift =
        calm ? 0.0 : math.sin((_idleCtrl.value + phase) * 2 * math.pi) * amp;

    final dx = from.dx * (1 - pop) + (-delta * screenW * parallax);
    final dy = from.dy * (1 - pop) + drift;

    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      width: width,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.scale(
          scale: 0.92 + 0.08 * pop,
          child: Opacity(
            opacity: fade,
            child: builder(reveal),
          ),
        ),
      ),
    );
  }

  // ── Page 4: permissions primer ────────────────────────────────────────────
  Widget _buildPermissionsPage(
      OnboardingItem item, int index, PageController pc) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          Expanded(
            flex: 55,
            child: AnimatedBuilder(
              animation:
                  Listenable.merge([pc, _permCtrl]),
              builder: (context, _) {
                final v = _permCtrl.value;
                final first = _seg(v, 0.1, 0.6, Curves.easeOutCubic);
                final second = _seg(v, 0.35, 0.85, Curves.easeOutCubic);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Opacity(
                      opacity: first,
                      child: Transform.translate(
                        offset: Offset(0, 24 * (1 - first)),
                        child: _PermissionRow(
                          icon: Icons.mic_rounded,
                          title: 'Microphone',
                          subtitle: 'Talk to customers on calls',
                          granted: _micGranted,
                          onAllow: () => _requestMic(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: second,
                      child: Transform.translate(
                        offset: Offset(0, 24 * (1 - second)),
                        child: _PermissionRow(
                          icon: Icons.notifications_rounded,
                          title: 'Push notifications',
                          subtitle: 'New tickets, replies and calls',
                          granted: _pushGranted,
                          onAllow: () => _requestPush(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: second,
                      child: Text(
                        'You can change either later in Settings.',
                        style: theme.bodySmall.copyWith(
                          color: theme.secondaryText,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildTextBlock(item, index, pc),
          const Spacer(flex: 5),
        ],
      ),
    );
  }

  Future<void> _requestMic() async {
    try {
      final status = await Permission.microphone.request();
      if (mounted) setState(() => _micGranted = status.isGranted);
    } catch (_) {
      // Best-effort primer: a failure never blocks onboarding.
    }
  }

  Future<void> _requestPush() async {
    try {
      final status = await Permission.notification.request();
      if (mounted) setState(() => _pushGranted = status.isGranted);
    } catch (_) {
      // Best-effort primer: a failure never blocks onboarding.
    }
  }

  Widget _buildPage(OnboardingItem item, int index, PageController pc) {
    switch (item.kind) {
      case OnBoardingPageKind.converge:
        return _buildConvergePage(item, index, pc);
      case OnBoardingPageKind.queue:
        return _buildPreviewPage(
          item,
          index,
          pc,
          ctrl: _queueCtrl,
          backdrop: const OnboardingPreviewBackdrop(
            screen: MiniQueuePreview(),
          ),
          floaters: _queueFloaters,
        );
      case OnBoardingPageKind.sla:
        return _buildPreviewPage(
          item,
          index,
          pc,
          ctrl: _slaCtrl,
          backdrop: const OnboardingPreviewBackdrop(
            screen: MiniQueuePreview(),
          ),
          floaters: _slaFloaters,
        );
      case OnBoardingPageKind.permissions:
        return _buildPermissionsPage(item, index, pc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onBoardingScreenProvider);
    final notifier = ref.read(onBoardingScreenProvider.notifier);
    final theme = FlutterFlowTheme.of(context);

    // Replay the text entrance when the page changes. Visual entrances are
    // started from the scroll position (see _onScroll).
    if (state.currentPageIndex != _lastAnimatedPage) {
      _lastAnimatedPage = state.currentPageIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enterCtrl.forward(from: 0);
      });
    }

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: counter + prominent Skip ────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${state.currentPageIndex + 1}/${state.totalPages}',
                    style: theme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: _complete,
                    child: Text(
                      'Skip',
                      style: theme.bodyMedium.copyWith(
                        color: theme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── PageView ─────────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: state.pageViewController,
                physics: const BouncingScrollPhysics(),
                itemCount: state.totalPages,
                onPageChanged: notifier.updatePageIndex,
                itemBuilder: (context, index) => _buildPage(
                  state.items[index],
                  index,
                  state.pageViewController,
                ),
              ),
            ),

            // ── Bottom bar ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(
                  left: 24.0, right: 24.0, bottom: 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: 72.0,
                    child: AnimatedOpacity(
                      opacity: state.isFirstPage ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      child: TextButton(
                        onPressed:
                            state.isFirstPage ? null : notifier.previousPage,
                        child: const Text('Prev'),
                      ),
                    ),
                  ),
                  smooth_page_indicator.SmoothPageIndicator(
                    controller: state.pageViewController,
                    count: state.totalPages,
                    onDotClicked: notifier.jumpToPage,
                    effect: smooth_page_indicator.ExpandingDotsEffect(
                      expansionFactor: 3.0,
                      spacing: 6.0,
                      dotWidth: 8.0,
                      dotHeight: 8.0,
                      dotColor: theme.alternate,
                      activeDotColor: theme.primary,
                    ),
                  ),
                  SizedBox(
                    width: 112,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: state.isLastPage
                            ? FilledButton(
                                key: const ValueKey('get_started'),
                                onPressed:
                                    state.isCompleting ? null : _complete,
                                child: const Text('Get started'),
                              )
                            : TextButton(
                                key: const ValueKey('next'),
                                onPressed: notifier.nextPage,
                                child: Text(
                                  'Next',
                                  style: TextStyle(
                                    color: theme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _complete() async {
    await ref.read(onBoardingScreenProvider.notifier).complete();
    if (mounted) context.go('/login');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission primer row
// ─────────────────────────────────────────────────────────────────────────────

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onAllow,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.alternate, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: theme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.bodySmall.copyWith(
                    color: theme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          granted
              ? Icon(
                  Icons.check_circle_rounded,
                  color: theme.success,
                  size: 26,
                )
              : OutlinedButton(
                  onPressed: onAllow,
                  child: const Text('Allow'),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ring slot for a channel icon (radians, 0 = east, positive clockwise).
// ─────────────────────────────────────────────────────────────────────────────

class _Orbit {
  const _Orbit({
    required this.icon,
    required this.angle,
    this.color,
  });

  final IconData icon;
  final double angle;
  final Color? color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-frame values handed to the floater lists.
// ─────────────────────────────────────────────────────────────────────────────

class _FloaterFrame {
  const _FloaterFrame({
    required this.w,
    required this.h,
    required this.v,
    required this.delta,
    required this.calm,
  });

  /// Size of the visual area.
  final double w, h;

  /// Entrance controller value (0..1).
  final double v;

  /// Page scroll delta (-1..1), for parallax.
  final double delta;

  /// Reduced-motion flag.
  final bool calm;
}
