import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/chroma_key_settings.dart';
import 'overlay_key_filter.dart';

/// A green-screen clip in the preview: the background (photo, looping video
/// or black) with the keyed clip on top, its centre at
/// [ChromaKeySettings.position] and sized by [ChromaKeySettings.scale] —
/// the same layout the exporter renders.
class ChromaComposite extends StatelessWidget {
  /// The clip's picture (already mirrored/rotated, colour filter applied).
  final Widget keyedMedia;
  final ChromaKeySettings settings;

  /// Time into the clip (drives a background video).
  final Duration localTime;
  final bool isPlaying;

  const ChromaComposite({
    super.key,
    required this.keyedMedia,
    required this.settings,
    required this.localTime,
    required this.isPlaying,
  });

  /// The clip with its key colour removed (put the colour filter on top of
  /// this, then pass it as [keyedMedia]).
  static Widget keyOut(ChromaKeySettings settings, Widget media) =>
      OverlayKeyFilter(settings: settings, child: media);

  @override
  Widget build(BuildContext context) {
    final bg = settings.backgroundPath;
    final hasBg = bg != null && File(bg).existsSync();
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          if (!hasBg)
            const ColoredBox(color: Colors.black)
          else if (settings.isBackgroundVideo)
            ChromaBackgroundVideo(
                path: bg, localTime: localTime, isPlaying: isPlaying)
          else
            Image.file(File(bg), fit: BoxFit.cover, gaplessPlayback: true),
          Transform.translate(
            offset: Offset((settings.position.dx - 0.5) * w,
                (settings.position.dy - 0.5) * h),
            child: Transform.scale(scale: settings.scale, child: keyedMedia),
          ),
        ],
      );
    });
  }
}

/// A muted background video that loops from the clip's start, following
/// the timeline (as the exporter loops it).
class ChromaBackgroundVideo extends StatefulWidget {
  final String path;
  final Duration localTime;
  final bool isPlaying;

  const ChromaBackgroundVideo({
    super.key,
    required this.path,
    required this.localTime,
    required this.isPlaying,
  });

  @override
  State<ChromaBackgroundVideo> createState() => _ChromaBackgroundVideoState();
}

class _ChromaBackgroundVideoState extends State<ChromaBackgroundVideo> {
  VideoPlayerController? _c;
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final c = VideoPlayerController.file(File(widget.path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _c = c;
    c.initialize().then((_) async {
      if (!mounted || _c != c) return;
      await c.setVolume(0);
      await c.setLooping(true);
      setState(() {});
      _sync(force: true);
    }).catchError((Object e) {
      debugPrint('Background video failed to load: $e');
    });
  }

  @override
  void didUpdateWidget(ChromaBackgroundVideo old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _c?.dispose();
      _init();
      return;
    }
    _sync();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _sync({bool force = false}) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final len = c.value.duration.inMilliseconds;
    if (len <= 0) return;
    final target = Duration(
        milliseconds: widget.localTime.inMilliseconds.abs() % len);
    if (widget.isPlaying) {
      if (!c.value.isPlaying) {
        unawaited(c.seekTo(target).then((_) => c.play()));
        return;
      }
      final drift = (c.value.position - target).inMilliseconds.abs();
      final sinceSeek = DateTime.now().difference(_lastSeek);
      // Ignore the loop seam; resync on real drift only.
      if (drift > 400 && drift < len - 400 && sinceSeek.inMilliseconds > 800) {
        _lastSeek = DateTime.now();
        unawaited(c.seekTo(target));
      }
    } else {
      if (c.value.isPlaying) c.pause();
      if (force || (c.value.position - target).inMilliseconds.abs() > 40) {
        unawaited(c.seekTo(target));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }
}
