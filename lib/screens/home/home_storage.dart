import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How much space the app uses, split the way the user thinks about it.
class StorageUsage {
  final int projectMedia;
  final int exports;
  final int renderCache;
  final int otherCache;

  const StorageUsage({
    required this.projectMedia,
    required this.exports,
    required this.renderCache,
    required this.otherCache,
  });

  int get cache => renderCache + otherCache;
  int get total => projectMedia + exports + cache;
}

/// An exported video that still exists on the device.
class ExportedVideo {
  final File file;
  final DateTime created;
  final int bytes;

  const ExportedVideo(this.file, this.created, this.bytes);

  String get path => file.path;
}

/// File-system helpers for the home screen: storage stats, cache cleanup
/// and discovering exported videos. The editor writes every export to the
/// temp folder as `edited_video_<time>.mp4` before saving a copy where the
/// user chose, so that folder is the export history.
class HomeStorage {
  HomeStorage._();

  static bool _isExport(String path) {
    final name = p.basename(path);
    return name.startsWith('edited_video_') && name.endsWith('.mp4');
  }

  static bool _isRenderCache(String relative) {
    final top = relative.split(RegExp(r'[\\/]')).first;
    return top == 'transition_previews' ||
        top.startsWith('transition_render_') ||
        top.startsWith('export_');
  }

  static Future<int> _sizeOf(FileSystemEntity e) async {
    try {
      if (e is File) return await e.length();
      if (e is Directory) {
        var total = 0;
        await for (final child in e.list(recursive: true, followLinks: false)) {
          if (child is File) {
            try {
              total += await child.length();
            } catch (_) {}
          }
        }
        return total;
      }
    } catch (_) {}
    return 0;
  }

  static Future<StorageUsage> usage() async {
    final docs = await getApplicationDocumentsDirectory();
    final temp = await getTemporaryDirectory();

    final projectMedia = await _sizeOf(docs);
    var exports = 0, render = 0, other = 0;
    if (await temp.exists()) {
      await for (final e in temp.list(followLinks: false)) {
        final size = await _sizeOf(e);
        final rel = p.relative(e.path, from: temp.path);
        if (e is File && _isExport(e.path)) {
          exports += size;
        } else if (_isRenderCache(rel)) {
          render += size;
        } else {
          other += size;
        }
      }
    }
    return StorageUsage(
      projectMedia: projectMedia,
      exports: exports,
      renderCache: render,
      otherCache: other,
    );
  }

  /// Deletes render leftovers and other temporary files, keeping exports.
  /// Only safe while no project is open (the home screen guarantees that).
  static Future<int> clearCache() async {
    final temp = await getTemporaryDirectory();
    var freed = 0;
    if (!await temp.exists()) return 0;
    await for (final e in temp.list(followLinks: false)) {
      if (e is File && _isExport(e.path)) continue;
      final size = await _sizeOf(e);
      try {
        await e.delete(recursive: true);
        freed += size;
      } catch (_) {}
    }
    return freed;
  }

  static Future<List<ExportedVideo>> exports() async {
    final temp = await getTemporaryDirectory();
    final result = <ExportedVideo>[];
    if (!await temp.exists()) return result;
    await for (final e in temp.list(followLinks: false)) {
      if (e is! File || !_isExport(e.path)) continue;
      try {
        final stat = await e.stat();
        if (stat.size <= 0) continue;
        result.add(ExportedVideo(e, stat.modified, stat.size));
      } catch (_) {}
    }
    result.sort((a, b) => b.created.compareTo(a.created));
    return result;
  }

  static Future<int> deleteExports(Iterable<ExportedVideo> videos) async {
    var freed = 0;
    for (final v in videos) {
      try {
        await v.file.delete();
        freed += v.bytes;
      } catch (_) {}
    }
    return freed;
  }
}
