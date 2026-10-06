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
      enabled: fields[0] as bool? ?? false,
      backgroundPath: fields[1] as String?,
      isBackgroundVideo: fields[2] as bool? ?? false,
      keyColor: fields[3] as Color? ?? const Color(0xFF00FF00),
      similarity: (fields[4] as num?)?.toDouble() ?? 0.30,
      blend: (fields[5] as num?)?.toDouble() ?? 0.05,
      position: fields[6] as Offset? ?? const Offset(0.5, 0.5),
      scale: (fields[7] as num?)?.toDouble() ?? 1.0,
      hueMin: (fields[8] as num?)?.toDouble() ?? 60.0,
      hueMax: (fields[9] as num?)?.toDouble() ?? 180.0,
      saturationMin: (fields[10] as num?)?.toDouble() ?? 0.15,
      saturationMax: (fields[14] as num?)?.toDouble() ?? 1.0,
      valueMin: (fields[11] as num?)?.toDouble() ?? 0.10,
      valueMax: (fields[15] as num?)?.toDouble() ?? 1.0,
      spillReduction: (fields[12] as num?)?.toDouble() ?? 1.0,
      edgeFeather: (fields[13] as num?)?.toDouble() ?? 0.10,
      edgeTransition: (fields[16] as num?)?.toDouble() ?? 0.20,
      shadowRemoval: (fields[17] as num?)?.toDouble() ?? 0.9,
      skinProtection: (fields[18] as num?)?.toDouble() ?? 0.8,
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
