library;

import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

// ──────────────────────────────────────────────
//  Base abstract class
// ──────────────────────────────────────────────

abstract class VideoTransition {
  String get displayName;
  IconData get icon;

  // Note: the progress 't' is normalized 0 -> 1.
  Widget build(double t, Widget A, Widget B);
}

// ──────────────────────────────────────────────
//  1. Zoom
// ──────────────────────────────────────────────
class ZoomTransition extends VideoTransition {
  @override
  String get displayName => 'Zoom';
  @override
  IconData get icon => Icons.zoom_in;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(scale: 1.0 + 0.3 * p, child: A),
        Opacity(
          opacity: p,
          child: Transform.scale(scale: 0.7 + 0.3 * p, child: B),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  2. Fade to Black
// ──────────────────────────────────────────────
class BlackTransition extends VideoTransition {
  @override
  String get displayName => 'Fade to Black';
  @override
  IconData get icon => Icons.brightness_1;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        if (p < 0.5)
          Opacity(opacity: (1.0 - (p * 2)).clamp(0.0, 1.0), child: A)
        else
          Opacity(opacity: ((p - 0.5) * 2).clamp(0.0, 1.0), child: B),
        IgnorePointer(
          child: ColoredBox(
              color: const Color(0xFF000000)
                  .withValues(alpha: 1.0 - (1.0 - (p * 2 - 1).abs()))),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  3. Fade to White
// ──────────────────────────────────────────────
class WhiteTransition extends VideoTransition {
  @override
  String get displayName => 'Fade to White';
  @override
  IconData get icon => Icons.brightness_5;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        if (p < 0.5)
          Opacity(opacity: (1.0 - (p * 2)).clamp(0.0, 1.0), child: A)
        else
          Opacity(opacity: ((p - 0.5) * 2).clamp(0.0, 1.0), child: B),
        IgnorePointer(
          child: ColoredBox(
              color: const Color(0xFFFFFFFF)
                  .withValues(alpha: 1.0 - (1.0 - (p * 2 - 1).abs()))),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  4. Dissolve
// ──────────────────────────────────────────────
class DissolveTransition extends VideoTransition {
  @override
  String get displayName => 'Dissolve';
  @override
  IconData get icon => Icons.opacity;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: (1.0 - p).clamp(0.0, 1.0), child: A),
        Opacity(opacity: p.clamp(0.0, 1.0), child: B),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  5. Shake
// ──────────────────────────────────────────────
class ShakeTransition extends VideoTransition {
  @override
  String get displayName => 'Shake';
  @override
  IconData get icon => Icons.vibration;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    final shake = sin(p * 20) * 25;

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.translate(offset: Offset(shake, 0), child: A),
        Opacity(opacity: p.clamp(0.0, 1.0), child: B),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  6. Light Flash
// ──────────────────────────────────────────────
class LightTransition extends VideoTransition {
  @override
  String get displayName => 'Light';
  @override
  IconData get icon => Icons.flash_on;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        A,
        Opacity(
          opacity: sin(p * pi).clamp(0.0, 1.0),
          child: const ColoredBox(color: Color(0xFFFFFFFF)),
        ),
        Opacity(opacity: p.clamp(0.0, 1.0), child: B),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  7. Blur
// ──────────────────────────────────────────────
class BlurTransition extends VideoTransition {
  @override
  String get displayName => 'Blur';
  @override
  IconData get icon => Icons.blur_on;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    // A fades out slightly while blurring to avoid holding sharp frame too long
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: (1.0 - (p * 0.5)).clamp(0.0, 1.0),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 10 * p, sigmaY: 10 * p),
            child: A,
          ),
        ),
        Opacity(
          opacity: p.clamp(0.0, 1.0),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 10 * (1.0 - p),
              sigmaY: 10 * (1.0 - p),
            ),
            child: B,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  8. Pixelate (Simulated scale trick)
// ──────────────────────────────────────────────
class PixelateTransition extends VideoTransition {
  @override
  String get displayName => 'Pixelate';
  @override
  IconData get icon => Icons.grid_on;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    double scaleFactor = 1.0 + (1.0 - p) * 0.4;

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(scale: scaleFactor, child: A),
        Opacity(
          opacity: p.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1.0 / scaleFactor,
            child: B,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  9. Circle Reveal
// ──────────────────────────────────────────────
class CircleTransition extends VideoTransition {
  @override
  String get displayName => 'Circle';
  @override
  IconData get icon => Icons.circle_outlined;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        A,
        ClipPath(
          clipper: CircleClipper(p),
          child: B,
        ),
      ],
    );
  }
}

class CircleClipper extends CustomClipper<Path> {
  final double t;
  CircleClipper(this.t);

  @override
  Path getClip(Size size) {
    final maxRadius = sqrt(size.width * size.width + size.height * size.height);
    final radius = maxRadius * t.clamp(0.0, 1.0);
    return Path()
      ..addOval(Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: radius,
      ));
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
}

// ──────────────────────────────────────────────
//  10. Push (Right to Left)
// ──────────────────────────────────────────────
class PushTransition extends VideoTransition {
  @override
  String get displayName => 'Push';
  @override
  IconData get icon => Icons.forward;

  @override
  Widget build(double t, Widget A, Widget B) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

      return Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(offset: Offset(-p * w, 0.0), child: A),
          Transform.translate(offset: Offset((1.0 - p) * w, 0.0), child: B),
        ],
      );
    });
  }
}

// ──────────────────────────────────────────────
//  11. Push Right (Left to Right)
// ──────────────────────────────────────────────
class PushRightTransition extends VideoTransition {
  @override
  String get displayName => 'Push Right';
  @override
  IconData get icon => Icons.arrow_forward;

  @override
  Widget build(double t, Widget A, Widget B) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

      return Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(offset: Offset(p * w, 0.0), child: A),
          Transform.translate(offset: Offset(-(1.0 - p) * w, 0.0), child: B),
        ],
      );
    });
  }
}

// ──────────────────────────────────────────────
//  11. Rotate 1
// ──────────────────────────────────────────────
class Rotate1Transition extends VideoTransition {
  @override
  String get displayName => 'Rotate 1';
  @override
  IconData get icon => Icons.rotate_right;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: (1.0 - p).clamp(0.0, 1.0),
          child: Transform.rotate(angle: -p * pi, child: A),
        ),
        Opacity(
          opacity: p.clamp(0.0, 1.0),
          child: Transform.rotate(angle: (1.0 - p) * pi, child: B),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  12. Rotate 2 (3D flip)
// ──────────────────────────────────────────────
class Rotate2Transition extends VideoTransition {
  @override
  String get displayName => 'Rotate 2';
  @override
  IconData get icon => Icons.rotate_left;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: (1.0 - p).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(-p * pi)..setEntry(3, 2, 0.001),
            child: A,
          ),
        ),
        Opacity(
          opacity: p.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY((1.0 - p) * pi)..setEntry(3, 2, 0.001),
            child: B,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  13. Slide
// ──────────────────────────────────────────────
class SlideTransitionEffect extends VideoTransition {
  @override
  String get displayName => 'Slide';
  @override
  IconData get icon => Icons.arrow_back;

  @override
  Widget build(double t, Widget A, Widget B) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

      return Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(offset: Offset(-p * w, 0.0), child: A),
          Transform.translate(offset: Offset((1.0 - p) * w, 0.0), child: B),
        ],
      );
    });
  }
}

// ──────────────────────────────────────────────
//  14. Wipe
// ──────────────────────────────────────────────
class WipeTransition extends VideoTransition {
  @override
  String get displayName => 'Wipe';
  @override
  IconData get icon => Icons.cleaning_services;

  @override
  Widget build(double t, Widget A, Widget B) {
    final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        A,
        ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: p,
            child: B,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  15. Blink
// ──────────────────────────────────────────────
class BlinkTransition extends VideoTransition {
  @override
  String get displayName => 'Blink';
  @override
  IconData get icon => Icons.visibility;

  @override
  Widget build(double t, Widget A, Widget B) {
    // 0.0 - 0.5 favors A, 0.5 - 1.0 favors B but oscillates wildly
    final rawFlash = sin(t * pi * 8);
    final isA = rawFlash > 0.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (t < 0.95) isA ? A : B else B,
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  16. Vertical
// ──────────────────────────────────────────────
class VerticalTransition extends VideoTransition {
  @override
  String get displayName => 'Vertical';
  @override
  IconData get icon => Icons.swap_vert;

  @override
  Widget build(double t, Widget A, Widget B) {
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight;
      final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

      return Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(offset: Offset(0.0, -p * h), child: A),
          Transform.translate(offset: Offset(0.0, (1.0 - p) * h), child: B),
        ],
      );
    });
  }
}

// ──────────────────────────────────────────────
//  17. Horizontal
// ──────────────────────────────────────────────
class HorizontalTransition extends VideoTransition {
  @override
  String get displayName => 'Horizontal';
  @override
  IconData get icon => Icons.swap_horiz;

  @override
  Widget build(double t, Widget A, Widget B) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final p = Curves.easeInOut.transform(t.clamp(0.0, 1.0));

      return Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(offset: Offset(-p * w, 0.0), child: A),
          Transform.translate(offset: Offset((1.0 - p) * w, 0.0), child: B),
        ],
      );
    });
  }
}
