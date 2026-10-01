import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../models/transition.dart';
import '../../models/video_project.dart';
import '../../providers/video_editor_provider.dart';
import '../../services/hive_service.dart';
import 'home_models.dart';
import 'home_prefs.dart';

/// A piece of media chosen on the home screen, before any project exists.
class HomeMedia {
  final File file;
  final bool isVideo;
  const HomeMedia(this.file, this.isVideo);
}

const _videoExts = {'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'};
const _imageExts = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'bmp',
  'heic',
  'heif',
  'webp',
};

bool isVideoPath(String path) =>
    _videoExts.contains(path.split('.').last.toLowerCase());

/// Project-level actions started from the home screen. They only use the
/// editor provider's public API (create, import, add transition/text/audio,
/// output settings) and the project store, so the editor, preview and export
/// code paths stay exactly as they are.
class HomeActions {
  HomeActions._();

  static const _uuid = Uuid();

  // ── Picking media ──────────────────────────────────────────────────────

  static Future<List<HomeMedia>> pickFromGallery(
      {bool imagesOnly = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: imagesOnly ? FileType.image : FileType.custom,
      allowedExtensions:
          imagesOnly ? null : [..._videoExts, ..._imageExts].toList(),
      allowMultiple: true,
    );
    if (result == null) return const [];
    final media = <HomeMedia>[];
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      final ext = (f.extension ?? path.split('.').last).toLowerCase();
      if (_videoExts.contains(ext) && !imagesOnly) {
        media.add(HomeMedia(File(path), true));
      } else if (_imageExts.contains(ext)) {
        media.add(HomeMedia(File(path), false));
      }
    }
    return media;
  }

  /// Records a clip with the device camera. Returns null when cancelled.
  static Future<HomeMedia?> recordVideo(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      messenger?.showSnackBar(const SnackBar(
          content: Text('Camera permission is needed to record a video.')));
      if (status.isPermanentlyDenied) await openAppSettings();
      return null;
    }
    await Permission.microphone.request();
    final file = await ImagePicker().pickVideo(source: ImageSource.camera);
    if (file == null) return null;
    return HomeMedia(File(file.path), true);
  }

  /// Copies bundled library assets to real files the importer can read.
  static Future<List<HomeMedia>> assetsToMedia(List<String> assets) async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/home_assets');
    if (!await dir.exists()) await dir.create(recursive: true);
    final media = <HomeMedia>[];
    for (final asset in assets) {
      try {
        final data = await rootBundle.load(asset);
        final file = File('${dir.path}/${asset.split('/').last}');
        if (!await file.exists() || await file.length() != data.lengthInBytes) {
          await file.writeAsBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        }
        media.add(HomeMedia(file, isVideoPath(asset)));
      } catch (_) {}
    }
    return media;
  }

  // ── Opening / creating ─────────────────────────────────────────────────

  static Future<void> openProject(
    VideoEditorProvider provider,
    HomePrefs prefs,
    String projectId,
  ) async {
    await prefs.markOpened(projectId);
    await provider.loadProject(projectId);
  }

  /// Creates a project, imports [media] into it, applies the output shape and,
  /// for templates/slideshows, adds transitions, a title and music.
  ///
  /// Once the project exists the home screen is replaced by the editor, so
  /// everything here works from captured references, not the home widgets.
  static Future<void> createProject({
    required BuildContext context,
    required VideoEditorProvider provider,
    required HomePrefs prefs,
    required String name,
    required AspectOption aspect,
    List<HomeMedia> media = const [],
    HomeTemplate? template,
    bool pickAfterCreate = false,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    await provider.createNewProject(
        name.trim().isEmpty ? autoProjectName() : name.trim());
    final projectId = provider.currentProject?.id;
    if (projectId != null) await prefs.markOpened(projectId);

    var items = media;
    if (pickAfterCreate && items.isEmpty) {
      items = await pickFromGallery();
    }

    var failed = 0;
    for (final item in items) {
      try {
        if (item.isVideo) {
          await provider.loadVideoFile(item.file);
        } else {
          await provider.loadImageFile(item.file);
        }
      } catch (_) {
        failed++;
      }
    }

    if (provider.currentProject == null) return;

    if (aspect.id != 'original') {
      await provider.setOutputSettings(resolution: aspect.resolution);
    }

    if (template != null) {
      await _applyTemplate(provider, template);
    }

    if (failed > 0) {
      messenger?.showSnackBar(SnackBar(
          content: Text(
              '$failed item${failed == 1 ? '' : 's'} could not be imported.')));
    } else if (template != null && items.isNotEmpty) {
      messenger?.showSnackBar(SnackBar(
          content:
              Text('"${template.name}" applied — tap any clip to swap it.')));
    }
  }

  static Future<void> _applyTemplate(
    VideoEditorProvider provider,
    HomeTemplate template,
  ) async {
    final project = provider.currentProject;
    if (project == null || project.videoClips.isEmpty) return;

    // Transition between every pair of clips, like the editor's own
    // transition tool (startTime = end of the outgoing clip - duration).
    final clips = [...project.videoClips]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    for (var i = 0; i < clips.length - 1; i++) {
      final c1 = clips[i];
      final c2 = clips[i + 1];
      final shortest = math.min(
        (c1.endTime - c1.startTime).inMilliseconds,
        (c2.endTime - c2.startTime).inMilliseconds,
      );
      final ms = math.min(
          template.transitionDuration.inMilliseconds, (shortest * 0.4).round());
      if (ms < 150) continue;
      final duration = Duration(milliseconds: ms);
      await provider.addTransition(Transition(
        id: '${DateTime.now().microsecondsSinceEpoch}_$i',
        clipId1: c1.id,
        clipId2: c2.id,
        type: template.transition,
        duration: duration,
        startTime: c1.endTime - duration,
      ));
    }

    final total = provider.currentProject!.calculateTotalDuration();

    if (template.title.isNotEmpty) {
      final end = total < const Duration(seconds: 3)
          ? total
          : const Duration(seconds: 3);
      if (end > Duration.zero) {
        await provider.addTextOverlay(
          text: template.title,
          position: const Offset(0.5, 0.5),
          startTime: Duration.zero,
          endTime: end,
          fontSize: 34,
          fontWeight: FontWeight.bold,
        );
      }
    }

    if (template.music) {
      await _addBackgroundMusic(provider, total);
    }
  }

  static Future<void> _addBackgroundMusic(
    VideoEditorProvider provider,
    Duration total,
  ) async {
    if (total <= Duration.zero) return;
    try {
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/home_assets/template_music.mp3');
      if (!await file.exists()) {
        await file.parent.create(recursive: true);
        final data = await rootBundle.load('assets/audio/audio.mp3');
        await file.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
      var length = total;
      final probe = AudioPlayer();
      try {
        final d = await probe.setFilePath(file.path);
        if (d != null && d < length) length = d;
      } finally {
        await probe.dispose();
      }
      await provider.addAudioOverlay(
        audioFile: file,
        startTime: Duration.zero,
        endTime: length,
        volume: 0.6,
        fadeIn: true,
        fadeOut: true,
      );
    } catch (_) {
      // Music is a nice-to-have; the project is usable without it.
    }
  }

  // ── Project management ─────────────────────────────────────────────────

  static Future<VideoProject> duplicate(VideoProject p) async {
    final copy = VideoProject(
      id: _uuid.v4(),
      name: '${displayName(p)} (copy)',
      videoClips: List.of(p.videoClips),
      textOverlays: List.of(p.textOverlays),
      audioOverlays: List.of(p.audioOverlays),
      stickers: List.of(p.stickers),
      colorFilter: p.colorFilter,
      overlayClips: List.of(p.overlayClips),
      totalDuration: p.calculateTotalDuration(),
      outputResolution: p.outputResolution,
      outputFrameRate: p.outputFrameRate,
      chromaKeyBackgrounds: List.of(p.chromaKeyBackgrounds),
      transitions: List.of(p.transitions),
      videoEffects: List.of(p.videoEffects),
    );
    await HiveService.saveProject(copy);
    return copy;
  }

  static Future<void> rename(VideoProject p, String name) async {
    await HiveService.saveProject(
        p.copyWith(name: name.trim(), lastModified: p.lastModified));
  }

  static Future<void> delete(
    VideoEditorProvider provider,
    HomePrefs prefs,
    VideoProject p,
  ) async {
    await provider.deleteProject(p.id);
    await prefs.forgetProject(p.id);
  }

  /// Puts a deleted project back (Undo).
  static Future<void> restore(
    VideoEditorProvider provider,
    VideoProject p,
  ) async {
    await HiveService.saveProject(p);
  }
}
