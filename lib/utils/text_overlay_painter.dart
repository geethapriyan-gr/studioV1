import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/video_project.dart';

/// Draws a text overlay (background box, outline, shadow, fill). The editor
/// preview and the exporter both paint through this class, so the styles
/// look identical in the editor and in the exported video.
class TextOverlayPainter {
  final TextOverlay overlay;
  final double fontSize;
  late final TextPainter _fill;
  TextPainter? _stroke;

  /// Largest font size drawn (canvas pixels). The editor's slider and pinch
  /// stop here so every size they offer is a size that renders.
  static const double maxFontSize = 512.0;

  TextOverlayPainter(this.overlay, {double? fontSize})
      : fontSize =
            (fontSize ?? overlay.fontSize).clamp(1.0, maxFontSize).toDouble() {
    _fill = TextPainter(
      text: TextSpan(text: overlay.text, style: style(this.fontSize)),
      textAlign: overlay.flutterTextAlign,
      textDirection: TextDirection.ltr,
    )..layout();
    final outline = overlay.outlineColor;
    if (outline != null && overlay.outlineWidth > 0) {
      _stroke = TextPainter(
        text: TextSpan(
          text: overlay.text,
          style: style(
            this.fontSize,
            withShadow: false,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = outline,
          ),
        ),
        textAlign: overlay.flutterTextAlign,
        textDirection: TextDirection.ltr,
      )..layout();
    }
  }

  /// Outline thickness in canvas pixels (scales with the font size).
  double get strokeWidth => overlay.outlineWidth * fontSize / 24;

  EdgeInsets get boxPadding => overlay.boxColor == null
      ? EdgeInsets.zero
      : EdgeInsets.symmetric(
          horizontal: fontSize * 0.35, vertical: fontSize * 0.14);

  /// Size of the drawn content: text plus box padding.
  Size get size {
    final p = boxPadding;
    final s = _fill.size;
    return Size(s.width + p.horizontal, s.height + p.vertical);
  }

  TextStyle style(double size, {bool withShadow = true, Paint? foreground}) {
    final shadows = withShadow && overlay.shadow
        ? [
            Shadow(
              offset: Offset(size * 0.04, size * 0.06),
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: size * 0.12,
            ),
          ]
        : const <Shadow>[];
    try {
      return GoogleFonts.getFont(
        overlay.fontFamily,
        fontSize: size,
        color: foreground == null ? overlay.color : null,
        foreground: foreground,
        fontWeight: overlay.fontWeight,
        fontStyle: overlay.flutterFontStyle,
        shadows: shadows,
      );
    } catch (_) {
      return GoogleFonts.roboto(
        fontSize: size,
        color: foreground == null ? overlay.color : null,
        foreground: foreground,
        fontWeight: overlay.fontWeight,
        fontStyle: overlay.flutterFontStyle,
        shadows: shadows,
      );
    }
  }

  /// Paints with the content's top-left at [origin]. [reveal] (0..1) shows
  /// only the left part of the content (typewriter animation).
  void paint(Canvas canvas, Offset origin, {double reveal = 1}) {
    final s = size;
    final r = reveal.clamp(0.0, 1.0);
    if (r <= 0) return;
    canvas.save();
    if (r < 1) {
      canvas.clipRect(Rect.fromLTWH(
          origin.dx - 2, origin.dy - s.height, s.width * r + 2, s.height * 3));
    }
    final box = overlay.boxColor;
    if (box != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          origin & s,
          Radius.circular(fontSize * 0.22),
        ),
        Paint()..color = box,
      );
    }
    final textOrigin = origin + Offset(boxPadding.left, boxPadding.top);
    _stroke?.paint(canvas, textOrigin);
    _fill.paint(canvas, textOrigin);
    canvas.restore();
  }

  /// Fonts the text styles may load (for awaiting before rasterizing).
  List<TextStyle> get styles => [style(fontSize)];
}

/// In/out text animations (shared by preview and export).
class TextAnimations {
  TextAnimations._();

  static const String none = 'none';
  static const List<(String, String, IconData)> all = [
    ('none', 'None', Icons.block_rounded),
    ('fade', 'Fade', Icons.blur_on_rounded),
    ('slide', 'Slide', Icons.swipe_up_rounded),
    ('pop', 'Pop', Icons.bubble_chart_rounded),
    ('typewriter', 'Type', Icons.keyboard_rounded),
  ];

  /// Animations for stickers and media overlays (typewriter is text-only).
  static const List<(String, String, IconData)> motion = [
    ('none', 'None', Icons.block_rounded),
    ('fade', 'Fade', Icons.blur_on_rounded),
    ('slide', 'Slide', Icons.swipe_up_rounded),
    ('pop', 'Pop', Icons.bubble_chart_rounded),
  ];

  /// Animation length: 0.5 s, or a third of the overlay when shorter.
  static double seconds(TextOverlay o) =>
      secondsFor((o.endTime - o.startTime).inMilliseconds / 1000.0);

  /// Animation length for an item [len] seconds long.
  static double secondsFor(double len) => math.min(0.5, len / 3);

  /// State of the text at [t] seconds into the overlay.
  static TextAnimState at(TextOverlay o, double t) => atTimes(o.animIn,
      o.animOut, (o.endTime - o.startTime).inMilliseconds / 1000.0, t);

  /// State of any animated item ([len] seconds long) at [t] seconds in.
  static TextAnimState atTimes(
      String animIn, String animOut, double len, double t) {
    final d = secondsFor(len);
    var state = const TextAnimState();
    if (d <= 0) return state;
    if (animIn != none && t < d) {
      state = _apply(animIn, (t / d).clamp(0.0, 1.0), state);
    }
    final fromEnd = len - t;
    if (animOut != none && fromEnd < d) {
      state = _apply(animOut, (fromEnd / d).clamp(0.0, 1.0), state);
    }
    return state;
  }

  /// [p] goes 0 -> 1 as the text becomes fully visible.
  static TextAnimState _apply(String kind, double p, TextAnimState s) {
    // Ease out for a lively feel.
    final e = 1 - math.pow(1 - p, 3).toDouble();
    switch (kind) {
      case 'fade':
        return s.copyWith(opacity: s.opacity * p);
      case 'slide':
        return s.copyWith(
            opacity: s.opacity * p, dy: s.dy + (1 - e) * slideDistance);
      case 'pop':
        return s.copyWith(
            opacity: s.opacity * math.min(1, p * 2), scale: s.scale * popScale(p));
      case 'typewriter':
        return s.copyWith(reveal: s.reveal * p);
      default:
        return s;
    }
  }

  /// Slide distance in canvas pixels (of the 1920-px-tall canvas).
  static const double slideDistance = 60;

  /// Pop: 0.6 -> 1.08 -> 1.0 (overshoot).
  static double popScale(double p) {
    if (p < 0.7) return 0.6 + 0.48 * (p / 0.7);
    return 1.08 - 0.08 * ((p - 0.7) / 0.3);
  }
}

class TextAnimState {
  final double opacity;
  final double scale;
  final double dy;
  final double reveal;

  const TextAnimState({
    this.opacity = 1,
    this.scale = 1,
    this.dy = 0,
    this.reveal = 1,
  });

  TextAnimState copyWith(
          {double? opacity, double? scale, double? dy, double? reveal}) =>
      TextAnimState(
        opacity: opacity ?? this.opacity,
        scale: scale ?? this.scale,
        dy: dy ?? this.dy,
        reveal: reveal ?? this.reveal,
      );

  bool get isIdle => opacity >= 1 && scale == 1 && dy == 0 && reveal >= 1;
}
