import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../models/video_effect.dart';
import '../providers/video_editor_provider.dart';
import 'effect_engine.dart';

/// Live preview of clip effects over [child] (the preview canvas content).
///
/// Cost model, to keep playback smooth:
/// * no effect at the playhead -> returns [child] untouched;
/// * colour effects -> one combined [ColorFiltered];
/// * animated effects (shake, flash, glitch) -> a ticker re-evaluates them
///   each frame only while one is on screen and the video is playing.
class EffectsPreview extends StatefulWidget {
  final VideoEditorProvider provider;
  final Widget child;

  const EffectsPreview({super.key, required this.provider, required this.child});

  @override
  State<EffectsPreview> createState() => _EffectsPreviewState();
}

class _EffectsPreviewState extends State<EffectsPreview>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) {
    if (mounted) setState(() {});
  });

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker(bool animate) {
    if (animate && !_ticker.isActive) {
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.provider.currentProject;
    if (project == null || project.videoEffects.isEmpty) {
      _syncTicker(false);
      return widget.child;
    }
    final active =
        EffectEngine.activeAt(project, widget.provider.smoothPosition);
    final animated = active.any((a) => EffectEngine.isAnimated(a.$1.type));
    _syncTicker(animated && widget.provider.isPlaying);
    if (active.isEmpty) return widget.child;

    var content = widget.child;

    // Colour effects, composed into a single matrix (one layer).
    List<double>? matrix;
    for (final (e, t) in active) {
      final m = EffectEngine.colorMatrix(e, t);
      if (m == null) continue;
      matrix = matrix == null ? m : EffectEngine.multiply(m, matrix);
    }
    if (matrix != null) {
      content = ColorFiltered(
        colorFilter: ui.ColorFilter.matrix(matrix),
        child: content,
      );
    }

    for (final (e, t) in active) {
      final i = e.intensity.clamp(0.05, 1.0).toDouble();
      switch (e.type) {
        case VideoEffectType.blur:
          final sigma = EffectEngine.blurSigma(i);
          content = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
                sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
            child: content,
          );
          break;
        case VideoEffectType.vintage:
          content = Stack(
            fit: StackFit.expand,
            children: [
              content,
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.95,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55 * i),
                      ],
                      stops: const [0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          );
          break;
        case VideoEffectType.glitch:
          if (!EffectEngine.glitchOn(t)) break;
          final d = EffectEngine.glitchShift(i);
          content = Stack(
            fit: StackFit.expand,
            children: [
              content,
              // Red and blue ghosts pushed apart: an RGB split.
              IgnorePointer(
                child: Opacity(
                  opacity: 0.45,
                  child: Transform.translate(
                    offset: Offset(-d, 0),
                    child: ColorFiltered(
                      colorFilter: const ui.ColorFilter.matrix([
                        1, 0, 0, 0, 0, //
                        0, 0, 0, 0, 0, //
                        0, 0, 0, 0, 0, //
                        0, 0, 0, 1, 0,
                      ]),
                      child: content,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Opacity(
                  opacity: 0.45,
                  child: Transform.translate(
                    offset: Offset(d, 0),
                    child: ColorFiltered(
                      colorFilter: const ui.ColorFilter.matrix([
                        0, 0, 0, 0, 0, //
                        0, 0, 0, 0, 0, //
                        0, 0, 1, 0, 0, //
                        0, 0, 0, 1, 0,
                      ]),
                      child: content,
                    ),
                  ),
                ),
              ),
            ],
          );
          break;
        case VideoEffectType.shake:
          final o = EffectEngine.shakeOffset(i, t);
          content = ClipRect(
            child: Transform.translate(
              offset: o,
              child: Transform.scale(
                scale: EffectEngine.shakeScale(i),
                child: content,
              ),
            ),
          );
          break;
        default:
          break;
      }
    }
    return content;
  }
}
