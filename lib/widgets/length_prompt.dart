import 'package:flutter/material.dart';

import '../main.dart' show AppColors;
import '../providers/video_editor_provider.dart';

String formatLength(Duration d) {
  final m = d.inMinutes;
  final s = d.inMilliseconds / 1000.0 - m * 60;
  return m > 0
      ? '$m:${s.toStringAsFixed(1).padLeft(4, '0')}'
      : '${s.toStringAsFixed(1)}s';
}

/// Every item counts toward the video's length. When an action makes the
/// video longer, the user decides whether that was intended.
class LengthPrompt {
  LengthPrompt._();

  /// Call right after adding item [id] of [kind]. If the video grew past
  /// [before], asks whether to keep the longer video or trim the new item to
  /// fit (or remove it, when it starts after the old end). Nothing is asked
  /// for an empty project.
  static Future<void> afterAdd(
    BuildContext context,
    VideoEditorProvider provider,
    Duration before,
    TimelineItemKind kind,
    String? id,
  ) async {
    final after = provider.totalDuration;
    if (id == null || before <= Duration.zero || after <= before) return;
    final startsAfterEnd = _startOf(provider, kind, id) >= before;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Make the video longer?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          startsAfterEnd
              ? 'This ${_name(kind)} starts after the end of your video, so '
                  'it will grow from ${formatLength(before)} to '
                  '${formatLength(after)}. The extra part shows black.'
              : 'This ${_name(kind)} runs past the end of your video, so it '
                  'will grow from ${formatLength(before)} to '
                  '${formatLength(after)}. The extra part shows black.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(startsAfterEnd ? 'Remove it' : 'Trim to fit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: const Text('Make longer'),
          ),
        ],
      ),
    );
    if (choice == 'keep') return;
    // Dismissed or declined: keep the video's length.
    if (startsAfterEnd) {
      await provider.undo();
    } else {
      provider.trimItemToEnd(kind, id, before);
    }
  }

  /// Call when a drag (stretching an item's end) finished. If the video got
  /// longer than [before], says so and offers Undo.
  static void afterStretch(
      BuildContext context, VideoEditorProvider provider, Duration before) {
    final after = provider.totalDuration;
    if (before <= Duration.zero || after <= before) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Video is now ${formatLength(after)} long '
            '(was ${formatLength(before)})'),
        action: SnackBarAction(label: 'UNDO', onPressed: provider.undo),
      ));
  }

  static String _name(TimelineItemKind kind) => switch (kind) {
        TimelineItemKind.text => 'text',
        TimelineItemKind.sticker => 'sticker',
        TimelineItemKind.audio => 'audio',
        TimelineItemKind.overlay => 'overlay',
      };

  static Duration _startOf(
      VideoEditorProvider p, TimelineItemKind kind, String id) {
    final project = p.currentProject;
    if (project == null) return Duration.zero;
    switch (kind) {
      case TimelineItemKind.text:
        for (final t in project.textOverlays) {
          if (t.id == id) return t.startTime;
        }
      case TimelineItemKind.sticker:
        for (final s in project.stickers) {
          if (s.id == id) return s.startTime;
        }
      case TimelineItemKind.audio:
        for (final a in project.audioOverlays) {
          if (a.id == id) return a.startTime;
        }
      case TimelineItemKind.overlay:
        for (final c in project.overlayClips) {
          if (c.id == id) return c.startTime;
        }
    }
    return Duration.zero;
  }
}
