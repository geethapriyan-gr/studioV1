import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'chroma_key_settings.dart';
import 'transition.dart';
import 'video_effect.dart';

part 'video_project.g.dart';

@HiveType(typeId: 0)
enum MediaType {
  @HiveField(0)
  video,
  @HiveField(1)
  image,
}

@HiveType(typeId: 7)
enum FontStyleEnum {
  @HiveField(0)
  normal,
  @HiveField(1)
  italic,
}

@HiveType(typeId: 8)
enum TextAlignEnum {
  @HiveField(0)
  left,
  @HiveField(1)
  center,
  @HiveField(2)
  right,
  @HiveField(3)
  justify,
  @HiveField(4)
  start,
  @HiveField(5)
  end,
}

@HiveType(typeId: 1)
class TextOverlay {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String text;
  @HiveField(2)
  final Offset position;
  @HiveField(3)
  final double fontSize;
  @HiveField(4)
  final Color color;
  @HiveField(5)
  final String fontFamily;
  @HiveField(6)
  final FontWeight fontWeight;
  @HiveField(7)
  final Duration startTime;
  @HiveField(8)
  final Duration endTime;
  @HiveField(9)
  final double rotation;
  @HiveField(10)
  final double opacity;
  @HiveField(11)
  final FontStyleEnum fontStyle;
  @HiveField(12)
  final TextAlignEnum textAlign;
  // In/out animation: 'none' | 'fade' | 'slide' | 'pop' | 'typewriter'.
  @HiveField(13, defaultValue: 'none')
  final String animIn;
  @HiveField(14, defaultValue: 'none')
  final String animOut;
  // Rounded background box behind the text (null = none).
  @HiveField(15)
  final Color? boxColor;
  // Text outline (null = none); width in px at font size 24.
  @HiveField(16)
  final Color? outlineColor;
  @HiveField(17, defaultValue: 0.0)
  final double outlineWidth;
  @HiveField(18, defaultValue: true)
  final bool shadow;

  TextOverlay({
    required this.id,
    required this.text,
    required this.position,
    this.fontSize = 24.0,
    this.color = Colors.white,
    this.fontFamily = 'Roboto',
    this.fontWeight = FontWeight.normal,
    required this.startTime,
    required this.endTime,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.fontStyle = FontStyleEnum.normal,
    this.textAlign = TextAlignEnum.center,
    this.animIn = 'none',
    this.animOut = 'none',
    this.boxColor,
    this.outlineColor,
    this.outlineWidth = 0,
    this.shadow = true,
  });

  TextOverlay copyWith({
    String? text,
    Offset? position,
    double? fontSize,
    Color? color,
    String? fontFamily,
    FontWeight? fontWeight,
    Duration? startTime,
    Duration? endTime,
    double? rotation,
    double? opacity,
    FontStyleEnum? fontStyle,
    TextAlignEnum? textAlign,
    String? animIn,
    String? animOut,
    Color? boxColor,
    bool clearBox = false,
    Color? outlineColor,
    bool clearOutline = false,
    double? outlineWidth,
    bool? shadow,
  }) {
    return TextOverlay(
      id: id,
      text: text ?? this.text,
      position: position ?? this.position,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      fontStyle: fontStyle ?? this.fontStyle,
      textAlign: textAlign ?? this.textAlign,
      animIn: animIn ?? this.animIn,
      animOut: animOut ?? this.animOut,
      boxColor: clearBox ? null : (boxColor ?? this.boxColor),
      outlineColor:
          clearOutline ? null : (outlineColor ?? this.outlineColor),
      outlineWidth: outlineWidth ?? this.outlineWidth,
      shadow: shadow ?? this.shadow,
    );
  }

  // Helper methods to convert between enum and Flutter types
  FontStyle get flutterFontStyle {
    switch (fontStyle) {
      case FontStyleEnum.normal:
        return FontStyle.normal;
      case FontStyleEnum.italic:
        return FontStyle.italic;
    }
  }

  TextAlign get flutterTextAlign {
    switch (textAlign) {
      case TextAlignEnum.left:
        return TextAlign.left;
      case TextAlignEnum.center:
        return TextAlign.center;
      case TextAlignEnum.right:
        return TextAlign.right;
      case TextAlignEnum.justify:
        return TextAlign.justify;
      case TextAlignEnum.start:
        return TextAlign.start;
      case TextAlignEnum.end:
        return TextAlign.end;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'position': {'dx': position.dx, 'dy': position.dy},
      'fontSize': fontSize,
      'color': color.value,
      'fontFamily': fontFamily,
      'fontWeight': fontWeight.index,
      'fontStyle': fontStyle.index,
      'textAlign': textAlign.index,
      'startTimeMs': startTime.inMilliseconds,
      'endTimeMs': endTime.inMilliseconds,
      'rotation': rotation,
      'opacity': opacity,
      'animIn': animIn,
      'animOut': animOut,
      'boxColor': boxColor?.toARGB32(),
      'outlineColor': outlineColor?.toARGB32(),
      'outlineWidth': outlineWidth,
      'shadow': shadow,
    };
  }
}

@HiveType(typeId: 2)
class AudioOverlay {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final File audioFile;
  @HiveField(2)
  final Duration startTime;
  @HiveField(3)
  final Duration endTime;
  @HiveField(4)
  final Duration audioStartOffset;
  @HiveField(5)
  final double volume;
  @HiveField(6)
  final bool fadeIn;
  @HiveField(7)
  final bool fadeOut;
  @HiveField(8)
  final int trackIndex;

  AudioOverlay({
    required this.id,
    required this.audioFile,
    required this.startTime,
    required this.endTime,
    this.audioStartOffset = Duration.zero,
    this.volume = 1.0,
    this.fadeIn = false,
    this.fadeOut = false,
    this.trackIndex = 0,
  });

  AudioOverlay copyWith({
    File? audioFile,
    Duration? startTime,
    Duration? endTime,
    Duration? audioStartOffset,
    double? volume,
    bool? fadeIn,
    bool? fadeOut,
    int? trackIndex,
  }) {
    return AudioOverlay(
      id: id,
      audioFile: audioFile ?? this.audioFile,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      audioStartOffset: audioStartOffset ?? this.audioStartOffset,
      volume: volume ?? this.volume,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      trackIndex: trackIndex ?? this.trackIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'audioPath': audioFile.path,
      'startTimeMs': startTime.inMilliseconds,
      'endTimeMs': endTime.inMilliseconds,
      'audioStartOffsetMs': audioStartOffset.inMilliseconds,
      'volume': volume,
      'fadeIn': fadeIn,
      'fadeOut': fadeOut,
      'trackIndex': trackIndex,
    };
  }
}

@HiveType(typeId: 3)
class VideoClip {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final MediaType mediaType;
  @HiveField(2)
  final File? videoFile;
  @HiveField(3)
  final File? imageFile;
  @HiveField(4)
  final Duration startTime;
  @HiveField(5)
  final Duration endTime;
  @HiveField(6)
  final Duration sourceStart;
  @HiveField(7)
  final Duration sourceEnd;
  @HiveField(8)
  final Duration trimStart;
  @HiveField(9)
  final Duration trimEnd;
  @HiveField(10)
  final double volume;
  @HiveField(11)
  final bool isMuted;
  @HiveField(12)
  final double rotation;
  @HiveField(13)
  final Rect? cropRect;
  @HiveField(14)
  final bool isMirrored;
  @HiveField(15)
  final double playbackSpeed;
  @HiveField(17)
  final bool isReversed;
  @HiveField(18)
  final String? reversedFilePath;
  @HiveField(19)
  final ChromaKeySettings? chromaKeySettings;
  @HiveField(20)
  final Offset overlayPosition;
  @HiveField(21)
  final Size overlaySize;
  @HiveField(22)
  final double overlayOpacity;
  @HiveField(23)
  final int trackIndex;

  // ── Media-overlay (picture-in-picture) look; unused for main clips ──
  /// Mask shape, see [OverlayShapes]: 'none' | 'rounded' | 'circle' | ...
  @HiveField(24, defaultValue: 'none')
  final String maskShape;
  /// Border thickness in canvas pixels (1920-px-tall design space).
  @HiveField(25, defaultValue: 0.0)
  final double borderWidth;
  @HiveField(26)
  final Color? borderColor;
  @HiveField(27, defaultValue: false)
  final bool shadow;
  /// In/out animation: 'none' | 'fade' | 'slide' | 'pop'.
  @HiveField(28, defaultValue: 'none')
  final String animIn;
  @HiveField(29, defaultValue: 'none')
  final String animOut;
  /// Motion keyframes, flattened as [OverlayKeyframe.encode] produces.
  @HiveField(30, defaultValue: <double>[])
  final List<double> keyframeData;

  VideoClip({
    required this.id,
    required this.mediaType,
    this.videoFile,
    this.imageFile,
    required this.startTime,
    required this.endTime,
    Duration? sourceStart,
    Duration? sourceEnd,
    Duration? trimStart,
    Duration? trimEnd,
    this.volume = 1.0,
    this.isMuted = false,
    this.rotation = 0.0,
    this.cropRect,
    this.isMirrored = false,
    this.playbackSpeed = 1.0,
    this.isReversed = false,
    this.reversedFilePath,
    this.chromaKeySettings,
    this.overlayPosition = const Offset(0.1, 0.1),
    this.overlaySize = const Size(0.3, 0.3),
    this.overlayOpacity = 1.0,
    this.trackIndex = 0,
    this.maskShape = 'none',
    this.borderWidth = 0.0,
    this.borderColor,
    this.shadow = false,
    this.animIn = 'none',
    this.animOut = 'none',
    this.keyframeData = const [],
  })  : sourceStart = sourceStart ?? startTime,
        sourceEnd = sourceEnd ?? endTime,
        trimStart = trimStart ?? (sourceStart ?? startTime),
        trimEnd = trimEnd ?? (sourceEnd ?? endTime);

  VideoClip copyWith({
    String? id,
    MediaType? mediaType,
    File? videoFile,
    File? imageFile,
    Duration? startTime,
    Duration? endTime,
    Duration? sourceStart,
    Duration? sourceEnd,
    Duration? trimStart,
    Duration? trimEnd,
    double? volume,
    bool? isMuted,
    double? rotation,
    Rect? cropRect,
    bool? isMirrored,
    double? playbackSpeed,
    bool? isReversed,
    String? reversedFilePath,
    bool clearReversedFilePath = false,
    ChromaKeySettings? chromaKeySettings,
    bool clearChromaKeySettings = false,
    Offset? overlayPosition,
    Size? overlaySize,
    double? overlayOpacity,
    int? trackIndex,
    bool clearCropRect = false,
    String? maskShape,
    double? borderWidth,
    Color? borderColor,
    bool clearBorderColor = false,
    bool? shadow,
    String? animIn,
    String? animOut,
    List<double>? keyframeData,
  }) {
    return VideoClip(
      id: id ?? this.id,
      mediaType: mediaType ?? this.mediaType,
      videoFile: videoFile ?? this.videoFile,
      imageFile: imageFile ?? this.imageFile,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceEnd: sourceEnd ?? this.sourceEnd,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      rotation: rotation ?? this.rotation,
      cropRect: clearCropRect ? null : (cropRect ?? this.cropRect),
      isMirrored: isMirrored ?? this.isMirrored,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      isReversed: isReversed ?? this.isReversed,
      reversedFilePath: clearReversedFilePath
          ? null
          : reversedFilePath ?? this.reversedFilePath,
      chromaKeySettings: clearChromaKeySettings
          ? null
          : chromaKeySettings ?? this.chromaKeySettings,
      overlayPosition: overlayPosition ?? this.overlayPosition,
      overlaySize: overlaySize ?? this.overlaySize,
      overlayOpacity: overlayOpacity ?? this.overlayOpacity,
      trackIndex: trackIndex ?? this.trackIndex,
      maskShape: maskShape ?? this.maskShape,
      borderWidth: borderWidth ?? this.borderWidth,
      borderColor:
          clearBorderColor ? null : (borderColor ?? this.borderColor),
      shadow: shadow ?? this.shadow,
      animIn: animIn ?? this.animIn,
      animOut: animOut ?? this.animOut,
      keyframeData: keyframeData ?? this.keyframeData,
    );
  }

  Duration get duration => endTime - startTime;
  Duration get trimmedDuration => trimEnd - trimStart;

  List<OverlayKeyframe> get keyframes => OverlayKeyframe.decode(keyframeData);

  /// True when a border is drawn around the overlay.
  bool get hasBorder => borderColor != null && borderWidth > 0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mediaType': mediaType.name,
      'videoPath': videoFile?.path,
      'imagePath': imageFile?.path,
      'startTimeMs': startTime.inMilliseconds,
      'endTimeMs': endTime.inMilliseconds,
      'sourceStartMs': sourceStart.inMilliseconds,
      'sourceEndMs': sourceEnd.inMilliseconds,
      'trimStartMs': trimStart.inMilliseconds,
      'trimEndMs': trimEnd.inMilliseconds,
      'volume': volume,
      'isMuted': isMuted,
      'rotation': rotation,
      'isMirrored': isMirrored,
      'playbackSpeed': playbackSpeed,
      'isReversed': isReversed,
      'reversedFilePath': reversedFilePath,
      'cropRect': cropRect == null
          ? null
          : {
              'l': cropRect!.left,
              't': cropRect!.top,
              'r': cropRect!.right,
              'b': cropRect!.bottom
            },
      'chromaKeySettings': chromaKeySettings?.toJson(),
      'overlayPositionDx': overlayPosition.dx,
      'overlayPositionDy': overlayPosition.dy,
      'overlayWidth': overlaySize.width,
      'overlayHeight': overlaySize.height,
      'overlayOpacity': overlayOpacity,
      'trackIndex': trackIndex,
      'maskShape': maskShape,
      'borderWidth': borderWidth,
      'borderColor': borderColor?.toARGB32(),
      'shadow': shadow,
      'animIn': animIn,
      'animOut': animOut,
      'keyframes': keyframeData,
    };
  }
}

/// A media-overlay motion keyframe: where the overlay box is (top-left and
/// size, normalized to the preview box) [time] after the overlay starts.
/// Between keyframes the box moves linearly; preview and export share
/// [OverlayKeyframe.boxAt].
class OverlayKeyframe {
  final Duration time;
  final Offset position;
  final Size size;

  const OverlayKeyframe(this.time, this.position, this.size);

  static const int _stride = 5;

  static List<OverlayKeyframe> decode(List<double> data) {
    final out = <OverlayKeyframe>[];
    for (int i = 0; i + _stride <= data.length; i += _stride) {
      out.add(OverlayKeyframe(
        Duration(microseconds: (data[i] * 1000).round()),
        Offset(data[i + 1], data[i + 2]),
        Size(data[i + 3], data[i + 4]),
      ));
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  static List<double> encode(List<OverlayKeyframe> frames) {
    final sorted = List<OverlayKeyframe>.from(frames)
      ..sort((a, b) => a.time.compareTo(b.time));
    return [
      for (final k in sorted) ...[
        k.time.inMicroseconds / 1000.0,
        k.position.dx,
        k.position.dy,
        k.size.width,
        k.size.height,
      ]
    ];
  }

  /// Box (position, size) of an overlay [local] time after it starts.
  /// Without keyframes this is the overlay's static box.
  static (Offset, Size) boxAt(VideoClip clip, Duration local) {
    final frames = clip.keyframes;
    if (frames.isEmpty) return (clip.overlayPosition, clip.overlaySize);
    if (local <= frames.first.time) {
      return (frames.first.position, frames.first.size);
    }
    if (local >= frames.last.time) {
      return (frames.last.position, frames.last.size);
    }
    for (int i = 0; i < frames.length - 1; i++) {
      final a = frames[i];
      final b = frames[i + 1];
      if (local >= a.time && local <= b.time) {
        final span = (b.time - a.time).inMicroseconds;
        final t = span <= 0 ? 1.0 : (local - a.time).inMicroseconds / span;
        return (
          Offset.lerp(a.position, b.position, t)!,
          Size.lerp(a.size, b.size, t)!,
        );
      }
    }
    return (frames.last.position, frames.last.size);
  }
}

@HiveType(typeId: 4)
class StickerModel {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String assetPath;
  @HiveField(2)
  final Offset position;
  @HiveField(3)
  final double scale;
  @HiveField(4)
  final double rotation;
  @HiveField(5)
  final Duration startTime;
  @HiveField(6)
  final Duration endTime;
  @HiveField(7)
  final double opacity;
  // Mirrored horizontally.
  @HiveField(8, defaultValue: false)
  final bool flipX;
  // In/out animation: 'none' | 'fade' | 'slide' | 'pop'.
  @HiveField(9, defaultValue: 'none')
  final String animIn;
  @HiveField(10, defaultValue: 'none')
  final String animOut;

  StickerModel({
    required this.id,
    required this.assetPath,
    this.position = const Offset(0.5, 0.5),
    this.scale = 1.0,
    this.rotation = 0.0,
    required this.startTime,
    required this.endTime,
    this.opacity = 1.0,
    this.flipX = false,
    this.animIn = 'none',
    this.animOut = 'none',
  });

  /// Bundled stickers are asset paths; stickers made from the user's own
  /// images are absolute file paths.
  bool get isAsset => assetPath.startsWith('assets/');

  /// Animated GIF stickers play in the preview and in the export.
  bool get isAnimated => assetPath.toLowerCase().endsWith('.gif');

  StickerModel copyWith({
    String? id,
    String? assetPath,
    Offset? position,
    double? scale,
    double? rotation,
    Duration? startTime,
    Duration? endTime,
    double? opacity,
    bool? flipX,
    String? animIn,
    String? animOut,
  }) {
    return StickerModel(
      id: id ?? this.id,
      assetPath: assetPath ?? this.assetPath,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      opacity: opacity ?? this.opacity,
      flipX: flipX ?? this.flipX,
      animIn: animIn ?? this.animIn,
      animOut: animOut ?? this.animOut,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assetPath': assetPath,
      'position': {'dx': position.dx, 'dy': position.dy},
      'scale': scale,
      'rotation': rotation,
      'startTimeMs': startTime.inMilliseconds,
      'endTimeMs': endTime.inMilliseconds,
      'opacity': opacity,
      'flipX': flipX,
      'animIn': animIn,
      'animOut': animOut,
    };
  }
}

@HiveType(typeId: 5)
class ColorFilter {
  @HiveField(0)
  final double brightness;
  @HiveField(1)
  final double contrast;
  @HiveField(2)
  final double saturation;
  @HiveField(3)
  final double hue;
  @HiveField(4)
  final double exposure;
  @HiveField(5)
  final double highlights;
  @HiveField(6)
  final double shadows;
  @HiveField(7)
  final double warmth;
  @HiveField(8)
  final double tint;
  @HiveField(9)
  final double sharpness;
  @HiveField(10)
  final double fade;
  @HiveField(11)
  final double luminance;
  @HiveField(12)
  final double temperature;
  @HiveField(13)
  final double opacity;
  @HiveField(14)
  final List<List<double>> filterPresetMatrices;

  const ColorFilter({
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.hue = 0.0,
    this.exposure = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.warmth = 0.0,
    this.tint = 0.0,
    this.sharpness = 0.0,
    this.fade = 0.0,
    this.luminance = 0.0,
    this.temperature = 0.0,
    this.opacity = 1.0,
    this.filterPresetMatrices = const [],
  });

  ColorFilter copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? hue,
    double? exposure,
    double? highlights,
    double? shadows,
    double? warmth,
    double? tint,
    double? sharpness,
    double? fade,
    double? luminance,
    double? temperature,
    double? opacity,
    List<List<double>>? filterPresetMatrices,
  }) {
    return ColorFilter(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      hue: hue ?? this.hue,
      exposure: exposure ?? this.exposure,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      warmth: warmth ?? this.warmth,
      tint: tint ?? this.tint,
      sharpness: sharpness ?? this.sharpness,
      fade: fade ?? this.fade,
      luminance: luminance ?? this.luminance,
      temperature: temperature ?? this.temperature,
      opacity: opacity ?? this.opacity,
      filterPresetMatrices: filterPresetMatrices ?? this.filterPresetMatrices,
    );
  }

  bool get hasFilters =>
      brightness != 0.0 ||
      contrast != 1.0 ||
      saturation != 1.0 ||
      hue != 0.0 ||
      exposure != 0.0 ||
      highlights != 0.0 ||
      shadows != 0.0 ||
      warmth != 0.0 ||
      tint != 0.0 ||
      sharpness != 0.0 ||
      fade != 0.0 ||
      luminance != 0.0 ||
      temperature != 0.0 ||
      opacity != 1.0 ||
      filterPresetMatrices.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'hue': hue,
      'exposure': exposure,
      'highlights': highlights,
      'shadows': shadows,
      'warmth': warmth,
      'tint': tint,
      'sharpness': sharpness,
      'fade': fade,
      'luminance': luminance,
      'temperature': temperature,
      'opacity': opacity,
      'filterPresetMatrices': filterPresetMatrices,
    };
  }
}

@HiveType(typeId: 6)
class VideoProject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final List<VideoClip> videoClips;
  @HiveField(3)
  final List<TextOverlay> textOverlays;
  @HiveField(4)
  final List<AudioOverlay> audioOverlays;
  @HiveField(5)
  final List<StickerModel> stickers;
  @HiveField(6)
  final ColorFilter colorFilter;
  @HiveField(7)
  final Duration totalDuration;
  @HiveField(8)
  final Size outputResolution;
  @HiveField(9)
  final int outputFrameRate;
  @HiveField(10)
  final DateTime createdAt;
  @HiveField(11)
  final DateTime lastModified;
  @HiveField(12)
  final List<String> chromaKeyBackgrounds;
  @HiveField(13)
  final List<Transition> transitions;
  @HiveField(14)
  final List<VideoEffect> videoEffects;
  @HiveField(15)
  final List<VideoClip> overlayClips;

  VideoProject({
    required this.id,
    required this.name,
    this.videoClips = const [],
    this.textOverlays = const [],
    this.audioOverlays = const [],
    this.stickers = const [],
    this.colorFilter = const ColorFilter(),
    this.overlayClips = const [],
    this.totalDuration = Duration.zero,
    this.outputResolution = const Size(1920, 1080),
    this.outputFrameRate = 30,
    DateTime? createdAt,
    DateTime? lastModified,
    this.chromaKeyBackgrounds = const [],
    this.transitions = const [],
    this.videoEffects = const [],
  })  : createdAt = createdAt ?? DateTime.now(),
        lastModified = lastModified ?? DateTime.now();

  VideoProject copyWith({
    String? name,
    List<VideoClip>? videoClips,
    List<TextOverlay>? textOverlays,
    List<AudioOverlay>? audioOverlays,
    List<StickerModel>? stickers,
    ColorFilter? colorFilter,
    Duration? totalDuration,
    Size? outputResolution,
    int? outputFrameRate,
    DateTime? lastModified,
    List<String>? chromaKeyBackgrounds,
    List<Transition>? transitions,
    List<VideoEffect>? videoEffects,
    List<VideoClip>? overlayClips,
  }) {
    return VideoProject(
      id: id,
      name: name ?? this.name,
      videoClips: videoClips ?? this.videoClips,
      textOverlays: textOverlays ?? this.textOverlays,
      audioOverlays: audioOverlays ?? this.audioOverlays,
      stickers: stickers ?? this.stickers,
      colorFilter: colorFilter ?? this.colorFilter,
      totalDuration: totalDuration ?? this.totalDuration,
      outputResolution: outputResolution ?? this.outputResolution,
      outputFrameRate: outputFrameRate ?? this.outputFrameRate,
      createdAt: createdAt,
      lastModified: lastModified ?? DateTime.now(),
      chromaKeyBackgrounds: chromaKeyBackgrounds ?? this.chromaKeyBackgrounds,
      transitions: transitions ?? this.transitions,
      videoEffects: videoEffects ?? this.videoEffects,
      overlayClips: overlayClips ?? this.overlayClips,
    );
  }

  VideoProject addSticker(StickerModel sticker) => copyWith(
      stickers: List.from(stickers)..add(sticker),
      lastModified: DateTime.now());

  VideoProject updateSticker(String id, StickerModel updated) => copyWith(
      stickers: stickers.map((s) => s.id == id ? updated : s).toList(),
      lastModified: DateTime.now());

  VideoProject removeSticker(String id) => copyWith(
      stickers: stickers.where((s) => s.id != id).toList(),
      lastModified: DateTime.now());

  Duration calculateTotalDuration() => _maxEnd(videoClips);

  static Duration _maxEnd(List<VideoClip> clips) {
    Duration maxEndTime = Duration.zero;
    for (final clip in clips) {
      if (clip.endTime > maxEndTime) maxEndTime = clip.endTime;
    }
    return maxEndTime;
  }

  /// End of the last item of any kind: clips, media overlays, text,
  /// stickers and audio. This is the length of the video the preview plays
  /// and the exporter renders.
  Duration get contentEnd {
    var end = _maxEnd(videoClips);
    void take(Duration d) {
      if (d > end) end = d;
    }

    for (final c in overlayClips) {
      take(c.endTime);
    }
    for (final t in textOverlays) {
      take(t.endTime);
    }
    for (final s in stickers) {
      take(s.endTime);
    }
    for (final a in audioOverlays) {
      take(a.endTime);
    }
    return end;
  }

  VideoProject addVideoClip(VideoClip clip) {
    final updatedClips = List<VideoClip>.from(videoClips)..add(clip);
    return copyWith(
      videoClips: updatedClips,
      totalDuration: _maxEnd(updatedClips),
      lastModified: DateTime.now(),
    );
  }

  VideoProject updateVideoClip(String clipId, VideoClip updatedClip) {
    final updatedClips =
        videoClips.map((c) => c.id == clipId ? updatedClip : c).toList();
    return copyWith(
      videoClips: updatedClips,
      totalDuration: _maxEnd(updatedClips),
      lastModified: DateTime.now(),
    );
  }

  VideoProject removeVideoClip(String clipId) {
    final updatedClips = videoClips.where((c) => c.id != clipId).toList();
    return copyWith(
      videoClips: updatedClips,
      totalDuration: _maxEnd(updatedClips),
      lastModified: DateTime.now(),
    );
  }

  VideoProject addTextOverlay(TextOverlay o) => copyWith(
      textOverlays: List.from(textOverlays)..add(o),
      lastModified: DateTime.now());
  VideoProject updateTextOverlay(String id, TextOverlay o) => copyWith(
      textOverlays: textOverlays.map((t) => t.id == id ? o : t).toList(),
      lastModified: DateTime.now());
  VideoProject removeTextOverlay(String id) => copyWith(
      textOverlays: textOverlays.where((t) => t.id != id).toList(),
      lastModified: DateTime.now());

  VideoProject addAudioOverlay(AudioOverlay o) => copyWith(
      audioOverlays: List.from(audioOverlays)..add(o),
      lastModified: DateTime.now());
  VideoProject updateAudioOverlay(String id, AudioOverlay o) => copyWith(
      audioOverlays: audioOverlays.map((a) => a.id == id ? o : a).toList(),
      lastModified: DateTime.now());
  VideoProject removeAudioOverlay(String id) => copyWith(
      audioOverlays: audioOverlays.where((a) => a.id != id).toList(),
      lastModified: DateTime.now());

  VideoProject addTransition(Transition transition) => copyWith(
      transitions: List.from(transitions)..add(transition),
      lastModified: DateTime.now());

  VideoProject updateTransition(String id, Transition updated) => copyWith(
      transitions: transitions.map((t) => t.id == id ? updated : t).toList(),
      lastModified: DateTime.now());

  VideoProject removeTransition(String id) => copyWith(
      transitions: transitions.where((t) => t.id != id).toList(),
      lastModified: DateTime.now());

  VideoProject addVideoEffect(VideoEffect effect) => copyWith(
      videoEffects: List.from(videoEffects)..add(effect),
      lastModified: DateTime.now());
  VideoProject addOverlayClip(VideoClip clip) => copyWith(
      overlayClips: List.from(overlayClips)..add(clip),
      lastModified: DateTime.now());
  VideoProject updateOverlayClip(String id, VideoClip clip) => copyWith(
      overlayClips: overlayClips.map((c) => c.id == id ? clip : c).toList(),
      lastModified: DateTime.now());
  VideoProject removeOverlayClip(String id) => copyWith(
      overlayClips: overlayClips.where((c) => c.id != id).toList(),
      lastModified: DateTime.now());

  VideoProject updateVideoEffect(String id, VideoEffect updated) => copyWith(
      videoEffects: videoEffects.map((e) => e.id == id ? updated : e).toList(),
      lastModified: DateTime.now());

  VideoProject removeVideoEffect(String id) => copyWith(
      videoEffects: videoEffects.where((e) => e.id != id).toList(),
      lastModified: DateTime.now());

  /// Add a background media path to the project
  VideoProject addChromaKeyBackground(String backgroundPath) {
    if (chromaKeyBackgrounds.contains(backgroundPath)) {
      return this;
    }
    return copyWith(
      chromaKeyBackgrounds: List.from(chromaKeyBackgrounds)
        ..add(backgroundPath),
      lastModified: DateTime.now(),
    );
  }

  /// Remove a background media path from the project
  VideoProject removeChromaKeyBackground(String backgroundPath) {
    return copyWith(
      chromaKeyBackgrounds:
          chromaKeyBackgrounds.where((p) => p != backgroundPath).toList(),
      lastModified: DateTime.now(),
    );
  }

  List<TextOverlay> getTextOverlaysAtTime(Duration time) => textOverlays
      .where((o) => time >= o.startTime && time <= o.endTime)
      .toList();
  List<AudioOverlay> getAudioOverlaysAtTime(Duration time) => audioOverlays
      .where((o) => time >= o.startTime && time <= o.endTime)
      .toList();
  List<StickerModel> getStickersAtTime(Duration time) =>
      stickers.where((s) => time >= s.startTime && time <= s.endTime).toList();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'videoClips': videoClips.map((c) => c.toJson()).toList(),
      'textOverlays': textOverlays.map((t) => t.toJson()).toList(),
      'audioOverlays': audioOverlays.map((a) => a.toJson()).toList(),
      'stickers': stickers.map((s) => s.toJson()).toList(),
      'colorFilter': colorFilter.toJson(),
      'output': {
        'width': outputResolution.width,
        'height': outputResolution.height,
        'frameRate': outputFrameRate,
      },
      'totalDurationMs': totalDuration.inMilliseconds,
      'createdAtMs': createdAt.millisecondsSinceEpoch,
      'lastModifiedMs': lastModified.millisecondsSinceEpoch,
      'chromaKeyBackgrounds': chromaKeyBackgrounds,
      'transitions': transitions.map((t) => t.toJson()).toList(),
      'videoEffects': videoEffects.map((e) => e.toJson()).toList(),
      'overlayClips': overlayClips.map((c) => c.toJson()).toList(),
    };
  }
}
