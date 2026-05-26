import 'dart:ui';
import 'package:hive/hive.dart';

part 'chroma_key_settings.g.dart';

/// Model class for storing chroma key (green screen) configuration
@HiveType(typeId: 18)
class ChromaKeySettings {
  /// Whether chroma key effect is enabled
  @HiveField(0)
  final bool enabled;

  /// Path to background media (image or video)
  @HiveField(1)
  final String? backgroundPath;

  /// Whether background is a video (true) or image (false)
  @HiveField(2)
  final bool isBackgroundVideo;

  /// The color to use for chroma key (default: green #00FF00)
  @HiveField(3)
  final Color keyColor;

  /// Similarity threshold - how similar colors must be to be removed (0.0-1.0)
  /// Lower = more precise, Higher = removes more colors
  @HiveField(4)
  final double similarity;

  /// Blend amount for soft edges around the key (0.0-1.0)
  /// Higher = smoother transitions
  @HiveField(5)
  final double blend;

  /// Position of the foreground object (normalized coordinates: 0.0-1.0)
  @HiveField(6)
  final Offset position;

  /// Scale of the foreground object (1.0 = original size)
  @HiveField(7)
  final double scale;

  /// Minimum hue value for chroma key range (0.0-360.0 degrees)
  @HiveField(8)
  final double hueMin;

  /// Maximum hue value for chroma key range (0.0-360.0 degrees)
  @HiveField(9)
  final double hueMax;

  /// Minimum saturation value for chroma key range (0.0-1.0)
  @HiveField(10)
  final double saturationMin;

  /// Maximum saturation value for chroma key range (0.0-1.0)
  @HiveField(14)
  final double saturationMax;

  /// Minimum value (brightness) for chroma key range (0.0-1.0)
  @HiveField(11)
  final double valueMin;

  /// Maximum value (brightness) for chroma key range (0.0-1.0)
  @HiveField(15)
  final double valueMax;

  /// Green spill reduction strength (0.0-1.0)
  @HiveField(12)
  final double spillReduction;

  /// Edge feathering amount (0.0-1.0)
  @HiveField(13)
  final double edgeFeather;

  /// Edge transition width (0.0-1.0) - narrow range for hair preservation
  @HiveField(16)
  final double edgeTransition;

  /// Shadow green removal strength (0.0-1.0)
  @HiveField(17)
  final double shadowRemoval;

  /// Skin tone protection strength (0.0-1.0)
  @HiveField(18)
  final double skinProtection;

  const ChromaKeySettings({
    this.enabled = false,
    this.backgroundPath,
    this.isBackgroundVideo = false,
    this.keyColor = const Color(0xFF00FF00), // Pure green
    this.similarity = 0.30, // Higher tolerance for complete green removal
    this.blend = 0.05,
    this.position = const Offset(0.5, 0.5), // Center position
    this.scale = 1.0, // Original size
    this.hueMin = 60.0, // Green range minimum (60 degrees)
    this.hueMax = 180.0, // Green range maximum (180 degrees)
    this.saturationMin = 0.15, // Lower saturation for dark green
    this.saturationMax = 1.0, // Maximum saturation
    this.valueMin = 0.10, // Lower value for shadow green
    this.valueMax = 1.0, // Maximum brightness (1.0)
    this.spillReduction = 1.0, // Maximum spill reduction
    this.edgeFeather = 0.10, // Minimal feathering for sharp edges
    this.edgeTransition = 0.20, // Narrow transition for hair
    this.shadowRemoval = 0.9, // Maximum shadow green detection
    this.skinProtection = 0.8, // Strong skin tone protection
  });

  /// Default green screen settings - optimized for CapCut-level quality
  factory ChromaKeySettings.greenScreen() {
    return const ChromaKeySettings(
      enabled: true,
      keyColor: Color(0xFF00FF00),
      similarity: 0.30,
      blend: 0.05,
      hueMin: 60.0,
      hueMax: 180.0,
      saturationMin: 0.15,
      saturationMax: 1.0,
      valueMin: 0.10,
      valueMax: 1.0,
      spillReduction: 1.0,
      edgeFeather: 0.10,
      edgeTransition: 0.20,
      shadowRemoval: 0.9,
      skinProtection: 0.8,
    );
  }

  /// Default blue screen settings
  factory ChromaKeySettings.blueScreen() {
    return const ChromaKeySettings(
      enabled: true,
      keyColor: Color(0xFF0000FF),
      similarity: 0.30,
      blend: 0.05,
      hueMin: 200.0,
      hueMax: 280.0,
      saturationMin: 0.15,
      saturationMax: 1.0,
      valueMin: 0.10,
      valueMax: 1.0,
      spillReduction: 1.0,
      edgeFeather: 0.10,
      edgeTransition: 0.20,
      shadowRemoval: 0.9,
      skinProtection: 0.8,
    );
  }

  ChromaKeySettings copyWith({
    bool? enabled,
    String? backgroundPath,
    bool? isBackgroundVideo,
    Color? keyColor,
    double? similarity,
    double? blend,
    Offset? position,
    double? scale,
    double? hueMin,
    double? hueMax,
    double? saturationMin,
    double? saturationMax,
    double? valueMin,
    double? valueMax,
    double? spillReduction,
    double? edgeFeather,
    double? edgeTransition,
    double? shadowRemoval,
    double? skinProtection,
    bool clearBackground = false,
  }) {
    return ChromaKeySettings(
      enabled: enabled ?? this.enabled,
      backgroundPath:
          clearBackground ? null : (backgroundPath ?? this.backgroundPath),
      isBackgroundVideo: isBackgroundVideo ?? this.isBackgroundVideo,
      keyColor: keyColor ?? this.keyColor,
      similarity: similarity ?? this.similarity,
      blend: blend ?? this.blend,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      hueMin: hueMin ?? this.hueMin,
      hueMax: hueMax ?? this.hueMax,
      saturationMin: saturationMin ?? this.saturationMin,
      saturationMax: saturationMax ?? this.saturationMax,
      valueMin: valueMin ?? this.valueMin,
      valueMax: valueMax ?? this.valueMax,
      spillReduction: spillReduction ?? this.spillReduction,
      edgeFeather: edgeFeather ?? this.edgeFeather,
      edgeTransition: edgeTransition ?? this.edgeTransition,
      shadowRemoval: shadowRemoval ?? this.shadowRemoval,
      skinProtection: skinProtection ?? this.skinProtection,
    );
  }

  /// Check if chroma key is properly configured for export
  bool get isReadyForExport => enabled && backgroundPath != null;

  /// Get hex string for FFmpeg colorkey filter
  /// Format: RRGGBB (without 0x prefix, e.g., "00ff00" for green)
  String get keyColorHex {
    final r = ((keyColor.value >> 16) & 0xFF);
    final g = ((keyColor.value >> 8) & 0xFF);
    final b = (keyColor.value & 0xFF);
    return '${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'backgroundPath': backgroundPath,
      'isBackgroundVideo': isBackgroundVideo,
      'keyColor': keyColor.value,
      'similarity': similarity,
      'blend': blend,
      'position': {'dx': position.dx, 'dy': position.dy},
      'scale': scale,
      'hueMin': hueMin,
      'hueMax': hueMax,
      'saturationMin': saturationMin,
      'saturationMax': saturationMax,
      'valueMin': valueMin,
      'valueMax': valueMax,
      'spillReduction': spillReduction,
      'edgeFeather': edgeFeather,
      'edgeTransition': edgeTransition,
      'shadowRemoval': shadowRemoval,
      'skinProtection': skinProtection,
    };
  }

  factory ChromaKeySettings.fromJson(Map<String, dynamic> json) {
    return ChromaKeySettings(
      enabled: json['enabled'] ?? false,
      backgroundPath: json['backgroundPath'],
      isBackgroundVideo: json['isBackgroundVideo'] ?? false,
      keyColor: Color(json['keyColor'] ?? 0xFF00FF00),
      similarity: (json['similarity'] ?? 0.30).toDouble(),
      blend: (json['blend'] ?? 0.05).toDouble(),
      position: json['position'] != null
          ? Offset(
              (json['position']['dx'] ?? 0.5).toDouble(),
              (json['position']['dy'] ?? 0.5).toDouble(),
            )
          : const Offset(0.5, 0.5),
      scale: (json['scale'] ?? 1.0).toDouble(),
      hueMin: (json['hueMin'] ?? 60.0).toDouble(),
      hueMax: (json['hueMax'] ?? 180.0).toDouble(),
      saturationMin: (json['saturationMin'] ?? 0.15).toDouble(),
      saturationMax: (json['saturationMax'] ?? 1.0).toDouble(),
      valueMin: (json['valueMin'] ?? 0.10).toDouble(),
      valueMax: (json['valueMax'] ?? 1.0).toDouble(),
      spillReduction: (json['spillReduction'] ?? 1.0).toDouble(),
      edgeFeather: (json['edgeFeather'] ?? 0.10).toDouble(),
      edgeTransition: (json['edgeTransition'] ?? 0.20).toDouble(),
      shadowRemoval: (json['shadowRemoval'] ?? 0.9).toDouble(),
      skinProtection: (json['skinProtection'] ?? 0.8).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChromaKeySettings &&
        other.enabled == enabled &&
        other.backgroundPath == backgroundPath &&
        other.isBackgroundVideo == isBackgroundVideo &&
        other.keyColor == keyColor &&
        other.similarity == similarity &&
        other.blend == blend &&
        other.position == position &&
        other.scale == scale &&
        other.hueMin == hueMin &&
        other.hueMax == hueMax &&
        other.saturationMin == saturationMin &&
        other.saturationMax == saturationMax &&
        other.valueMin == valueMin &&
        other.valueMax == valueMax &&
        other.spillReduction == spillReduction &&
        other.edgeFeather == edgeFeather &&
        other.edgeTransition == edgeTransition &&
        other.shadowRemoval == shadowRemoval &&
        other.skinProtection == skinProtection;
  }

  @override
  int get hashCode {
    return Object.hash(
      enabled,
      backgroundPath,
      isBackgroundVideo,
      keyColor,
      similarity,
      blend,
      position,
      scale,
      hueMin,
      hueMax,
      saturationMin,
      saturationMax,
      valueMin,
      valueMax,
      spillReduction,
      edgeFeather,
      edgeTransition,
      shadowRemoval,
      skinProtection,
    );
  }
}

/// Model class for storing chroma key background media (image or video)
class ChromaKeyBackground {
  /// Unique identifier for this background
  final String id;

  /// Path to the background media file
  final String filePath;

  /// Whether this background is a video (true) or image (false)
  final bool isVideo;

  const ChromaKeyBackground({
    required this.id,
    required this.filePath,
    required this.isVideo,
  });

  ChromaKeyBackground copyWith({
    String? id,
    String? filePath,
    bool? isVideo,
  }) {
    return ChromaKeyBackground(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      isVideo: isVideo ?? this.isVideo,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': filePath,
      'isVideo': isVideo,
    };
  }

  factory ChromaKeyBackground.fromJson(Map<String, dynamic> json) {
    return ChromaKeyBackground(
      id: json['id'] ?? '',
      filePath: json['filePath'] ?? '',
      isVideo: json['isVideo'] ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChromaKeyBackground &&
        other.id == id &&
        other.filePath == filePath &&
        other.isVideo == isVideo;
  }

  @override
  int get hashCode => Object.hash(id, filePath, isVideo);
}
