import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A vector shape (rectangle, highlight box, circle, arrow, line) used like
/// a sticker. It is stored in [StickerModel.assetPath] as
/// `shape:<type>?c=<argb hex>&s=<stroke>&f=<0|1>&a=<aspect>`, so shapes get
/// everything stickers have (drag, pinch, rotate, motion, animation,
/// timeline, export); the picture is drawn from this spec instead of loaded
/// from a file.
@immutable
class ShapeSpec {
  /// 'rect' | 'round' | 'circle' | 'highlight' | 'arrow' | 'line'
  final String type;
  final Color color;

  /// Line thickness in thousandths of the shape's longer side.
  final double stroke;
  final bool filled;

  /// Width / height of the shape's box.
  final double aspect;

  const ShapeSpec({
    required this.type,
    this.color = const Color(0xFFFF3B30),
    this.stroke = 14,
    this.filled = false,
    this.aspect = 1.5,
  });

  static const String prefix = 'shape:';

  static bool isShape(String path) => path.startsWith(prefix);

  static const List<(String, String, IconData)> types = [
    ('rect', 'Box', Icons.crop_square_rounded),
    ('round', 'Rounded', Icons.rounded_corner_rounded),
    ('circle', 'Circle', Icons.circle_outlined),
    ('highlight', 'Highlight', Icons.highlight_alt_rounded),
    ('arrow', 'Arrow', Icons.arrow_right_alt_rounded),
    ('line', 'Line', Icons.horizontal_rule_rounded),
  ];

  /// Ready-made shapes offered in the sticker panel.
  static const List<(String, ShapeSpec)> presets = [
    ('Red box', ShapeSpec(type: 'rect')),
    ('Highlight', ShapeSpec(type: 'highlight', color: Color(0xFFFFD60A), aspect: 2.5)),
    ('Circle', ShapeSpec(type: 'circle', aspect: 1.0)),
    ('Arrow', ShapeSpec(type: 'arrow', aspect: 3.0, stroke: 40)),
    ('White arrow', ShapeSpec(type: 'arrow', color: Colors.white, aspect: 3.0, stroke: 40)),
    ('Rounded box', ShapeSpec(type: 'round', color: Color(0xFF34C759))),
    ('Underline', ShapeSpec(type: 'line', color: Color(0xFFFFD60A), aspect: 6, stroke: 40)),
    ('Filled tag', ShapeSpec(type: 'round', color: Color(0xCC000000), filled: true, aspect: 3)),
  ];

  /// Shapes that can be filled solid (arrows and lines are always solid).
  bool get canFill => type == 'rect' || type == 'round' || type == 'circle';

  static ShapeSpec? parse(String path) {
    if (!isShape(path)) return null;
    final uri = Uri.tryParse('x://${path.substring(prefix.length)}');
    if (uri == null) return null;
    final q = uri.queryParameters;
    final type = uri.host.isNotEmpty ? uri.host : 'rect';
    return ShapeSpec(
      type: type,
      color: Color(int.tryParse(q['c'] ?? '', radix: 16) ?? 0xFFFF3B30),
      stroke: double.tryParse(q['s'] ?? '') ?? 14,
      filled: q['f'] == '1',
      aspect: (double.tryParse(q['a'] ?? '') ?? 1.5).clamp(0.2, 10.0),
    );
  }

  String toPath() =>
      '$prefix$type?c=${color.toARGB32().toRadixString(16).padLeft(8, '0')}'
      '&s=${stroke.toStringAsFixed(1)}&f=${filled ? 1 : 0}'
      '&a=${aspect.toStringAsFixed(3)}';

  ShapeSpec copyWith(
          {String? type,
          Color? color,
          double? stroke,
          bool? filled,
          double? aspect}) =>
      ShapeSpec(
        type: type ?? this.type,
        color: color ?? this.color,
        stroke: stroke ?? this.stroke,
        filled: filled ?? this.filled,
        aspect: aspect ?? this.aspect,
      );

  /// Picture size for a longer side of [longSide] pixels.
  Size sizeFor(double longSide) => aspect >= 1
      ? Size(longSide, longSide / aspect)
      : Size(longSide * aspect, longSide);

  /// Draws the shape filling [size] (origin top-left).
  void paint(Canvas canvas, Size size) {
    final long = math.max(size.width, size.height);
    final sw = math.max(1.0, stroke / 1000 * long);
    final inset = Rect.fromLTWH(0, 0, size.width, size.height).deflate(sw / 2);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;
    final radius = Radius.circular(math.min(size.width, size.height) * 0.18);
    switch (type) {
      case 'round':
        final r = RRect.fromRectAndRadius(inset, radius);
        canvas.drawRRect(r, filled ? fill : line);
      case 'circle':
        canvas.drawOval(inset, filled ? fill : line);
      case 'highlight':
        final r = RRect.fromRectAndRadius(inset, radius * 0.4);
        canvas.drawRRect(
            r, Paint()..color = color.withValues(alpha: color.a * 0.32));
        canvas.drawRRect(r, line);
      case 'arrow':
        final h = size.height;
        final shaft = math.min(sw, h * 0.5);
        final headLen = math.min(size.width * 0.45, h * 0.95);
        final cy = h / 2;
        final x1 = size.width - headLen;
        canvas.drawLine(Offset(shaft / 2, cy), Offset(x1 + 1, cy),
            line..strokeWidth = shaft);
        canvas.drawPath(
          Path()
            ..moveTo(size.width, cy)
            ..lineTo(x1, cy - h * 0.48)
            ..lineTo(x1, cy + h * 0.48)
            ..close(),
          fill,
        );
      case 'line':
        final w = math.min(sw, size.height);
        canvas.drawLine(Offset(w / 2, size.height / 2),
            Offset(size.width - w / 2, size.height / 2), line..strokeWidth = w);
      default: // rect
        canvas.drawRect(inset, filled ? fill : line);
    }
  }

  /// Renders the shape to an image with a longer side of [longSide] px.
  Future<ui.Image> render({double longSide = 1200}) async {
    final size = sizeFor(longSide);
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
        math.max(1, size.width.round()), math.max(1, size.height.round()));
    picture.dispose();
    return image;
  }

  @override
  bool operator ==(Object other) =>
      other is ShapeSpec && other.toPath() == toPath();

  @override
  int get hashCode => toPath().hashCode;
}

/// Image provider drawing a [ShapeSpec] (so shapes work anywhere a sticker
/// picture is shown: preview, panel, timeline).
class ShapeImageProvider extends ImageProvider<ShapeImageProvider> {
  final ShapeSpec spec;
  const ShapeImageProvider(this.spec);

  @override
  Future<ShapeImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      ShapeImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      key.spec.render().then((image) => ImageInfo(image: image)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShapeImageProvider && other.spec == spec;

  @override
  int get hashCode => spec.hashCode;
}
