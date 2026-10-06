// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transition.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TransitionAdapter extends TypeAdapter<Transition> {
  @override
  final int typeId = 20;

  @override
  Transition read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Transition(
      id: fields[0] as String,
      clipId1: fields[1] as String,
      clipId2: fields[2] as String,
      type: fields[3] as TransitionType,
      duration: fields[4] as Duration? ?? const Duration(milliseconds: 500),
      startTime: fields[5] as Duration? ?? Duration.zero,
    );
  }

  @override
  void write(BinaryWriter writer, Transition obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.clipId1)
      ..writeByte(2)
      ..write(obj.clipId2)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.duration)
      ..writeByte(5)
      ..write(obj.startTime);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransitionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TransitionTypeAdapter extends TypeAdapter<TransitionType> {
  @override
  final int typeId = 19;

  @override
  TransitionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TransitionType.crossfade;
      case 1:
        return TransitionType.zoom;
      case 2:
        return TransitionType.slideLeft;
      case 3:
        return TransitionType.slideRight;
      case 4:
        return TransitionType.slideUp;
      case 5:
        return TransitionType.slideDown;
      case 7:
        return TransitionType.black;
      case 8:
        return TransitionType.white;
      case 9:
        return TransitionType.shake;
      case 10:
        return TransitionType.light;
      case 12:
        return TransitionType.pixelate;
      case 13:
        return TransitionType.circle;
      case 14:
        return TransitionType.push;
      case 22:
        return TransitionType.pushRight;
      case 15:
        return TransitionType.rotate1;
      case 16:
        return TransitionType.rotate2;
      case 19:
        return TransitionType.blink;
      case 20:
        return TransitionType.vertical;
      case 21:
        return TransitionType.horizontal;
      default:
        return TransitionType.crossfade;
    }
  }

  @override
  void write(BinaryWriter writer, TransitionType obj) {
    switch (obj) {
      case TransitionType.crossfade:
        writer.writeByte(0);
        break;
      case TransitionType.zoom:
        writer.writeByte(1);
        break;
      case TransitionType.slideLeft:
        writer.writeByte(2);
        break;
      case TransitionType.slideRight:
        writer.writeByte(3);
        break;
      case TransitionType.slideUp:
        writer.writeByte(4);
        break;
      case TransitionType.slideDown:
        writer.writeByte(5);
        break;
      case TransitionType.black:
        writer.writeByte(7);
        break;
      case TransitionType.white:
        writer.writeByte(8);
        break;
      case TransitionType.shake:
        writer.writeByte(9);
        break;
      case TransitionType.light:
        writer.writeByte(10);
        break;
      case TransitionType.pixelate:
        writer.writeByte(12);
        break;
      case TransitionType.circle:
        writer.writeByte(13);
        break;
      case TransitionType.push:
        writer.writeByte(14);
        break;
      case TransitionType.pushRight:
        writer.writeByte(22);
        break;
      case TransitionType.rotate1:
        writer.writeByte(15);
        break;
      case TransitionType.rotate2:
        writer.writeByte(16);
        break;
      case TransitionType.blink:
        writer.writeByte(19);
        break;
      case TransitionType.vertical:
        writer.writeByte(20);
        break;
      case TransitionType.horizontal:
        writer.writeByte(21);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransitionTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
