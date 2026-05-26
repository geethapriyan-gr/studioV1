import 'dart:math';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  static const String backgroundAsset = 'assets/background_image.jpeg';

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Controllers
  late AnimationController _irisCtrl;
  late AnimationController _bgCtrl;
  late AnimationController _mandalaCtrl;
  late AnimationController _logoCtrl;
  late AnimationController _scanCtrl;
  late AnimationController _glowCtrl;
  late AnimationController _raysCtrl;

  // Animations
  late Animation<double> _irisOpen;
  late Animation<double> _bgFade;
  late Animation<double> _logoFlipY;
  late Animation<double> _logoFade;
  late Animation<double> _mandalaAppear;
  late Animation<double> _raysAppear;
  late Animation<double> _scanProgress;
  late Animation<double> _glowPulse;
  late Animation<double> _studioVSpacing;
  late Animation<double> _studioVScale;

  @override
  void initState() {
    super.initState();

    _irisCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 950));
    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _mandalaCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 10))
      ..repeat();
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850));
    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _raysCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    _irisOpen = CurvedAnimation(parent: _irisCtrl, curve: Curves.easeInOutCubic);
    _bgFade = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeIn);

    // Logo 3D Y-axis flip: pi/2 → 0
    _logoFlipY = Tween<double>(begin: pi / 2, end: 0.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoCtrl,
            curve: const Interval(0.0, 0.4, curve: Curves.easeIn)));

    _mandalaAppear = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoCtrl,
            curve: const Interval(0.2, 0.9, curve: Curves.easeOut)));

    _raysAppear = CurvedAnimation(
        parent: _raysCtrl, curve: Curves.easeOut);

    _scanProgress = CurvedAnimation(
        parent: _scanCtrl, curve: Curves.easeInOut);

    _glowPulse = Tween<double>(begin: 0.35, end: 1.0).animate(_glowCtrl);

    _studioVSpacing = Tween<double>(begin: 40.0, end: 8.0).animate(
        CurvedAnimation(
            parent: _logoCtrl,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic)));
    _studioVScale = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoCtrl,
            curve: const Interval(0.0, 1.0, curve: Curves.elasticOut)));

    _runSequence();
  }

  Future<void> _runSequence() async {
    // 1. Brief black hold
    await Future.delayed(const Duration(milliseconds: 200));
    // 2. Iris opens
    _irisCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 350));
    // 3. Background bleeds in through open iris
    _bgCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 450));
    // 4. Mandala + logo 3D flip
    _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 350));
    // 5. Light rays burst
    _raysCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 450));
    // 6. Text scans in left → right
    _scanCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 1500));

    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  void dispose() {
    _irisCtrl.dispose();
    _bgCtrl.dispose();
    _mandalaCtrl.dispose();
    _logoCtrl.dispose();
    _scanCtrl.dispose();
    _glowCtrl.dispose();
    _raysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. Background ─────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _bgFade,
            builder: (_, child) =>
                Opacity(opacity: _bgFade.value, child: child!),
            child: Image.asset(SplashScreen.backgroundAsset, fit: BoxFit.cover),
          ),

          // ── 2. Dark vignette overlay ───────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),

          // ── 3. Light rays burst ─────────────────────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_raysCtrl, _glowCtrl]),
              builder: (_, __) => CustomPaint(
                size: Size(size.width, size.width),
                painter: _RaysPainter(
                  progress: _raysAppear.value,
                  glowIntensity: _glowPulse.value,
                  color: const Color(0xFFDEC29A),
                ),
              ),
            ),
          ),

          // ── 4. Rotating mandala (behind logo) ──────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge(
                  [_mandalaCtrl, _logoCtrl, _glowCtrl]),
              builder: (_, __) => Opacity(
                opacity: _mandalaAppear.value,
                child: CustomPaint(
                  size: const Size(500, 500),
                  painter: _MandalaPainter(
                    rotation: _mandalaCtrl.value * 2 * pi,
                    glow: _glowPulse.value,
                    color: const Color(0xFFDEC29A),
                  ),
                ),
              ),
            ),
          ),

          // ── 5. Logo + text ─────────────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 3D flip logo
                AnimatedBuilder(
                  animation: _logoCtrl,
                  builder: (_, child) => Opacity(
                    opacity: _logoFade.value,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..rotateY(_logoFlipY.value),
                      child: child,
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: _glowCtrl,
                    builder: (_, child) => Container(
                      width: size.width * 1.2,
                      height: size.width * 1.2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFB07840).withOpacity(0.6),
                            const Color(0xFFDEC29A).withOpacity(0.3),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                      child: Center(child: child),
                    ),
                    child: Image.asset('assets/logo.png', width: 250),
                  ),
                ),

                const SizedBox(height: 10),

                // Studio V label
                AnimatedBuilder(
                  animation: _logoCtrl,
                  builder: (_, child) => Opacity(
                    opacity: _logoFade.value,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..scale(_studioVScale.value)
                        ..setEntry(3, 2, 0.001)
                        ..rotateX((1 - _logoFade.value) * -0.5),
                      child: Text(
                        'STUDIO V',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          letterSpacing: _studioVSpacing.value,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                              color: const Color(0xFFB07840).withOpacity(0.5),
                              blurRadius: 15,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // Scanner text reveal
                AnimatedBuilder(
                  animation: _scanCtrl,
                  builder: (_, child) => Stack(
                    children: [
                      // Reveal clip
                      ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: _scanProgress.value,
                          child: child,
                        ),
                      ),
                      // Scanner leading edge glow
                      if (_scanProgress.value > 0 && _scanProgress.value < 1)
                        Positioned(
                          left: _scanProgress.value *
                              (child!.key == null ? 200 : 200),
                          child: Container(
                            width: 3,
                            height: 18,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDEC29A),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFDEC29A)
                                      .withOpacity(0.9),
                                  blurRadius: 10,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  child: const Text(
                    'SAIRAM INSTITUTIONS',
                    style: TextStyle(
                      color: Color(0xFFDEC29A),
                      fontSize: 15,
                      letterSpacing: 3.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 6. Iris shutter (on top of everything, opens from center) ──
          AnimatedBuilder(
            animation: _irisCtrl,
            builder: (_, __) => CustomPaint(
              painter: _IrisPainter(progress: _irisOpen.value),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Camera iris shutter — circular black overlay with hole that grows open
// ──────────────────────────────────────────────────────────────────────────────
class _IrisPainter extends CustomPainter {
  final double progress;
  _IrisPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1.0) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = sqrt(cx * cx + cy * cy) + 20;
    final openR = maxR * Curves.easeInOut.transform(progress);

    final paint = Paint()..color = Colors.black;
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    canvas.drawCircle(
      Offset(cx, cy),
      openR,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IrisPainter old) => old.progress != progress;
}

// ──────────────────────────────────────────────────────────────────────────────
// Rotating mandala rings + hexagon + spokes
// ──────────────────────────────────────────────────────────────────────────────
class _MandalaPainter extends CustomPainter {
  final double rotation;
  final double glow;
  final Color color;
  _MandalaPainter(
      {required this.rotation, required this.glow, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);

    // Outer dashed ring (counter-clockwise)
    _drawDashedRing(canvas, 220.0, 24, 1.2, 0.25 * glow, -rotation * 0.7);

    // Middle dashed ring (clockwise)
    _drawDashedRing(canvas, 175.0, 18, 1.8, 0.45 * glow, rotation);

    // Inner dashed ring (counter-clockwise)
    _drawDashedRing(canvas, 125.0, 12, 1.2, 0.35 * glow, -rotation * 1.3);

    // Hexagon (slowly rotates)
    _drawPolygon(canvas, 6, 90.0, 1.8, 0.3 * glow, rotation * 0.3);

    // Inner diamond
    _drawPolygon(canvas, 4, 50.0, 1.2, 0.2 * glow, rotation * 0.5 + pi / 4);

    // Radial spokes
    final spokePaint = Paint()
      ..color = color.withOpacity(0.12 * glow)
      ..strokeWidth = 0.8;
    for (int i = 0; i < 16; i++) {
      final angle = rotation * 0.2 + i * pi / 8;
      canvas.drawLine(
        Offset(cos(angle) * 50, sin(angle) * 50),
        Offset(cos(angle) * 230, sin(angle) * 230),
        spokePaint,
      );
    }
  }

  void _drawDashedRing(Canvas canvas, double radius, int dashes,
      double strokeW, double opacity, double angleOffset) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke;

    final step = 2 * pi / dashes;
    for (int i = 0; i < dashes; i++) {
      final start = angleOffset + i * step;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        start,
        step * 0.55,
        false,
        paint,
      );
    }
  }

  void _drawPolygon(Canvas canvas, int sides, double radius, double strokeW,
      double opacity, double angleOffset) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = angleOffset + i * 2 * pi / sides;
      final x = radius * cos(angle);
      final y = radius * sin(angle);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MandalaPainter old) =>
      old.rotation != rotation || old.glow != glow;
}

// ──────────────────────────────────────────────────────────────────────────────
// Light rays burst from center
// ──────────────────────────────────────────────────────────────────────────────
class _RaysPainter extends CustomPainter {
  final double progress;
  final double glowIntensity;
  final Color color;
  _RaysPainter(
      {required this.progress,
      required this.glowIntensity,
      required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxLen = size.width * 0.7 * progress;
    const rayCount = 18;

    for (int i = 0; i < rayCount; i++) {
      final angle = i * 2 * pi / rayCount;
      final rayLen = maxLen * (0.5 + 0.5 * sin(i * 1.7));
      final opacity =
          (0.08 + 0.1 * cos(i * 1.3)) * progress * glowIntensity;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.center,
          end: Alignment.centerRight,
          colors: [
            color.withOpacity(opacity.clamp(0.0, 0.25)),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(cx, cy - 2, rayLen, 4))
        ..strokeWidth = 2.0 + (i % 3) * 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + cos(angle) * rayLen, cy + sin(angle) * rayLen),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) =>
      old.progress != progress || old.glowIntensity != glowIntensity;
}
