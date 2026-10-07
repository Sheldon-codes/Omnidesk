import 'package:flutter/material.dart';

import '../../flutter_flow/flutter_flow_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock data — nothing here touches the API or the session. All surfaces use
// theme tokens only, so they flex between light mode and true-black dark mode.
// ─────────────────────────────────────────────────────────────────────────────

/// Channel accent colors. Used sparingly: chips and presence dots only, with
/// pink (theme.primary) reserved as the single product accent.
class _ChannelColors {
  static const whatsapp = Color(0xFF22C55E);
  static const email = Color(0xFF3B82F6);
}

/// Hairline card used by every floater: flat editorial surface, no heavy
/// drop shadows — depth comes from staggered arrival and parallax instead.
BoxDecoration _floaterDecoration(FlutterFlowTheme theme) => BoxDecoration(
      color: theme.secondaryBackground,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: theme.alternate, width: 1),
    );

/// Small channel label. The only place a channel color is allowed to appear.
class ChannelChip extends StatelessWidget {
  const ChannelChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.7),
      ),
      child: Text(
        label,
        style: theme.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Backdrop: mini agent queue inside a device frame, faded at the bottom.
// Built once and cached by the parent AnimatedBuilder.
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingPreviewBackdrop extends StatelessWidget {
  const OnboardingPreviewBackdrop({super.key, required this.screen});

  /// The fixed-width (360) mini screen to show inside the device frame.
  final Widget screen;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.78, 1.0],
        ).createShader(rect),
        child: Container(
          decoration: BoxDecoration(
            color: theme.primaryBackground,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: theme.alternate, width: 1.2),
          ),
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: IgnorePointer(child: screen),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed-width (360) mini agent queue: header + three channel rows.
class MiniQueuePreview extends StatelessWidget {
  const MiniQueuePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return SizedBox(
      width: 360,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Inbox',
                  style: theme.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '3 new',
                    style: theme.bodySmall.copyWith(
                      color: theme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _QueueRow(
              name: 'David Mwangi',
              snippet: 'My M-Pesa payment is not reflecting…',
              time: 'now',
              unread: 2,
              chipLabel: 'WhatsApp',
              chipColor: _ChannelColors.whatsapp,
              icon: Icons.chat_bubble_rounded,
            ),
            const SizedBox(height: 10),
            _QueueRow(
              name: '+254 722 000 111',
              snippet: 'Incoming call • ringing',
              time: 'now',
              unread: 1,
              chipLabel: 'Call',
              chipColor: theme.primary,
              icon: Icons.call_rounded,
            ),
            const SizedBox(height: 10),
            _QueueRow(
              name: 'Billing support',
              snippet: 'Invoice INV-2041 is overdue…',
              time: '2m',
              unread: 0,
              chipLabel: 'Email',
              chipColor: _ChannelColors.email,
              icon: Icons.email_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.name,
    required this.snippet,
    required this.time,
    required this.unread,
    required this.chipLabel,
    required this.chipColor,
    required this.icon,
  });

  final String name;
  final String snippet;
  final String time;
  final int unread;
  final String chipLabel;
  final Color chipColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _floaterDecoration(theme),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.alternate,
                child: Text(
                  name.characters.first.toUpperCase(),
                  style: theme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: chipColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.secondaryBackground,
                      width: 2,
                    ),
                  ),
                  child: Icon(icon, size: 9, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: theme.bodySmall.copyWith(
                        color: theme.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall.copyWith(
                    color: theme.secondaryText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                ChannelChip(label: chipLabel, color: chipColor),
              ],
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 10,
              backgroundColor: theme.primary,
              child: Text(
                '$unread',
                style: theme.bodySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arriving floaters for page 2: WhatsApp bubble, incoming call, email preview.
// ─────────────────────────────────────────────────────────────────────────────

/// Incoming WhatsApp message bubble.
class PreviewWhatsAppBubble extends StatelessWidget {
  const PreviewWhatsAppBubble({super.key, required this.reveal});

  /// 0..1 staged entrance progress (drives inner content fade).
  final double reveal;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _floaterDecoration(theme),
      child: Opacity(
        opacity: reveal.clamp(0.0, 1.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChannelChip(
              label: 'WhatsApp',
              color: _ChannelColors.whatsapp,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _ChannelColors.whatsapp.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Text(
                'Hi! Is my order arriving today?',
                style: theme.bodyMedium.copyWith(fontSize: 13),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '09:41 • David Mwangi',
              style: theme.bodySmall.copyWith(
                color: theme.secondaryText,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Incoming call card with a pulsing Answer button.
class PreviewIncomingCallCard extends StatelessWidget {
  const PreviewIncomingCallCard({
    super.key,
    required this.reveal,
    required this.press,
  });

  /// 0..1 staged entrance progress.
  final double reveal;

  /// 0..1 looping Answer-button pulse (0 when reduced motion is on).
  final double press;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _floaterDecoration(theme),
      child: Opacity(
        opacity: reveal.clamp(0.0, 1.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.alternate,
                  child: Icon(
                    Icons.person_rounded,
                    size: 20,
                    color: theme.secondaryText,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '+254 743 379 990',
                        style: theme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: theme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Incoming call',
                            style: theme.bodySmall.copyWith(
                              color: theme.secondaryText,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ChannelChip(label: 'Call', color: theme.primary),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Transform.scale(
                    scale: 1 + press * 0.06,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: theme.success,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.call_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Answer',
                            style: theme.bodyMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: theme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.call_end_rounded,
                    size: 16,
                    color: theme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Email preview card.
class PreviewEmailCard extends StatelessWidget {
  const PreviewEmailCard({super.key, required this.reveal});

  /// 0..1 staged entrance progress.
  final double reveal;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _floaterDecoration(theme),
      child: Opacity(
        opacity: reveal.clamp(0.0, 1.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChannelChip(label: 'Email', color: _ChannelColors.email),
            const SizedBox(height: 8),
            Text(
              'Re: Invoice INV-2041 overdue',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Hello — following up on the outstanding balance of KES 48,500…',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall.copyWith(
                color: theme.secondaryText,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 3: needs-attention card with live timer + availability toggle.
// ─────────────────────────────────────────────────────────────────────────────

/// Escalated / overdue ticket with a ticking SLA timer.
class PreviewSlaCard extends StatelessWidget {
  const PreviewSlaCard({super.key, required this.reveal, required this.tick});

  /// 0..1 staged entrance progress.
  final double reveal;

  /// Live `m:ss` countdown text, derived from the idle clock by the parent.
  final String tick;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _floaterDecoration(theme),
      child: Opacity(
        opacity: reveal.clamp(0.0, 1.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.priority_high_rounded,
                  size: 15,
                  color: theme.error,
                ),
                const SizedBox(width: 6),
                Text(
                  'Needs attention',
                  style: theme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: theme.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        tick,
                        style: theme.bodySmall.copyWith(
                          color: theme.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SlaTagRow(
              label: 'Escalated',
              color: theme.error,
              detail: 'VIP customer waiting 12m',
            ),
            const SizedBox(height: 6),
            _SlaTagRow(
              label: 'Overdue',
              color: theme.warning,
              detail: 'Reply target passed by 0:42',
            ),
          ],
        ),
      ),
    );
  }
}

class _SlaTagRow extends StatelessWidget {
  const _SlaTagRow({
    required this.label,
    required this.color,
    required this.detail,
  });

  final String label;
  final Color color;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: color.withValues(alpha: 0.45),
              width: 0.7,
            ),
          ),
          child: Text(
            label,
            style: theme.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall.copyWith(
              color: theme.secondaryText,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Agent availability control: flips to Available as the entrance completes.
class PreviewAvailabilityRow extends StatelessWidget {
  const PreviewAvailabilityRow({super.key, required this.available});

  /// Whether the toggle has flipped on.
  final bool available;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _floaterDecoration(theme),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.headset_mic_rounded,
              size: 16,
              color: theme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available ? 'Available' : 'Away',
                  style: theme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Receive incoming calls',
                  style: theme.bodySmall.copyWith(
                    color: theme.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: available
                  ? theme.primary
                  : theme.alternate.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment:
                available ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
