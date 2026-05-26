// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_effect.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VideoEffectAdapter extends TypeAdapter<VideoEffect> {
  @override
  final int typeId = 22;

  @override
  VideoEffect read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VideoEffect(
      id: fields[0] as String,
      clipId: fields[1] as String,
      type: fields[2] as VideoEffectType,
      intensity: fields[3] as double,
      startTime: fields[4] as Duration,
      duration: fields[5] as Duration,
      parameters: (fields[6] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, VideoEffect obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.clipId)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.intensity)
      ..writeByte(4)
      ..write(obj.startTime)
      ..writeByte(5)
      ..write(obj.duration)
      ..writeByte(6)
      ..write(obj.parameters);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoEffectAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class VideoEffectTypeAdapter extends TypeAdapter<VideoEffectType> {
  @override
  final int typeId = 21;

  @override
  VideoEffectType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return VideoEffectType.blur;
      case 1:
        return VideoEffectType.shake;
      case 2:
        return VideoEffectType.glitch;
      case 3:
        return VideoEffectType.flash;
      case 4:
        return VideoEffectType.grayscale;
      case 5:
        return VideoEffectType.sepia;
      case 6:
        return VideoEffectType.vintage;
      case 7:
        return VideoEffectType.neon;
      default:
        return VideoEffectType.blur;
    }
  }

  @override
  void write(BinaryWriter writer, VideoEffectType obj) {
    switch (obj) {
      case VideoEffectType.blur:
        writer.writeByte(0);
        break;
      case VideoEffectType.shake:
        writer.writeByte(1);
        break;
      case VideoEffectType.glitch:
        writer.writeByte(2);
        break;
      case VideoEffectType.flash:
        writer.writeByte(3);
        break;
      case VideoEffectType.grayscale:
        writer.writeByte(4);
        break;
      case VideoEffectType.sepia:
        writer.writeByte(5);
        break;
      case VideoEffectType.vintage:
        writer.writeByte(6);
        break;
      case VideoEffectType.neon:
        writer.writeByte(7);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoEffectTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
