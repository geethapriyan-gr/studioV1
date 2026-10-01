import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../models/video_project.dart';
import '../../services/video_thumbnail_service.dart';
import 'home_models.dart';
import 'home_prefs.dart';
import 'home_storage.dart';
import 'home_widgets.dart';
import 'templates_tab.dart' show HomeTabTitle;

/// Gallery of exported videos: play, share, re-export or delete them.
class ExportsTab extends StatefulWidget {
  final HomePrefs prefs;
  final List<VideoProject> projects;
  final Future<void> Function(String projectId) onExportProject;
  final int refreshToken;

  const ExportsTab({
    super.key,
    required this.prefs,
    required this.projects,
    required this.onExportProject,
    required this.refreshToken,
  });

  @override
  State<ExportsTab> createState() => _ExportsTabState();
}

class _ExportsTabState extends State<ExportsTab> {
  List<ExportedVideo>? _exports;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ExportsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final list = await HomeStorage.exports();
    if (mounted) setState(() => _exports = list);
  }

  VideoProject? _projectFor(ExportedVideo v) {
    final id = widget.prefs.projectOfExport(v.path);
    if (id == null) return null;
    for (final p in widget.projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _delete(ExportedVideo v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete export?'),
        content: const Text(
            'The video file in Studio V is removed. Copies you already saved or shared are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    homeHaptic(widget.prefs, heavy: true);
    await HomeStorage.deleteExports([v]);
    await widget.prefs.forgetExports([v.path]);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final exports = _exports;
    return RefreshIndicator(
      color: kHomeAccent,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, top + 18, 20, 8),
              child: const HomeTabTitle(
                'Exports',
                'Videos you exported from Studio V.',
              ),
            ),
          ),
          if (exports == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child:
                  Center(child: CircularProgressIndicator(color: kHomeAccent)),
            )
          else if (exports.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.movie_filter_outlined,
                          size: 56, color: Colors.white.withValues(alpha: 0.5)),
                      const SizedBox(height: 14),
                      const Text('No exports yet',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        'Open a project and tap Save, or long-press a project and choose Export.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              sliver: SliverList.separated(
                itemCount: exports.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final v = exports[i];
                  final project = _projectFor(v);
                  return StaggeredEntry(
                    index: i,
                    child: _ExportCard(
                      video: v,
                      title: project != null
                          ? displayName(project)
                          : 'Exported video',
                      onPlay: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ExportPlayerPage(video: v),
                        ),
                      ),
                      onShare: () => SharePlus.instance
                          .share(ShareParams(files: [XFile(v.path)])),
                      onReExport: project == null
                          ? null
                          : () => widget.onExportProject(project.id),
                      onDelete: () => _delete(v),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ExportCard extends StatefulWidget {
  final ExportedVideo video;
  final String title;
  final VoidCallback onPlay;
  final VoidCallback onShare;
  final VoidCallback? onReExport;
  final VoidCallback onDelete;

  const _ExportCard({
    required this.video,
    required this.title,
    required this.onPlay,
    required this.onShare,
    required this.onReExport,
    required this.onDelete,
  });

  @override
  State<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends State<_ExportCard> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    VideoThumbnailService()
        .getThumbnail(
            videoPath: widget.video.path,
            timeMs: 500,
            maxHeight: 300,
            quality: 75)
        .then((b) {
      if (mounted && b != null) setState(() => _thumb = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    return GlassPanel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onPlay,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 110,
                height: 80,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.black45,
                      child: _thumb == null
                          ? null
                          : Image.memory(_thumb!, fit: BoxFit.cover),
                    ),
                    const Center(
                      child: Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white, size: 34),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  '${relativeTime(v.created)} · ${formatBytes(v.bytes)}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _SmallAction(Icons.share_rounded, 'Share', widget.onShare),
                    if (widget.onReExport != null)
                      _SmallAction(Icons.refresh_rounded, 'Re-export',
                          widget.onReExport!),
                    _SmallAction(
                        Icons.delete_outline_rounded, 'Delete', widget.onDelete,
                        color: const Color(0xFFEF4444)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  const _SmallAction(this.icon, this.tooltip, this.onTap, {this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: color ?? Colors.white70),
    );
  }
}

/// Full-screen player for an exported video.
class ExportPlayerPage extends StatefulWidget {
  final ExportedVideo video;
  const ExportPlayerPage({super.key, required this.video});

  @override
  State<ExportPlayerPage> createState() => _ExportPlayerPageState();
}

class _ExportPlayerPageState extends State<ExportPlayerPage> {
  late final VideoPlayerController _c =
      VideoPlayerController.file(widget.video.file);

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      _c.setLooping(true);
      _c.play();
      setState(() {});
    });
    _c.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Export'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => SharePlus.instance
                .share(ShareParams(files: [XFile(widget.video.path)])),
          ),
        ],
      ),
      body: v.isInitialized
          ? GestureDetector(
              onTap: () => v.isPlaying ? _c.pause() : _c.play(),
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: VideoPlayer(_c),
                    ),
                  ),
                  if (!v.isPlaying)
                    const Center(
                      child: Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white70, size: 72),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: VideoProgressIndicator(
                      _c,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      colors: const VideoProgressColors(
                        playedColor: kHomeAccent,
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator(color: kHomeAccent)),
    );
  }
}
