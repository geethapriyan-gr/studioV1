import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/chroma_key_settings.dart';
import '../services/transition_shader_service.dart';

class ChromaKeyPainter extends ChangeNotifier {
  ChromaKeySettings settings;
  ui.Image? foregroundImage;
  ui.Image? backgroundImage;
  ui.FragmentProgram? _shaderProgram;

  ChromaKeyPainter({required this.settings});

  Future<void> initialize() async {
    try {
      _shaderProgram = await TransitionShaderService.getShader(
          'assets/shaders/chroma_key.frag');
      notifyListeners();
    } catch (e) {
      print('Failed to load chroma key shader: $e');
    }
  }

  void updateSettings(ChromaKeySettings newSettings) {
    settings = newSettings;
    notifyListeners();
  }

  void updateForegroundImage(ui.Image image) {
    foregroundImage?.dispose();
    foregroundImage = image;
    notifyListeners();
  }

  void updateBackgroundImage(ui.Image image) {
    backgroundImage?.dispose();
    backgroundImage = image;
    notifyListeners();
  }

  @override
  void dispose() {
    foregroundImage?.dispose();
    backgroundImage?.dispose();
    super.dispose();
  }
}

class ChromaKeyShaderPainter extends CustomPainter {
  final ChromaKeyPainter painter;

  ChromaKeyShaderPainter(this.painter) : super(repaint: painter);

  @override
  void paint(Canvas canvas, Size size) {
    if (painter.foregroundImage == null ||
        painter.backgroundImage == null ||
        painter._shaderProgram == null) {
      _drawFallback(canvas, size);
      return;
    }

    // Draw background
    final bgPaint = Paint()
      ..shader = ImageShader(
        painter.backgroundImage!,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Create shader for chroma key
    final shader = painter._shaderProgram!.fragmentShader()
      ..setImageSampler(0, painter.foregroundImage!)
      ..setFloat(0, painter.settings.hueMin)
      ..setFloat(1, painter.settings.hueMax)
      ..setFloat(2, painter.settings.saturationMin)
      ..setFloat(3, painter.settings.similarity)
      ..setFloat(4, painter.settings.shadowRemoval)
      ..setFloat(5, painter.settings.spillReduction)
      ..setFloat(6, painter.settings.edgeTransition)
      ..setFloat(7, painter.settings.skinProtection)
      ..setFloat(8, size.width)
      ..setFloat(9, size.height);

    // Draw foreground with chroma key
    final fgPaint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, fgPaint);
  }

  void _drawFallback(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.grey[900]!;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Chroma Key Preview',
        style: TextStyle(color: Colors.white70, fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(maxWidth: size.width);
    textPainter.paint(
        canvas,
        Offset(size.width / 2 - textPainter.width / 2,
            size.height / 2 - textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
