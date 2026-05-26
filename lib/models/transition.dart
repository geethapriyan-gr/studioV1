import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'transition.g.dart';

@HiveType(typeId: 19)
enum TransitionType {
  @HiveField(0)
  crossfade,
  @HiveField(1)
  zoom,
  @HiveField(2)
  slideLeft,
  @HiveField(3)
  slideRight,
  @HiveField(4)
  slideUp,
  @HiveField(5)
  slideDown,
  // --- Additional cinematic transitions (CapCut/VN style) ---
  @HiveField(7)
  black,
  @HiveField(8)
  white,
  @HiveField(9)
  shake,
  @HiveField(10)
  light,
  @HiveField(12)
  pixelate,
  @HiveField(13)
  circle,
  @HiveField(14)
  push,
  @HiveField(22)
  pushRight,
  @HiveField(15)
  rotate1,
  @HiveField(16)
  rotate2,
  @HiveField(19)
  blink,
  @HiveField(20)
  vertical,
  @HiveField(21)
  horizontal,
}

@HiveType(typeId: 20)
class Transition {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String clipId1;
  @HiveField(2)
  final String clipId2;
  @HiveField(3)
  final TransitionType type;
  @HiveField(4)
  final Duration duration;
  @HiveField(5)
  final Duration startTime;

  Transition({
    required this.id,
    required this.clipId1,
    required this.clipId2,
    this.type = TransitionType.crossfade,
    this.duration = const Duration(milliseconds: 500),
    required this.startTime,
  });

  Transition copyWith({
    String? id,
    String? clipId1,
    String? clipId2,
    TransitionType? type,
    Duration? duration,
    Duration? startTime,
  }) {
    return Transition(
      id: id ?? this.id,
      clipId1: clipId1 ?? this.clipId1,
      clipId2: clipId2 ?? this.clipId2,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      startTime: startTime ?? this.startTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clipId1': clipId1,
      'clipId2': clipId2,
      'type': type.name,
      'durationMs': duration.inMilliseconds,
      'startTimeMs': startTime.inMilliseconds,
    };
  }

  static TransitionType fromName(String name) {
    try {
      return TransitionType.values.firstWhere(
        (e) => e.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return TransitionType.crossfade;
    }
  }

  String getShaderPath() {
    switch (type) {
      case TransitionType.crossfade:
        return 'assets/shaders/crossfade.frag';
      case TransitionType.zoom:
        return 'assets/shaders/zoom.frag';
      default:
        return 'assets/shaders/crossfade.frag';
    }
  }

  String getDisplayName() {
    switch (type) {
      case TransitionType.crossfade:
        return 'Crossfade';
      case TransitionType.zoom:
        return 'Zoom';
      case TransitionType.slideLeft:
        return 'Slide Left';
      case TransitionType.slideRight:
        return 'Slide Right';
      case TransitionType.slideUp:
        return 'Slide Up';
      case TransitionType.slideDown:
        return 'Slide Down';
      case TransitionType.black:
        return 'Black';
      case TransitionType.white:
        return 'White';
      case TransitionType.shake:
        return 'Shake';
      case TransitionType.light:
        return 'Light';
      case TransitionType.pixelate:
        return 'Pixelate';
      case TransitionType.circle:
        return 'Circle';
      case TransitionType.push:
        return 'Push';
      case TransitionType.pushRight:
        return 'Push Right';
      case TransitionType.rotate1:
        return 'Rotate 1';
      case TransitionType.rotate2:
        return 'Rotate 2';
      case TransitionType.blink:
        return 'Blink';
      case TransitionType.vertical:
        return 'Vertical';
      case TransitionType.horizontal:
        return 'Horizontal';
    }
  }

  IconData getIcon() {
    switch (type) {
      case TransitionType.crossfade:
        return Icons.blur_circular;
      case TransitionType.zoom:
        return Icons.zoom_in;
      case TransitionType.slideLeft:
        return Icons.arrow_back;
      case TransitionType.slideRight:
        return Icons.arrow_forward;
      case TransitionType.slideUp:
        return Icons.arrow_upward;
      case TransitionType.slideDown:
        return Icons.arrow_downward;
      case TransitionType.black:
        return Icons.brightness_1;
      case TransitionType.white:
        return Icons.brightness_5;
      case TransitionType.shake:
        return Icons.vibration;
      case TransitionType.light:
        return Icons.flash_on;
      case TransitionType.pixelate:
        return Icons.grid_on;
      case TransitionType.circle:
        return Icons.circle_outlined;
      case TransitionType.push:
        return Icons.forward;
      case TransitionType.pushRight:
        return Icons.arrow_forward;
      case TransitionType.rotate1:
        return Icons.rotate_right;
      case TransitionType.rotate2:
        return Icons.rotate_left;
      case TransitionType.blink:
        return Icons.visibility;
      case TransitionType.vertical:
        return Icons.swap_vert;
      case TransitionType.horizontal:
        return Icons.swap_horiz;
    }
  }
}
