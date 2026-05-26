// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chroma_key_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChromaKeySettingsAdapter extends TypeAdapter<ChromaKeySettings> {
  @override
  final int typeId = 18;

  @override
  ChromaKeySettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChromaKeySettings(
      enabled: fields[0] as bool,
      backgroundPath: fields[1] as String?,
      isBackgroundVideo: fields[2] as bool,
      keyColor: fields[3] as Color,
      similarity: fields[4] as double,
      blend: fields[5] as double,
      position: fields[6] as Offset,
      scale: fields[7] as double,
      hueMin: fields[8] as double,
      hueMax: fields[9] as double,
      saturationMin: fields[10] as double,
      saturationMax: fields[14] as double,
      valueMin: fields[11] as double,
      valueMax: fields[15] as double,
      spillReduction: fields[12] as double,
      edgeFeather: fields[13] as double,
      edgeTransition: fields[16] as double,
      shadowRemoval: fields[17] as double,
      skinProtection: fields[18] as double,
    );
  }

  @override
  void write(BinaryWriter writer, ChromaKeySettings obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.enabled)
      ..writeByte(1)
      ..write(obj.backgroundPath)
      ..writeByte(2)
      ..write(obj.isBackgroundVideo)
      ..writeByte(3)
      ..write(obj.keyColor)
      ..writeByte(4)
      ..write(obj.similarity)
      ..writeByte(5)
      ..write(obj.blend)
      ..writeByte(6)
      ..write(obj.position)
      ..writeByte(7)
      ..write(obj.scale)
      ..writeByte(8)
      ..write(obj.hueMin)
      ..writeByte(9)
      ..write(obj.hueMax)
      ..writeByte(10)
      ..write(obj.saturationMin)
      ..writeByte(14)
      ..write(obj.saturationMax)
      ..writeByte(11)
      ..write(obj.valueMin)
      ..writeByte(15)
      ..write(obj.valueMax)
      ..writeByte(12)
      ..write(obj.spillReduction)
      ..writeByte(13)
      ..write(obj.edgeFeather)
      ..writeByte(16)
      ..write(obj.edgeTransition)
      ..writeByte(17)
      ..write(obj.shadowRemoval)
      ..writeByte(18)
      ..write(obj.skinProtection);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChromaKeySettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
