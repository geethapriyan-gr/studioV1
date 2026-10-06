import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../main.dart' show AppColors;
import '../models/video_project.dart';
import '../providers/video_editor_provider.dart';
import '../utils/overlay_shapes.dart';
import '../utils/snap_guides.dart';
import '../utils/text_overlay_painter.dart';
import 'overlay_key_filter.dart';

/// A picture-in-picture overlay on the preview canvas.
///
/// The canvas ([parentSize]) is the editor's 1920-px-tall design space, so
/// canvas pixels and the exporter's design pixels are the same unit.
/// Playback follows the timeline ([timelinePosition]), not the main clip's
/// player, so overlays stay in sync over any clip, gap or photo.
class DraggableMediaOverlay extends StatefulWidget {
  final VideoClip overlayClip;
  final Size parentSize;
  final Duration timelinePosition;
  final bool isPlaying;
  final double masterVolume;
  final bool isSelected;
  final VoidCallback onSelected;
  final VoidCallback onDelete;

  /// Called once when a drag/pinch/rotate ends with the final box and
  /// rotation (degrees).
  final void Function(Offset position, Size size, double rotation)
      onTransformEnd;

  const DraggableMediaOverlay({
    super.key,
    required this.overlayClip,
    required this.parentSize,
    required this.timelinePosition,
    required this.isPlaying,
    required this.onSelected,
    required this.onDelete,
    required this.onTransformEnd,
    this.masterVolume = 1.0,
    this.isSelected = false,
  });

  @override
  State<DraggableMediaOverlay> createState() => _DraggableMediaOverlayState();
}

class _DraggableMediaOverlayState extends State<DraggableMediaOverlay> {
  VideoPlayerController? _controller;
  Size? _imageSize;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  // Drag state (null when not dragging).
  Offset? _dragPos;
  Offset? _snappedPos;
  Size? _dragSize;
  double? _dragRotation;
  Offset _startPos = Offset.zero;
  Size _startSize = Size.zero;
  double _startRotation = 0;

  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);
  bool _seeking = false;

  VideoClip get _clip => widget.overlayClip;

  @override
  void initState() {
    super.initState();
    _initMedia();
  }

  @override
  void didUpdateWidget(DraggableMediaOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = oldWidget.overlayClip;
    if (o.videoFile?.path != _clip.videoFile?.path ||
        o.imageFile?.path != _clip.imageFile?.path) {
      _disposeMedia();
      _initMedia();
      return;
    }
    _applyVolume();
    _sync();
  }

  @override
  void dispose() {
    _disposeMedia();
    super.dispose();
  }

  void _initMedia() {
    final video = _clip.videoFile;
    if (_clip.mediaType == MediaType.video && video != null) {
      final c = VideoPlayerController.file(
        video,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = c;
      // No looping: the export plays the trimmed window once, so does this.
      c.initialize().then((_) {
        if (!mounted || _controller != c) return;
        _applyVolume();
        setState(() {});
        _sync(force: true);
      }).catchError((Object e) {
        debugPrint('Overlay video failed to load: $e');
      });
    } else if (_clip.imageFile != null) {
      final stream =
          FileImage(_clip.imageFile!).resolve(ImageConfiguration.empty);
      _imageListener = ImageStreamListener((info, _) {
        if (!mounted) return;
        setState(() => _imageSize = Size(
            info.image.width.toDouble(), info.image.height.toDouble()));
      });
      stream.addListener(_imageListener!);
      _imageStream = stream;
    }
  }

  void _disposeMedia() {
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.pause().catchError((_) {});
      c.dispose();
    }
    if (_imageListener != null) _imageStream?.removeListener(_imageListener!);
    _imageStream = null;
    _imageListener = null;
    _imageSize = null;
  }

  void _applyVolume() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    // Overlay audio is part of the video mix, so the video master volume
    // applies to it (the exporter does the same).
    final v = _clip.isMuted
        ? 0.0
        : (_clip.volume * widget.masterVolume).clamp(0.0, 1.0);
    if ((c.value.volume - v).abs() > 0.001) c.setVolume(v);
  }

  /// Source position of the overlay video for the current timeline time.
  Duration _sourceTarget() {
    final local = widget.timelinePosition - _clip.startTime;
    var target = _clip.trimStart +
        VideoEditorProvider.sourceLengthForTimeline(
            local < Duration.zero ? Duration.zero : local,
            _clip.playbackSpeed);
    final last = _clip.trimEnd - const Duration(milliseconds: 1);
    if (target > last) target = last;
    if (target < _clip.trimStart) target = _clip.trimStart;
    return target;
  }

  Future<void> _seek(Duration target) async {
    final c = _controller;
    if (c == null) return;
    _seeking = true;
    _lastSeek = DateTime.now();
    try {
      await c.seekTo(target);
    } catch (_) {
    } finally {
      _seeking = false;
    }
  }

  void _sync({bool force = false}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final pos = widget.timelinePosition;
    final active = pos >= _clip.startTime && pos < _clip.endTime;
    final target = _sourceTarget();
    final speed = _clip.playbackSpeed.clamp(0.1, 8.0).toDouble();

    if (widget.isPlaying && active) {
      if ((c.value.playbackSpeed - speed).abs() > 0.001) {
        c.setPlaybackSpeed(speed);
      }
      if (c.value.position >= _clip.trimEnd) {
        if (c.value.isPlaying) c.pause();
        return;
      }
      if (!c.value.isPlaying) {
        unawaited(_seek(target).then((_) {
          if (mounted && widget.isPlaying) c.play();
        }));
        return;
      }
      final drift = (c.value.position - target).abs();
      final sinceSeek = DateTime.now().difference(_lastSeek);
      if (drift > const Duration(milliseconds: 300) &&
          !_seeking &&
          sinceSeek > const Duration(milliseconds: 600)) {
        unawaited(_seek(target));
      }
    } else {
      if (c.value.isPlaying) c.pause();
      if (!active) return;
      final drift = (c.value.position - target).abs();
      if ((force || drift > const Duration(milliseconds: 40)) && !_seeking) {
        unawaited(_seek(target));
      }
    }
  }

  // ── Layout ─────────────────────────────────────────────────────────────

  /// Natural (display) size of the media, rotation metadata applied.
  Size? get _mediaSize {
    final c = _controller;
    if (c != null && c.value.isInitialized && !c.value.size.isEmpty) {
      final s = c.value.size;
      return (c.value.rotationCorrection % 180) != 0
          ? Size(s.height, s.width)
          : s;
    }
    return _imageSize;
  }

  Widget _rawMedia(Size media) {
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      return SizedBox(
        width: media.width,
        height: media.height,
        child: VideoPlayer(c),
      );
    }
    if (_clip.imageFile != null) {
      return Image.file(_clip.imageFile!,
          width: media.width, height: media.height, fit: BoxFit.fill);
    }
    return const SizedBox.shrink();
  }

  /// Media cropped (crop rect normalized to the media), mirrored, keyed and
  /// fitted into the box: cover when a mask shape is set, else contain.
  Widget _media() {
    final media = _mediaSize;
    if (media == null) {
      return Container(
        color: AppColors.surface.withValues(alpha: 0.6),
        child: Icon(Icons.videocam_outlined, color: AppColors.textTertiary),
      );
    }
    final crop = _clip.cropRect ?? const Rect.fromLTWH(0, 0, 1, 1);
    final cw = math.max(1.0, media.width * crop.width);
    final ch = math.max(1.0, media.height * crop.height);
    Widget content = SizedBox(
      width: cw,
      height: ch,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: media.width,
          maxWidth: media.width,
          minHeight: media.height,
          maxHeight: media.height,
          child: Transform.translate(
            offset: Offset(-crop.left * media.width, -crop.top * media.height),
            child: _rawMedia(media),
          ),
        ),
      ),
    );
    final key = _clip.chromaKeySettings;
    if (key != null && key.enabled) {
      content = OverlayKeyFilter(settings: key, child: content);
    }
    if (_clip.isMirrored) {
      content = Transform.flip(flipX: true, child: content);
    }
    return FittedBox(
      fit: OverlayShapes.isMasked(_clip) ? BoxFit.cover : BoxFit.contain,
      clipBehavior: Clip.hardEdge,
      child: content,
    );
  }

  // ── Gestures ───────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d, Offset pos, Size size) {
    widget.onSelected();
    _startPos = pos;
    _startSize = size;
    _startRotation = _clip.rotation;
    setState(() {
      _dragPos = pos;
      _dragSize = size;
      _dragRotation = _startRotation;
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final parent = widget.parentSize;
    var size = _dragSize ?? _startSize;
    var pos = _dragPos ?? _startPos;
    var rotation = _dragRotation ?? _startRotation;
    if (d.pointerCount >= 2) {
      // Pinch keeps the aspect ratio and the centre; twist rotates.
      final f = d.scale.clamp(0.2, 6.0);
      final aspect = _startSize.width / _startSize.height;
      var w = (_startSize.width * f).clamp(0.05, 1.5);
      var h = w / aspect;
      if (h > 1.5) {
        h = 1.5;
        w = h * aspect;
      }
      final center = pos + Offset(size.width / 2, size.height / 2);
      size = Size(w, h);
      pos = center - Offset(w / 2, h / 2);
      rotation = _startRotation + d.rotation * 180 / math.pi;
    }
    pos += Offset(d.focalPointDelta.dx / parent.width,
        d.focalPointDelta.dy / parent.height);
    // Keep at least a sliver on the canvas.
    pos = Offset(pos.dx.clamp(-size.width + 0.05, 0.95),
        pos.dy.clamp(-size.height + 0.05, 0.95));
    setState(() {
      _dragSize = size;
      _dragPos = pos;
      // Shown (and dropped) snapped to the guides; the raw position keeps
      // following the finger so the item can leave a guide again.
      _snappedPos = SnapGuides.snapBox(pos, size);
      _dragRotation = rotation;
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final size = _dragSize ?? _startSize;
    final pos = _snappedPos ?? _dragPos ?? _startPos;
    var rotation = _dragRotation ?? _startRotation;
    // Snap near-straight rotations to the nearest quarter turn.
    final quarter = (rotation / 90).round() * 90.0;
    if ((rotation - quarter).abs() < 4) rotation = quarter;
    SnapGuides.clear();
    widget.onTransformEnd(pos, size, rotation);
    setState(() {
      _dragPos = null;
      _snappedPos = null;
      _dragSize = null;
      _dragRotation = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    final parent = widget.parentSize;
    final local = widget.timelinePosition - clip.startTime;
    final (kfPos, kfSize) = OverlayKeyframe.boxAt(clip, local);
    final pos = _snappedPos ?? _dragPos ?? kfPos;
    final size = _dragSize ?? kfSize;
    final rotation = _dragRotation ?? clip.rotation;

    // In/out animation while playing (shown fully while editing or paused,
    // so the overlay can be seen and dragged).
    var anim = const TextAnimState();
    if (widget.isPlaying && !widget.isSelected && _dragPos == null) {
      final len = (clip.endTime - clip.startTime).inMilliseconds / 1000.0;
      anim = TextAnimations.atTimes(
          clip.animIn, clip.animOut, len, local.inMilliseconds / 1000.0);
    }

    final w = size.width * parent.width;
    final h = size.height * parent.height;
    final masked = OverlayShapes.isMasked(clip);
    final buttonSize = (math.min(w, h) * 0.22).clamp(44.0, 88.0);

    Widget tile = Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        if (masked)
          ClipPath(
              clipper: OverlayShapeClipper(clip.maskShape), child: _media())
        else
          _media(),
        if (OverlayShapes.hasDecoration(clip))
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: OverlayDecorationPainter(clip)),
            ),
          ),
        if (widget.isSelected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 6),
                ),
              ),
            ),
          ),
      ],
    );
    if (rotation != 0) {
      tile = Transform.rotate(angle: rotation * math.pi / 180, child: tile);
    }

    final opacity =
        (clip.overlayOpacity * anim.opacity).clamp(0.0, 1.0).toDouble();
    return Positioned(
      left: pos.dx * parent.width,
      top: pos.dy * parent.height,
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected,
        onScaleStart: (d) => _onScaleStart(d, kfPos, kfSize),
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Transform.translate(
              offset: Offset(0, anim.dy),
              child: Transform.scale(
                scale: anim.scale,
                child: Opacity(opacity: opacity, child: tile),
              ),
            ),
            if (widget.isSelected)
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: Container(
                    width: buttonSize,
                    height: buttonSize,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close,
                        size: buttonSize * 0.5, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
