import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'video_effect.g.dart';

@HiveType(typeId: 21)
enum VideoEffectType {
  @HiveField(0)
  blur,
  @HiveField(1)
  shake,
  @HiveField(2)
  glitch,
  @HiveField(3)
  flash,
  @HiveField(4)
  grayscale,
  @HiveField(5)
  sepia,
  @HiveField(6)
  vintage,
  @HiveField(7)
  neon,
}

@HiveType(typeId: 22)
class VideoEffect {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String clipId;
  @HiveField(2)
  final VideoEffectType type;
  @HiveField(3)
  final double intensity;
  @HiveField(4)
  final Duration startTime;
  @HiveField(5)
  final Duration duration;
  @HiveField(6)
  final Map<String, dynamic>? parameters;

  VideoEffect({
    required this.id,
    required this.clipId,
    this.type = VideoEffectType.blur,
    this.intensity = 0.5,
    required this.startTime,
    required this.duration,
    this.parameters,
  });

  VideoEffect copyWith({
    String? id,
    String? clipId,
    VideoEffectType? type,
    double? intensity,
    Duration? startTime,
    Duration? duration,
    Map<String, dynamic>? parameters,
  }) {
    return VideoEffect(
      id: id ?? this.id,
      clipId: clipId ?? this.clipId,
      type: type ?? this.type,
      intensity: intensity ?? this.intensity,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      parameters: parameters ?? this.parameters,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clipId': clipId,
      'type': type.name,
      'intensity': intensity,
      'startTimeMs': startTime.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'parameters': parameters,
    };
  }

  static VideoEffectType fromName(String name) {
    try {
      return VideoEffectType.values.firstWhere(
        (e) => e.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return VideoEffectType.blur;
    }
  }

  String? getShaderPath() {
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

  String getDisplayName() {
    switch (type) {
      case VideoEffectType.blur:
        return 'Blur';
      case VideoEffectType.shake:
        return 'Shake';
      case VideoEffectType.glitch:
        return 'Glitch';
      case VideoEffectType.flash:
        return 'Flash';
      case VideoEffectType.grayscale:
        return 'Grayscale';
      case VideoEffectType.sepia:
        return 'Sepia';
      case VideoEffectType.vintage:
        return 'Vintage';
      case VideoEffectType.neon:
        return 'Neon';
    }
  }

  IconData getIcon() {
    switch (type) {
      case VideoEffectType.blur:
        return Icons.blur_on;
      case VideoEffectType.shake:
        return Icons.shutter_speed;
      case VideoEffectType.glitch:
        return Icons.videogame_asset;
      case VideoEffectType.flash:
        return Icons.flash_on;
      case VideoEffectType.grayscale:
        return Icons.filter_b_and_w;
      case VideoEffectType.sepia:
        return Icons.palette;
      case VideoEffectType.vintage:
        return Icons.history_edu;
      case VideoEffectType.neon:
        return Icons.lightbulb;
    }
  }

  bool get isShaderEffect =>
      type == VideoEffectType.blur ||
      type == VideoEffectType.shake ||
      type == VideoEffectType.glitch ||
      type == VideoEffectType.flash;
}
