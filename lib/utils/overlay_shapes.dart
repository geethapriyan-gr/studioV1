import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/video_project.dart';

/// Mask shapes, borders and drop shadows for media overlays. The editor
/// preview and the exporter both draw through this class, so an overlay
/// looks the same in both.
///
/// Sizes are in canvas pixels of the 1920-px-tall preview design space;
/// callers scale them to their own pixels.
class OverlayShapes {
  OverlayShapes._();

  static const List<(String, String, IconData)> all = [
    ('none', 'None', Icons.crop_square_rounded),
    ('rounded', 'Rounded', Icons.rounded_corner_rounded),
    ('circle', 'Circle', Icons.circle_outlined),
    ('heart', 'Heart', Icons.favorite_border_rounded),
    ('star', 'Star', Icons.star_border_rounded),
    ('hexagon', 'Hexagon', Icons.hexagon_outlined),
    ('diamond', 'Diamond', Icons.diamond_outlined),
  ];

  /// Shadow look, in canvas pixels.
  static const double shadowBlur = 28;
  static const Offset shadowOffset = Offset(0, 12);
  static const Color shadowColor = Color(0x80000000);

  /// Space around the box that a border and shadow may paint into, in
  /// canvas pixels.
  static double margin(VideoClip clip) {
    var m = 0.0;
    if (clip.hasBorder) m = math.max(m, clip.borderWidth);
    if (clip.shadow) {
      m = math.max(m, shadowBlur * 1.5 + shadowOffset.distance);
    }
    return m.ceilToDouble();
  }

  /// True when the overlay is drawn through a mask (media fills the box).
  static bool isMasked(VideoClip clip) =>
      clip.maskShape != 'none' && clip.maskShape.isNotEmpty;

  /// Whether the overlay has anything for [paintDecoration] to draw.
  static bool hasDecoration(VideoClip clip) => clip.hasBorder || clip.shadow;

  /// Outline of [shape] filling [box].
  static Path pathFor(String shape, Rect box) {
    final w = box.width;
    final h = box.height;
    final c = box.center;
    switch (shape) {
      case 'rounded':
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
              box, Radius.circular(math.min(w, h) * 0.12)));
      case 'circle':
        return Path()
          ..addOval(Rect.fromCenter(
              center: c, width: math.min(w, h), height: math.min(w, h)));
      case 'heart':
        final path = Path();
        path.moveTo(c.dx, box.top + h * 0.28);
        path.cubicTo(box.left + w * 0.95, box.top - h * 0.12,
            box.right + w * 0.25, box.top + h * 0.55, c.dx, box.bottom);
        path.cubicTo(box.left - w * 0.25, box.top + h * 0.55,
            box.left + w * 0.05, box.top - h * 0.12, c.dx, box.top + h * 0.28);
        path.close();
        return path;
      case 'star':
        final path = Path();
        final outer = math.min(w, h) / 2;
        final inner = outer * 0.45;
        for (int i = 0; i < 10; i++) {
          final r = i.isEven ? outer : inner;
          final a = -math.pi / 2 + i * math.pi / 5;
          final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        return path..close();
      case 'hexagon':
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final a = math.pi / 6 + i * math.pi / 3;
          final pt =
              Offset(c.dx + w / 2 * math.cos(a), c.dy + h / 2 * math.sin(a));
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        return path..close();
      case 'diamond':
        return Path()
          ..moveTo(c.dx, box.top)
          ..lineTo(box.right, c.dy)
          ..lineTo(c.dx, box.bottom)
          ..lineTo(box.left, c.dy)
          ..close();
      default:
        return Path()..addRect(box);
    }
  }

  /// Draws the shadow (outside the shape only, so keyed or masked media
  /// never shows it through) and the border of an overlay whose box is
  /// [box]. [scale] converts canvas pixels to the target's pixels.
  static void paintDecoration(
      Canvas canvas, Rect box, VideoClip clip, double scale) {
    final shape = pathFor(clip.maskShape, box);
    if (clip.shadow) {
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(box.inflate(margin(clip) * scale + 4))
        ..addPath(shape, Offset.zero);
      canvas.save();
      canvas.clipPath(outside);
      canvas.drawPath(
        shape.shift(shadowOffset * scale),
        Paint()
          ..color = shadowColor
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, shadowBlur * scale / 2),
      );
      canvas.restore();
    }
    if (clip.hasBorder) {
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = clip.borderWidth * scale
          ..strokeJoin = StrokeJoin.round
          ..color = clip.borderColor!,
      );
    }
  }
}

/// Paints [OverlayShapes.paintDecoration] for a widget whose size is the
/// overlay box (paints outside its bounds for the shadow and border).
class OverlayDecorationPainter extends CustomPainter {
  final VideoClip clip;
  final double scale;

  OverlayDecorationPainter(this.clip, {this.scale = 1});

  @override
  void paint(Canvas canvas, Size size) {
    OverlayShapes.paintDecoration(canvas, Offset.zero & size, clip, scale);
  }

  @override
  bool shouldRepaint(OverlayDecorationPainter old) =>
      old.clip.maskShape != clip.maskShape ||
      old.clip.borderWidth != clip.borderWidth ||
      old.clip.borderColor != clip.borderColor ||
      old.clip.shadow != clip.shadow ||
      old.scale != scale;
}

/// Clips its child to an overlay mask shape.
class OverlayShapeClipper extends CustomClipper<Path> {
  final String shape;
  OverlayShapeClipper(this.shape);

  @override
  Path getClip(Size size) => OverlayShapes.pathFor(shape, Offset.zero & size);

  @override
  bool shouldReclip(OverlayShapeClipper old) => old.shape != shape;
}
