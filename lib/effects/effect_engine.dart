import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/video_effect.dart';
import '../models/video_project.dart';

/// Single source of truth for clip effects.
///
/// The live preview ([EffectsPreview]) and the exporter
/// ([EffectEngine.ffmpegGraph]) evaluate the same formulas, so what plays in
/// the editor is what ends up in the exported video. Distances are in
/// "design pixels" of the 1920-px-tall preview canvas and are scaled to the
/// output height on export.
class EffectEngine {
  EffectEngine._();

  static const double designHeight = 1920;

  /// Effects with a sensible default intensity, in picker order.
  static const List<VideoEffectType> pickerOrder = [
    VideoEffectType.shake,
    VideoEffectType.glitch,
    VideoEffectType.flash,
    VideoEffectType.blur,
    VideoEffectType.neon,
    VideoEffectType.vintage,
    VideoEffectType.sepia,
    VideoEffectType.grayscale,
  ];

  static String describe(VideoEffectType t) => switch (t) {
        VideoEffectType.shake => 'Camera shake',
        VideoEffectType.glitch => 'RGB split bursts',
        VideoEffectType.flash => 'Strobe flashes',
        VideoEffectType.blur => 'Soft focus',
        VideoEffectType.neon => 'Punchy colour',
        VideoEffectType.vintage => 'Faded film + vignette',
        VideoEffectType.sepia => 'Warm old photo',
        VideoEffectType.grayscale => 'Black & white',
      };

  static bool isAnimated(VideoEffectType t) =>
      t == VideoEffectType.shake ||
      t == VideoEffectType.glitch ||
      t == VideoEffectType.flash;

  // ── Timing ─────────────────────────────────────────────────────────────

  /// Timeline window of [e]: the whole clip it belongs to (so it follows the
  /// clip when it is moved or trimmed). Effects whose clip was deleted are
  /// inactive. Effects without a clip use their own start/duration.
  static (Duration, Duration)? window(VideoProject project, VideoEffect e) {
    if (e.clipId.isNotEmpty) {
      for (final c in project.videoClips) {
        if (c.id == e.clipId) return (c.startTime, c.endTime);
      }
      return null;
    }
    return (e.startTime, e.startTime + e.duration);
  }

  static List<(VideoEffect, double)> activeAt(
      VideoProject project, Duration position) {
    final out = <(VideoEffect, double)>[];
    for (final e in project.videoEffects) {
      final w = window(project, e);
      if (w == null) continue;
      if (position >= w.$1 && position < w.$2) {
        out.add((e, (position - w.$1).inMicroseconds / 1e6));
      }
    }
    return out;
  }

  static double _i(VideoEffect e) => e.intensity.clamp(0.05, 1.0).toDouble();

  // ── Shared formulas (t = seconds since the effect window started) ──────

  /// Shake amplitude in design pixels and the matching zoom that hides the
  /// borders the movement would reveal.
  static double shakeAmplitude(double i) => 34 * i;
  static double shakeScale(double i) =>
      1 + 2.2 * shakeAmplitude(i) / designHeight;
  static Offset shakeOffset(double i, double t) {
    final a = shakeAmplitude(i);
    return Offset(a * math.sin(t * 41), a * math.cos(t * 33));
  }

  /// Strobe: a flash at the start of every 0.6 s that decays over 0.2 s.
  static double flashAmount(double i, double t) {
    final phase = (t % 0.6) / 0.6;
    return 0.85 * i * math.max(0.0, 1 - phase * 3);
  }

  /// Glitch bursts: on for 45 % of every 1/7 s cycle.
  static bool glitchOn(double t) => (t * 7) % 1.0 < 0.45;
  static double glitchShift(double i) => 18 * i;

  static double blurSigma(double i) => 14 * i;

  // ── Colour matrices (preview) ──────────────────────────────────────────

  static const List<double> identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  static const List<double> _gray = [
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  static const List<double> _sepia = [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  /// Faded, warm film look (lifted blacks, softened colour).
  static const List<double> _vintage = [
    0.62, 0.32, 0.10, 0, 18, //
    0.22, 0.66, 0.10, 0, 12, //
    0.18, 0.28, 0.48, 0, 4, //
    0, 0, 0, 1, 0,
  ];

  static List<double> _lerp(List<double> to, double k) => [
        for (var n = 0; n < 20; n++) identity[n] + (to[n] - identity[n]) * k,
      ];

  static List<double> _saturation(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    return [
      lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0, //
      lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0, //
      lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _contrast(double c) {
    final o = 128 * (1 - c);
    return [
      c, 0, 0, 0, o, //
      0, c, 0, 0, o, //
      0, 0, c, 0, o, //
      0, 0, 0, 1, 0,
    ];
  }

  /// a ∘ b (apply b, then a).
  static List<double> multiply(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += a[r * 5 + k] * b[k * 5 + c];
        }
        if (c == 4) v += a[r * 5 + 4];
        out[r * 5 + c] = v;
      }
    }
    return out;
  }

  static double neonSaturation(double i) => 1 + 1.4 * i;
  static double neonContrast(double i) => 1 + 0.3 * i;

  /// Colour matrix of an effect at time t, or null when it is not a colour
  /// effect (or has no visible change at this instant).
  static List<double>? colorMatrix(VideoEffect e, double t) {
    final i = _i(e);
    switch (e.type) {
      case VideoEffectType.grayscale:
        return _lerp(_gray, i);
      case VideoEffectType.sepia:
        return _lerp(_sepia, i);
      case VideoEffectType.vintage:
        return _lerp(_vintage, i);
      case VideoEffectType.neon:
        return multiply(
            _contrast(neonContrast(i)), _saturation(neonSaturation(i)));
      case VideoEffectType.flash:
        final k = flashAmount(i, t);
        if (k <= 0.001) return null;
        // Brighten (like ffmpeg eq brightness) and wash out colour.
        return multiply(
          [
            1, 0, 0, 0, 0.6 * k * 255, //
            0, 1, 0, 0, 0.6 * k * 255, //
            0, 0, 1, 0, 0.6 * k * 255, //
            0, 0, 0, 1, 0,
          ],
          _saturation(1 - k),
        );
      default:
        return null;
    }
  }

  // ── Export (FFmpeg) ────────────────────────────────────────────────────

  static String _n(double v) => v.toStringAsFixed(5);

  static String _mixer(List<double> m) =>
      'colorchannelmixer=rr=${_n(m[0])}:rg=${_n(m[1])}:rb=${_n(m[2])}'
      ':gr=${_n(m[5])}:gg=${_n(m[6])}:gb=${_n(m[7])}'
      ':br=${_n(m[10])}:bg=${_n(m[11])}:bb=${_n(m[12])}';

  /// Builds a filtergraph segment from `[e0]` to `[$outLabel]` that applies
  /// every effect of [project] in its time window. Returns null when the
  /// project has no active effect. [width]/[height] are the output size.
  static String? ffmpegGraph(
    VideoProject project, {
    required int width,
    required int height,
    required double duration,
    String outLabel = 'b0',
  }) {
    final parts = <String>[];
    var cur = 'e0';
    var n = 0;
    final px = height / designHeight; // design px -> output px

    String next() => 'e${++n}';

    for (final e in project.videoEffects) {
      final w = window(project, e);
      if (w == null) continue;
      final s = w.$1.inMicroseconds / 1e6;
      final end = w.$2.inMicroseconds / 1e6;
      if (end <= s || s >= duration) continue;
      final i = _i(e);
      final en = "enable='between(t,${_n(s)},${_n(end)})'";
      // t relative to the window start, as in the preview formulas.
      final rt = '(t-${_n(s)})';

      switch (e.type) {
        case VideoEffectType.grayscale:
        case VideoEffectType.sepia:
        case VideoEffectType.vintage:
          final m = colorMatrix(e, 0)!;
          final o = next();
          parts.add('[$cur]${_mixer(m)}:$en[$o]');
          cur = o;
          // colorchannelmixer has no offsets; add them (lifted blacks).
          if (m[4].abs() > 0.5 || m[9].abs() > 0.5 || m[14].abs() > 0.5) {
            final l = next();
            parts.add("[$cur]lutrgb=r='clip(val+${_n(m[4])},0,255)'"
                ":g='clip(val+${_n(m[9])},0,255)'"
                ":b='clip(val+${_n(m[14])},0,255)':$en[$l]");
            cur = l;
          }
          if (e.type == VideoEffectType.vintage) {
            final v = next();
            parts.add('[$cur]vignette=angle=${_n(0.35 + 0.35 * i)}:$en[$v]');
            cur = v;
          }
          break;
        case VideoEffectType.neon:
          final o = next();
          parts.add('[$cur]eq=saturation=${_n(neonSaturation(i))}'
              ':contrast=${_n(neonContrast(i))}:$en[$o]');
          cur = o;
          break;
        case VideoEffectType.blur:
          final o = next();
          parts.add('[$cur]gblur=sigma=${_n(blurSigma(i) * px)}:$en[$o]');
          cur = o;
          break;
        case VideoEffectType.flash:
          // k = 0.85*i*max(0, 1 - 3*mod(rt,0.6)/0.6) inside the window.
          final k = 'between(t,${_n(s)},${_n(end)})*${_n(0.85 * i)}'
              '*max(0,1-3*mod($rt,0.6)/0.6)';
          final o = next();
          parts.add("[$cur]eq=brightness='0.6*$k':saturation='1-$k':eval=frame[$o]");
          cur = o;
          break;
        case VideoEffectType.glitch:
          final shift = math.max(1, (glitchShift(i) * px).round());
          final burst = "enable='between(t,${_n(s)},${_n(end)})"
              "*lt(mod($rt*7,1),0.45)'";
          final o1 = next();
          parts.add('[$cur]rgbashift=rh=-$shift:bh=$shift:$burst[$o1]');
          final o2 = next();
          parts.add('[$o1]noise=alls=${(18 * i).round()}:allf=t:$burst[$o2]');
          cur = o2;
          break;
        case VideoEffectType.shake:
          // Zoom in slightly and move the crop window; only the window is
          // processed (trim) and laid over the untouched frames.
          final scale = shakeScale(i);
          final amp = shakeAmplitude(i) * px;
          final a = next(), b = next(), sh = next(), o = next();
          final cw = '(iw/${_n(scale)})';
          final ch = '(ih/${_n(scale)})';
          final x = "'(iw-ow)/2-${_n(amp / scale)}*sin($rt*41)'";
          final y = "'(ih-oh)/2-${_n(amp / scale)}*cos($rt*33)'";
          parts.add('[$cur]split[$a][$b]');
          parts.add('[$b]trim=start=${_n(s)}:end=${_n(end)},'
              'crop=w=$cw:h=$ch:x=$x:y=$y,'
              'scale=$width:$height,setsar=1[$sh]');
          parts.add('[$a][$sh]overlay=0:0:eof_action=pass[$o]');
          cur = o;
          break;
      }
    }
    if (parts.isEmpty) return null;
    // Rename the last label to the requested output.
    final last = parts.removeLast();
    parts.add(last.replaceFirst(RegExp(r'\[[^\]]+\]$'), '[$outLabel]'));
    return '${parts.join(';')};';
  }
}
