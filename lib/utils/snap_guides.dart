import 'package:flutter/material.dart';

/// Guide lines an item being dragged on the preview can snap to.
enum SnapLine { centerV, centerH, left, right, top, bottom }

/// Snapping for items dragged on the preview canvas (normalized 0..1
/// coordinates). While a drag snaps, [active] holds the lines to draw.
class SnapGuides {
  SnapGuides._();

  /// Lines currently snapped to (shown by [SnapGuideOverlay]).
  static final ValueNotifier<Set<SnapLine>> active =
      ValueNotifier<Set<SnapLine>>(const {});

  /// Snap distance as a fraction of the canvas.
  static const double threshold = 0.018;

  static void clear() {
    if (active.value.isNotEmpty) active.value = const {};
  }

  /// Snaps a point (an item's centre) to the canvas centre lines.
  static Offset snapCenter(Offset center) {
    final lines = <SnapLine>{};
    var x = center.dx;
    var y = center.dy;
    if ((x - 0.5).abs() < threshold) {
      x = 0.5;
      lines.add(SnapLine.centerV);
    }
    if ((y - 0.5).abs() < threshold) {
      y = 0.5;
      lines.add(SnapLine.centerH);
    }
    _publish(lines);
    return Offset(x, y);
  }

  /// Snaps a box (top-left [topLeft], [size]) by its centre to the canvas
  /// centre lines and by its edges to the canvas edges. Returns the new
  /// top-left.
  static Offset snapBox(Offset topLeft, Size size) {
    final lines = <SnapLine>{};
    var x = topLeft.dx;
    var y = topLeft.dy;
    final cx = x + size.width / 2;
    final cy = y + size.height / 2;
    if ((cx - 0.5).abs() < threshold) {
      x = 0.5 - size.width / 2;
      lines.add(SnapLine.centerV);
    } else if (x.abs() < threshold) {
      x = 0;
      lines.add(SnapLine.left);
    } else if ((x + size.width - 1).abs() < threshold) {
      x = 1 - size.width;
      lines.add(SnapLine.right);
    }
    if ((cy - 0.5).abs() < threshold) {
      y = 0.5 - size.height / 2;
      lines.add(SnapLine.centerH);
    } else if (y.abs() < threshold) {
      y = 0;
      lines.add(SnapLine.top);
    } else if ((y + size.height - 1).abs() < threshold) {
      y = 1 - size.height;
      lines.add(SnapLine.bottom);
    }
    _publish(lines);
    return Offset(x, y);
  }

  static void _publish(Set<SnapLine> lines) {
    final cur = active.value;
    if (cur.length == lines.length && cur.containsAll(lines)) return;
    active.value = lines;
  }
}

/// Draws the snap guide lines over the preview canvas while dragging.
class SnapGuideOverlay extends StatelessWidget {
  const SnapGuideOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<Set<SnapLine>>(
        valueListenable: SnapGuides.active,
        builder: (context, lines, _) => lines.isEmpty
            ? const SizedBox.expand()
            : CustomPaint(
                size: Size.infinite, painter: _SnapGuidePainter(lines)),
      ),
    );
  }
}

class _SnapGuidePainter extends CustomPainter {
  final Set<SnapLine> lines;
  _SnapGuidePainter(this.lines);

  @override
  void paint(Canvas canvas, Size size) {
    // The canvas is the 1920-px-tall design space; keep lines visible after
    // the preview is scaled down to the screen.
    final paint = Paint()
      ..color = const Color(0xFFFF2D95)
      ..strokeWidth = size.height / 320;
    for (final l in lines) {
      switch (l) {
        case SnapLine.centerV:
          canvas.drawLine(Offset(size.width / 2, 0),
              Offset(size.width / 2, size.height), paint);
        case SnapLine.centerH:
          canvas.drawLine(Offset(0, size.height / 2),
              Offset(size.width, size.height / 2), paint);
        case SnapLine.left:
          canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
        case SnapLine.right:
          canvas.drawLine(Offset(size.width, 0),
              Offset(size.width, size.height), paint);
        case SnapLine.top:
          canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
        case SnapLine.bottom:
          canvas.drawLine(Offset(0, size.height),
              Offset(size.width, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SnapGuidePainter old) => old.lines != lines;
}
