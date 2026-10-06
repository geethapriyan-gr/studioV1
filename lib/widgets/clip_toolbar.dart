import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show AppColors;
import '../models/editor_panel_mode.dart';
import '../models/video_project.dart';
import '../providers/video_editor_provider.dart';
import 'clip_tool_sheets.dart';

/// Toolbar shown instead of the main toolbar while a timeline clip is
/// selected: every tool for that clip in one row.
class ClipToolbar extends StatelessWidget {
  final VideoEditorProvider provider;
  final VideoClip clip;

  const ClipToolbar({super.key, required this.provider, required this.clip});

  void _snack(BuildContext context, String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = clip.mediaType == MediaType.video;
    final index = (provider.currentProject?.videoClips ?? const <VideoClip>[])
            .indexWhere((c) => c.id == clip.id) +
        1;
    final effectsCount = provider.currentProject?.videoEffects
            .where((e) => e.clipId == clip.id)
            .length ??
        0;
    final length = (clip.endTime - clip.startTime).inMilliseconds / 1000;

    final tools = <ToolbarTool>[
      ToolbarTool(Icons.content_cut_rounded, 'Split', () {
        final pos = provider.currentPosition;
        if (pos <= clip.startTime || pos >= clip.endTime) {
          _snack(context, 'Move the playhead inside the clip to split it');
          return;
        }
        provider.cutVideoClip(clip.id);
      }),
      ToolbarTool(Icons.speed_rounded, 'Speed',
          () => ClipToolSheets.speed(context, clip.id),
          badge: (clip.playbackSpeed - 1).abs() > 0.001
              ? '${clip.playbackSpeed}x'
              : null),
      if (isVideo)
        ToolbarTool(
          clip.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          'Volume',
          () => ClipToolSheets.volume(context, clip.id),
          badge: clip.isMuted
              ? 'off'
              : (clip.volume < 0.999 ? '${(clip.volume * 100).round()}' : null),
        ),
      ToolbarTool(Icons.auto_awesome_rounded, 'Effects',
          () => ClipToolSheets.effects(context, clip.id),
          badge: effectsCount > 0 ? '$effectsCount' : null, highlight: true),
      // Tapping an open panel's tool again returns to the timeline.
      ToolbarTool(
          Icons.tune_rounded,
          'Filter',
          provider.showFilters
              ? provider.toggleTimeline
              : provider.toggleFilters,
          active: provider.showFilters),
      ToolbarTool(
          Icons.crop_rounded,
          'Crop',
          provider.showCropEditor
              ? provider.toggleTimeline
              : provider.toggleCropEditor,
          active: provider.showCropEditor),
      ToolbarTool(Icons.rotate_90_degrees_ccw_rounded, 'Rotate',
          () => ClipToolSheets.rotate(context, clip.id),
          badge: clip.rotation.abs() > 0.5 || clip.isMirrored ? '•' : null),
      if (isVideo)
        ToolbarTool(Icons.replay_rounded, 'Reverse',
            () => provider.toggleVideoClipReverse(clip.id),
            active: clip.isReversed),
      if (isVideo)
        ToolbarTool(Icons.filter_vintage_outlined, 'Chroma',
            provider.toggleChromaKeyEditor,
            active: provider.editorPanelMode == EditorPanelMode.chromaKey),
      ToolbarTool(Icons.copy_rounded, 'Duplicate', () {
        provider.duplicateVideoClip(clip.id);
        _snack(context, 'Clip duplicated at the end of the timeline');
      }),
      ToolbarTool(Icons.delete_outline_rounded, 'Delete', () {
        HapticFeedback.mediumImpact();
        provider.deleteVideoClip(clip.id);
        _snack(context, 'Clip deleted',
            action: SnackBarAction(label: 'UNDO', onPressed: provider.undo));
      }, danger: true),
    ];

    return SelectionToolbar(
      title: 'Clip $index',
      subtitle: '${length.toStringAsFixed(1)}s',
      onClose: () => provider.selectVideoClip(null),
      tools: tools,
    );
  }
}

/// Bottom toolbar for a selected timeline item: a leading tile naming the
/// item (tap to close) and a scrolling row of that item's tools. Shared by
/// clips, media overlays, text, stickers and audio.
class SelectionToolbar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final List<ToolbarTool> tools;
  final Color? accent;

  const SelectionToolbar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.tools,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.primary;
    // Dense toolbar: cap text scaling so labels never overflow the tiles.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Container(
          height: 84,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: color, width: 1.2)),
          ),
          child: Row(
            children: [
              // Leading: which item is being edited + close.
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onClose();
                },
                child: Container(
                  width: 74,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    border: Border(right: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: color, size: 26),
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 10.5)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  itemCount: tools.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => ToolbarToolTile(tool: tools[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ToolbarTool {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;
  final bool highlight;
  final String? badge;

  const ToolbarTool(
    this.icon,
    this.label,
    this.onTap, {
    this.active = false,
    this.danger = false,
    this.highlight = false,
    this.badge,
  });
}

class ToolbarToolTile extends StatelessWidget {
  final ToolbarTool tool;
  const ToolbarToolTile({required this.tool});

  @override
  Widget build(BuildContext context) {
    final color = tool.danger
        ? AppColors.error
        : (tool.active ? AppColors.primary : AppColors.textSecondary);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        tool.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        decoration: BoxDecoration(
          color: tool.active
              ? AppColors.primary.withValues(alpha: 0.14)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tool.active
                ? AppColors.primary.withValues(alpha: 0.6)
                : (tool.highlight
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : AppColors.border),
          ),
          gradient: tool.highlight && !tool.active
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.18),
                    AppColors.surfaceLight,
                  ],
                )
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tool.icon, size: 22, color: color),
                  const SizedBox(height: 4),
                  Text(
                    tool.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight:
                          tool.active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (tool.badge != null)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tool.badge!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
