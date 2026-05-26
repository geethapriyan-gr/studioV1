import 'package:flutter/material.dart';
import '../main.dart' show AppColors;
import '../services/media_picker_service.dart';

/// A full-screen gallery of bundled asset images and videos.
///
/// Displays the contents of `assets/image-library/` and `assets/video-library/`
/// in a premium grid layout. Tapping an item pops this screen and returns
/// the selected [PickedMedia].
class AssetMediaLibrary extends StatefulWidget {
  final String? mediaFilter; // 'image', 'video', or null for all

  const AssetMediaLibrary({super.key, this.mediaFilter});

  @override
  State<AssetMediaLibrary> createState() => _AssetMediaLibraryState();
}

class _AssetMediaLibraryState extends State<AssetMediaLibrary>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Bundled asset lists
  static const List<String> _imageAssets = [
    'assets/image-library/0bb9b1683c1110041607bf2909f66957.jpg',
    'assets/image-library/232b7b8ede330a2c09cd0594b59c2044.jpg',
    'assets/image-library/55a69e7b6586595d356252d623157b44.jpg',
    'assets/image-library/811e5a915055c8a4165e3e60f8a494aa.jpg',
    'assets/image-library/86a02fe3ca5507d5d2537844ae40644c.jpg',
    'assets/image-library/9489cb837b3d909d8deb6868e4271c1b.jpg',
    'assets/image-library/94bbf777af6801e47c0af1ce0d4fbaff.jpg',
    'assets/image-library/9a084a30e6cf6f69fa41ae6751a66ee5.jpg',
    'assets/image-library/a4438eb2c0e60d42f2b8772b2d31827b.jpg',
    'assets/image-library/e5f64ef268722f4f7a185614d03a2c19.jpg',
    'assets/image-library/e8d50fb1e2516ce5aa7adf8429c70f2e.jpg',
    'assets/image-library/e97cfc921feb5fdf0537c6ca6fccf9c7.jpg',
    'assets/image-library/ee66b022e69848ee61675ed70267c667.jpg',
    'assets/image-library/fd91a535d32ae15048f7fc4e79698c32.jpg',
    'assets/image-library/goal 1.png',
    'assets/image-library/Full SDG poster with.png',
    'assets/image-library/Modern SDG 2 Zero Hu.png',
    'assets/image-library/Modern SDG 3 Good He.png',
    'assets/image-library/Modern SDG 4 Quality.png',
    'assets/image-library/Modern SDG 5 Gender .png',
    'assets/image-library/Modern SDG 6 Afforda.png',
    'assets/image-library/Modern SDG 7 Afforda.png',
    'assets/image-library/Modern SDG 8 Decent .png',
    'assets/image-library/Modern SDG 9 Industr.png',
    'assets/image-library/Modern SDG 10 Reduce.png',
    'assets/image-library/Modern SDG 11 Sustai.png',
    'assets/image-library/Modern SDG 12 Respon.png',
    'assets/image-library/Modern SDG 13 Climat.png',
    'assets/image-library/Modern SDG 14 Life B.png',
    'assets/image-library/Modern SDG 15 Life o.png',
    'assets/image-library/Modern SDG 17 Partne.png',
  ];

  static const List<String> _videoAssets = [
    'assets/video-library/Cleaning.mp4',
    'assets/video-library/Drinking .mp4',
    'assets/video-library/Healthy-Food.mp4',
    'assets/video-library/Playing.mp4',
    'assets/video-library/Studying.mp4',
  ];

  String _activeFilter = 'all'; // 'all', 'images', 'videos'

  List<_AssetItem> get _filteredAssets {
    final List<_AssetItem> all = [];

    if (widget.mediaFilter != 'video') {
      for (final path in _imageAssets) {
        all.add(_AssetItem(path: path, isVideo: false));
      }
    }
    if (widget.mediaFilter != 'image') {
      for (final path in _videoAssets) {
        all.add(_AssetItem(path: path, isVideo: true));
      }
    }

    if (_activeFilter == 'images') {
      return all.where((a) => !a.isVideo).toList();
    } else if (_activeFilter == 'videos') {
      return all.where((a) => a.isVideo).toList();
    }
    return all;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _activeFilter = ['all', 'images', 'videos'][_tabController.index];
      });
    });

    // Set initial filter based on mediaFilter
    if (widget.mediaFilter == 'image') {
      _activeFilter = 'images';
      _tabController.index = 1;
    } else if (widget.mediaFilter == 'video') {
      _activeFilter = 'videos';
      _tabController.index = 2;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = _filteredAssets;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
          color: AppColors.textSecondary,
        ),
        title: const Text(
          'Media Library',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            height: 48,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textTertiary,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.apps_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('All'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Images'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Videos'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: assets.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.perm_media_outlined,
                    size: 48,
                    color: AppColors.textTertiary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No media available',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1.0,
                ),
                itemCount: assets.length,
                itemBuilder: (_, index) {
                  final item = assets[index];
                  return _AssetGridTile(
                    item: item,
                    onTap: () {
                      Navigator.pop(
                        context,
                        PickedMedia(
                          path: item.path,
                          isAsset: true,
                          isVideo: item.isVideo,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}

/// Internal model for an asset item.
class _AssetItem {
  final String path;
  final bool isVideo;

  const _AssetItem({required this.path, required this.isVideo});

  String get fileName {
    final parts = path.split('/');
    return parts.last;
  }
}

/// A single grid tile displaying an asset thumbnail.
class _AssetGridTile extends StatefulWidget {
  final _AssetItem item;
  final VoidCallback onTap;

  const _AssetGridTile({required this.item, required this.onTap});

  @override
  State<_AssetGridTile> createState() => _AssetGridTileState();
}

class _AssetGridTileState extends State<_AssetGridTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_isPressed ? 0.94 : 1.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isPressed
                ? AppColors.primary.withOpacity(0.5)
                : AppColors.border.withOpacity(0.3),
            width: _isPressed ? 2 : 1,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.15),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail
              widget.item.isVideo
                  ? _VideoAssetThumbnail(assetPath: widget.item.path)
                  : Image.asset(
                      widget.item.path,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surfaceLight,
                        child: const Icon(
                          Icons.broken_image_rounded,
                          color: AppColors.textTertiary,
                          size: 28,
                        ),
                      ),
                    ),

              // Gradient overlay at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                  ),
                ),
              ),

              // Video badge
              if (widget.item.isVideo)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          color: AppColors.textPrimary,
                          size: 12,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'VIDEO',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // File name at bottom
              Positioned(
                left: 6,
                right: 6,
                bottom: 4,
                child: Text(
                  _truncateFileName(widget.item.fileName),
                  style: TextStyle(
                    color: AppColors.textPrimary.withOpacity(0.9),
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _truncateFileName(String name) {
    if (name.length <= 20) return name;
    final ext = name.contains('.') ? name.split('.').last : '';
    final base = name.substring(0, name.length - ext.length - 1);
    if (base.length <= 16) return name;
    return '${base.substring(0, 14)}...$ext';
  }
}

/// Displays an icon-based thumbnail for video assets
/// since flutter cannot directly render video frames from assets.
class _VideoAssetThumbnail extends StatelessWidget {
  final String assetPath;

  const _VideoAssetThumbnail({required this.assetPath});

  @override
  Widget build(BuildContext context) {
    // Extract readable name from path
    final fileName = assetPath.split('/').last;
    final name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '').trim();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceLighter,
            AppColors.surface,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_display_rounded,
              color: AppColors.primary.withOpacity(0.7),
              size: 32,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                name,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
