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
      text: fields[1] as String,
      position: fields[2] as Offset,
      fontSize: fields[3] as double,
      color: fields[4] as Color,
      fontFamily: fields[5] as String,
      fontWeight: fields[6] as FontWeight,
      startTime: fields[7] as Duration,
      endTime: fields[8] as Duration,
      rotation: fields[9] as double,
      opacity: fields[10] as double,
      fontStyle: fields[11] as FontStyleEnum,
      textAlign: fields[12] as TextAlignEnum,
    );
  }

  @override
  void write(BinaryWriter writer, TextOverlay obj) {
    writer
      ..writeByte(13)
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
      ..write(obj.textAlign);
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
      audioStartOffset: fields[4] as Duration,
      volume: fields[5] as double,
      fadeIn: fields[6] as bool,
      fadeOut: fields[7] as bool,
      trackIndex: fields[8] as int,
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
      volume: fields[10] as double,
      isMuted: fields[11] as bool,
      rotation: fields[12] as double,
      cropRect: fields[13] as Rect?,
      isMirrored: fields[14] as bool,
      playbackSpeed: fields[15] as double,
      isReversed: fields[17] as bool,
      reversedFilePath: fields[18] as String?,
      chromaKeySettings: fields[19] as ChromaKeySettings?,
      overlayPosition: fields[20] as Offset,
      overlaySize: fields[21] as Size,
      overlayOpacity: fields[22] as double,
      trackIndex: fields[23] as int,
    );
  }

  @override
  void write(BinaryWriter writer, VideoClip obj) {
    writer
      ..writeByte(23)
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
      ..write(obj.trackIndex);
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
      position: fields[2] as Offset,
      scale: fields[3] as double,
      rotation: fields[4] as double,
      startTime: fields[5] as Duration,
      endTime: fields[6] as Duration,
      opacity: fields[7] as double,
    );
  }

  @override
  void write(BinaryWriter writer, StickerModel obj) {
    writer
      ..writeByte(8)
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
      ..write(obj.opacity);
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
    return ColorFilter(
      brightness: fields[0] as double,
      contrast: fields[1] as double,
      saturation: fields[2] as double,
      hue: fields[3] as double,
      exposure: fields[4] as double,
      highlights: fields[5] as double,
      shadows: fields[6] as double,
      warmth: fields[7] as double,
      tint: fields[8] as double,
      sharpness: fields[9] as double,
      fade: fields[10] as double,
      luminance: fields[11] as double,
      temperature: fields[12] as double,
      opacity: fields[13] as double,
      filterPresetMatrices: (fields[14] as List)
          .map((dynamic e) => (e as List).cast<double>())
          .toList(),
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
      name: fields[1] as String,
      videoClips: (fields[2] as List).cast<VideoClip>(),
      textOverlays: (fields[3] as List).cast<TextOverlay>(),
      audioOverlays: (fields[4] as List).cast<AudioOverlay>(),
      stickers: (fields[5] as List).cast<StickerModel>(),
      colorFilter: fields[6] as ColorFilter,
      overlayClips: (fields[15] as List).cast<VideoClip>(),
      totalDuration: fields[7] as Duration,
      outputResolution: fields[8] as Size,
      outputFrameRate: fields[9] as int,
      createdAt: fields[10] as DateTime?,
      lastModified: fields[11] as DateTime?,
      chromaKeyBackgrounds: (fields[12] as List).cast<String>(),
      transitions: (fields[13] as List).cast<Transition>(),
      videoEffects: (fields[14] as List).cast<VideoEffect>(),
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
