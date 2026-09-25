import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';

import '../providers/video_editor_provider.dart';
import '../services/permissions_service.dart';
import '../services/video_thumbnail_service.dart';
import '../widgets/timeline_widget.dart';
import '../widgets/text_overlay_editor.dart';
import '../widgets/audio_overlay_editor.dart';
import '../widgets/filter_editor.dart';
import '../widgets/crop_editor.dart';
import '../widgets/trim_editor.dart';
import '../widgets/chroma_key_editor.dart';
import '../widgets/sticker_panel.dart';
import '../widgets/sticker_layer.dart';

import '../widgets/draggable_media_overlay_widget.dart';
import '../widgets/transformable_text_overlay.dart';
import '../models/video_project.dart';
import '../models/editor_panel_mode.dart';
import '../models/chroma_key_settings.dart';
import '../models/transition.dart';
import '../transitions/transition_factory.dart';
import '../main.dart' show AppColors;
import '../splash_screen.dart';

class _RectClipper extends CustomClipper<Path> {
  final Rect rect;
  _RectClipper(this.rect);

  @override
  Path getClip(Size size) {
    return Path()..addRect(rect);
  }

  @override
  bool shouldReclip(covariant _RectClipper oldClipper) {
    return oldClipper.rect != rect;
  }
}

class _DraggableTextWidget extends StatefulWidget {
  final TextOverlay overlay;
  final BoxConstraints constraints;
  final VoidCallback onDragStart;
  final Function(Offset) onDragEnd;
  final Function(double fontSize)? onFontSizeChanged;
  final VoidCallback onSelected;
  final VoidCallback onDelete;
  final bool isSelected;

  const _DraggableTextWidget({
    Key? key,
    required this.overlay,
    required this.constraints,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onSelected,
    required this.onDelete,
    this.isSelected = false,
    this.onFontSizeChanged,
  }) : super(key: key);

  @override
  State<_DraggableTextWidget> createState() => _DraggableTextWidgetState();
}

class _DraggableTextWidgetState extends State<_DraggableTextWidget> {
  Offset? _localPosition;
  // Pinch-to-zoom state
  double _pinchScale = 1.0;
  double _baseScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final position = _localPosition ?? widget.overlay.position;
    final effectiveFontSize = widget.overlay.fontSize * _pinchScale;

    return Positioned(
      left: position.dx * widget.constraints.maxWidth,
      top: position.dy * widget.constraints.maxHeight,
      child: GestureDetector(
        onTap: widget.onSelected,
        behavior: HitTestBehavior.opaque,
        // Use scale gesture for both drag and pinch-to-zoom
        onScaleStart: (details) {
          widget.onDragStart();
          _localPosition = widget.overlay.position;
          _baseScale = _pinchScale;
        },
        onScaleUpdate: (details) {
          setState(() {
            // Unconditionally use scale to handle pinch.
            // Drag registers as 1.0 natively.
            if (details.scale != 1.0) {
              _pinchScale = (_baseScale * details.scale).clamp(0.2, 5.0);
            }
            // Handle drag via focal point delta
            final currentX = _localPosition!.dx * widget.constraints.maxWidth;
            final currentY = _localPosition!.dy * widget.constraints.maxHeight;

            final newX = currentX + details.focalPointDelta.dx;
            final newY = currentY + details.focalPointDelta.dy;

            _localPosition = Offset(
              newX / widget.constraints.maxWidth,
              newY / widget.constraints.maxHeight,
            );
          });
        },
        onScaleEnd: (details) {
          widget.onDragEnd(_localPosition!);
          // Commit the pinch-scaled fontSize
          if (_pinchScale != 1.0 && widget.onFontSizeChanged != null) {
            final newFontSize =
                (widget.overlay.fontSize * _pinchScale).clamp(4.0, 500.0);
            widget.onFontSizeChanged!(newFontSize);
            // Reset pinch scale since fontSize is now committed
            _pinchScale = 1.0;
            _baseScale = 1.0;
          }
          _localPosition = null;
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: widget.isSelected
                ? Border.all(color: AppColors.primary, width: 3)
                : Border.all(color: Colors.transparent, width: 3),
          ),
          padding: const EdgeInsets.all(4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                widget.overlay.text,
                textAlign: widget.overlay.flutterTextAlign,
                style: GoogleFonts.getFont(
                  widget.overlay.fontFamily,
                  fontSize: effectiveFontSize,
                  color: widget.overlay.color,
                  fontWeight: widget.overlay.fontWeight,
                  fontStyle: widget.overlay.flutterFontStyle,
                  shadows: const [
                    Shadow(
                      offset: Offset(1, 1),
                      color: Colors.black54,
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
              if (widget.isSelected)
                Positioned(
                  right: -14,
                  top: -14,
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.close,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayClipper extends CustomClipper<Path> {
  final Rect holeRect;
  _OverlayClipper(this.holeRect);

  @override
  Path getClip(Size size) {
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(holeRect)
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(covariant _OverlayClipper oldClipper) =>
      oldClipper.holeRect != holeRect;
}

class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({super.key});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen>
    with WidgetsBindingObserver {
  static const String _backgroundAsset = SplashScreen.backgroundAsset;

  final PermissionsService _permissionsService = PermissionsService();
  bool _permissionsGranted = false;
  bool _isCheckingPermissions = true;
  // Fraction of total editor height for the bottom panel (timeline + toolbar).
  double _bottomPanelFraction = 0.60;
  static const double _dividerHeight = 10.0;
  final Map<String, _TransitionFrameCacheEntry> _transitionFrameCache = {};

  String _normalizeMp4Path(String path) {
    if (path.toLowerCase().endsWith('.mp4')) return path;
    final re = RegExp(r"\.mp4\((\d+)\)$", caseSensitive: false);
    final m = re.firstMatch(path);
    if (m != null) {
      final n = m.group(1) ?? '2';
      return path.replaceFirst(re, ' ($n).mp4');
    }
    return '$path.mp4';
  }

  Widget _buildProjectThumbnail(VideoProject project) {
    if (project.videoClips.isEmpty) {
      return const Center(
        child: Icon(Icons.video_library_outlined,
            size: 24, color: AppColors.textTertiary),
      );
    }
    final first = project.videoClips.first;
    if (first.mediaType == MediaType.image && first.imageFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          first.imageFile!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _thumbFallbackIcon(),
        ),
      );
    }
    if (first.mediaType == MediaType.video && first.videoFile != null) {
      final cached =
          VideoThumbnailService().getCached(first.videoFile!.path, 0);
      if (cached != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            cached,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        );
      }

      return FutureBuilder<Uint8List?>(
        future:
            VideoThumbnailService().extractFirstFrame(first.videoFile!.path),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.primary,
                ),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return _thumbFallbackIcon();
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          );
        },
      );
    }
    return _thumbFallbackIcon();
  }

  Widget _thumbFallbackIcon() {
    return const Center(
      child: Icon(Icons.play_circle_outline,
          size: 24, color: AppColors.textTertiary),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionsSilently();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    if (state == AppLifecycleState.resumed) {
      _checkPermissionsSilently();
      // Restart video if the OS paused it while app was in background
      // (e.g. file picker, notification shade, home button).
      provider.handleAppResume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Proactively pause media so Android doesn't trigger audio-focus loss.
      provider.handleAppPause();
    }
  }

  Future<void> _checkPermissionsSilently() async {
    final hasPermissions =
        await _permissionsService.hasAllRequiredPermissions();
    if (mounted) {
      setState(() {
        _permissionsGranted = hasPermissions;
        _isCheckingPermissions = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    await _permissionsService.requestBasicPermissions();
    final hasAccessNow = await _permissionsService.hasAllRequiredPermissions();
    if (mounted) {
      setState(() {
        _permissionsGranted = hasAccessNow;
      });
      if (!hasAccessNow) {
        _showPermissionsDeniedDialog();
      }
    }
  }

  void _showPermissionsDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Permissions Denied',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Storage permission is required to edit videos. Please enable it in Settings.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _permissionsService.openAppSettingsPage();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermissions) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: _buildScreenBackground(
          const Center(
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2),
          ),
        ),
      );
    }

    if (!_permissionsGranted) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: _buildScreenBackground(
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.folder_off,
                        size: 48, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Storage Access Required',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'To import and edit videos, Studio V needs access to your device storage.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _requestPermissions,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Grant Access'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final hasProject = context.select<VideoEditorProvider, bool>(
      (provider) => provider.hasProject,
    );
    final isReversing = context.select<VideoEditorProvider, bool>(
      (provider) => provider.isReversing,
    );
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          appBar: isLandscape || !hasProject ? null : _buildAppBar(),
          body: _buildScreenBackground(
            Consumer<VideoEditorProvider>(
              builder: (context, provider, child) {
                if (!provider.hasProject) {
                  return _buildWelcomeView();
                }
                return _buildEditorView(provider, isLandscape);
              },
            ),
          ),
        ),
        if (isReversing)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // Blocks interactions
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: Colors.black.withOpacity(0.65),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Reversing Video...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Please wait, applying effect',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildScreenBackground(Widget child) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _backgroundAsset,
          fit: BoxFit.cover,
        ),
        Container(
          color: Colors.black.withOpacity(0.15),
        ),
        child,
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leadingWidth: 140,
      leading: Consumer<VideoEditorProvider>(
        builder: (context, provider, child) {
          if (!provider.hasProject) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCompactIconButton(
                icon: Icons.home_outlined,
                onPressed: () async {
                  await provider.closeProject();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Returned to Home')),
                    );
                  }
                },
              ),
              _buildCompactIconButton(
                icon: Icons.equalizer_outlined,
                onPressed: () => TimelineWidget.showMixerDialog(context, provider),
              ),
            ],
          );
        },
      ),
      title: const Text('Studio V'),
      actions: [
        Consumer<VideoEditorProvider>(
          builder: (context, provider, child) {
            if (!provider.hasProject) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAutoSaveIndicator(provider),
                _buildCompactIconButton(
                  icon: Icons.save_outlined,
                  onPressed: _exportVideo,
                ),
                const SizedBox(width: 4),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAutoSaveIndicator(VideoEditorProvider provider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: provider.isAutoSaving
            ? AppColors.primary.withOpacity(0.2)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: provider.isAutoSaving
              ? AppColors.primary.withOpacity(0.5)
              : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (provider.isAutoSaving)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.primary,
              ),
            )
          else if (provider.lastAutoSaved != null)
            const Icon(
              Icons.cloud_done_outlined,
              size: 14,
              color: AppColors.success,
            )
          else
            const Icon(
              Icons.cloud_off_outlined,
              size: 14,
              color: AppColors.textTertiary,
            ),
          const SizedBox(width: 4),
          Text(
            provider.isAutoSaving
                ? 'Saving...'
                : provider.lastAutoSaved != null
                    ? _formatAutoSaveTime(provider.lastAutoSaved!)
                    : 'Not saved',
            style: TextStyle(
              fontSize: 9,
              color: provider.isAutoSaving
                  ? AppColors.primary
                  : provider.lastAutoSaved != null
                      ? AppColors.textSecondary
                      : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAutoSaveTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }

  Widget _buildCompactIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  void _showAspectRatioDialog(VideoEditorProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text('Select Aspect Ratio',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAspectRatioOption(
                icon: Icons.settings_backup_restore_outlined,
                title: 'Original Size',
                onTap: () {
                  provider.setOriginalResolution();
                  Navigator.pop(context);
                },
              ),
              const Divider(color: AppColors.border, height: 1),
              _buildAspectRatioOption(
                icon: Icons.crop_portrait,
                title: 'Portrait (9:16)',
                onTap: () {
                  provider.setAspectRatio(9 / 16);
                  Navigator.pop(context);
                },
              ),
              _buildAspectRatioOption(
                icon: Icons.crop_landscape,
                title: 'Landscape (16:9)',
                onTap: () {
                  provider.setAspectRatio(16 / 9);
                  Navigator.pop(context);
                },
              ),
              _buildAspectRatioOption(
                icon: Icons.crop_square,
                title: 'Square (1:1)',
                onTap: () {
                  provider.setAspectRatio(1.0);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAspectRatioOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 20),
      title: Text(title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      minLeadingWidth: 24,
    );
  }

  void _openPreviewScreen(VideoEditorProvider provider) {
    if (provider.isPlaying) {
      provider.togglePlayback();
    }

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              Center(
                child: Consumer<VideoEditorProvider>(
                  builder: (ctx, p, _) => FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: _getPreviewWidth(p),
                      height: _getPreviewHeight(p),
                      child: _buildFilteredMedia(p, isPreviewMode: true),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                left: 20,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        color: AppColors.textPrimary, size: 20),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: Consumer<VideoEditorProvider>(
                    builder: (ctx, p, _) {
                      if (p.isPlaying) {
                        return GestureDetector(
                          onTap: p.togglePlayback,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 100,
                            height: 100,
                            color: Colors.transparent,
                          ),
                        );
                      } else {
                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface.withOpacity(0.8),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            iconSize: 48,
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              color: AppColors.textPrimary,
                            ),
                            onPressed: p.togglePlayback,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .then((_) {
      if (provider.isPlaying) provider.togglePlayback();
    });
  }

  Widget _buildWelcomeView() {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final recentProjects = provider.getSavedProjects();
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.05),
                      Colors.black.withOpacity(0.02),
                      Colors.black.withOpacity(0.10),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeHeader(),
                    const SizedBox(height: 34),
                    Text(
                      'Recent Projects',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: recentProjects.isNotEmpty
                          ? ListView.separated(
                              padding: const EdgeInsets.only(bottom: 132),
                              itemCount: recentProjects.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 18),
                              itemBuilder: (context, index) {
                                final project = recentProjects[index];
                                return _buildProjectCard(project, provider);
                              },
                            )
                          : _buildEmptyProjectsState(),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 28,
              bottom: 28,
              child: _buildCreateProjectButton(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWelcomeHeader() {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/studiov_logo.png',
            width: 54,
            height: 54,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'Studio V',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.40),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyProjectsState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _buildGlassPanel(
          borderRadius: BorderRadius.circular(30),
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: const Icon(
                  Icons.video_collection_outlined,
                  color: Colors.white70,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No projects yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Create a new project to start editing, or import media directly without changing your current workflow.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: _importMedia,
                icon: const Icon(Icons.video_file_outlined, size: 18),
                label: const Text('Import Media'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.24)),
                  backgroundColor: Colors.white.withOpacity(0.04),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateProjectButton() {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCBAAFF).withOpacity(0.45),
            blurRadius: 28,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        width: 72,
        height: 72,
        child: ElevatedButton(
          onPressed: _createNewProjectFlow,
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
            backgroundColor: const Color(0xFFCBAAFF),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Icon(Icons.add, size: 36, weight: 600),
        ),
      ),
    );
  }

  Widget _buildProjectCard(VideoProject project, VideoEditorProvider provider) {
    return _buildGlassPanel(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: () async {
          await provider.loadProject(project.id);
        },
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            _buildProjectThumbnailFrame(project),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    project.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildProjectMeta(
                        icon: Icons.calendar_today_outlined,
                        label: _formatDate(project.lastModified),
                        color: Colors.white.withOpacity(0.70),
                      ),
                      const SizedBox(width: 14),
                      _buildProjectMeta(
                        icon: Icons.movie_creation_outlined,
                        label: '${project.videoClips.length} clips',
                        color: Colors.white.withOpacity(0.70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildProjectActionButton(
                  icon: Icons.edit_outlined,
                  onPressed: () async {
                    await provider.loadProject(project.id);
                  },
                ),
                const SizedBox(height: 8),
                _buildProjectActionButton(
                  icon: Icons.delete_outline_rounded,
                  onPressed: () => _showDeleteProjectDialog(project, provider),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectThumbnailFrame(VideoProject project) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 90,
        height: 90,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
              ),
              child: _buildProjectThumbnail(project),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatDuration(project.totalDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectMeta({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildProjectActionButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white.withOpacity(0.70), size: 20),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassPanel({
    required Widget child,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(18);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: child,
    );
  }

  Widget _buildEditorView(VideoEditorProvider provider, bool isLandscape) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        const minFraction = 0.12;
        const maxFraction = 0.65;
        const dividerH = _dividerHeight;
        final bottomFraction =
            _bottomPanelFraction.clamp(minFraction, maxFraction);
        final bottomHeight =
            (totalHeight * bottomFraction).clamp(0.0, totalHeight - dividerH);
        final previewHeight =
            (totalHeight - bottomHeight - dividerH).clamp(0.0, totalHeight);

        return Column(
          children: [
            // Video Preview Area (fixed height to allow resizing)
            SizedBox(
              height: previewHeight,
              width: double.infinity,
              child: Container(
                color: AppColors.background,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (provider.isLoading)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                                color: AppColors.primary, strokeWidth: 2.5),
                            if (provider.loadingMessage != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                provider.loadingMessage!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    else if (provider.hasProject)
                      Center(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: _getPreviewWidth(provider),
                            height: _getPreviewHeight(provider),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => provider.clearSelection(),
                              child: Stack(
                                children: [
                                  _buildFilteredMedia(provider),
                                  if (provider.isInGap)
                                    Container(color: AppColors.background),
                                  // Media Overlays (Videos/Images)
                                  LayoutBuilder(
                                    builder: (context, overlayConstraints) {
                                      return Stack(
                                        children: [
                                          ...provider
                                                  .currentProject?.overlayClips
                                                  .where((clip) =>
                                                      provider.currentPosition >=
                                                          clip.startTime &&
                                                      provider.currentPosition <
                                                          clip.endTime)
                                                  .map((overlayClip) {
                                                return DraggableMediaOverlay(
                                                  key: ValueKey(overlayClip.id),
                                                  overlayClip: overlayClip,
                                                  parentSize: Size(
                                                    overlayConstraints.maxWidth,
                                                    overlayConstraints
                                                        .maxHeight,
                                                  ),
                                                  previewController: provider
                                                      .previewController,
                                                  onPositionChanged: () {},
                                                  onUpdatePosition: (newPos) {
                                                    provider
                                                        .updateOverlayClipPosition(
                                                      overlayClip.id,
                                                      newPos,
                                                    );
                                                  },
                                                  onUpdateSize: (newSize) {
                                                    provider
                                                        .updateOverlayClipSize(
                                                      overlayClip.id,
                                                      newSize,
                                                    );
                                                  },
                                                  onSelected: () {
                                                    provider.selectOverlayClip(
                                                      overlayClip.id,
                                                    );
                                                  },
                                                  onDelete: () {
                                                    provider.removeOverlayClip(
                                                      overlayClip.id,
                                                    );
                                                  },
                                                  isSelected: provider
                                                          .selectedOverlayClipId ==
                                                      overlayClip.id,
                                                );
                                              }).toList() ??
                                              [],
                                        ],
                                      );
                                    },
                                  ),
                                  // Text Overlays
                                  LayoutBuilder(
                                    builder: (context, textConstraints) {
                                      return Stack(
                                        children: [
                                          ...provider.currentTextOverlays.map(
                                              (overlay) => _DraggableTextWidget(
                                                    key: ValueKey(overlay.id),
                                                    overlay: overlay,
                                                    constraints:
                                                        textConstraints,
                                                    onDragStart: () {
                                                      provider.recordUndo();
                                                    },
                                                    onDragEnd: (newPosition) {
                                                      provider
                                                          .updateTextOverlayPosition(
                                                              overlay.id,
                                                              newPosition);
                                                    },
                                                    onFontSizeChanged:
                                                        (newFontSize) {
                                                      provider
                                                          .updateTextOverlay(
                                                        overlay.id,
                                                        fontSize: newFontSize,
                                                      );
                                                    },
                                                    onSelected: () {
                                                      provider
                                                          .selectTextOverlay(
                                                              overlay.id);
                                                    },
                                                    onDelete: () {
                                                      provider
                                                          .removeTextOverlay(
                                                              overlay.id);
                                                    },
                                                    isSelected: provider
                                                            .selectedTextOverlayId ==
                                                        overlay.id,
                                                  )),
                                        ],
                                      );
                                    },
                                  ),
                                  // Sticker Layer
                                  const StickerLayer(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Draggable Divider
            MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (details) {
                  setState(() {
                    _bottomPanelFraction =
                        (_bottomPanelFraction - details.delta.dy / totalHeight)
                            .clamp(minFraction, maxFraction);
                  });
                },
                child: Container(
                  height: dividerH,
                  color: AppColors.surface,
                  alignment: Alignment.center,
                  child: Container(
                    width: 64,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Panel (resizable)
            SizedBox(
              height: bottomHeight,
              width: double.infinity,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                      top: BorderSide(color: AppColors.border, width: 1)),
                ),
                child: Column(
                  children: [
                    // Playback Controls
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: _buildPlaybackControls(provider),
                      ),
                    ),
                    // Panel Content
                    Expanded(
                      child: (provider.showTimeline ||
                              provider.showFilters ||
                              provider.showTextEditor ||
                              provider.showAudioEditor ||
                              provider.showCropEditor ||
                              provider.showTrimEditor ||
                              provider.showStickerPanel ||
                              provider.editorPanelMode ==
                                  EditorPanelMode.chromaKey)
                          ? _buildBottomPanel(provider)
                          : const SizedBox.shrink(),
                    ),
                    // Tool Bar
                    _buildToolBar(provider),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _getPreviewWidth(VideoEditorProvider provider) {
    // Basic fallback if no project
    final project = provider.currentProject;
    if (project == null) return 1080.0;

    final currentClip = provider.currentVideoClip;

    // If it's an image, or we have no initialized controller, follow project settings
    if (currentClip?.mediaType == MediaType.image ||
        provider.previewController == null ||
        !provider.previewController!.value.isInitialized) {
      final res = project.outputResolution;
      final aspect = res.width / res.height;
      return (1920.0 * aspect).roundToDouble();
    }

    // Compute width based on current video's aspect ratio
    final aspectRatio = provider.previewController!.value.aspectRatio;
    final rotationDeg = provider.previewController!.value.rotationCorrection;

    // If rotated by 90/270, invert the aspect ratio
    var displayAspectRatio = aspectRatio;
    if ((rotationDeg % 180) != 0) {
      displayAspectRatio = 1 / aspectRatio;
    }

    // Use a consistent base height and compute width from display aspect ratio
    return (1920.0 * displayAspectRatio).roundToDouble();
  }

  double _getPreviewHeight(VideoEditorProvider provider) {
    // Always use a consistent base height (matches export orientation logic)
    return 1920.0;
  }

  Widget _buildToolBar(VideoEditorProvider provider) {
    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Container(
        height: 84,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildToolButton(
                icon: provider.showTimeline
                    ? Icons.timeline
                    : Icons.timeline_outlined,
                label: 'Timeline',
                isActive: provider.showTimeline,
                onPressed: provider.toggleTimeline,
              ),
              const SizedBox(width: 6),
              _buildToolButton(
                icon: provider.showFilters ? Icons.tune : Icons.tune_outlined,
                label: 'Filter',
                isActive: provider.showFilters,
                onPressed: provider.toggleFilters,
              ),
              const SizedBox(width: 6),
              _buildToolButton(
                icon: (provider.showTextEditor ||
                        provider.selectedTextOverlayId != null)
                    ? Icons.text_fields
                    : Icons.text_fields_outlined,
                label: 'Text',
                isActive: provider.showTextEditor ||
                    provider.selectedTextOverlayId != null,
                activeColor: AppColors.textTrack,
                onPressed: provider.toggleTextEditor,
              ),
              const SizedBox(width: 6),
              _buildToolButton(
                icon: (provider.showAudioEditor ||
                        provider.selectedAudioOverlayId != null)
                    ? Icons.audiotrack
                    : Icons.audiotrack_outlined,
                label: 'Music',
                isActive: provider.showAudioEditor ||
                    provider.selectedAudioOverlayId != null,
                activeColor: AppColors.audioTrack,
                onPressed: provider.toggleAudioEditor,
              ),
              const SizedBox(width: 6),
              _buildToolButton(
                icon: provider.showStickerPanel
                    ? Icons.emoji_emotions
                    : Icons.emoji_emotions_outlined,
                label: 'Sticker',
                isActive: provider.showStickerPanel,
                onPressed: provider.toggleStickerPanel,
              ),
              const SizedBox(width: 6),
              _buildToolButton(
                icon: provider.showCropEditor ? Icons.crop : Icons.crop_outlined,
                label: 'Crop',
                isActive: provider.showCropEditor,
                onPressed: () {
                  if (provider.selectedVideoClipId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Select a clip first')),
                    );
                    return;
                  }
                  provider.toggleCropEditor();
                },
              ),
              const SizedBox(width: 6),
              _buildToolButton(
                icon: provider.selectedVideoClipId != null &&
                        provider.currentProject!.videoClips.any((c) =>
                            c.id == provider.selectedVideoClipId && c.isReversed)
                    ? Icons.replay
                    : Icons.replay_outlined,
                label: 'Reverse',
                isActive: provider.selectedVideoClipId != null &&
                    provider.currentProject!.videoClips.any((c) =>
                        c.id == provider.selectedVideoClipId && c.isReversed),
                onPressed: provider.selectedVideoClipId != null
                    ? () => provider
                        .toggleVideoClipReverse(provider.selectedVideoClipId!)
                    : null,
              ),
              const SizedBox(width: 6),
              _buildTrimButton(provider),
              const SizedBox(width: 6),
              _buildChromaKeyButton(provider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChromaKeyButton(VideoEditorProvider provider) {
    final isActive = provider.editorPanelMode == EditorPanelMode.chromaKey;
    final iconColor = isActive ? AppColors.primary : AppColors.textSecondary;
    final bgColor = isActive
        ? AppColors.primary.withOpacity(0.12)
        : AppColors.surfaceLight;
    final borderColor =
        isActive ? AppColors.primary.withOpacity(0.5) : AppColors.border;

    return GestureDetector(
      onTap: () {
        print('DEBUG: Chroma key button pressed');
        print('DEBUG: selectedVideoClipId = ${provider.selectedVideoClipId}');
        if (provider.selectedVideoClipId == null) {
          print('DEBUG: No clip selected - showing snackbar');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select a clip first')),
          );
          return;
        }
        print('DEBUG: Calling toggleChromaKeyEditor');
        provider.toggleChromaKeyEditor();
        print(
            'DEBUG: After toggleChromaKeyEditor, editorPanelMode = ${provider.editorPanelMode}');
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive
                      ? Icons.filter_vintage
                      : Icons.filter_vintage_outlined,
                  size: 22,
                  color: iconColor,
                ),
                if (provider.isChromaKeyEnabled)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Chroma',
              style: TextStyle(
                color: iconColor,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrimButton(VideoEditorProvider provider) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (provider.selectedVideoClipId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select a clip first')),
          );
          return;
        }

        final clipId = provider.selectedVideoClipId!;

        switch (value) {
          case 'left':
            // Left Trim: Delete everything before current position, keep from current position onwards
            await provider.applyLeftTrimAtCursor(clipId);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('Left portion deleted - video starts from cursor')),
            );
            break;
          case 'right':
            // Right Trim: Delete everything after current position
            await provider.applyRightTrimAtCursor(clipId);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Right portion deleted')),
            );
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'left',
          child: Row(
            children: [
              Icon(Icons.first_page, color: AppColors.textSecondary, size: 18),
              SizedBox(width: 8),
              Text('Left Trim', style: TextStyle(color: AppColors.textPrimary)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'right',
          child: Row(
            children: [
              Icon(Icons.last_page, color: AppColors.textSecondary, size: 18),
              SizedBox(width: 8),
              Text('Right Trim',
                  style: TextStyle(color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: _buildPremiumToolBox(
        icon: provider.showTrimEditor
            ? Icons.content_cut
            : Icons.content_cut_outlined,
        label: 'Trim',
        isActive: provider.showTrimEditor,
        isEnabled: true,
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    Color? activeColor,
    required VoidCallback? onPressed,
  }) {
    return _buildPremiumToolBox(
      icon: icon,
      label: label,
      isActive: isActive,
      activeColor: activeColor,
      isEnabled: onPressed != null,
      onTap: onPressed,
    );
  }

  Widget _buildPremiumToolBox({
    required IconData icon,
    required String label,
    bool isActive = false,
    bool isEnabled = true,
    Color? activeColor,
    VoidCallback? onTap,
  }) {
    final effectiveColor = activeColor ?? AppColors.primary;
    final iconColor = isActive
        ? effectiveColor
        : isEnabled
            ? AppColors.textSecondary
            : AppColors.textTertiary;
    final bgColor = isActive
        ? effectiveColor.withOpacity(0.12)
        : AppColors.surfaceLight;
    final borderColor = isActive
        ? effectiveColor.withOpacity(0.5)
        : AppColors.border;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: iconColor,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackControls(VideoEditorProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              provider.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
            onPressed: provider.togglePlayback,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          Text(
            '${_formatDuration(provider.currentPosition)} / ${_formatDuration(provider.totalDuration)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(VideoEditorProvider provider) {
    // Check chromaKey FIRST - highest priority (overrides other panels)
    if (provider.editorPanelMode == EditorPanelMode.chromaKey) {
      return const ChromaKeyEditor();
    } else if (provider.showTimeline) {
      return const TimelineWidget();
    } else if (provider.showFilters) {
      return const FilterEditor();
    } else if (provider.showTextEditor) {
      return const TextOverlayEditor();
    } else if (provider.showAudioEditor) {
      return const AudioOverlayEditor();
    } else if (provider.showCropEditor) {
      return const CropEditor();
    } else if (provider.showTrimEditor) {
      return const TrimEditor();
    } else if (provider.showStickerPanel) {
      return const StickerPanel();
    }
    return const SizedBox.shrink();
  }

  bool _isImageExtension(String? ext) {
    if (ext == null) return false;
    final e = ext.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'heic', 'heif', 'webp']
        .contains(e);
  }

  bool _isVideoExtension(String? ext) {
    if (ext == null) return false;
    final e = ext.toLowerCase();
    return ['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'].contains(e);
  }

  Future<void> _importMedia() async {
    try {
      if (Platform.isIOS) {
        await _importFromPhotosIOS();
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4',
          'mov',
          'm4v',
          'avi',
          'mkv',
          'webm',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'bmp',
          'heic',
          'heif',
          'webp'
        ],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final provider =
            Provider.of<VideoEditorProvider>(context, listen: false);
        for (final f in result.files) {
          final path = f.path;
          if (path == null) continue;
          final file = File(path);
          final ext = f.extension;
          if (_isImageExtension(ext)) {
            await provider.loadImageFile(file);
          } else if (_isVideoExtension(ext)) {
            await provider.loadVideoFile(file);
          }
        }
      }
    } catch (e) {
      _showErrorDialog('Failed to import media: $e');
    }
  }

  Future<void> _importFromPhotosIOS() async {
    final hasPhotos = await _permissionsService.hasStoragePermission();
    bool granted = hasPhotos;
    if (!hasPhotos) {
      granted = await _permissionsService.requestStoragePermission();
    }
    if (!granted) {
      _showErrorDialog(
          'Photos permission is required to import from your library.');
      return;
    }

    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4',
          'mov',
          'm4v',
          'avi',
          'mkv',
          'webm',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'bmp',
          'heic',
          'heif',
          'webp'
        ],
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        for (final f in result.files) {
          final path = f.path;
          if (path == null) continue;
          final file = File(path);
          final ext = f.extension;
          if (_isImageExtension(ext)) {
            await provider.loadImageFile(file);
          } else if (_isVideoExtension(ext)) {
            await provider.loadVideoFile(file);
          }
        }
      }
    } catch (e) {
      _showErrorDialog('Import failed: $e');
    }
  }

  Future<void> _exportVideo() async {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    if (!provider.hasProject) {
      _showErrorDialog('No project to export');
      return;
    }
    try {
      await provider.forceAutoSave();
      String? outputPath;
      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getTemporaryDirectory();
        final fileName =
            'edited_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        outputPath = '${dir.path}/$fileName';
      } else {
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Video',
          fileName: 'edited_video.mp4',
          type: FileType.video,
        );
        if (outputPath != null) {
          outputPath = _normalizeMp4Path(outputPath);
        }
      }
      if (outputPath != null) {
        _showExportDialog(provider, outputPath);
      }
    } catch (e) {
      _showErrorDialog('Failed to export video: $e');
    }
  }

  Future<void> _createNewProjectFlow() async {
    final name = await _promptForProjectName(context,
        title: 'New Project', initial: 'Untitled V');
    if (name == null) return;
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    await provider.createNewProject(name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project "$name" created')),
      );
    }
    await _importMedia();
  }

  Future<String?> _promptForProjectName(BuildContext context,
      {required String title, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showGeneralDialog<String>(
      context: context,
      barrierLabel: title,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  // Blurred background overlay
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          color: Colors.black.withOpacity(0.50),
                        ),
                      ),
                    ),
                  ),
                  // Dark bottom sheet - sits above keyboard
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom,
                      ),
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A1A1E),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Handle bar
                                Center(
                                  child: Container(
                                    width: 44,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.20),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                // Title
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                // Label
                                const Text(
                                  'PROJECT NAME',
                                  style: TextStyle(
                                    color: Color(0xFF9B6FD6),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Underlined purple line
                                Container(
                                  height: 2,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF9B6FD6),
                                        Color(0xFFCBAAFF),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Input field with character count
                                Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 4, 0, 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: controller,
                                          autofocus: true,
                                          maxLength: 50,
                                          onChanged: (_) => setState(() {}),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w400,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Untitled V',
                                            hintStyle: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.35),
                                              fontSize: 20,
                                              fontWeight: FontWeight.w400,
                                            ),
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            counterText: '',
                                            contentPadding: EdgeInsets.zero,
                                            filled: false,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Text(
                                          '${controller.text.length}/50',
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.40),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Bottom separator line
                                Container(
                                  height: 1,
                                  color: Colors.white.withOpacity(0.10),
                                ),
                                const SizedBox(height: 28),
                                // Buttons
                                Row(
                                  children: [
                                    // Cancel button
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            Colors.white.withOpacity(0.60),
                                        minimumSize: const Size(80, 52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(26),
                                        ),
                                      ),
                                      child: const Text(
                                        'CANCEL',
                                        style: TextStyle(
                                          letterSpacing: 2.0,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Create button
                                    Expanded(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(30),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFCBAAFF)
                                                  .withOpacity(0.30),
                                              blurRadius: 20,
                                              spreadRadius: 0,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: () {
                                            final value =
                                                controller.text.trim();
                                            if (value.isEmpty) {
                                              Navigator.of(context).pop();
                                            } else {
                                              Navigator.of(context).pop(value);
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFFCBAAFF),
                                            foregroundColor:
                                                const Color(0xFF1A1A1E),
                                            minimumSize:
                                                const Size.fromHeight(52),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),
                                            elevation: 0,
                                            textStyle: const TextStyle(
                                              letterSpacing: 2.0,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          child: const Text('CREATE'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  void _showExportDialog(VideoEditorProvider provider, String outputPath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        int crf = 23;
        final proj = provider.currentProject;
        Size selectedResolution =
            proj?.outputResolution ?? const Size(1920, 1080);

        final allowed = {
          const Size(1920, 1080),
          const Size(1080, 1920),
          const Size(1280, 720),
          const Size(720, 1280),
          const Size(854, 480),
          const Size(480, 854),
        };

        int selectedFps = proj?.outputFrameRate ?? 30;

        Future<void> startExport() async {
          await Provider.of<VideoEditorProvider>(context, listen: false)
              .setOutputSettings(
                  resolution: selectedResolution, frameRate: selectedFps);
          final result = await Provider.of<VideoEditorProvider>(context,
                  listen: false)
              .exportVideo(outputPath: outputPath, crf: crf, preset: 'ultrafast');
          if (result != null && mounted) {
            Navigator.of(dialogContext).pop();
            String finalPath = result;
            if (Platform.isAndroid || Platform.isIOS) {
              try {
                final bytes = await File(result).readAsBytes();
                final pickedPath = await FilePicker.platform.saveFile(
                  dialogTitle: 'Save Video',
                  fileName: 'edited_video.mp4',
                  type: FileType.video,
                  bytes: bytes,
                );
                if (pickedPath != null) {
                  final fixed = _normalizeMp4Path(pickedPath);
                  if (fixed == pickedPath) {
                    finalPath = pickedPath;
                  } else {
                    await File(fixed).writeAsBytes(bytes, flush: true);
                    finalPath = fixed;
                  }
                }
              } catch (_) {}
            }
            _showSuccessDialog('Video exported successfully to: $finalPath');
          }
        }

        return StatefulBuilder(
          builder: (context, setState) {
            return Consumer<VideoEditorProvider>(
              builder: (context, p, child) {
                final exporting = p.isExporting;
                return AlertDialog(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  title: const Text('Export Video',
                      style: TextStyle(color: AppColors.textPrimary)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Output',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Resolution',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value:
                                  '${selectedResolution.width.toInt()}x${selectedResolution.height.toInt()}',
                              isExpanded: true,
                              dropdownColor: AppColors.surface,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: [
                                if (!allowed.contains(selectedResolution))
                                  DropdownMenuItem(
                                    value:
                                        '${selectedResolution.width.toInt()}x${selectedResolution.height.toInt()}',
                                    child: Text(
                                        '${selectedResolution.width.toInt()}x${selectedResolution.height.toInt()} (Custom)'),
                                  ),
                                ...allowed.map((s) => DropdownMenuItem(
                                      value:
                                          '${s.width.toInt()}x${s.height.toInt()}',
                                      child: Text(
                                          '${s.width.toInt()}x${s.height.toInt()}'),
                                    )),
                              ],
                              onChanged: exporting
                                  ? null
                                  : (v) {
                                      if (v == null) return;
                                      final parts = v.split('x');
                                      if (parts.length >= 2) {
                                        final wStr = parts[0].trim();
                                        final hStr =
                                            parts[1].split(' ')[0].trim();
                                        final w = int.tryParse(wStr) ??
                                            selectedResolution.width.toInt();
                                        final h = int.tryParse(hStr) ??
                                            selectedResolution.height.toInt();
                                        setState(() => selectedResolution =
                                            Size(w.toDouble(), h.toDouble()));
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Framerate',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: selectedFps,
                              isExpanded: true,
                              dropdownColor: AppColors.surface,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: const [24, 25, 30, 50, 60]
                                  .map((e) => DropdownMenuItem(
                                      value: e, child: Text('$e fps')))
                                  .toList(),
                              onChanged: exporting
                                  ? null
                                  : (v) => setState(
                                      () => selectedFps = v ?? selectedFps),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (exporting) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: p.exportProgress,
                            backgroundColor: AppColors.border,
                            color: AppColors.primary,
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(p.exportProgress * 100).toInt()}%',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                      if (p.exportError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            p.exportError!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    if (!exporting)
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Close'),
                      ),
                    if (!exporting)
                      ElevatedButton.icon(
                        onPressed: startExport,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Start Export'),
                      ),
                    if (exporting)
                      TextButton.icon(
                        onPressed: () async {
                          final cancelled = await p.cancelExport();
                          if (cancelled && mounted) {
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Export cancelled')),
                            );
                          }
                        },
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Cancel Export'),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title:
            const Text('Error', style: TextStyle(color: AppColors.textPrimary)),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showMergeDialog(VideoEditorProvider provider) {
    final clips = provider.currentProject?.videoClips ?? [];
    final selectedClipId = provider.selectedVideoClipId;
    if (selectedClipId == null || clips.length < 2) {
      _showErrorDialog(
          'Please select a clip and ensure there are at least 2 clips to merge.');
      return;
    }
    final selectedIndex = clips.indexWhere((clip) => clip.id == selectedClipId);
    final adjacentClips = <VideoClip>[];
    if (selectedIndex > 0) {
      adjacentClips.add(clips[selectedIndex - 1]);
    }
    if (selectedIndex < clips.length - 1) {
      adjacentClips.add(clips[selectedIndex + 1]);
    }
    if (adjacentClips.isEmpty) {
      _showErrorDialog('No adjacent clips found to merge with.');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Merge Clips',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select a clip to merge with:',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ...adjacentClips.map((clip) => ListTile(
                  title: Text('Clip ${clips.indexOf(clip) + 1}',
                      style: const TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(
                      '${_formatDuration(clip.startTime)} - ${_formatDuration(clip.endTime)}',
                      style: const TextStyle(color: AppColors.textTertiary)),
                  onTap: () {
                    Navigator.of(context).pop();
                    provider.mergeVideoClips(selectedClipId, clip.id);
                  },
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(VideoEditorProvider provider) {
    final selectedClipId = provider.selectedVideoClipId;
    if (selectedClipId == null) {
      _showErrorDialog('Please select a clip to delete.');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete Clip',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to delete this video clip? This action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              provider.deleteVideoClip(selectedClipId);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Success',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(message,
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  _ResolvedTransitionPreview? _resolveTransitionPreview(
      VideoEditorProvider provider) {
    final project = provider.currentProject;
    if (project == null || project.transitions.isEmpty) return null;

    for (final transition in project.transitions) {
      VideoClip? clip1;
      VideoClip? clip2;
      try {
        clip1 = project.videoClips
            .firstWhere((clip) => clip.id == transition.clipId1);
        clip2 = project.videoClips
            .firstWhere((clip) => clip.id == transition.clipId2);
      } catch (_) {
        continue;
      }

      final isPrewarm = VideoEditorProvider.isTransitionPreviewPrewarmAt(
        provider.currentPosition,
        transition,
        clip1,
        clip2,
      );
      if (!isPrewarm) continue;

      final isActive = VideoEditorProvider.isTransitionPreviewActiveAt(
        provider.currentPosition,
        transition,
        clip2,
      );

      return _ResolvedTransitionPreview(
        transition: transition,
        clip1: clip1,
        clip2: clip2,
        isActive: isActive,
      );
    }

    return null;
  }

  String _transitionPreviewCacheKey(
    Transition transition,
    VideoClip clip1,
    VideoClip clip2,
  ) {
    return '${transition.id}|${clip1.id}|${clip2.id}';
  }

  String? _transitionPlaybackPath(VideoClip clip) {
    if (clip.mediaType != MediaType.video || clip.videoFile == null) {
      return null;
    }
    if (clip.isReversed &&
        clip.reversedFilePath != null &&
        File(clip.reversedFilePath!).existsSync()) {
      return clip.reversedFilePath!;
    }
    return clip.videoFile!.path;
  }

  int _transitionStaticFrameTimeMs(VideoClip clip, {required bool lastFrame}) {
    // Same source window the exporter uses (trimStart..trimEnd).
    final position = lastFrame
        ? (clip.trimEnd > clip.trimStart
            ? clip.trimEnd - const Duration(milliseconds: 1)
            : clip.trimStart)
        : clip.trimStart;
    return position.inMilliseconds < 0 ? 0 : position.inMilliseconds;
  }

  void _prewarmTransitionFrames(_ResolvedTransitionPreview preview) {
    final cacheKey = _transitionPreviewCacheKey(
      preview.transition,
      preview.clip1,
      preview.clip2,
    );
    final entry = _transitionFrameCache.putIfAbsent(
      cacheKey,
      () => _TransitionFrameCacheEntry(),
    );

    _queueTransitionFrameLoad(
      cacheKey: cacheKey,
      entry: entry,
      clip: preview.clip1,
      isClip1: true,
      lastFrame: true,
    );
    _queueTransitionFrameLoad(
      cacheKey: cacheKey,
      entry: entry,
      clip: preview.clip2,
      isClip1: false,
      lastFrame: false,
    );
  }

  void _queueTransitionFrameLoad({
    required String cacheKey,
    required _TransitionFrameCacheEntry entry,
    required VideoClip clip,
    required bool isClip1,
    required bool lastFrame,
  }) {
    final path = _transitionPlaybackPath(clip);
    if (path == null) {
      entry.markResolved(isClip1, null, null);
      return;
    }

    final timeMs = _transitionStaticFrameTimeMs(clip, lastFrame: lastFrame);
    final frameKey = '$path|$timeMs';
    if (entry.hasFrameRequest(isClip1, frameKey)) return;

    entry.markLoading(isClip1, frameKey);
    unawaited(_loadTransitionFrame(
      cacheKey: cacheKey,
      frameKey: frameKey,
      path: path,
      timeMs: timeMs,
      isClip1: isClip1,
    ));
  }

  Future<void> _loadTransitionFrame({
    required String cacheKey,
    required String frameKey,
    required String path,
    required int timeMs,
    required bool isClip1,
  }) async {
    Uint8List? bytes;
    try {
      bytes = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.PNG,
        timeMs: timeMs,
        quality: 75,
      );
    } catch (_) {
      bytes = null;
    }

    if (!mounted) return;
    final entry = _transitionFrameCache[cacheKey];
    if (entry == null || !entry.matchesFrameKey(isClip1, frameKey)) return;
    setState(() {
      entry.markResolved(isClip1, frameKey, bytes);
    });
  }

  Widget _buildFilteredMedia(VideoEditorProvider provider,
      {bool isPreviewMode = false}) {
    // Use per-clip filter if available, otherwise fall back to project-wide filter
    final currentClipForFilter = provider.currentVideoClip;
    final ColorFilter colorFilter;
    final clipFilter = currentClipForFilter != null
        ? provider.clipColorFilters[currentClipForFilter.id]
        : null;
    if (clipFilter != null && clipFilter.hasFilters) {
      colorFilter = clipFilter;
    } else {
      // Same fallback as the exporter: project-wide filter when the clip has
      // no filter of its own.
      colorFilter =
          provider.currentProject?.colorFilter ?? const ColorFilter();
    }
    final selectedClipId = provider.selectedVideoClipId;
    final currentClip = provider.currentVideoClip;
    double rotation = 0.0;
    bool isMirrored = false;

    // Only use selected clip's rotation when that specific clip is currently playing
    // This ensures each clip maintains its own independent rotation
    if (!isPreviewMode && provider.currentProject != null) {
      if (selectedClipId != null && currentClip?.id == selectedClipId) {
        // Selected clip is currently playing - use its rotation for editing
        rotation = currentClip!.rotation;
        isMirrored = currentClip.isMirrored;
      } else if (currentClip != null) {
        // Either no clip selected, or selected clip is not currently playing
        // Use the currently playing clip's own rotation
        rotation = currentClip.rotation;
        isMirrored = currentClip.isMirrored;
      }
    }

    Widget mediaWidget;
    if (currentClip == null) {
      return Container(color: AppColors.background);
    }

    final transitionPreview = _resolveTransitionPreview(provider);
    if (transitionPreview != null) {
      _prewarmTransitionFrames(transitionPreview);
    }

    if (transitionPreview != null && transitionPreview.isActive) {
      final outputRes =
          provider.currentProject?.outputResolution ?? const Size(1920, 1080);
      final transitionAspectRatio = outputRes.height == 0
          ? 16.0 / 9.0
          : outputRes.width / outputRes.height;
      final cacheKey = _transitionPreviewCacheKey(
        transitionPreview.transition,
        transitionPreview.clip1,
        transitionPreview.clip2,
      );
      final frameCache = _transitionFrameCache[cacheKey];

      mediaWidget = Center(
        child: AspectRatio(
          aspectRatio: transitionAspectRatio,
          child: _TransitionPreview(
            provider: provider,
            transition: transitionPreview.transition,
            clip1: transitionPreview.clip1,
            clip2: transitionPreview.clip2,
            clip1FrameBytes: frameCache?.clip1FrameBytes,
            clip2FrameBytes: frameCache?.clip2FrameBytes,
            progress: VideoEditorProvider.transitionPreviewProgress(
              provider.currentPosition,
              transitionPreview.transition,
              transitionPreview.clip2,
            ),
          ),
        ),
      );
    } else if (currentClip.mediaType == MediaType.image &&
        currentClip.imageFile != null) {
      final outputRes =
          provider.currentProject?.outputResolution ?? const Size(1080, 1920);
      final imageAspectRatio = outputRes.width / outputRes.height;

      mediaWidget = Center(
        child: AspectRatio(
          aspectRatio: imageAspectRatio,
          child: Image.file(
            currentClip.imageFile!,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            key: ValueKey(currentClip.id),
          ),
        ),
      );
    } else {
      if (provider.previewController == null ||
          !provider.previewController!.value.isInitialized) {
        return Container(color: AppColors.background);
      }

      double videoAspectRatio = provider.previewController!.value.aspectRatio;
      final rotationDeg = provider.previewController!.value.rotationCorrection;
      if ((rotationDeg % 180) != 0) {
        videoAspectRatio = 1 / videoAspectRatio;
      }

      mediaWidget = Center(
        child: AspectRatio(
          aspectRatio: videoAspectRatio,
          child: VideoPlayer(
            provider.previewController!,
            key: ValueKey(provider.previewController),
          ),
        ),
      );
    }

    if (isMirrored) {
      mediaWidget = Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(math.pi),
        child: mediaWidget,
      );
    }

    if (rotation != 0.0) {
      final rotatedChild = mediaWidget;
      // The exporter rotates the frame and then fits the rotated frame inside
      // the output canvas, so scale the preview the same way.
      mediaWidget = LayoutBuilder(
        builder: (context, constraints) {
          return Transform.rotate(
            angle: rotation * (3.14159 / 180),
            child: Transform.scale(
              scale: _rotationFitScale(
                  rotation, constraints.maxWidth, constraints.maxHeight),
              child: rotatedChild,
            ),
          );
        },
      );
    }

    mediaWidget = ColorFiltered(
      colorFilter: ui.ColorFilter.matrix(_calculateColorMatrix(colorFilter)),
      child: mediaWidget,
    );

    if (colorFilter.warmth != 0.0 || colorFilter.tint != 0.0) {
      mediaWidget = Stack(
        fit: StackFit.expand,
        children: [
          mediaWidget,
          Container(
            color: _getFilterOverlayColor(colorFilter),
          ),
        ],
      );
    }

    // ============ CHROMA KEY PREVIEW SUPPORT ============
    // Apply chroma key effect - show background behind video.
    // Use per-clip settings at the playhead; fall back to the editor draft only
    // when the chroma panel is open on the clip currently being previewed.
    final chromaKeySettings =
        (provider.editorPanelMode == EditorPanelMode.chromaKey &&
                selectedClipId != null &&
                currentClip.id == selectedClipId)
            ? provider.currentChromaKeySettings
            : currentClip.chromaKeySettings;
    if (chromaKeySettings != null && chromaKeySettings.enabled) {
      final backgrounds = provider.currentProject?.chromaKeyBackgrounds ?? [];
      if (backgrounds.isNotEmpty) {
        // Get the active background path
        final backgroundPath = chromaKeySettings.backgroundPath;
        if (backgroundPath != null && backgrounds.contains(backgroundPath)) {
          // Build the background widget
          final isBgVideo = _isVideoExtension(backgroundPath.split('.').last);

          Widget backgroundWidget;
          if (isBgVideo) {
            // For video background in preview, show a static placeholder
            backgroundWidget = Container(
              color: AppColors.background,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.movie_outlined,
                      size: 48,
                      color: AppColors.textTertiary.withOpacity(0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Video Background',
                      style: TextStyle(
                        color: AppColors.textTertiary.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            // For image background, show the actual image
            backgroundWidget = Image.file(
              File(backgroundPath),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.background,
                child: const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 48,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            );
          }

          // Apply chroma key preview: stack background behind media
          mediaWidget = _buildChromaKeyPreview(
            mediaWidget,
            backgroundWidget,
            chromaKeySettings,
          );
        }
      }
    }
    // ============ END CHROMA KEY PREVIEW ============

    VideoClip? clipForCrop;
    if (!isPreviewMode &&
        provider.showCropEditor &&
        provider.selectedVideoClipId != null &&
        provider.currentProject != null) {
      try {
        clipForCrop = provider.currentProject!.videoClips.firstWhere(
          (c) => c.id == provider.selectedVideoClipId,
        );
      } catch (_) {
        clipForCrop = provider.currentVideoClip;
      }
    } else {
      clipForCrop = provider.currentVideoClip;
    }

    final filteredMedia = mediaWidget;
    final cropRect = clipForCrop?.cropRect ?? const Rect.fromLTWH(0, 0, 1, 1);

    if (!isPreviewMode && provider.showCropEditor) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final absRect = Rect.fromLTRB(
            cropRect.left * width,
            cropRect.top * height,
            cropRect.right * width,
            cropRect.bottom * height,
          );
          return Stack(
            children: [
              SizedBox.expand(child: filteredMedia),
              ClipPath(
                clipper: _OverlayClipper(absRect),
                child: Container(
                  color: AppColors.background.withOpacity(0.6),
                ),
              ),
              Positioned.fromRect(
                rect: absRect,
                child: CustomPaint(
                  painter: GridPainter(),
                ),
              ),
              _buildCropHandles(constraints, cropRect, provider),
            ],
          );
        },
      );
    } else {
      if (clipForCrop != null && clipForCrop.cropRect != null) {
        final crop = clipForCrop.cropRect!;
        return LayoutBuilder(
          builder: (context, constraints) {
            final originalRect = Rect.fromLTRB(
              crop.left * constraints.maxWidth,
              crop.top * constraints.maxHeight,
              crop.right * constraints.maxWidth,
              crop.bottom * constraints.maxHeight,
            );
            if (originalRect.width <= 0 || originalRect.height <= 0) {
              return filteredMedia;
            }
            final center =
                Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
            // The exporter crops this region and scales it to fit the output
            // frame, so enlarge it the same way here.
            final fitScale = math.min(
              constraints.maxWidth / originalRect.width,
              constraints.maxHeight / originalRect.height,
            );
            return SizedBox.expand(
              child: ClipRect(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(center.dx, center.dy)
                    ..scale(fitScale, fitScale)
                    ..translate(
                        -originalRect.center.dx, -originalRect.center.dy),
                  child: ClipPath(
                    clipper: _RectClipper(originalRect),
                    child: SizedBox.expand(child: filteredMedia),
                  ),
                ),
              ),
            );
          },
        );
      }
      return filteredMedia;
    }
  }

  /// Scale applied after rotating the preview so the rotated frame fits the
  /// preview box exactly like the exporter fits it into the output canvas
  /// (transpose for 90/270, rotate onto a hypot x hypot canvas otherwise).
  static double _rotationFitScale(double rotation, double w, double h) {
    if (w <= 0 || h <= 0 || !w.isFinite || !h.isFinite) return 1.0;
    final rot = rotation % 360;
    if (rot.abs() < 0.1 || (rot - 180).abs() < 0.1) return 1.0;
    if ((rot - 90).abs() < 0.1 || (rot - 270).abs() < 0.1) {
      return math.min(w / h, h / w);
    }
    return math.min(w, h) / math.sqrt(w * w + h * h);
  }

  List<double> _calculateColorMatrix(ColorFilter filter) {
    // Start with identity matrix
    List<double> mat = [
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];

    // Apply saturation (desaturation matrix)
    final s = filter.saturation;
    const lumR = 0.2126;
    const lumG = 0.7152;
    const lumB = 0.0722;
    final oneMinusS = 1 - s;
    List<double> satMat = [
      (oneMinusS * lumR) + s,
      (oneMinusS * lumG),
      (oneMinusS * lumB),
      0,
      0,
      (oneMinusS * lumR),
      (oneMinusS * lumG) + s,
      (oneMinusS * lumB),
      0,
      0,
      (oneMinusS * lumR),
      (oneMinusS * lumG),
      (oneMinusS * lumB) + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
    mat = _multiplyMatrices(mat, satMat);

    // Apply hue rotation (simplified hue adjustment)
    if (filter.hue != 0.0) {
      final cosH = math.cos(filter.hue * math.pi / 180);
      final sinH = math.sin(filter.hue * math.pi / 180);
      List<double> hueMat = [
        cosH + (1 - cosH) * lumR,
        (1 - cosH) * lumG - sinH * 0.168,
        (1 - cosH) * lumB + sinH,
        0,
        0,
        (1 - cosH) * lumR + sinH * 0.330,
        cosH + (1 - cosH) * lumG,
        (1 - cosH) * lumB - sinH * 0.497,
        0,
        0,
        (1 - cosH) * lumR - sinH,
        (1 - cosH) * lumG + sinH * 0.169,
        cosH + (1 - cosH) * lumB,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ];
      mat = _multiplyMatrices(mat, hueMat);
    }

    // Apply exposure (exponential brightness multiplier)
    final expFactor = math.pow(2, filter.exposure).toDouble();
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        mat[i * 5 + j] *= expFactor;
      }
      mat[i * 5 + 4] *= expFactor;
    }

    // Apply highlights and shadows
    final hGain = 1.0 + (filter.highlights * 0.5);
    final sGain = 1.0 - (filter.shadows * 0.3);
    final c = filter.contrast * hGain;
    final t = 128.0 * (1.0 - c);
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        mat[i * 5 + j] *= c * sGain;
      }
      mat[i * 5 + 4] = mat[i * 5 + 4] * c + t;
    }

    // Apply brightness and shadow lift
    final shadowLift = filter.shadows * 40.0;
    final b = (filter.brightness * 255.0) + shadowLift;
    for (int i = 0; i < 3; i++) {
      mat[i * 5 + 4] += b;
    }

    // Apply warmth (yellow/blue shift) - reduce blue, increase red
    if (filter.warmth != 0.0) {
      final warmthAmount = filter.warmth * 40.0;
      mat[4] += warmthAmount; // Red channel offset
      mat[14] -= warmthAmount * 0.5; // Blue channel offset
    }

    // Apply tint (green/magenta shift)
    if (filter.tint != 0.0) {
      final tintAmount = filter.tint * 40.0;
      mat[9] += tintAmount; // Green channel offset
      mat[4] -= tintAmount * 0.3; // Red channel offset
    }

    // Apply opacity/fade
    if (filter.opacity != 1.0) {
      mat[18] *= filter.opacity;
      mat[14] *= filter.opacity;
      mat[9] *= filter.opacity;
      mat[4] *= filter.opacity;
    }

    // Apply fade (blend to white)
    if (filter.fade != 0.0) {
      final fadeAmount = filter.fade * 50.0;
      mat[4] += fadeAmount;
      mat[9] += fadeAmount;
      mat[14] += fadeAmount;
    }

    // Apply temperature (kelvin-like adjustment - warm/cool)
    if (filter.temperature != 0.0) {
      final tempAmount = filter.temperature * 30.0;
      mat[4] += tempAmount; // Red
      mat[9] += tempAmount * 0.3; // Green
      mat[14] -= tempAmount * 0.5; // Blue
    }

    // Apply sharpness (affects luminance)
    if (filter.sharpness != 0.0) {
      final sharpnessAmount = filter.sharpness * 0.2;
      mat[0] += sharpnessAmount * lumR;
      mat[1] += sharpnessAmount * lumG;
      mat[2] += sharpnessAmount * lumB;
      mat[5] += sharpnessAmount * lumR;
      mat[6] += sharpnessAmount * lumG;
      mat[7] += sharpnessAmount * lumB;
      mat[10] += sharpnessAmount * lumR;
      mat[11] += sharpnessAmount * lumG;
      mat[12] += sharpnessAmount * lumB;
    }

    // Apply luminance
    if (filter.luminance != 0.0) {
      final lumFactor = 1.0 + filter.luminance;
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 5; j++) {
          mat[i * 5 + j] *= lumFactor;
        }
      }
    }

    // Apply filter preset matrices if any
    if (filter.filterPresetMatrices.isNotEmpty) {
      for (final presetMatrix in filter.filterPresetMatrices) {
        if (presetMatrix.length == 20) {
          mat = _multiplyMatrices(mat, presetMatrix);
        }
      }
    }

    // Clamp values to reasonable ranges
    for (int i = 0; i < mat.length; i++) {
      if (i % 5 == 4) {
        mat[i] = mat[i].clamp(-255.0, 255.0).toDouble();
      } else {
        mat[i] = mat[i].clamp(-2.0, 2.0).toDouble();
      }
    }

    return mat;
  }

  /// Multiply two 4x5 color matrices
  List<double> _multiplyMatrices(List<double> mat1, List<double> mat2) {
    List<double> result = List<double>.filled(20, 0.0);

    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 5; j++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += mat1[i * 5 + k] * mat2[k * 5 + j];
        }
        if (j == 4) {
          sum += mat1[i * 5 + 4];
        }
        result[i * 5 + j] = sum;
      }
    }

    return result;
  }

  Widget _buildCropHandles(
      BoxConstraints constraints, Rect rect, VideoEditorProvider provider) {
    void updateCrop(Rect newRect) {
      if (provider.selectedVideoClipId != null) {
        double left = newRect.left.clamp(0.0, 1.0);
        double top = newRect.top.clamp(0.0, 1.0);
        double right = newRect.right.clamp(0.0, 1.0);
        double bottom = newRect.bottom.clamp(0.0, 1.0);
        if (right - left < 0.1) {
          if (left > 0.9) left = 0.9;
          right = left + 0.1;
        }
        if (bottom - top < 0.1) {
          if (top > 0.9) top = 0.9;
          bottom = top + 0.1;
        }
        provider.cropVideoClip(
          provider.selectedVideoClipId!,
          Rect.fromLTRB(left, top, right, bottom),
        );
      }
    }

    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    const hitArea = 40.0;

    final l = rect.left * w;
    final t = rect.top * h;
    final r = rect.right * w;
    final b = rect.bottom * h;

    Widget buildHandle(double dx, double dy, Function(Offset) onDrag,
        {bool isCorner = true}) {
      return Positioned(
        left: dx - hitArea / 2,
        top: dy - hitArea / 2,
        child: GestureDetector(
          onPanUpdate: (details) {
            onDrag(details.delta);
          },
          child: Container(
            width: hitArea,
            height: hitArea,
            color: Colors.transparent,
            child: Center(
              child: Container(
                width: isCorner ? 14 : 24,
                height: isCorner ? 14 : 6,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  shape: isCorner ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: isCorner ? null : BorderRadius.circular(3),
                  border: Border.all(color: AppColors.background, width: 1),
                  boxShadow: const [
                    BoxShadow(
                        color: AppColors.background,
                        blurRadius: 4,
                        spreadRadius: 1)
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        buildHandle(
            l,
            t,
            (delta) => updateCrop(Rect.fromLTRB(rect.left + delta.dx / w,
                rect.top + delta.dy / h, rect.right, rect.bottom))),
        buildHandle(
            r,
            t,
            (delta) => updateCrop(Rect.fromLTRB(
                rect.left,
                rect.top + delta.dy / h,
                rect.right + delta.dx / w,
                rect.bottom))),
        buildHandle(
            l,
            b,
            (delta) => updateCrop(Rect.fromLTRB(rect.left + delta.dx / w,
                rect.top, rect.right, rect.bottom + delta.dy / h))),
        buildHandle(
            r,
            b,
            (delta) => updateCrop(Rect.fromLTRB(rect.left, rect.top,
                rect.right + delta.dx / w, rect.bottom + delta.dy / h))),
        buildHandle(
            (l + r) / 2,
            t,
            (delta) => updateCrop(Rect.fromLTRB(
                rect.left, rect.top + delta.dy / h, rect.right, rect.bottom)),
            isCorner: false),
        buildHandle(
            (l + r) / 2,
            b,
            (delta) => updateCrop(Rect.fromLTRB(
                rect.left, rect.top, rect.right, rect.bottom + delta.dy / h)),
            isCorner: false),
        buildHandle(
            l,
            (t + b) / 2,
            (delta) => updateCrop(Rect.fromLTRB(
                rect.left + delta.dx / w, rect.top, rect.right, rect.bottom)),
            isCorner: false),
        buildHandle(
            r,
            (t + b) / 2,
            (delta) => updateCrop(Rect.fromLTRB(
                rect.left, rect.top, rect.right + delta.dx / w, rect.bottom)),
            isCorner: false),
      ],
    );
  }

  Color _getFilterOverlayColor(ColorFilter filter) {
    double r = 0.5;
    double g = 0.5;
    double b = 0.5;
    if (filter.warmth != 0.0) {
      r += filter.warmth * 0.2;
      b -= filter.warmth * 0.2;
    }
    if (filter.tint != 0.0) {
      g += filter.tint * 0.1;
    }
    r = r.clamp(0.0, 1.0);
    g = g.clamp(0.0, 1.0);
    b = b.clamp(0.0, 1.0);
    double opacity = 0.0;
    if (filter.warmth != 0.0) opacity += filter.warmth.abs() * 0.2;
    if (filter.tint != 0.0) opacity += filter.tint.abs() * 0.2;
    opacity = opacity.clamp(0.0, 0.4);
    return Color.fromRGBO(
      (r * 255).toInt(),
      (g * 255).toInt(),
      (b * 255).toInt(),
      opacity,
    );
  }

  /// Build chroma key preview
  /// Note: For real-time preview, we simply stack the background behind the video.
  /// The actual green removal happens in the export using FFmpeg's chroma key filter
  /// with our new HSV-based settings.
  Widget _buildChromaKeyPreview(
    Widget foreground,
    Widget background,
    ChromaKeySettings settings,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background at bottom
        background,
        // Video on top
        foreground,
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showDeleteProjectDialog(
      VideoProject project, VideoEditorProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete Project',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Are you sure you want to delete "${project.name}"? This action cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await provider.deleteProject(project.id);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textPrimary.withOpacity(0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(2 * size.width / 3, 0),
        Offset(2 * size.width / 3, size.height), paint);
    canvas.drawLine(
        Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, 2 * size.height / 3),
        Offset(size.width, 2 * size.height / 3), paint);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _ResolvedTransitionPreview {
  final Transition transition;
  final VideoClip clip1;
  final VideoClip clip2;
  final bool isActive;

  const _ResolvedTransitionPreview({
    required this.transition,
    required this.clip1,
    required this.clip2,
    required this.isActive,
  });
}

class _TransitionFrameCacheEntry {
  Uint8List? clip1FrameBytes;
  Uint8List? clip2FrameBytes;
  String? clip1FrameKey;
  String? clip2FrameKey;
  bool clip1Loading = false;
  bool clip2Loading = false;
  bool clip1Resolved = false;
  bool clip2Resolved = false;

  bool hasFrameRequest(bool isClip1, String frameKey) {
    if (isClip1) {
      return clip1FrameKey == frameKey && (clip1Loading || clip1Resolved);
    }
    return clip2FrameKey == frameKey && (clip2Loading || clip2Resolved);
  }

  bool matchesFrameKey(bool isClip1, String frameKey) {
    return isClip1 ? clip1FrameKey == frameKey : clip2FrameKey == frameKey;
  }

  void markLoading(bool isClip1, String frameKey) {
    if (isClip1) {
      clip1FrameKey = frameKey;
      clip1FrameBytes = null;
      clip1Loading = true;
      clip1Resolved = false;
    } else {
      clip2FrameKey = frameKey;
      clip2FrameBytes = null;
      clip2Loading = true;
      clip2Resolved = false;
    }
  }

  void markResolved(bool isClip1, String? frameKey, Uint8List? bytes) {
    if (isClip1) {
      clip1FrameKey = frameKey;
      clip1FrameBytes = bytes;
      clip1Loading = false;
      clip1Resolved = true;
    } else {
      clip2FrameKey = frameKey;
      clip2FrameBytes = bytes;
      clip2Loading = false;
      clip2Resolved = true;
    }
  }
}

class _TransitionPreview extends StatelessWidget {
  final VideoEditorProvider provider;
  final Transition transition;
  final VideoClip clip1;
  final VideoClip clip2;
  final Uint8List? clip1FrameBytes;
  final Uint8List? clip2FrameBytes;
  final double progress;

  const _TransitionPreview({
    required this.provider,
    required this.transition,
    required this.clip1,
    required this.clip2,
    required this.clip1FrameBytes,
    required this.clip2FrameBytes,
    required this.progress,
  });

  String? _playbackPath(VideoClip clip) {
    if (clip.mediaType != MediaType.video || clip.videoFile == null) {
      return null;
    }
    if (clip.isReversed &&
        clip.reversedFilePath != null &&
        File(clip.reversedFilePath!).existsSync()) {
      return clip.reversedFilePath!;
    }
    return clip.videoFile!.path;
  }

  bool _isProviderShowingClip(VideoClip clip) {
    final path = _playbackPath(clip);
    final controller = provider.previewController;
    return path != null &&
        provider.activeFilePath == path &&
        controller != null &&
        controller.value.isInitialized;
  }

  bool _clipReady(VideoClip clip, {required bool isClip1}) {
    if (clip.mediaType == MediaType.image) {
      return clip.imageFile != null;
    }
    if (!isClip1 && _isProviderShowingClip(clip)) return true;
    return isClip1 ? clip1FrameBytes != null : clip2FrameBytes != null;
  }

  Widget _buildClipChild(VideoClip clip, {required bool isClip1}) {
    if (clip.mediaType == MediaType.image && clip.imageFile != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Image.file(
            clip.imageFile!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            key: ValueKey(clip.id),
          ),
        ),
      );
    }

    if (!isClip1 && clip.mediaType == MediaType.video) {
      final controller = provider.previewController;
      if (_isProviderShowingClip(clip) && controller != null) {
        return _buildVideoPlayer(controller);
      }
    }

    final bytes = isClip1 ? clip1FrameBytes : clip2FrameBytes;
    if (clip.mediaType == MediaType.video && bytes != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            gaplessPlayback: true,
          ),
        ),
      );
    }

    return Container(color: AppColors.background);
  }

  Widget _buildVideoPlayer(VideoPlayerController controller) {
    if (controller.value.isInitialized) {
      var aspectRatio = controller.value.aspectRatio;
      final rotationDeg = controller.value.rotationCorrection;
      if ((rotationDeg % 180) != 0) {
        aspectRatio = 1 / aspectRatio;
      }
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: VideoPlayer(controller, key: ValueKey(controller)),
          ),
        ),
      );
    }
    return Container(color: AppColors.background);
  }

  @override
  Widget build(BuildContext context) {
    final childA = RepaintBoundary(
      child: _buildClipChild(clip1, isClip1: true),
    );
    final childB = RepaintBoundary(
      child: _buildClipChild(clip2, isClip1: false),
    );

    final aReady = _clipReady(clip1, isClip1: true);
    final bReady = _clipReady(clip2, isClip1: false);
    if (!aReady || !bReady) {
      return aReady ? childA : Container(color: AppColors.background);
    }

    // Delegate to the modular transition engine.
    // The factory applies easeInOut by default for smooth 60 FPS playback.
    return TransitionFactory.buildWithCurve(
      type: transition.type,
      linearT: progress,
      childA: childA,
      childB: childB,
      curve: Curves.easeInOut,
    );
  }
}

class _CircleRevealClipper extends CustomClipper<Path> {
  final double progress;

  const _CircleRevealClipper({required this.progress});

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.sqrt(size.width * size.width + size.height * size.height);
    final r = maxR * progress.clamp(0.0, 1.0);
    return Path()..addOval(Rect.fromCircle(center: center, radius: r));
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}
