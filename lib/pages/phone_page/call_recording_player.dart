import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../flutter_flow/flutter_flow_theme.dart';

/// Full-width waveform player shared by call-history surfaces.
class CallRecordingPlayerSheet extends StatefulWidget {
  const CallRecordingPlayerSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.recordingUrl,
  });

  final String title;
  final String subtitle;
  final String recordingUrl;

  @override
  State<CallRecordingPlayerSheet> createState() =>
      _CallRecordingPlayerSheetState();
}

class _CallRecordingPlayerSheetState extends State<CallRecordingPlayerSheet> {
  final _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _prepared = false;
  bool _playing = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_configureAudioOutput());
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
    _player.positionStream.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _player.durationStream.listen((value) {
      if (mounted && value != null) setState(() => _duration = value);
    });
  }

  Future<void> _configureAudioOutput() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _player.setVolume(1.0);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (!_prepared) {
        setState(() {
          _loading = true;
          _error = null;
        });
        await _configureAudioOutput();
        await _player.setUrl(widget.recordingUrl);
        if (!mounted) return;
        setState(() {
          _prepared = true;
          _loading = false;
        });
      }
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load this call recording.';
      });
    }
  }

  Future<void> _skip(int seconds) async {
    if (!_prepared || _duration <= Duration.zero) return;
    final next = _position + Duration(seconds: seconds);
    await _player.seek(next.isNegative
        ? Duration.zero
        : next > _duration
            ? _duration
            : next);
  }

  String _time(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return value.inHours > 0
        ? '${value.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final progress = _duration <= Duration.zero
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.titleMedium.override(
                  fontFamily: theme.titleMediumFamily,
                  color: theme.primaryText,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 4),
            Text(widget.subtitle,
                style: theme.bodySmall.override(
                  fontFamily: theme.bodySmallFamily,
                  color: theme.secondaryText,
                )),
            const SizedBox(height: 28),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (_duration <= Duration.zero) return;
                final width = context.size?.width ?? 1;
                unawaited(_player.seek(_duration *
                    (details.localPosition.dx / width).clamp(0, 1)));
              },
              child: SizedBox(
                height: 78,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    progress: progress,
                    activeColor: theme.primary,
                    inactiveColor: theme.alternate,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_time(_position), style: theme.bodySmall),
                Text(_time(_duration), style: theme.bodySmall),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Back 10 seconds',
                  onPressed: _prepared ? () => _skip(-10) : null,
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                const SizedBox(width: 18),
                IconButton.filled(
                  tooltip: _playing ? 'Pause recording' : 'Play recording',
                  onPressed: _toggle,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(64, 64),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 18),
                IconButton(
                  tooltip: 'Forward 10 seconds',
                  onPressed: _prepared ? () => _skip(10) : null,
                  icon: const Icon(Icons.forward_10_rounded),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: theme.bodySmall.override(
                    fontFamily: theme.bodySmallFamily,
                    color: theme.error,
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 64;
    final width = size.width / (bars * 1.65);
    final gap = width * .65;
    final activeBars = (bars * progress).floor();
    for (var i = 0; i < bars; i++) {
      final envelope = math.sin((i + 1) / (bars + 1) * math.pi) * .32 + .68;
      final variation = .35 + ((i * 37) % 61) / 100;
      final height =
          (size.height * .86 * envelope * variation).clamp(8.0, size.height);
      final x = i * (width + gap) + width / 2;
      final top = (size.height - height) / 2;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + height),
        Paint()
          ..color = i <= activeBars ? activeColor : inactiveColor
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor;
}
