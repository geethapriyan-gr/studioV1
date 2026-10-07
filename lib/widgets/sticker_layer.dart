import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show AppColors;
import '../models/video_project.dart';
import '../providers/video_editor_provider.dart';
import '../utils/snap_guides.dart';
import '../utils/sticker_catalog.dart';
import '../utils/text_overlay_painter.dart';

/// Size of a sticker at scale 1, in canvas pixels of the 1920-px-tall
/// preview design space (the exporter uses the same value).
const double kStickerBaseSize = 600.0;

/// Image provider for a stored sticker path (bundled asset or own image).
ImageProvider stickerImageProvider(String path) {
  final resolved = StickerCatalog.resolve(path);
  return resolved.startsWith('assets/')
      ? AssetImage(resolved)
      : FileImage(File(resolved)) as ImageProvider;
}

class StickerLayer extends StatelessWidget {
  const StickerLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VideoEditorProvider>(context);
    final stickers = provider.currentStickers;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: stickers
              .map((sticker) => _DraggableStickerWidget(
                    key: ValueKey(sticker.id),
                    sticker: sticker,
                    constraints: constraints,
                  ))
              .toList(),
        );
      },
    );
  }
}

class _DraggableStickerWidget extends StatefulWidget {
  final StickerModel sticker;
  final BoxConstraints constraints;

  const _DraggableStickerWidget({
    super.key,
    required this.sticker,
    required this.constraints,
  });

  @override
  State<_DraggableStickerWidget> createState() =>
      _DraggableStickerWidgetState();
}

class _DraggableStickerWidgetState extends State<_DraggableStickerWidget>
    with SingleTickerProviderStateMixin {
  // Drag/pinch state; null when idle.
  Offset? _dragPos;
  double? _dragScale;
  double? _dragRotation;
  double _startScale = 1;
  double _startRotation = 0;

  /// Aspect ratio (w/h) of the sticker image, once known.
  double? _aspect;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  // Animations re-evaluate every frame while playing.
  late final _ticker = createTicker((_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(_DraggableStickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sticker.assetPath != widget.sticker.assetPath) {
      _unlisten();
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _unlisten();
    _ticker.dispose();
    super.dispose();
  }

  void _resolveImage() {
    final stream = stickerImageProvider(widget.sticker.assetPath)
        .resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener((info, _) {
      final w = info.image.width;
      final h = info.image.height;
      if (!mounted || w == 0 || h == 0) return;
      final a = w / h;
      if (_aspect != a) setState(() => _aspect = a);
    });
    stream.addListener(_listener!);
    _stream = stream;
  }

  void _unlisten() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  TextAnimState _anim(VideoEditorProvider p, bool selected) {
    final s = widget.sticker;
    final animated = s.animIn != 'none' || s.animOut != 'none';
    // Moving stickers re-evaluate every frame while playing, too.
    final moving =
        s.keyframeData.isNotEmpty && p.isPlaying && _dragPos == null;
    if (!animated || selected || !p.isPlaying || _dragPos != null) {
      _setTicking(moving);
      return const TextAnimState();
    }
    final len = (s.endTime - s.startTime).inMilliseconds / 1000.0;
    final t = (p.smoothPosition - s.startTime).inMicroseconds / 1e6;
    final state = TextAnimations.atTimes(s.animIn, s.animOut, len, t);
    _setTicking(moving || !state.isIdle);
    return state;
  }

  void _setTicking(bool on) {
    if (on && !_ticker.isActive) {
      _ticker.start();
    } else if (!on && _ticker.isActive) {
      _ticker.stop();
    }
  }

  /// Centre and scale at the current time (motion keyframes).
  (Offset, double) _motion(VideoEditorProvider p) {
    final s = widget.sticker;
    if (s.keyframeData.isEmpty) return (s.position, s.scale);
    final now = p.isPlaying ? p.smoothPosition : p.currentPosition;
    return ItemKeyframe.at(
        s.keyframeData, now - s.startTime, s.position, s.scale);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final s = widget.sticker;
    final isSelected = provider.selectedStickerId == s.id;
    final (motionPos, motionScale) = _motion(provider);
    final position = _dragPos ?? motionPos;
    final scale = _dragScale ?? motionScale;
    final rotation = _dragRotation ?? s.rotation;
    final cw = widget.constraints.maxWidth;
    final ch = widget.constraints.maxHeight;

    // The picture is contain-fitted into a square (600 * scale) centred on
    // the position, exactly as the exporter draws it. The widget covers
    // only the picture, so empty space around it does not steal taps.
    final side = kStickerBaseSize * scale;
    final aspect = _aspect ?? 1.0;
    final w = aspect >= 1 ? side : side * aspect;
    final h = aspect >= 1 ? side / aspect : side;
    final anim = _anim(provider, isSelected);
    final buttonSize = (math.min(w, h) * 0.25).clamp(44.0, 80.0);

    Widget picture = Image(
      image: stickerImageProvider(s.assetPath),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.broken_image_outlined, color: AppColors.textTertiary),
    );
    if (s.flipX) picture = Transform.flip(flipX: true, child: picture);

    return Positioned(
      left: position.dx * cw - w / 2,
      top: position.dy * ch - h / 2,
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => provider.selectSticker(s.id),
        onScaleStart: (_) {
          provider.selectSticker(s.id);
          _startScale = motionScale;
          _startRotation = s.rotation;
          setState(() {
            _dragPos = motionPos;
            _dragScale = motionScale;
            _dragRotation = s.rotation;
          });
        },
        onScaleUpdate: (d) {
          final raw = (_dragPos ?? motionPos) +
              Offset(d.focalPointDelta.dx / cw, d.focalPointDelta.dy / ch);
          setState(() {
            _dragPos = Offset(raw.dx.clamp(0.0, 1.0), raw.dy.clamp(0.0, 1.0));
            if (d.pointerCount >= 2) {
              _dragScale = (_startScale * d.scale).clamp(0.1, 10.0);
              _dragRotation = _startRotation + d.rotation;
            }
          });
          // Show the guides the centre will snap to.
          SnapGuides.snapCenter(_dragPos!);
        },
        onScaleEnd: (_) {
          final pos = SnapGuides.snapCenter(_dragPos ?? motionPos);
          SnapGuides.clear();
          var rot = _dragRotation ?? s.rotation;
          // Snap near-straight angles to the nearest quarter turn.
          final quarter = (rot / (math.pi / 2)).round() * (math.pi / 2);
          if ((rot - quarter).abs() < 0.07) rot = quarter;
          // One undo step for the whole gesture; with motion this edits the
          // keyframe at the playhead.
          provider.updateStickerTransform(
            s.id,
            position: pos,
            scale: _dragScale ?? motionScale,
            rotation: rot,
          );
          provider.sealUndo();
          setState(() {
            _dragPos = null;
            _dragScale = null;
            _dragRotation = null;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Transform.translate(
              offset: Offset(0, anim.dy),
              child: Transform.scale(
                scale: anim.scale,
                child: Transform.rotate(
                  angle: rotation,
                  child: Opacity(
                    opacity: (s.opacity * anim.opacity).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        border: isSelected
                            ? Border.all(color: AppColors.primary, width: 4)
                            : null,
                      ),
                      child: picture,
                    ),
                  ),
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => provider.removeSticker(s.id),
                  child: Container(
                    width: buttonSize,
                    height: buttonSize,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(blurRadius: 4, color: Colors.black26)
                      ],
                    ),
                    child: Icon(Icons.close,
                        color: Colors.white, size: buttonSize * 0.55),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
