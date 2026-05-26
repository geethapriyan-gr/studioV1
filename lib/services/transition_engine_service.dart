import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/transition.dart';
import '../models/video_effect.dart';
import 'transition_shader_service.dart';

class TransitionEngineService {
  static final TransitionEngineService _instance = TransitionEngineService._();
  factory TransitionEngineService() => _instance;
  TransitionEngineService._();

  Future<ui.Image?> applyTransition({
    required ui.Image texture1,
    required ui.Image texture2,
    required TransitionType transitionType,
    required double progress,
    Size? size,
  }) async {
    final targetSize =
        size ?? Size(texture1.width.toDouble(), texture1.height.toDouble());

    final shaderPath = _getShaderPath(transitionType);
    if (shaderPath == null) {
      return _defaultTransition(texture1, texture2, progress, targetSize);
    }

    try {
      final program = await TransitionShaderService.getShader(shaderPath);
      if (program == null) {
        return _defaultTransition(texture1, texture2, progress, targetSize);
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final paint = Paint()..isAntiAlias = true;

      final shader = program.fragmentShader()
        ..setImageSampler(0, texture1)
        ..setImageSampler(1, texture2)
        ..setFloat(0, progress)
        ..setFloat(1, targetSize.width)
        ..setFloat(2, targetSize.height);

      paint.shader = shader;

      canvas.drawRect(
        Rect.fromLTWH(0, 0, targetSize.width, targetSize.height),
        paint,
      );

      final picture = recorder.endRecording();
      return await picture.toImage(
        targetSize.width.toInt(),
        targetSize.height.toInt(),
      );
    } catch (e) {
      print('Transition engine error: $e');
      return _defaultTransition(texture1, texture2, progress, targetSize);
    }
  }

  String? _getShaderPath(TransitionType type) {
    switch (type) {
      case TransitionType.crossfade:
        return 'assets/shaders/crossfade.frag';
      case TransitionType.zoom:
        return 'assets/shaders/zoom.frag';
      default:
        return null;
    }
  }

  Future<ui.Image> _defaultTransition(
    ui.Image texture1,
    ui.Image texture2,
    double progress,
    Size size,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final paint1 = Paint()..color = Colors.white.withOpacity(1 - progress);
    canvas.drawImageRect(texture1, rect, rect, paint1);

    final paint2 = Paint()..color = Colors.white.withOpacity(progress);
    canvas.drawImageRect(texture2, rect, rect, paint2);

    final picture = recorder.endRecording();
    return await picture.toImage(size.width.toInt(), size.height.toInt());
  }

  Future<ui.Image?> applyVideoEffect({
    required ui.Image texture,
    required VideoEffectType effectType,
    required double intensity,
    Size? size,
  }) async {
    final targetSize =
        size ?? Size(texture.width.toDouble(), texture.height.toDouble());

    final shaderPath = _getEffectShaderPath(effectType);
    if (shaderPath == null) {
      return texture;
    }

    try {
      final program = await TransitionShaderService.getShader(shaderPath);
      if (program == null) {
        return texture;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final paint = Paint()..isAntiAlias = true;

      final shader = program.fragmentShader()
        ..setImageSampler(0, texture)
        ..setFloat(0, intensity)
        ..setFloat(1, targetSize.width)
        ..setFloat(2, targetSize.height);

      paint.shader = shader;

      canvas.drawRect(
        Rect.fromLTWH(0, 0, targetSize.width, targetSize.height),
        paint,
      );

      final picture = recorder.endRecording();
      return await picture.toImage(
        targetSize.width.toInt(),
        targetSize.height.toInt(),
      );
    } catch (e) {
      print('Video effect engine error: $e');
      return texture;
    }
  }

  String? _getEffectShaderPath(VideoEffectType type) {
    switch (type) {
      case VideoEffectType.blur:
        return 'assets/shaders/blur.frag';
      case VideoEffectType.shake:
        return 'assets/shaders/shake.frag';
      case VideoEffectType.glitch:
        return 'assets/shaders/glitch.frag';
      case VideoEffectType.flash:
        return 'assets/shaders/flash.frag';
      default:
        return null;
    }
  }

  Future<void> initialize() async {
    await TransitionShaderService.initialize();
  }

  void dispose() {
    TransitionShaderService.dispose();
  }
}
