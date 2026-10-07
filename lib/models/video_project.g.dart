// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_project.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TextOverlayAdapter extends TypeAdapter<TextOverlay> {
  @override
  final int typeId = 1;

  @override
  TextOverlay read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TextOverlay(
      id: fields[0] as String,
      text: fields[1] as String? ?? '',
      position: fields[2] as Offset? ?? const Offset(0.5, 0.5),
      fontSize: (fields[3] as num?)?.toDouble() ?? 24.0,
      color: fields[4] as Color? ?? const Color(0xFFFFFFFF),
      fontFamily: fields[5] as String? ?? 'Roboto',
      fontWeight: fields[6] as FontWeight? ?? FontWeight.normal,
      startTime: fields[7] as Duration? ?? Duration.zero,
      endTime: fields[8] as Duration? ?? const Duration(seconds: 3),
      rotation: (fields[9] as num?)?.toDouble() ?? 0.0,
      opacity: (fields[10] as num?)?.toDouble() ?? 1.0,
      fontStyle: fields[11] as FontStyleEnum? ?? FontStyleEnum.normal,
      textAlign: fields[12] as TextAlignEnum? ?? TextAlignEnum.center,
      // Fields 13+ were added later; older projects read the defaults.
      animIn: fields[13] as String? ?? 'none',
      animOut: fields[14] as String? ?? 'none',
      boxColor: fields[15] as Color?,
      outlineColor: fields[16] as Color?,
      outlineWidth: (fields[17] as num?)?.toDouble() ?? 0,
      shadow: fields[18] as bool? ?? true,
      keyframeData: _doubles(fields[19]),
    );
  }

  @override
  void write(BinaryWriter writer, TextOverlay obj) {
    writer
      ..writeByte(20)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.position)
      ..writeByte(3)
      ..write(obj.fontSize)
      ..writeByte(4)
      ..write(obj.color)
      ..writeByte(5)
      ..write(obj.fontFamily)
      ..writeByte(6)
      ..write(obj.fontWeight)
      ..writeByte(7)
      ..write(obj.startTime)
      ..writeByte(8)
      ..write(obj.endTime)
      ..writeByte(9)
      ..write(obj.rotation)
      ..writeByte(10)
      ..write(obj.opacity)
      ..writeByte(11)
      ..write(obj.fontStyle)
      ..writeByte(12)
      ..write(obj.textAlign)
      ..writeByte(13)
      ..write(obj.animIn)
      ..writeByte(14)
      ..write(obj.animOut)
      ..writeByte(15)
      ..write(obj.boxColor)
      ..writeByte(16)
      ..write(obj.outlineColor)
      ..writeByte(17)
      ..write(obj.outlineWidth)
      ..writeByte(18)
      ..write(obj.shadow)
      ..writeByte(19)
      ..write(obj.keyframeData);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextOverlayAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AudioOverlayAdapter extends TypeAdapter<AudioOverlay> {
  @override
  final int typeId = 2;

  @override
  AudioOverlay read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AudioOverlay(
      id: fields[0] as String,
      audioFile: fields[1] as File,
      startTime: fields[2] as Duration,
      endTime: fields[3] as Duration,
      // Every field below may be missing in projects saved by older builds.
      audioStartOffset: fields[4] as Duration? ?? Duration.zero,
      volume: (fields[5] as num?)?.toDouble() ?? 1.0,
      fadeIn: fields[6] as bool? ?? false,
      fadeOut: fields[7] as bool? ?? false,
      trackIndex: (fields[8] as num?)?.toInt() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, AudioOverlay obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.audioFile)
      ..writeByte(2)
      ..write(obj.startTime)
      ..writeByte(3)
      ..write(obj.endTime)
      ..writeByte(4)
      ..write(obj.audioStartOffset)
      ..writeByte(5)
      ..write(obj.volume)
      ..writeByte(6)
      ..write(obj.fadeIn)
      ..writeByte(7)
      ..write(obj.fadeOut)
      ..writeByte(8)
      ..write(obj.trackIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioOverlayAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class VideoClipAdapter extends TypeAdapter<VideoClip> {
  @override
  final int typeId = 3;

  @override
  VideoClip read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VideoClip(
      id: fields[0] as String,
      mediaType: fields[1] as MediaType,
      videoFile: fields[2] as File?,
      imageFile: fields[3] as File?,
      startTime: fields[4] as Duration,
      endTime: fields[5] as Duration,
      sourceStart: fields[6] as Duration?,
      sourceEnd: fields[7] as Duration?,
      trimStart: fields[8] as Duration?,
      trimEnd: fields[9] as Duration?,
      // Fields 10+ may be missing in projects saved by older builds.
      volume: (fields[10] as num?)?.toDouble() ?? 1.0,
      isMuted: fields[11] as bool? ?? false,
      rotation: (fields[12] as num?)?.toDouble() ?? 0.0,
      cropRect: fields[13] as Rect?,
      isMirrored: fields[14] as bool? ?? false,
      playbackSpeed: (fields[15] as num?)?.toDouble() ?? 1.0,
      isReversed: fields[17] as bool? ?? false,
      reversedFilePath: fields[18] as String?,
      chromaKeySettings: fields[19] as ChromaKeySettings?,
      overlayPosition: fields[20] as Offset? ?? const Offset(0.1, 0.1),
      overlaySize: fields[21] as Size? ?? const Size(0.3, 0.3),
      overlayOpacity: (fields[22] as num?)?.toDouble() ?? 1.0,
      trackIndex: (fields[23] as num?)?.toInt() ?? 0,
      maskShape: fields[24] as String? ?? 'none',
      borderWidth: (fields[25] as num?)?.toDouble() ?? 0.0,
      borderColor: fields[26] as Color?,
      shadow: fields[27] as bool? ?? false,
      animIn: fields[28] as String? ?? 'none',
      animOut: fields[29] as String? ?? 'none',
      keyframeData: _doubles(fields[30]),
    );
  }

  @override
  void write(BinaryWriter writer, VideoClip obj) {
    writer
      ..writeByte(30)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.mediaType)
      ..writeByte(2)
      ..write(obj.videoFile)
      ..writeByte(3)
      ..write(obj.imageFile)
      ..writeByte(4)
      ..write(obj.startTime)
      ..writeByte(5)
      ..write(obj.endTime)
      ..writeByte(6)
      ..write(obj.sourceStart)
      ..writeByte(7)
      ..write(obj.sourceEnd)
      ..writeByte(8)
      ..write(obj.trimStart)
      ..writeByte(9)
      ..write(obj.trimEnd)
      ..writeByte(10)
      ..write(obj.volume)
      ..writeByte(11)
      ..write(obj.isMuted)
      ..writeByte(12)
      ..write(obj.rotation)
      ..writeByte(13)
      ..write(obj.cropRect)
      ..writeByte(14)
      ..write(obj.isMirrored)
      ..writeByte(15)
      ..write(obj.playbackSpeed)
      ..writeByte(17)
      ..write(obj.isReversed)
      ..writeByte(18)
      ..write(obj.reversedFilePath)
      ..writeByte(19)
      ..write(obj.chromaKeySettings)
      ..writeByte(20)
      ..write(obj.overlayPosition)
      ..writeByte(21)
      ..write(obj.overlaySize)
      ..writeByte(22)
      ..write(obj.overlayOpacity)
      ..writeByte(23)
      ..write(obj.trackIndex)
      ..writeByte(24)
      ..write(obj.maskShape)
      ..writeByte(25)
      ..write(obj.borderWidth)
      ..writeByte(26)
      ..write(obj.borderColor)
      ..writeByte(27)
      ..write(obj.shadow)
      ..writeByte(28)
      ..write(obj.animIn)
      ..writeByte(29)
      ..write(obj.animOut)
      ..writeByte(30)
      ..write(obj.keyframeData);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoClipAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class StickerModelAdapter extends TypeAdapter<StickerModel> {
  @override
  final int typeId = 4;

  @override
  StickerModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StickerModel(
      id: fields[0] as String,
      assetPath: fields[1] as String,
      position: fields[2] as Offset? ?? const Offset(0.5, 0.5),
      scale: (fields[3] as num?)?.toDouble() ?? 1.0,
      rotation: (fields[4] as num?)?.toDouble() ?? 0.0,
      startTime: fields[5] as Duration? ?? Duration.zero,
      endTime: fields[6] as Duration? ?? const Duration(seconds: 5),
      opacity: (fields[7] as num?)?.toDouble() ?? 1.0,
      // Fields 8+ were added later; older projects read the defaults.
      flipX: fields[8] as bool? ?? false,
      animIn: fields[9] as String? ?? 'none',
      animOut: fields[10] as String? ?? 'none',
      keyframeData: _doubles(fields[11]),
    );
  }

  @override
  void write(BinaryWriter writer, StickerModel obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.assetPath)
      ..writeByte(2)
      ..write(obj.position)
      ..writeByte(3)
      ..write(obj.scale)
      ..writeByte(4)
      ..write(obj.rotation)
      ..writeByte(5)
      ..write(obj.startTime)
      ..writeByte(6)
      ..write(obj.endTime)
      ..writeByte(7)
      ..write(obj.opacity)
      ..writeByte(8)
      ..write(obj.flipX)
      ..writeByte(9)
      ..write(obj.animIn)
      ..writeByte(10)
      ..write(obj.animOut)
      ..writeByte(11)
      ..write(obj.keyframeData);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StickerModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ColorFilterAdapter extends TypeAdapter<ColorFilter> {
  @override
  final int typeId = 5;

  @override
  ColorFilter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    double d(int i, double fallback) =>
        (fields[i] as num?)?.toDouble() ?? fallback;
    return ColorFilter(
      brightness: d(0, 0.0),
      contrast: d(1, 1.0),
      saturation: d(2, 1.0),
      hue: d(3, 0.0),
      exposure: d(4, 0.0),
      highlights: d(5, 0.0),
      shadows: d(6, 0.0),
      warmth: d(7, 0.0),
      tint: d(8, 0.0),
      sharpness: d(9, 0.0),
      fade: d(10, 0.0),
      luminance: d(11, 0.0),
      temperature: d(12, 0.0),
      opacity: d(13, 1.0),
      filterPresetMatrices: (fields[14] as List?)
              ?.map((dynamic e) =>
                  (e as List).map((v) => (v as num).toDouble()).toList())
              .toList() ??
          const [],
    );
  }

  @override
  void write(BinaryWriter writer, ColorFilter obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.brightness)
      ..writeByte(1)
      ..write(obj.contrast)
      ..writeByte(2)
      ..write(obj.saturation)
      ..writeByte(3)
      ..write(obj.hue)
      ..writeByte(4)
      ..write(obj.exposure)
      ..writeByte(5)
      ..write(obj.highlights)
      ..writeByte(6)
      ..write(obj.shadows)
      ..writeByte(7)
      ..write(obj.warmth)
      ..writeByte(8)
      ..write(obj.tint)
      ..writeByte(9)
      ..write(obj.sharpness)
      ..writeByte(10)
      ..write(obj.fade)
      ..writeByte(11)
      ..write(obj.luminance)
      ..writeByte(12)
      ..write(obj.temperature)
      ..writeByte(13)
      ..write(obj.opacity)
      ..writeByte(14)
      ..write(obj.filterPresetMatrices);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorFilterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class VideoProjectAdapter extends TypeAdapter<VideoProject> {
  @override
  final int typeId = 6;

  @override
  VideoProject read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VideoProject(
      id: fields[0] as String,
      // Lists and settings may be missing in projects saved by older builds.
      name: fields[1] as String? ?? 'Untitled',
      videoClips: (fields[2] as List?)?.cast<VideoClip>() ?? const [],
      textOverlays: (fields[3] as List?)?.cast<TextOverlay>() ?? const [],
      audioOverlays: (fields[4] as List?)?.cast<AudioOverlay>() ?? const [],
      stickers: (fields[5] as List?)?.cast<StickerModel>() ?? const [],
      colorFilter: fields[6] as ColorFilter? ?? const ColorFilter(),
      overlayClips: (fields[15] as List?)?.cast<VideoClip>() ?? const [],
      totalDuration: fields[7] as Duration? ?? Duration.zero,
      outputResolution: fields[8] as Size? ?? const Size(1920, 1080),
      outputFrameRate: (fields[9] as num?)?.toInt() ?? 30,
      createdAt: fields[10] as DateTime?,
      lastModified: fields[11] as DateTime?,
      chromaKeyBackgrounds:
          (fields[12] as List?)?.cast<String>() ?? const [],
      transitions: (fields[13] as List?)?.cast<Transition>() ?? const [],
      videoEffects: (fields[14] as List?)?.cast<VideoEffect>() ?? const [],
    );
  }

  @override
  void write(BinaryWriter writer, VideoProject obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.videoClips)
      ..writeByte(3)
      ..write(obj.textOverlays)
      ..writeByte(4)
      ..write(obj.audioOverlays)
      ..writeByte(5)
      ..write(obj.stickers)
      ..writeByte(6)
      ..write(obj.colorFilter)
      ..writeByte(7)
      ..write(obj.totalDuration)
      ..writeByte(8)
      ..write(obj.outputResolution)
      ..writeByte(9)
      ..write(obj.outputFrameRate)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.lastModified)
      ..writeByte(12)
      ..write(obj.chromaKeyBackgrounds)
      ..writeByte(13)
      ..write(obj.transitions)
      ..writeByte(14)
      ..write(obj.videoEffects)
      ..writeByte(15)
      ..write(obj.overlayClips);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoProjectAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MediaTypeAdapter extends TypeAdapter<MediaType> {
  @override
  final int typeId = 0;

  @override
  MediaType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MediaType.video;
      case 1:
        return MediaType.image;
      default:
        return MediaType.video;
    }
  }

  @override
  void write(BinaryWriter writer, MediaType obj) {
    switch (obj) {
      case MediaType.video:
        writer.writeByte(0);
        break;
      case MediaType.image:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FontStyleEnumAdapter extends TypeAdapter<FontStyleEnum> {
  @override
  final int typeId = 7;

  @override
  FontStyleEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return FontStyleEnum.normal;
      case 1:
        return FontStyleEnum.italic;
      default:
        return FontStyleEnum.normal;
    }
  }

  @override
  void write(BinaryWriter writer, FontStyleEnum obj) {
    switch (obj) {
      case FontStyleEnum.normal:
        writer.writeByte(0);
        break;
      case FontStyleEnum.italic:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FontStyleEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TextAlignEnumAdapter extends TypeAdapter<TextAlignEnum> {
  @override
  final int typeId = 8;

  @override
  TextAlignEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TextAlignEnum.left;
      case 1:
        return TextAlignEnum.center;
      case 2:
        return TextAlignEnum.right;
      case 3:
        return TextAlignEnum.justify;
      case 4:
        return TextAlignEnum.start;
      case 5:
        return TextAlignEnum.end;
      default:
        return TextAlignEnum.left;
    }
  }

  @override
  void write(BinaryWriter writer, TextAlignEnum obj) {
    switch (obj) {
      case TextAlignEnum.left:
        writer.writeByte(0);
        break;
      case TextAlignEnum.center:
        writer.writeByte(1);
        break;
      case TextAlignEnum.right:
        writer.writeByte(2);
        break;
      case TextAlignEnum.justify:
        writer.writeByte(3);
        break;
      case TextAlignEnum.start:
        writer.writeByte(4);
        break;
      case TextAlignEnum.end:
        writer.writeByte(5);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextAlignEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

/// Reads a stored list of numbers (missing in older projects) as doubles.
List<double> _doubles(dynamic value) =>
    (value as List?)?.map((e) => (e as num).toDouble()).toList() ??
    const <double>[];
