import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import 'call_session_controller.dart';

class CallExperienceHost extends ConsumerWidget {
  const CallExperienceHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callSessionControllerProvider);
    if (!state.hasCall) return child;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (state.presentation == CallPresentation.fullscreen &&
            !(state.lifecycle == CallLifecycle.incomingRinging &&
                state.nativeIncomingSurfaceActive))
          Positioned.fill(
            key: const ValueKey('fullscreen-call-position'),
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: FullscreenCallView(
                key: const ValueKey('fullscreen-call'),
                state: state,
              ),
            ),
          )
        else if (!(state.lifecycle == CallLifecycle.incomingRinging &&
            state.nativeIncomingSurfaceActive))
          Positioned(
            key: const ValueKey('collapsed-call-position'),
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: CollapsedCallBar(
                key: const ValueKey('collapsed-call'),
                state: state,
              ),
            ),
          ),
      ],
    );
  }
}

class FullscreenCallView extends ConsumerWidget {
  const FullscreenCallView({super.key, required this.state});

  final CallSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FlutterFlowTheme.of(context);
    final controller = ref.read(callSessionControllerProvider.notifier);
    return Material(
      color: theme.primaryBackground,
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Minimize call',
                  excludeSemantics: true,
                  child: IconButton(
                    onPressed: controller.minimize,
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: Icon(Icons.close_fullscreen_rounded,
                        color: theme.primaryText, size: 23),
                  ),
                ),
              ),
            ),
            Expanded(
              child: state.keypadVisible
                  ? _InCallKeypad(state: state, theme: theme)
                  : _CallMainSurface(state: state, theme: theme),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallMainSurface extends ConsumerWidget {
  const _CallMainSurface({required this.state, required this.theme});

  final CallSessionState state;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callSessionControllerProvider.notifier);
    return LayoutBuilder(builder: (context, constraints) {
      if (state.lifecycle == CallLifecycle.incomingRinging) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _CallIdentity(
                    state: state,
                    theme: theme,
                    large: true,
                  ),
                ),
              ),
              _IncomingActions(theme: theme),
              const SizedBox(height: 12),
            ],
          ),
        );
      }
      final topGap = (constraints.maxHeight * .08).clamp(20.0, 64.0);
      final actionGap = (constraints.maxHeight * .12).clamp(32.0, 88.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          children: [
            SizedBox(height: topGap),
            _CallIdentity(state: state, theme: theme, large: true),
            SizedBox(height: actionGap),
            _CallControls(state: state, theme: theme),
            const SizedBox(height: 30),
            _EndCallButton(
              theme: theme,
              label: state.lifecycle == CallLifecycle.outgoingRinging
                  ? 'Cancel call'
                  : 'End call',
              onTap: controller.end,
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    });
  }
}

class _CallIdentity extends StatelessWidget {
  const _CallIdentity(
      {required this.state, required this.theme, required this.large});

  final CallSessionState state;
  final FlutterFlowTheme theme;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final party = state.party!;
    if (!large) {
      return Row(
        children: [
          _PartyAvatar(party: party, theme: theme, radius: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(party.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium.override(
                        fontFamily: theme.bodyMediumFamily,
                        color: theme.primaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(state.statusLabel,
                    style: theme.bodySmall.override(
                        fontFamily: theme.bodySmallFamily,
                        color: theme.secondaryText,
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _PartyAvatar(party: party, theme: theme, radius: 48),
        const SizedBox(height: 20),
        Text(party.displayName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.headlineSmall.override(
                fontFamily: theme.headlineSmallFamily,
                color: theme.primaryText,
                fontSize: 25,
                fontWeight: FontWeight.w600,
                letterSpacing: -.4)),
        const SizedBox(height: 6),
        Text(party.phoneNumber,
            style: theme.bodyMedium.override(
                fontFamily: theme.bodyMediumFamily,
                color: theme.secondaryText,
                fontSize: 14)),
        const SizedBox(height: 14),
        Semantics(
          liveRegion: true,
          label: state.statusLabel,
          child: Text(state.statusLabel,
              style: theme.bodyLarge.override(
                  fontFamily: theme.bodyLargeFamily,
                  color: state.lifecycle == CallLifecycle.active
                      ? theme.primaryText
                      : theme.secondaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _PartyAvatar extends StatelessWidget {
  const _PartyAvatar(
      {required this.party, required this.theme, required this.radius});
  final CallParty party;
  final FlutterFlowTheme theme;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: theme.secondaryBackground,
        child: Text(party.avatar ?? party.initial,
            style: theme.titleLarge.override(
                fontFamily: theme.titleLargeFamily,
                color: theme.primaryText,
                fontSize: radius * .68,
                fontWeight: FontWeight.w500)),
      );
}

class _IncomingActions extends ConsumerWidget {
  const _IncomingActions({required this.theme});
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callSessionControllerProvider.notifier);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _PrimaryCallAction(
          label: 'Decline',
          icon: Icons.call_end,
          color: theme.error,
          onTap: controller.decline,
        ),
        _PrimaryCallAction(
          label: 'Answer',
          icon: Icons.call,
          color: theme.success,
          onTap: controller.answer,
        ),
      ],
    );
  }
}

class _PrimaryCallAction extends StatelessWidget {
  const _PrimaryCallAction(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Column(
          children: [
            IconButton.filled(
              onPressed: onTap,
              style: IconButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                minimumSize: const Size(68, 68),
              ),
              icon: Icon(icon, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _CallControls extends ConsumerWidget {
  const _CallControls({required this.state, required this.theme});
  final CallSessionState state;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callSessionControllerProvider.notifier);
    final controls = <Widget>[
      _ControlButton(
        label: 'Mute',
        icon: state.muted ? Icons.mic_off_outlined : Icons.mic_none_outlined,
        selected: state.muted,
        theme: theme,
        onTap: controller.toggleMute,
      ),
      _ControlButton(
        label: 'Keypad',
        icon: Icons.dialpad_outlined,
        selected: false,
        theme: theme,
        onTap: controller.openKeypad,
      ),
      _ControlButton(
        label: 'Speaker',
        icon: state.speakerEnabled
            ? Icons.volume_up_outlined
            : Icons.volume_down_outlined,
        selected: state.speakerEnabled,
        theme: theme,
        onTap: controller.toggleSpeaker,
      ),
    ];
    if (state.lifecycle == CallLifecycle.active) {
      controls.addAll([
        _ControlButton(
          label: 'Hold',
          icon: Icons.pause_outlined,
          selected: state.onHold,
          theme: theme,
          onTap: controller.toggleHold,
        ),
        _ControlButton(
          label: 'Contact',
          icon: IconsaxPlusBroken.user,
          selected: false,
          theme: theme,
          onTap: () => _comingSoon(context),
        ),
        _ControlButton(
          label: 'Notes',
          icon: IconsaxPlusBroken.note,
          selected: false,
          theme: theme,
          onTap: () => _comingSoon(context),
        ),
      ]);
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 1.35,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: controls,
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.theme,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(32),
          splashColor: theme.accent1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? theme.primary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color:
                        selected ? theme.primaryBackground : theme.primaryText,
                    size: 22),
              ),
              const SizedBox(height: 5),
              Text(label,
                  style: theme.bodySmall.override(
                      fontFamily: theme.bodySmallFamily,
                      color: theme.primaryText,
                      fontSize: 12)),
            ],
          ),
        ),
      );
}

class _EndCallButton extends StatelessWidget {
  const _EndCallButton(
      {required this.theme, required this.label, required this.onTap});
  final FlutterFlowTheme theme;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _PrimaryCallAction(
        label: label,
        icon: Icons.call_end,
        color: theme.error,
        onTap: onTap,
      );
}

class _InCallKeypad extends ConsumerWidget {
  const _InCallKeypad({required this.state, required this.theme});
  final CallSessionState state;
  final FlutterFlowTheme theme;

  static const _keys = [
    ('1', ''),
    ('2', 'ABC'),
    ('3', 'DEF'),
    ('4', 'GHI'),
    ('5', 'JKL'),
    ('6', 'MNO'),
    ('7', 'PQRS'),
    ('8', 'TUV'),
    ('9', 'WXYZ'),
    ('*', ''),
    ('0', '+'),
    ('#', ''),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callSessionControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 18),
      child: Column(
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Close keypad',
                excludeSemantics: true,
                child: IconButton(
                  onPressed: controller.closeKeypad,
                  icon: Icon(IconsaxPlusBroken.close_circle,
                      color: theme.primaryText),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Text(
                    state.dtmfDigits.isEmpty ? 'Keypad' : state.dtmfDigits,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: theme.titleLarge.override(
                        fontFamily: theme.titleLargeFamily,
                        color: theme.primaryText,
                        fontSize: 24,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Delete last digit. Long press to clear',
                excludeSemantics: true,
                child: IconButton(
                  onPressed: state.dtmfDigits.isEmpty
                      ? null
                      : controller.deleteLastDtmfDigit,
                  onLongPress: state.dtmfDigits.isEmpty
                      ? null
                      : controller.clearDtmfDigits,
                  icon: Icon(Icons.backspace_outlined,
                      color: state.dtmfDigits.isEmpty
                          ? theme.secondaryText
                          : theme.primaryText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 10, 28, 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var row = 0; row < 4; row++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var column = 0; column < 3; column++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 5,
                                ),
                                child: _DtmfKey(
                                  digit: _keys[row * 3 + column].$1,
                                  letters: _keys[row * 3 + column].$2,
                                  theme: theme,
                                  onTap: controller.appendDtmfDigit,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          _EndCallButton(
              theme: theme, label: 'End call', onTap: controller.end),
        ],
      ),
    );
  }
}

class _DtmfKey extends StatelessWidget {
  const _DtmfKey({
    required this.digit,
    required this.letters,
    required this.theme,
    required this.onTap,
  });
  final String digit;
  final String letters;
  final FlutterFlowTheme theme;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: letters.isEmpty ? 'Digit $digit' : 'Digit $digit, $letters',
        child: InkWell(
          onTap: () => onTap(digit),
          borderRadius: BorderRadius.circular(44),
          overlayColor:
              WidgetStatePropertyAll(theme.primary.withValues(alpha: .10)),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(digit,
                    style: theme.titleLarge.override(
                        fontFamily: theme.titleLargeFamily,
                        color: theme.primaryText,
                        fontSize: 27,
                        fontWeight: FontWeight.w400)),
                if (letters.isNotEmpty)
                  Text(letters,
                      style: theme.bodySmall.override(
                          fontFamily: theme.bodySmallFamily,
                          color: theme.secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 1.2)),
              ],
            ),
          ),
        ),
      );
}

class CollapsedCallBar extends ConsumerWidget {
  const CollapsedCallBar({super.key, required this.state});

  final CallSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FlutterFlowTheme.of(context);
    final controller = ref.read(callSessionControllerProvider.notifier);
    return Material(
      color: theme.primaryBackground,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: .16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.alternate.withValues(alpha: .8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 66,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: controller.restore,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child:
                      _CallIdentity(state: state, theme: theme, large: false),
                ),
              ),
            ),
            if (state.lifecycle == CallLifecycle.incomingRinging) ...[
              _CompactAction(
                label: 'Decline',
                icon: Icons.call_end,
                color: theme.error,
                onTap: controller.decline,
              ),
              _CompactAction(
                label: 'Answer',
                icon: Icons.call,
                color: theme.success,
                onTap: controller.answer,
              ),
            ] else ...[
              _CompactToggleAction(
                label: state.speakerEnabled
                    ? 'Turn off loudspeaker'
                    : 'Loudspeaker',
                icon: state.speakerEnabled
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_outlined,
                selected: state.speakerEnabled,
                theme: theme,
                onTap: controller.toggleSpeaker,
              ),
              _CompactAction(
                label: 'End call',
                icon: Icons.call_end,
                color: theme.error,
                onTap: controller.end,
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _CompactToggleAction extends StatelessWidget {
  const _CompactToggleAction({
    required this.label,
    required this.icon,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        selected: selected,
        excludeSemantics: true,
        child: IconButton.filled(
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor:
                selected ? theme.primaryText : theme.secondaryBackground,
            foregroundColor:
                selected ? theme.primaryBackground : theme.primaryText,
            minimumSize: const Size(44, 44),
          ),
          icon: Icon(icon, size: 20),
        ),
      );
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: IconButton.filled(
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 44),
          ),
          icon: Icon(icon, size: 20),
        ),
      );
}

void _comingSoon(BuildContext context) => ScaffoldMessenger.of(context)
    .showSnackBar(const SnackBar(content: Text('Coming soon')));
