import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../providers/video_editor_provider.dart';
import '../../services/video_thumbnail_service.dart';
import 'home_actions.dart';
import 'home_prefs.dart';
import 'home_widgets.dart';
import 'templates_tab.dart' show HomeTabTitle;

/// Bundled media library: stock photos, SDG posters, stock videos and
/// stickers. Tap any item to preview it.
class LibraryTab extends StatefulWidget {
  final VideoEditorProvider provider;
  final HomePrefs prefs;

  const LibraryTab({super.key, required this.provider, required this.prefs});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  List<String> _images = const [];
  List<String> _videos = const [];
  List<String> _stickers = const [];
  String _section = 'photos'; // photos | videos | stickers
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  Future<void> _loadManifest() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets();
      List<String> under(String prefix) =>
          assets.where((a) => a.startsWith(prefix)).toList()..sort();
      _images = under('assets/image-library/');
      _videos = under('assets/video-library/');
      _stickers = under('assets/stickers/');
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  List<String> get _items => switch (_section) {
        'videos' => _videos,
        'stickers' => _stickers,
        _ => _images,
      };

  /// Opens the media enlarged in a popup.
  void _preview(String asset) {
    homeHaptic(widget.prefs);
    final isVideo = _section == 'videos';
    final isSticker = _section == 'stickers';
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close preview',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (context, animation, _, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, _, __) => _MediaPreview(
        asset: asset,
        isVideo: isVideo,
        isSticker: isSticker,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final items = _items;
    final width = MediaQuery.of(context).size.width;
    final columns =
        _section == 'stickers' ? (width > 600 ? 6 : 4) : (width > 600 ? 4 : 3);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, top + 18, 20, 12),
            child: const HomeTabTitle(
              'Library',
              'Free photos, videos and stickers. Tap any item to preview it.',
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'photos',
                    label: Text('Photos (${_images.length})'),
                    icon: const Icon(Icons.image_outlined)),
                ButtonSegment(
                    value: 'videos',
                    label: Text('Videos (${_videos.length})'),
                    icon: const Icon(Icons.movie_outlined)),
                const ButtonSegment(
                    value: 'stickers',
                    label: Text('Stickers'),
                    icon: Icon(Icons.emoji_emotions_outlined)),
              ],
              selected: {_section},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _section = s.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
                selectedBackgroundColor: kHomeAccent,
                selectedForegroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
        if (!_loaded)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator(color: kHomeAccent)),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 140),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: _section == 'stickers' ? 1 : 0.8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final asset = items[i];
                  return _AssetTile(
                    asset: asset,
                    isVideo: _section == 'videos',
                    isSticker: _section == 'stickers',
                    onTap: () => _preview(asset),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _AssetTile extends StatelessWidget {
  final String asset;
  final bool isVideo;
  final bool isSticker;

  /// Opens the preview popup.
  final VoidCallback onTap;

  const _AssetTile({
    required this.asset,
    required this.isVideo,
    required this.isSticker,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = asset.split('/').last.split('.').first;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: isSticker
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.4),
              child: isVideo
                  ? _AssetVideoThumb(asset: asset)
                  : Padding(
                      padding: EdgeInsets.all(isSticker ? 10 : 0),
                      child: Image.asset(
                        asset,
                        fit: isSticker ? BoxFit.contain : BoxFit.cover,
                        cacheWidth: 300,
                      ),
                    ),
            ),
            if (isVideo) ...[
              const Center(
                child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white70, size: 30),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Text(
                  name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 6)]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssetVideoThumb extends StatefulWidget {
  final String asset;
  const _AssetVideoThumb({required this.asset});

  @override
  State<_AssetVideoThumb> createState() => _AssetVideoThumbState();
}

class _AssetVideoThumbState extends State<_AssetVideoThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final media = await HomeActions.assetsToMedia([widget.asset]);
    if (media.isEmpty) return;
    final bytes = await VideoThumbnailService().getThumbnail(
      videoPath: media.first.file.path,
      timeMs: 1000,
      maxHeight: 300,
      quality: 70,
    );
    if (mounted && bytes != null) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return _bytes == null
        ? const SizedBox.expand()
        : Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true);
  }
}

/// Enlarged preview of a library item with a close button at the top.
class _MediaPreview extends StatefulWidget {
  final String asset;
  final bool isVideo;
  final bool isSticker;

  const _MediaPreview({
    required this.asset,
    required this.isVideo,
    required this.isSticker,
  });

  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      final c = VideoPlayerController.asset(widget.asset);
      _video = c;
      c.initialize().then((_) {
        if (!mounted) return;
        c.setLooping(true);
        c.play();
        setState(() {});
      });
      c.addListener(_onVideoTick);
    }
  }

  void _onVideoTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    super.dispose();
  }

  Widget _buildMedia() {
    final video = _video;
    if (widget.isVideo) {
      if (video == null || !video.value.isInitialized) {
        return const CircularProgressIndicator(color: kHomeAccent);
      }
      return GestureDetector(
        onTap: () => video.value.isPlaying ? video.pause() : video.play(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: video.value.aspectRatio,
                child: VideoPlayer(video),
              ),
            ),
            AnimatedOpacity(
              opacity: video.value.isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white70, size: 72),
            ),
          ],
        ),
      );
    }
    return InteractiveViewer(
      maxScale: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.isSticker ? 0 : 16),
        child: Image.asset(
          widget.asset,
          fit: BoxFit.contain,
          width: widget.isSticker ? 260 : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.asset.split('/').last.split('.').first.trim();
    final video = _video;
    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            // Top bar with the close button.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  // White icon on a dark circle with a white ring: readable
                  // over any photo or the dimmed background.
                  Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: const CircleBorder(
                        side: BorderSide(color: Colors.white70, width: 1.5)),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      tooltip: 'Close',
                      iconSize: 26,
                      onPressed: () => Navigator.of(context).pop(),
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(child: _buildMedia()),
              ),
            ),
            if (widget.isVideo && video != null && video.value.isInitialized)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: VideoProgressIndicator(
                  video,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: kHomeAccent,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white10,
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
