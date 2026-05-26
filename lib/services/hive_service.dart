import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transition.dart';
import '../models/video_project.dart';
import '../models/chroma_key_settings.dart';
import '../models/video_effect.dart';

class HiveService {
  static const String _projectsBoxName = 'projects';
  static Box<VideoProject>? _projectsBox;

  /// Initialize Hive and register adapters
  static Future<void> init() async {
    await Hive.initFlutter();

    // Register built-in type adapters for Flutter/Dart types
    _registerBuiltInAdapters();

    // Register custom model adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MediaTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TextOverlayAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AudioOverlayAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(VideoClipAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(StickerModelAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(ColorFilterAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(VideoProjectAdapter());
    }
    if (!Hive.isAdapterRegistered(18)) {
      Hive.registerAdapter(ChromaKeySettingsAdapter());
    }
    if (!Hive.isAdapterRegistered(19)) {
      Hive.registerAdapter(TransitionTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(20)) {
      Hive.registerAdapter(TransitionAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(VideoEffectTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(VideoEffectAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(FontStyleEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(TextAlignEnumAdapter());
    }

    try {
      // Try to open the box
      _projectsBox = await Hive.openBox<VideoProject>(_projectsBoxName);
    } catch (e) {
      // If opening fails due to schema mismatch, delete the box and recreate it
      print('Failed to open projects box: $e');
      print('Deleting and recreating projects box...');
      await Hive.deleteBoxFromDisk(_projectsBoxName);
      _projectsBox = await Hive.openBox<VideoProject>(_projectsBoxName);
    }
  }

  /// Register built-in type adapters for Flutter/Dart types
  static void _registerBuiltInAdapters() {
    // Register Offset adapter
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(OffsetAdapter());
    }

    // Register Color adapter
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(ColorAdapter());
    }

    // Register FontWeight adapter
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(FontWeightAdapter());
    }

    // Register Duration adapter
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(DurationAdapter());
    }

    // Register DateTime adapter
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(DateTimeAdapter());
    }

    // Register Size adapter
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(SizeAdapter());
    }

    // Register Rect adapter
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(RectAdapter());
    }

    // Register File adapter
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(FileAdapter());
    }
  }

  /// Save a project to Hive
  static Future<void> saveProject(VideoProject project) async {
    if (_projectsBox == null) await init();
    await _projectsBox!.put(project.id, project);
  }

  /// Get a project by ID
  static VideoProject? getProject(String id) {
    if (_projectsBox == null) return null;
    return _projectsBox!.get(id);
  }

  /// Get all projects
  static List<VideoProject> getAllProjects() {
    if (_projectsBox == null) return [];
    return _projectsBox!.values.toList()
      ..sort((a, b) =>
          b.lastModified.compareTo(a.lastModified)); // Most recent first
  }

  /// Delete a project
  static Future<void> deleteProject(String id) async {
    if (_projectsBox == null) return;
    await _projectsBox!.delete(id);
  }

  /// Update a project
  static Future<void> updateProject(VideoProject project) async {
    await saveProject(project); // Same as save since we use ID as key
  }

  /// Get recent projects (last 10)
  static List<VideoProject> getRecentProjects({int limit = 10}) {
    final allProjects = getAllProjects();
    return allProjects.take(limit).toList();
  }

  /// Clear all projects (for testing/debugging)
  static Future<void> clearAllProjects() async {
    if (_projectsBox == null) return;
    await _projectsBox!.clear();
  }

  /// Close Hive boxes
  static Future<void> close() async {
    await _projectsBox?.close();
    await Hive.close();
  }
}

// Custom type adapters for Flutter/Dart types
class OffsetAdapter extends TypeAdapter<Offset> {
  @override
  final int typeId = 10;

  @override
  Offset read(BinaryReader reader) {
    final dx = reader.readDouble();
    final dy = reader.readDouble();
    return Offset(dx, dy);
  }

  @override
  void write(BinaryWriter writer, Offset obj) {
    writer.writeDouble(obj.dx);
    writer.writeDouble(obj.dy);
  }
}

class ColorAdapter extends TypeAdapter<Color> {
  @override
  final int typeId = 11;

  @override
  Color read(BinaryReader reader) {
    final value = reader.readInt();
    return Color(value);
  }

  @override
  void write(BinaryWriter writer, Color obj) {
    writer.writeInt(obj.value);
  }
}

class FontWeightAdapter extends TypeAdapter<FontWeight> {
  @override
  final int typeId = 12;

  @override
  FontWeight read(BinaryReader reader) {
    final index = reader.readInt();
    return FontWeight.values[index];
  }

  @override
  void write(BinaryWriter writer, FontWeight obj) {
    writer.writeInt(obj.index);
  }
}

class DurationAdapter extends TypeAdapter<Duration> {
  @override
  final int typeId = 13;

  @override
  Duration read(BinaryReader reader) {
    final microseconds = reader.readInt();
    return Duration(microseconds: microseconds);
  }

  @override
  void write(BinaryWriter writer, Duration obj) {
    writer.writeInt(obj.inMicroseconds);
  }
}

class DateTimeAdapter extends TypeAdapter<DateTime> {
  @override
  final int typeId = 14;

  @override
  DateTime read(BinaryReader reader) {
    final milliseconds = reader.readInt();
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  @override
  void write(BinaryWriter writer, DateTime obj) {
    writer.writeInt(obj.millisecondsSinceEpoch);
  }
}

class SizeAdapter extends TypeAdapter<Size> {
  @override
  final int typeId = 15;

  @override
  Size read(BinaryReader reader) {
    final width = reader.readDouble();
    final height = reader.readDouble();
    return Size(width, height);
  }

  @override
  void write(BinaryWriter writer, Size obj) {
    writer.writeDouble(obj.width);
    writer.writeDouble(obj.height);
  }
}

class RectAdapter extends TypeAdapter<Rect> {
  @override
  final int typeId = 16;

  @override
  Rect read(BinaryReader reader) {
    final left = reader.readDouble();
    final top = reader.readDouble();
    final right = reader.readDouble();
    final bottom = reader.readDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  void write(BinaryWriter writer, Rect obj) {
    writer.writeDouble(obj.left);
    writer.writeDouble(obj.top);
    writer.writeDouble(obj.right);
    writer.writeDouble(obj.bottom);
  }
}

class FileAdapter extends TypeAdapter<File> {
  @override
  final int typeId = 17;

  @override
  File read(BinaryReader reader) {
    final path = reader.readString();
    return File(path);
  }

  @override
  void write(BinaryWriter writer, File obj) {
    writer.writeString(obj.path);
  }
}
