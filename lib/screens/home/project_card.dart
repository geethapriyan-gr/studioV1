import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/video_project.dart';
import 'home_models.dart';
import 'home_prefs.dart';
import 'home_widgets.dart';

/// Project tile for the grid (big cover) or the list (compact row).
class ProjectCard extends StatelessWidget {
  final VideoProject project;
  final HomePrefs prefs;
  final bool grid;
  final int refreshToken;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  const ProjectCard({
    super.key,
    required this.project,
    required this.prefs,
    required this.grid,
    required this.refreshToken,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return grid ? _buildGrid(context) : _buildList(context);
  }

  Widget _cover({double radius = 14}) {
    final exported = prefs.isExported(project.id);
    final res = resolutionBadge(project.outputResolution);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ProjectCover(project: project, refreshToken: refreshToken),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
                stops: [0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 6,
            top: 6,
            child: Row(
              children: [
                HomeBadge(aspectBadge(project.outputResolution)),
                if (res.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  HomeBadge(res),
                ],
              ],
            ),
          ),
          if (exported)
            const Positioned(
              right: 6,
              top: 6,
              child: HomeBadge('Exported',
                  icon: Icons.check_rounded, color: Color(0xFF16A34A)),
            ),
          Positioned(
            left: 6,
            bottom: 6,
            child: HomeBadge(formatLength(projectLength(project)),
                icon: Icons.play_arrow_rounded),
          ),
        ],
      ),
    );
  }

  Widget _meta() {
    final folder = prefs.folderOf(project.id);
    final n = project.videoClips.length;
    return Text(
      [
        relativeTime(project.lastModified),
        '$n clip${n == 1 ? '' : 's'}',
        if (folder != null) folder,
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.68),
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _title({double size = 14.5}) {
    return Text(
      displayName(project),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: size,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      onLongPress: onMenu,
      child: GlassPanel(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _cover()),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _title(),
                      const SizedBox(height: 2),
                      _meta(),
                    ],
                  ),
                ),
                _MoreButton(onTap: onMenu),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      onLongPress: onMenu,
      child: GlassPanel(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(width: 118, height: 84, child: _cover(radius: 12)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(size: 16),
                  const SizedBox(height: 6),
                  _meta(),
                ],
              ),
            ),
            _MoreButton(onTap: onMenu),
          ],
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MoreButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: Icon(Icons.more_vert_rounded,
            color: Colors.white.withValues(alpha: 0.75), size: 20),
      ),
    );
  }
}

/// Actions offered from the long-press menu.
enum ProjectMenuAction { open, duplicate, rename, export, share, move, delete }

/// Long-press menu: a muted, looping preview of the project on top and its
/// actions below.
Future<ProjectMenuAction?> showProjectMenu(
  BuildContext context, {
  required VideoProject project,
  required HomePrefs prefs,
}) {
  homeHaptic(prefs, heavy: true);
  return showHomeSheet<ProjectMenuAction>(
    context,
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ProjectPreviewPlayer(project: project),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayName(project),
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatLength(projectLength(project))} · '
            '${aspectBadge(project.outputResolution)} · '
            '${resolutionBadge(project.outputResolution)} · '
            'edited ${relativeTime(project.lastModified).toLowerCase()}',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          for (final a in _menuItems)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(a.$2,
                  color: a.$1 == ProjectMenuAction.delete
                      ? const Color(0xFFEF4444)
                      : Colors.white70),
              title: Text(
                a.$3,
                style: TextStyle(
                  color: a.$1 == ProjectMenuAction.delete
                      ? const Color(0xFFEF4444)
                      : Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(ctx, a.$1),
            ),
        ],
      ),
    ),
  );
}

const _menuItems = [
  (ProjectMenuAction.open, Icons.edit_rounded, 'Open in editor'),
  (ProjectMenuAction.duplicate, Icons.copy_rounded, 'Duplicate'),
  (ProjectMenuAction.rename, Icons.drive_file_rename_outline_rounded, 'Rename'),
  (ProjectMenuAction.export, Icons.file_upload_outlined, 'Export'),
  (ProjectMenuAction.share, Icons.share_rounded, 'Share'),
  (ProjectMenuAction.move, Icons.drive_file_move_outline, 'Move to folder'),
  (ProjectMenuAction.delete, Icons.delete_outline_rounded, 'Delete'),
];

/// Muted, looping preview of a project's first clips (hold-to-preview).
/// Plays the first video clip's trimmed range; image-only projects show a
/// slow slideshow of their photos.
class ProjectPreviewPlayer extends StatefulWidget {
  final VideoProject project;
  const ProjectPreviewPlayer({super.key, required this.project});

  @override
  State<ProjectPreviewPlayer> createState() => _ProjectPreviewPlayerState();
}

class _ProjectPreviewPlayerState extends State<ProjectPreviewPlayer> {
  VideoPlayerController? _controller;
  VideoClip? _clip;
  Timer? _slideTimer;
  int _slide = 0;

  List<VideoClip> get _sorted => [...widget.project.videoClips]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  @override
  void initState() {
    super.initState();
    final clips = _sorted;
    for (final c in clips) {
      if (c.mediaType == MediaType.video &&
          c.videoFile != null &&
          c.videoFile!.existsSync()) {
        _clip = c;
        break;
      }
    }
    if (_clip != null) {
      _startVideo();
    } else if (clips.length > 1) {
      _slideTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
        if (mounted) setState(() => _slide = (_slide + 1) % clips.length);
      });
    }
  }

  Future<void> _startVideo() async {
    final clip = _clip!;
    final controller = VideoPlayerController.file(
      clip.videoFile!,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.seekTo(clip.trimStart);
      await controller.play();
      controller.addListener(_loopWithinTrim);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _controller = null);
    }
  }

  bool _rewinding = false;

  void _loopWithinTrim() {
    final c = _controller;
    final clip = _clip;
    if (_rewinding || c == null || clip == null || !c.value.isInitialized) {
      return;
    }
    final end = clip.trimEnd > clip.trimStart ? clip.trimEnd : c.value.duration;
    if (c.value.position >= end - const Duration(milliseconds: 80) ||
        (!c.value.isPlaying && c.value.position >= c.value.duration)) {
      _rewinding = true;
      c.seekTo(clip.trimStart).then((_) => c.play()).whenComplete(() {
        _rewinding = false;
      });
    }
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _controller?.removeListener(_loopWithinTrim);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    Widget child;
    if (c != null && c.value.isInitialized) {
      var ar = c.value.aspectRatio;
      if ((c.value.rotationCorrection % 180) != 0) ar = 1 / ar;
      child = Center(
        child: AspectRatio(aspectRatio: ar, child: VideoPlayer(c)),
      );
    } else {
      final clips = _sorted;
      final clip = clips.isEmpty ? null : clips[_slide % clips.length];
      if (clip != null &&
          clip.mediaType == MediaType.image &&
          clip.imageFile != null) {
        child = AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: Image.file(
            File(clip.imageFile!.path),
            key: ValueKey(clip.id),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
        );
      } else {
        child = ProjectCover(project: widget.project, fit: BoxFit.contain);
      }
    }
    return ColoredBox(color: Colors.black, child: child);
  }
}
