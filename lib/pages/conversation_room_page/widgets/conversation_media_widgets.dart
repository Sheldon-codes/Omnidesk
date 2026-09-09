import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../conversation_room_page_model.dart';

class ConversationAudioController extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  String? _activeAsset;

  AudioPlayer get player => _player;
  String? get activeAsset => _activeAsset;

  Future<void> toggle(String assetPath) async {
    if (_activeAsset != assetPath) {
      await _player.stop();
      _activeAsset = assetPath;
      notifyListeners();
      if (isRemoteConversationMedia(assetPath)) {
        await _player.setUrl(assetPath);
      } else {
        await _player.setAsset(assetPath);
      }
      await _player.play();
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

class ConversationImageMessage extends StatelessWidget {
  const ConversationImageMessage({
    super.key,
    required this.content,
    required this.textColor,
    required this.onOpen,
  });

  final ImageMessageContent content;
  final Color textColor;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ratio = content.width != null && content.height != null
        ? content.width! / content.height!
        : 4 / 3;
    final remote = isRemoteConversationMedia(content.assetPath);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          image: true,
          label: content.caption ?? 'Open photo',
          child: GestureDetector(
            onTap: onOpen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: AspectRatio(
                aspectRatio: ratio.clamp(.76, 1.5),
                child: remote
                    ? CachedNetworkImage(
                        imageUrl: content.assetPath,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _MediaLoading(
                            color: textColor, label: 'Loading image…'),
                        errorWidget: (_, __, ___) =>
                            _MediaError(color: textColor),
                      )
                    : Image.asset(
                        content.assetPath,
                        fit: BoxFit.cover,
                        cacheWidth: 900,
                        errorBuilder: (_, __, ___) =>
                            _MediaError(color: textColor),
                      ),
              ),
            ),
          ),
        ),
        if (content.caption case final caption?) ...[
          const SizedBox(height: 8),
          Text(caption,
              style: TextStyle(color: textColor, fontSize: 14, height: 1.35)),
        ],
      ],
    );
  }
}

class ConversationVideoMessage extends StatelessWidget {
  const ConversationVideoMessage({
    super.key,
    required this.content,
    required this.textColor,
    required this.onOpen,
  });

  final VideoMessageContent content;
  final Color textColor;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final remoteThumb =
        isRemoteConversationMedia(content.thumbnailAssetPath);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Play video, ${formatChatDuration(content.duration)}',
            child: GestureDetector(
              onTap: onOpen,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (remoteThumb)
                        CachedNetworkImage(
                          imageUrl: content.thumbnailAssetPath,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _MediaLoading(
                              color: textColor, label: 'Loading video…'),
                          errorWidget: (_, __, ___) =>
                              _MediaError(color: textColor),
                        )
                      else
                        Image.asset(content.thumbnailAssetPath,
                            fit: BoxFit.cover, cacheWidth: 900),
                      ColoredBox(color: Colors.black.withValues(alpha: .16)),
                      const Center(
                        child: Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 52),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 7,
                        child: Text(
                          formatChatDuration(content.duration),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(blurRadius: 4)]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (content.caption case final caption?) ...[
            const SizedBox(height: 8),
            Text(caption,
                style: TextStyle(color: textColor, fontSize: 14, height: 1.35)),
          ],
        ],
      );
  }
}

bool isRemoteConversationMedia(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
}

class _MediaLoading extends StatelessWidget {
  const _MediaLoading({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: color.withValues(alpha: .10),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: color.withValues(alpha: .78)),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ]),
        ),
      );
}

class ConversationAudioMessage extends StatelessWidget {
  const ConversationAudioMessage({
    super.key,
    required this.content,
    required this.textColor,
    required this.controller,
  });

  final AudioMessageContent content;
  final Color textColor;
  final ConversationAudioController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final active = controller.activeAsset == content.assetPath;
          return StreamBuilder<PlayerState>(
            stream: controller.player.playerStateStream,
            builder: (context, stateSnapshot) => StreamBuilder<Duration>(
              stream: controller.player.positionStream,
              builder: (context, positionSnapshot) {
                final playing = active &&
                    (stateSnapshot.data?.playing ?? false) &&
                    stateSnapshot.data?.processingState !=
                        ProcessingState.completed;
                final position = active
                    ? (positionSnapshot.data ?? Duration.zero)
                    : Duration.zero;
                final progress = content.duration.inMilliseconds == 0
                    ? 0.0
                    : (position.inMilliseconds /
                            content.duration.inMilliseconds)
                        .clamp(0.0, 1.0);
                return Row(
                  children: [
                    Semantics(
                      button: true,
                      label: playing
                          ? 'Pause voice message'
                          : 'Play voice message',
                      child: IconButton(
                        onPressed: () => controller.toggle(content.assetPath),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: textColor,
                          size: 28,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 30,
                            child: CustomPaint(
                              painter: _WaveformPainter(
                                samples: content.waveform,
                                progress: progress,
                                color: textColor,
                              ),
                            ),
                          ),
                          Text(
                            active && position > Duration.zero
                                ? '${formatChatDuration(position)} / ${formatChatDuration(content.duration)}'
                                : formatChatDuration(content.duration),
                            style: TextStyle(
                                color: textColor.withValues(alpha: .76),
                                fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
}

class ConversationDocumentMessage extends StatelessWidget {
  const ConversationDocumentMessage({
    super.key,
    required this.content,
    required this.textColor,
    required this.onOpen,
  });
  final DocumentMessageContent content;
  final Color textColor;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Open ${content.fileName}',
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: textColor.withValues(alpha: .28)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(content.mimeType.toUpperCase(),
                      style: TextStyle(
                          color: textColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(content.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(content.description,
                          style: TextStyle(
                              color: textColor.withValues(alpha: .72),
                              fontSize: 11)),
                    ],
                  ),
                ),
                Icon(IconsaxPlusBroken.document_download,
                    color: textColor.withValues(alpha: .72), size: 19),
              ],
            ),
          ),
        ),
      );
}

class ConversationLocationMessage extends StatelessWidget {
  const ConversationLocationMessage({
    super.key,
    required this.content,
    required this.textColor,
    required this.onOpen,
  });
  final LocationMessageContent content;
  final Color textColor;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Open ${content.title} location',
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.asset(content.previewAssetPath,
                      fit: BoxFit.cover, cacheWidth: 900),
                ),
              ),
              const SizedBox(height: 8),
              Text(content.title,
                  style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              Text(content.subtitle,
                  style: TextStyle(
                      color: textColor.withValues(alpha: .75), fontSize: 11)),
            ],
          ),
        ),
      );
}

class ConversationContactMessage extends StatelessWidget {
  const ConversationContactMessage({
    super.key,
    required this.content,
    required this.textColor,
    required this.onOpen,
  });
  final ContactMessageContent content;
  final Color textColor;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: textColor.withValues(alpha: .12),
                child: Text(content.avatar ?? content.name[0].toUpperCase(),
                    style: TextStyle(color: textColor)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(content.name,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text(content.phone,
                        style: TextStyle(
                            color: textColor.withValues(alpha: .76),
                            fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                foregroundColor: textColor,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                  content.customerId == null ? 'Add contact' : 'View customer'),
            ),
          ),
        ],
      );
}

Future<void> showConversationImageViewer(
  BuildContext context,
  ImageMessageContent content,
) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImageViewer(content: content),
      ),
    );

Future<void> showConversationVideoViewer(
  BuildContext context,
  VideoMessageContent content,
) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _VideoViewer(content: content),
      ),
    );

Future<void> openBundledDocument(DocumentMessageContent content) async {
  if (isRemoteConversationMedia(content.assetPath)) {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${content.fileName}');
    if (!await file.exists()) {
      await Dio().download(content.assetPath, file.path);
    }
    await OpenFile.open(file.path);
    return;
  }
  final bytes = await rootBundle.load(content.assetPath);
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/${content.fileName}');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  await OpenFile.open(file.path, type: 'application/pdf');
}

String formatChatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.content});
  final ImageMessageContent content;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Photo', style: TextStyle(fontSize: 16)),
        ),
        body: SafeArea(
          top: false,
          child: Dismissible(
            key: ValueKey('image-viewer-${content.assetPath}'),
            direction: DismissDirection.vertical,
            onDismissed: (_) => Navigator.pop(context),
            child: Column(
              children: [
                Expanded(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Center(
                      child: isRemoteConversationMedia(content.assetPath)
                          ? CachedNetworkImage(
                              imageUrl: content.assetPath,
                              placeholder: (_, __) => const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white)),
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white70,
                                  size: 48),
                            )
                          : Image.asset(content.assetPath),
                    ),
                  ),
                ),
                if (content.caption case final caption?)
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(caption,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.content});
  final VideoMessageContent content;

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;

  @override
  void initState() {
    super.initState();
    _controller = isRemoteConversationMedia(widget.content.assetPath)
        ? VideoPlayerController.networkUrl(Uri.parse(widget.content.assetPath))
        : VideoPlayerController.asset(widget.content.assetPath);
    _initialize = _controller.initialize();
    _controller.addListener(_onVideoChanged);
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Video', style: TextStyle(fontSize: 16)),
        ),
        body: SafeArea(
          top: false,
          child: Dismissible(
            key: ValueKey('video-viewer-${widget.content.assetPath}'),
            direction: DismissDirection.vertical,
            onDismissed: (_) => Navigator.pop(context),
            child: Column(
              children: [
                Expanded(
                  child: FutureBuilder<void>(
                    future: _initialize,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return Center(
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_controller),
                              IconButton.filled(
                                onPressed: () => setState(() {
                                  _controller.value.isPlaying
                                      ? _controller.pause()
                                      : _controller.play();
                                }),
                                icon: Icon(_controller.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.content.caption case final caption?)
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(caption,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.color,
  });
  final List<double> samples;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final spacing = size.width / samples.length;
    for (var index = 0; index < samples.length; index++) {
      final x = spacing * index + spacing / 2;
      final height = (size.height * samples[index]).clamp(3.0, size.height);
      final played = x / size.width <= progress;
      final paint = Paint()
        ..color = color.withValues(alpha: played ? .92 : .35)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, (size.height - height) / 2),
          Offset(x, (size.height + height) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _MediaError extends StatelessWidget {
  const _MediaError({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: color.withValues(alpha: .08),
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              color: color.withValues(alpha: .65)),
        ),
      );
}
