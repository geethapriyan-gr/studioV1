import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:async';

import '../providers/video_editor_provider.dart';
import '../services/permissions_service.dart';
import '../widgets/timeline_widget.dart';
import '../widgets/text_overlay_editor.dart';
import '../widgets/audio_overlay_editor.dart';
import '../widgets/filter_editor.dart';
import '../widgets/crop_editor.dart';
import '../widgets/trim_editor.dart';
import '../widgets/chroma_key_editor.dart';
import '../widgets/chroma_composite.dart';
import '../widgets/sticker_panel.dart';
import '../widgets/sticker_layer.dart';

import '../widgets/draggable_media_overlay_widget.dart';
import '../models/video_project.dart';
import '../models/editor_panel_mode.dart';
import '../models/transition.dart';
import '../transitions/transition_factory.dart';
import '../main.dart' show AppColors;
import '../splash_screen.dart';
import 'home/home_shell.dart';
import '../effects/effects_preview.dart';
import '../widgets/clip_toolbar.dart';
import 'export_screen.dart';
import '../widgets/clip_tool_sheets.dart';
import '../utils/text_overlay_painter.dart';
import '../utils/snap_guides.dart';
import '../widgets/item_toolbars.dart';

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
  final VideoEditorProvider provider;
  final BoxConstraints constraints;
  final VoidCallback onDragStart;
  final Function(Offset) onDragEnd;
  final Function(double fontSize)? onFontSizeChanged;
  final VoidCallback onSelected;
  final VoidCallback onDelete;
  final VoidCallback onGestureEnd;
  final bool isSelected;

  const _DraggableTextWidget({
    Key? key,
    required this.overlay,
    required this.provider,
    required this.constraints,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onSelected,
    required this.onDelete,
    required this.onGestureEnd,
    this.isSelected = false,
    this.onFontSizeChanged,
  }) : super(key: key);

  @override
  State<_DraggableTextWidget> createState() => _DraggableTextWidgetState();
}

class _DraggableTextWidgetState extends State<_DraggableTextWidget>
    with SingleTickerProviderStateMixin {
  Offset? _localPosition;
  // Pinch-to-zoom state
  double _pinchScale = 1.0;
  double _baseScale = 1.0;

  // Animations re-evaluate every frame (not just on the 30 Hz timeline
  // tick) while the text is animating during playback.
  late final Ticker _ticker = createTicker((_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    // Repaint once a (bundled or downloaded) font finishes loading.
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
  }

  void _onFontsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _ticker.dispose();
    super.dispose();
  }

  /// Current animation state. While editing (selected) or paused the text is
  /// shown fully so it can be seen and dragged.
  TextAnimState _animState() {
    final o = widget.overlay;
    final p = widget.provider;
    final animated = o.animIn != TextAnimations.none ||
        o.animOut != TextAnimations.none;
    // Moving text re-evaluates every frame while playing, too.
    final moving = o.keyframeData.isNotEmpty && p.isPlaying;
    if (!animated || widget.isSelected || !p.isPlaying) {
      _setTicking(moving);
      return const TextAnimState();
    }
    final t = (p.smoothPosition - o.startTime).inMicroseconds / 1e6;
    final state = TextAnimations.at(o, t);
    _setTicking(moving || !state.isIdle);
    return state;
  }

  void _setTicking(bool on) {
    if (on && !_ticker.isActive) {
      _ticker.start();
    } else if (!on && _ticker.isActive) {
      _ticker.stop();
    }
  }

  /// Top-left and font size at the current time (motion keyframes).
  (Offset, double) _motionState() {
    final o = widget.overlay;
    if (o.keyframeData.isEmpty) return (o.position, o.fontSize);
    final p = widget.provider;
    final now = p.isPlaying ? p.smoothPosition : p.currentPosition;
    return ItemKeyframe.at(
        o.keyframeData, now - o.startTime, o.position, o.fontSize);
  }

  // Size (normalized) and centre of the text when the gesture started, so a
  // pinch grows the text around its centre instead of its corner.
  Size _startSizeNorm = Size.zero;
  Offset _startCenter = Offset.zero;
  Offset _dragDelta = Offset.zero;
  Offset? _snappedPosition;
  double _gestureFont = 0;

  /// Box the preview draws around the text: 3 px border + 4 px padding.
  static const double _inset = 7.0;

  Size _normSize(TextOverlayPainter painter) => Size(
        (painter.size.width + _inset * 2) / widget.constraints.maxWidth,
        (painter.size.height + _inset * 2) / widget.constraints.maxHeight,
      );

  @override
  Widget build(BuildContext context) {
    final (motionPos, motionFont) = _motionState();
    final position = _snappedPosition ?? _localPosition ?? motionPos;
    final effectiveFontSize = motionFont * _pinchScale;
    final anim = _animState();
    final textPainter =
        TextOverlayPainter(widget.overlay, fontSize: effectiveFontSize);
    final opacity =
        (widget.overlay.opacity * anim.opacity).clamp(0.0, 1.0).toDouble();

    Widget content = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: widget.isSelected
            ? Border.all(color: AppColors.primary, width: 3)
            : Border.all(color: Colors.transparent, width: 3),
      ),
      padding: const EdgeInsets.all(4),
      // Drawn by the same painter the exporter uses (box, outline, shadow).
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(
          size: textPainter.size,
          painter: _OverlayTextPainter(textPainter, anim.reveal),
        ),
      ),
    );
    if (widget.overlay.rotation != 0) {
      // Rotates around the text's centre, like the exporter.
      content = Transform.rotate(
          angle: widget.overlay.rotation * math.pi / 180, child: content);
    }
    // The in/out animation moves and scales the (rotated) text upright,
    // as the exporter does with the rendered text image.
    content = Transform.translate(
      offset: Offset(0, anim.dy),
      child: Transform.scale(scale: anim.scale, child: content),
    );

    return Positioned(
      left: position.dx * widget.constraints.maxWidth,
      top: position.dy * widget.constraints.maxHeight,
      child: GestureDetector(
        onTap: widget.onSelected,
        behavior: HitTestBehavior.opaque,
        // Use scale gesture for both drag and pinch-to-zoom
        onScaleStart: (details) {
          widget.onDragStart();
          _localPosition = motionPos;
          _gestureFont = motionFont;
          _baseScale = _pinchScale;
          _startSizeNorm = _normSize(textPainter);
          _startCenter = motionPos +
              Offset(_startSizeNorm.width / 2, _startSizeNorm.height / 2);
          _dragDelta = Offset.zero;
        },
        onScaleUpdate: (details) {
          setState(() {
            if (details.pointerCount >= 2) {
              _pinchScale = (_baseScale * details.scale).clamp(0.2, 5.0);
            }
            _dragDelta += Offset(
              details.focalPointDelta.dx / widget.constraints.maxWidth,
              details.focalPointDelta.dy / widget.constraints.maxHeight,
            );
            final size = Size(_startSizeNorm.width * _pinchScale,
                _startSizeNorm.height * _pinchScale);
            final center = _startCenter + _dragDelta;
            // Keep at least a corner of the text on the canvas.
            final raw = Offset(
              (center.dx - size.width / 2).clamp(-size.width + 0.05, 0.95),
              (center.dy - size.height / 2).clamp(-size.height + 0.05, 0.95),
            );
            _localPosition = raw;
            _snappedPosition = SnapGuides.snapBox(raw, size);
          });
        },
        onScaleEnd: (details) {
          SnapGuides.clear();
          widget.onDragEnd(_snappedPosition ?? _localPosition!);
          // Commit the pinch-scaled fontSize
          if (_pinchScale != 1.0 && widget.onFontSizeChanged != null) {
            final newFontSize = (_gestureFont * _pinchScale)
                .clamp(4.0, TextOverlayPainter.maxFontSize);
            widget.onFontSizeChanged!(newFontSize);
          }
          widget.onGestureEnd();
          setState(() {
            _pinchScale = 1.0;
            _baseScale = 1.0;
            _localPosition = null;
            _snappedPosition = null;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            if (widget.isSelected)
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(10),
                    child: const Icon(Icons.close,
                        size: 28, color: Colors.white),
                  ),
                ),
              ),
          ],
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
  // Decoded transition stills keyed by '<path>|<timeMs>' (null = failed).
  final Map<String, ui.Image?> _transitionFrames = {};
  final Set<String> _transitionFramesLoading = {};
  final List<_TransitionFrameRequest> _transitionFrameQueue = [];
  final Set<String> _precachedTransitionImages = {};
  bool _transitionFrameWorkerRunning = false;
  static const int _transitionFrameMaxSize = 1280;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionsSilently();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _transitionFrameQueue.clear();
    for (final image in _transitionFrames.values) {
      image?.dispose();
    }
    _transitionFrames.clear();
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
          side: BorderSide(color: AppColors.border),
        ),
        title: Text('Permissions Denied',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
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
          Center(
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
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.folder_off,
                        size: 48, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Storage Access Required',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
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
                child: Center(
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
            SizedBox(
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
            Icon(
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
            side: BorderSide(color: AppColors.border),
          ),
          title: Text('Select Aspect Ratio',
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
              Divider(color: AppColors.border, height: 1),
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
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      minLeadingWidth: 24,
    );
  }

  Widget _buildWelcomeView() {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) => HomeShell(
        provider: provider,
        // Opens the project and runs the editor's normal export flow.
        onExportProject: (projectId) async {
          await provider.loadProject(projectId);
          if (mounted && provider.hasProject) await _exportVideo();
        },
      ),
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
                            CircularProgressIndicator(
                                color: AppColors.primary, strokeWidth: 2.5),
                            if (provider.loadingMessage != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                provider.loadingMessage!,
                                style: TextStyle(
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
                      _buildPreviewCanvas(provider, interactive: true),
                    // Tap / double-tap feedback bubble.
                    if (provider.hasProject)
                      Positioned.fill(
                        child: _PreviewPulse(pulse: _pulse),
                      ),
                    if (provider.hasProject && provider.isRenderingTransitions)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _TransitionRenderBadge(
                          progress: provider.transitionRenderProgress,
                          pending: provider.transitionRendersPending,
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
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                      top: BorderSide(color: AppColors.border, width: 1)),
                ),
                child: Column(
                  children: [
                    // Playback Controls
                    Container(
                      height: 50,
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

  /// The preview canvas: media (with effects) plus media overlays, text and
  /// stickers, scaled to fit. [interactive] is false in fullscreen, where
  /// overlays are shown but cannot be dragged or selected.
  Widget _buildPreviewCanvas(VideoEditorProvider provider,
      {required bool interactive}) {
    final canvas = Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _getPreviewWidth(provider),
          height: _getPreviewHeight(provider),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _onPreviewTap(provider, interactive),
            onDoubleTapDown: (d) => _lastDoubleTapDx = d.localPosition.dx,
            onDoubleTap: () => _onPreviewDoubleTap(
                provider, _lastDoubleTapDx < _getPreviewWidth(provider) / 2),
            child: Stack(
              children: [
                _buildFilteredMedia(provider),
                if (provider.isInGap)
                  Container(color: AppColors.background),
                // Media Overlays (Videos/Images)
                IgnorePointer(
                 ignoring: !interactive,
                 child: LayoutBuilder(
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
                                timelinePosition:
                                    provider.currentPosition,
                                isPlaying: provider.isPlaying,
                                masterVolume: provider.videoMasterVolume,
                                onTransformEnd: (pos, size, rotation) {
                                  // Move, resize and rotate: one undo step.
                                  provider.beginUndoGesture(
                                      'overlay-transform:${overlayClip.id}');
                                  provider.updateOverlayClipBox(
                                      overlayClip.id,
                                      position: pos,
                                      size: size);
                                  if (rotation != overlayClip.rotation) {
                                    provider.updateOverlayClipStyle(
                                        overlayClip.id,
                                        rotation: rotation);
                                  }
                                  provider.endUndoGesture();
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
                )),
                // Text Overlays
                IgnorePointer(
                 ignoring: !interactive,
                 child: LayoutBuilder(
                  builder: (context, textConstraints) {
                    return Stack(
                      children: [
                        ...provider.currentTextOverlays.map(
                            (overlay) => _DraggableTextWidget(
                                  key: ValueKey(overlay.id),
                                  overlay: overlay,
                                  provider: provider,
                                  constraints:
                                      textConstraints,
                                  // Move + pinch: one undo step.
                                  onDragStart: () {
                                    provider.beginUndoGesture(
                                        'text-gesture:${overlay.id}');
                                  },
                                  onGestureEnd: provider.endUndoGesture,
                                  // Motion-aware: edits the keyframe at
                                  // the playhead when the text moves.
                                  onDragEnd: (newPosition) =>
                                      provider.updateTextTransform(
                                          overlay.id,
                                          position: newPosition),
                                  onFontSizeChanged: (newFontSize) =>
                                      provider.updateTextTransform(
                                          overlay.id,
                                          fontSize: newFontSize),
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
                )),
                // Sticker Layer
                IgnorePointer(
                  ignoring: !interactive,
                  child: const StickerLayer(),
                ),
                // Snap guides shown while dragging text/stickers/overlays.
                if (interactive)
                  const Positioned.fill(child: SnapGuideOverlay()),
                // Green screen: tap to pick the colour, drag/pinch to place
                // the person over the background.
                if (interactive) ..._buildChromaInteraction(provider),
              ],
            ),
          ),
        ),
      ),
    );
    return canvas;
  }

  // Subject drag/pinch state for the green-screen layer.
  Offset _chromaStartPos = const Offset(0.5, 0.5);
  double _chromaStartScale = 1.0;
  Offset _chromaDrag = Offset.zero;
  bool _chromaPicking = false;

  /// Layers over the preview while the green-screen panel is open on the
  /// clip under the playhead.
  List<Widget> _buildChromaInteraction(VideoEditorProvider provider) {
    if (provider.editorPanelMode != EditorPanelMode.chromaKey) return const [];
    final clip = provider.currentVideoClip;
    if (clip == null || clip.id != provider.selectedVideoClipId) return const [];
    final s = provider.currentChromaKeySettings;
    final picking = provider.chromaPickMode;
    if (!picking && (s == null || !s.enabled)) return const [];
    final size =
        Size(_getPreviewWidth(provider), _getPreviewHeight(provider));

    /// Canvas point → position in the clip's own picture (0..1).
    Offset toPicture(Offset local) {
      var uv = Offset(local.dx / size.width, local.dy / size.height);
      if (s != null && s.enabled) {
        // Undo the subject's move/scale.
        uv = (uv - s.position) / s.scale + const Offset(0.5, 0.5);
      }
      final crop = clip.cropRect;
      if (crop != null) {
        uv = Offset(crop.left + uv.dx * crop.width,
            crop.top + uv.dy * crop.height);
      }
      if (clip.isMirrored) uv = Offset(1 - uv.dx, uv.dy);
      return uv;
    }

    return [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: picking
              ? (d) async {
                  setState(() => _chromaPicking = true);
                  final ok = await provider
                      .pickChromaColorAt(toPicture(d.localPosition));
                  if (!mounted) return;
                  setState(() => _chromaPicking = false);
                  HapticFeedback.lightImpact();
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not read this frame — '
                            'try another moment of the clip.')));
                  }
                }
              : null,
          onScaleStart: picking
              ? null
              : (d) {
                  _chromaStartPos = s!.position;
                  _chromaStartScale = s.scale;
                  _chromaDrag = Offset.zero;
                  provider.beginUndoGesture('chroma-subject');
                },
          onScaleUpdate: picking
              ? null
              : (d) {
                  _chromaDrag += Offset(d.focalPointDelta.dx / size.width,
                      d.focalPointDelta.dy / size.height);
                  var pos = _chromaStartPos + _chromaDrag;
                  // Snap back to the centre lines.
                  if ((pos.dx - 0.5).abs() < 0.015) pos = Offset(0.5, pos.dy);
                  if ((pos.dy - 0.5).abs() < 0.015) pos = Offset(pos.dx, 0.5);
                  provider.updateChromaKeySettings(
                    position: Offset(
                        pos.dx.clamp(-0.5, 1.5), pos.dy.clamp(-0.5, 1.5)),
                    scale: d.pointerCount >= 2
                        ? (_chromaStartScale * d.scale).clamp(0.2, 3.0)
                        : null,
                  );
                },
          onScaleEnd: picking ? null : (_) => provider.endUndoGesture(),
        ),
      ),
      if (picking)
        Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(60),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _chromaPicking
                        ? const SizedBox(
                            width: 56,
                            height: 56,
                            child: CircularProgressIndicator(
                                strokeWidth: 6, color: Colors.white))
                        : const Icon(Icons.colorize_rounded,
                            color: Colors.white, size: 64),
                    const SizedBox(width: 24),
                    const Text('Tap the background colour',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 52,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
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

  /// Bottom toolbar: the selected clip's own tools while a timeline clip is
  /// selected, otherwise the main toolbar. Switching slides between them.
  Widget _buildToolBar(VideoEditorProvider provider) {
    final project = provider.currentProject;
    T? find<T>(Iterable<T>? items, String? id, String Function(T) getId) {
      if (id == null || items == null) return null;
      for (final item in items) {
        if (getId(item) == id) return item;
      }
      return null;
    }

    // Each kind of selected item gets its own toolbar.
    final Widget toolbar;
    final clip = find<VideoClip>(
        project?.videoClips, provider.selectedVideoClipId, (c) => c.id);
    final overlay = find<VideoClip>(
        project?.overlayClips, provider.selectedOverlayClipId, (c) => c.id);
    final text = find<TextOverlay>(
        project?.textOverlays, provider.selectedTextOverlayId, (t) => t.id);
    final sticker = find<StickerModel>(
        project?.stickers, provider.selectedStickerId, (s) => s.id);
    final audio = find<AudioOverlay>(
        project?.audioOverlays, provider.selectedAudioOverlayId, (a) => a.id);
    if (clip != null) {
      toolbar = ClipToolbar(
          key: const ValueKey('clip-toolbar'), provider: provider, clip: clip);
    } else if (overlay != null) {
      toolbar = OverlayItemToolbar(
          key: const ValueKey('overlay-toolbar'),
          provider: provider,
          clip: overlay);
    } else if (text != null) {
      toolbar = TextItemToolbar(
          key: const ValueKey('text-toolbar'),
          provider: provider,
          overlay: text);
    } else if (sticker != null) {
      toolbar = StickerItemToolbar(
          key: const ValueKey('sticker-toolbar'),
          provider: provider,
          sticker: sticker);
    } else if (audio != null) {
      toolbar = AudioItemToolbar(
          key: const ValueKey('audio-toolbar'),
          provider: provider,
          overlay: audio);
    } else {
      toolbar = KeyedSubtree(
        key: const ValueKey('main-toolbar'),
        child: _buildMainToolBar(provider),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: toolbar,
    );
  }

  /// Runs a clip tool from the main toolbar on the clip under the playhead
  /// (selecting it, which also brings up the clip toolbar).
  void _withClipAtPlayhead(
      VideoEditorProvider provider, void Function(String clipId) action) {
    final clip = provider.currentVideoClip;
    if (clip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Move the playhead over a clip first')),
      );
      return;
    }
    provider.selectVideoClip(clip.id);
    action(clip.id);
  }

  Widget _buildMainToolBar(VideoEditorProvider provider) {
    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Container(
        height: 84,
        decoration: BoxDecoration(
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
                icon: Icons.auto_awesome_outlined,
                label: 'Effects',
                onPressed: () => _withClipAtPlayhead(provider,
                    (id) => ClipToolSheets.effects(context, id)),
              ),
              const SizedBox(width: 6),
              _buildToolButton(
                icon: Icons.speed_rounded,
                label: 'Speed',
                onPressed: () => _withClipAtPlayhead(
                    provider, (id) => ClipToolSheets.speed(context, id)),
              ),
              const SizedBox(width: 6),
              _buildToolButton(
                icon: Icons.rotate_90_degrees_ccw_rounded,
                label: 'Rotate',
                onPressed: () => _withClipAtPlayhead(
                    provider, (id) => ClipToolSheets.rotate(context, id)),
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

  // ── Preview gestures & playback controls ─────────────────────────────

  double _lastDoubleTapDx = 0;

  /// Feedback bubble (play/pause/skip) shown over the preview.
  final ValueNotifier<_PreviewPulseData?> _pulse = ValueNotifier(null);
  int _pulseSerial = 0;

  void _showPulse(IconData icon, {String? label, Alignment? alignment}) {
    _pulse.value = _PreviewPulseData(
      ++_pulseSerial,
      icon,
      label,
      alignment ?? Alignment.center,
    );
  }

  /// Tap on the preview: deselect if something is selected, otherwise
  /// play/pause.
  void _onPreviewTap(VideoEditorProvider provider, bool interactive) {
    if (interactive && provider.hasTimelineSelection) {
      provider.clearSelection();
      return;
    }
    HapticFeedback.selectionClick();
    final willPlay = !provider.isPlaying;
    provider.togglePlayback();
    _showPulse(willPlay ? Icons.play_arrow_rounded : Icons.pause_rounded);
  }

  /// Double-tap left/right half of the preview: skip back/forward 2 s.
  void _onPreviewDoubleTap(VideoEditorProvider provider, bool left) {
    HapticFeedback.lightImpact();
    const step = Duration(seconds: 2);
    var target = left
        ? provider.currentPosition - step
        : provider.currentPosition + step;
    if (target < Duration.zero) target = Duration.zero;
    final total = provider.totalDuration;
    if (target > total) target = total;
    provider.seekTo(target);
    _showPulse(
      left ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
      label: left ? '−2s' : '+2s',
      alignment: left ? const Alignment(-0.6, 0) : const Alignment(0.6, 0),
    );
  }

  /// Steps one frame (at the project frame rate), pausing first.
  Future<void> _stepFrame(VideoEditorProvider provider, int direction) async {
    HapticFeedback.selectionClick();
    if (provider.isPlaying) await provider.togglePlayback();
    final fps = (provider.currentProject?.outputFrameRate ?? 30)
        .clamp(1, 120)
        .toDouble();
    final frame = Duration(microseconds: (1e6 / fps).round());
    var target = provider.currentPosition + frame * direction;
    if (target < Duration.zero) target = Duration.zero;
    final total = provider.totalDuration;
    if (target > total) target = total;
    await provider.seekTo(target);
  }

  String _formatPrecise(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final tenth = (d.inMilliseconds.remainder(1000) ~/ 100);
    return '$m:$s.$tenth';
  }

  Widget _buildPlaybackControls(VideoEditorProvider provider) {
    Widget stepButton(IconData icon, String tip, VoidCallback onTap) =>
        IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, color: AppColors.textSecondary, size: 22),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        );

    return Stack(
      alignment: Alignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _formatPrecise(provider.currentPosition),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: ' / ${_formatDuration(provider.totalDuration)}',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                ],
              ),
              style: const TextStyle(
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            stepButton(Icons.keyboard_arrow_left_rounded, 'Previous frame',
                () => _stepFrame(provider, -1)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                provider.togglePlayback();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryLight, AppColors.primaryDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary
                          .withValues(alpha: provider.isPlaying ? 0.55 : 0.3),
                      blurRadius: provider.isPlaying ? 16 : 8,
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: Icon(
                    provider.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    key: ValueKey(provider.isPlaying),
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            stepButton(Icons.keyboard_arrow_right_rounded, 'Next frame',
                () => _stepFrame(provider, 1)),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Fullscreen preview',
            onPressed: () => _openFullscreen(provider),
            icon: Icon(Icons.fullscreen_rounded,
                color: AppColors.textSecondary, size: 24),
          ),
        ),
      ],
    );
  }

  void _openFullscreen(VideoEditorProvider provider) {
    HapticFeedback.selectionClick();
    provider.clearSelection();
    Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _FullscreenPreview(
        canvasBuilder: (p) => _buildPreviewCanvas(p, interactive: false),
        pulse: _pulse,
        onTogglePlay: (p) => _onPreviewTap(p, false),
        onStepFrame: _stepFrame,
        formatTime: _formatPrecise,
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
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
      if (outputPath != null && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ExportScreen(outputPath: outputPath!),
        ));
      }
    } catch (e) {
      _showErrorDialog('Failed to export video: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
        title:
            Text('Error', style: TextStyle(color: AppColors.textPrimary)),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: TextStyle(color: AppColors.textSecondary),
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
          side: BorderSide(color: AppColors.border),
        ),
        title: Text('Merge Clips',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select a clip to merge with:',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ...adjacentClips.map((clip) => ListTile(
                  title: Text('Clip ${clips.indexOf(clip) + 1}',
                      style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(
                      '${_formatDuration(clip.startTime)} - ${_formatDuration(clip.endTime)}',
                      style: TextStyle(color: AppColors.textTertiary)),
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
          side: BorderSide(color: AppColors.border),
        ),
        title: Text('Delete Clip',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
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

  /// Cache key of the still frame a transition needs from [clip]: the last
  /// frame of the outgoing clip (the exporter freezes it the same way) or the
  /// first frame of the incoming one. Null for clips that are not videos.
  String? _transitionFrameKey(VideoClip clip, {required bool lastFrame}) {
    final path = _transitionPlaybackPath(clip);
    if (path == null) return null;
    return '$path|${_transitionStaticFrameTimeMs(clip, lastFrame: lastFrame)}';
  }

  /// Queues the still frame for [clip] unless it is cached or loading.
  /// [urgent] requests (the transition the playhead is approaching) jump the
  /// queue. Returns the frame's cache key.
  String? _requestTransitionFrame(
    VideoClip clip, {
    required bool lastFrame,
    bool urgent = false,
  }) {
    if (clip.mediaType == MediaType.image) {
      final file = clip.imageFile;
      if (file != null && _precachedTransitionImages.add(file.path)) {
        // Decode it now so the first transition frame is not blank.
        unawaited(precacheImage(FileImage(file), context).catchError((_) {}));
      }
      return null;
    }

    final key = _transitionFrameKey(clip, lastFrame: lastFrame);
    if (key == null) return null;
    if (_transitionFrames.containsKey(key)) return key;

    final queued = _transitionFrameQueue.indexWhere((r) => r.key == key);
    if (_transitionFramesLoading.contains(key)) return key;
    if (queued >= 0) {
      if (urgent && queued > 0) {
        _transitionFrameQueue.insert(0, _transitionFrameQueue.removeAt(queued));
      }
      return key;
    }

    final request = _TransitionFrameRequest(
      key: key,
      path: _transitionPlaybackPath(clip)!,
      timeMs: _transitionStaticFrameTimeMs(clip, lastFrame: lastFrame),
    );
    if (urgent) {
      _transitionFrameQueue.insert(0, request);
    } else {
      _transitionFrameQueue.add(request);
    }
    unawaited(_runTransitionFrameWorker());
    return key;
  }

  /// Extracts transition stills ahead of time so nothing is decoded when the
  /// playhead reaches a transition. While playing, only transitions in the
  /// next few seconds are fetched to keep the decoder free for playback.
  void _prefetchTransitionFrames(
    VideoEditorProvider provider,
    _ResolvedTransitionPreview? upcoming,
  ) {
    final project = provider.currentProject;
    if (project == null) return;

    if (upcoming != null &&
        !provider.hasRenderedTransition(upcoming.transition.id)) {
      _requestTransitionFrame(upcoming.clip1, lastFrame: true, urgent: true);
      _requestTransitionFrame(upcoming.clip2, lastFrame: false, urgent: true);
    }

    final playing = provider.isPlaying;
    final position = provider.currentPosition;
    const lookAhead = Duration(seconds: 10);
    final needed = <String>{};

    for (final transition in project.transitions) {
      final clip1 = _clipByIdOrNull(project, transition.clipId1);
      final clip2 = _clipByIdOrNull(project, transition.clipId2);
      if (clip1 == null || clip2 == null) continue;

      final k1 = _transitionFrameKey(clip1, lastFrame: true);
      final k2 = _transitionFrameKey(clip2, lastFrame: false);
      if (k1 != null) needed.add(k1);
      if (k2 != null) needed.add(k2);

      // Rendered transitions never need the live stills.
      if (provider.hasRenderedTransition(transition.id)) continue;
      if (playing) {
        final until = clip2.startTime - position;
        if (until < -transition.duration || until > lookAhead) continue;
      }
      _requestTransitionFrame(clip1, lastFrame: true);
      _requestTransitionFrame(clip2, lastFrame: false);
    }

    if (!playing) {
      // Drop stills of transitions that were removed or re-trimmed.
      final stale =
          _transitionFrames.keys.where((k) => !needed.contains(k)).toList();
      for (final key in stale) {
        _transitionFrames.remove(key)?.dispose();
      }
      _transitionFrameQueue.removeWhere((r) => !needed.contains(r.key));
    }
  }

  static VideoClip? _clipByIdOrNull(VideoProject project, String id) {
    for (final clip in project.videoClips) {
      if (clip.id == id) return clip;
    }
    return null;
  }

  /// Decodes queued stills one at a time (parallel extractions would fight
  /// the playback decoder, which is what made 4K transitions stall).
  Future<void> _runTransitionFrameWorker() async {
    if (_transitionFrameWorkerRunning) return;
    _transitionFrameWorkerRunning = true;
    try {
      while (_transitionFrameQueue.isNotEmpty && mounted) {
        final request = _transitionFrameQueue.removeAt(0);
        if (_transitionFrames.containsKey(request.key)) continue;
        _transitionFramesLoading.add(request.key);

        ui.Image? image;
        try {
          // Downscaled JPEG: a full-resolution PNG of a 4K frame takes
          // seconds to encode and decode and is far larger than the preview.
          final bytes = await VideoThumbnail.thumbnailData(
            video: request.path,
            imageFormat: ImageFormat.JPEG,
            timeMs: request.timeMs,
            maxWidth: _transitionFrameMaxSize,
            maxHeight: _transitionFrameMaxSize,
            quality: 90,
          );
          if (bytes != null) {
            final codec = await ui.instantiateImageCodec(bytes);
            image = (await codec.getNextFrame()).image;
            codec.dispose();
          }
        } catch (_) {
          image = null;
        }

        _transitionFramesLoading.remove(request.key);
        if (!mounted) {
          image?.dispose();
          return;
        }
        setState(() {
          _transitionFrames.remove(request.key)?.dispose();
          _transitionFrames[request.key] = image;
        });
      }
    } finally {
      _transitionFrameWorkerRunning = false;
    }
  }

  /// Preview media with clip effects on top (effects follow the timeline,
  /// exactly like the exporter applies them). Effects are skipped while the
  /// crop editor is open so the crop handles stay still.
  Widget _buildFilteredMedia(VideoEditorProvider provider,
      {bool isPreviewMode = false}) {
    final media =
        _buildFilteredMediaInner(provider, isPreviewMode: isPreviewMode);
    if (!isPreviewMode && provider.showCropEditor) return media;
    return EffectsPreview(provider: provider, child: media);
  }

  Widget _buildFilteredMediaInner(VideoEditorProvider provider,
      {bool isPreviewMode = false}) {
    final currentClip = provider.currentVideoClip;
    if (currentClip == null) {
      return Container(color: AppColors.background);
    }

    final transitionPreview = _resolveTransitionPreview(provider);
    _prefetchTransitionFrames(provider, transitionPreview);

    final cropEditorOpen = !isPreviewMode && provider.showCropEditor;

    if (transitionPreview != null &&
        transitionPreview.isActive &&
        !cropEditorOpen) {
      // Pre-rendered transition: a finished clip made by the exporter's own
      // filters (rotation, crop, color and the xfade are already baked in).
      final rendered = provider
          .renderedTransitionControllerFor(transitionPreview.transition.id);
      if (rendered != null) {
        var aspectRatio = rendered.value.aspectRatio;
        if ((rendered.value.rotationCorrection % 180) != 0) {
          aspectRatio = 1 / aspectRatio;
        }
        return SizedBox.expand(
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: VideoPlayer(rendered, key: ValueKey(rendered)),
              ),
            ),
          ),
        );
      }

      final clip1Key =
          _transitionFrameKey(transitionPreview.clip1, lastFrame: true);
      final clip2Key =
          _transitionFrameKey(transitionPreview.clip2, lastFrame: false);

      // Fill the preview canvas exactly like normal playback does. Forcing
      // the project aspect ratio here resized the picture at the start and
      // end of every transition, which looked like a built-in zoom.
      return SizedBox.expand(
        child: _TransitionPreview(
          provider: provider,
          transition: transitionPreview.transition,
          clip1: transitionPreview.clip1,
          clip2: transitionPreview.clip2,
          clip1Frame: clip1Key == null ? null : _transitionFrames[clip1Key],
          clip2Frame: clip2Key == null ? null : _transitionFrames[clip2Key],
          // Each side keeps its own rotation, filter and crop, as in export.
          decorate: (clip, media) => _decorateClipMedia(
            provider,
            clip,
            media,
            isPreviewMode: isPreviewMode,
          ),
        ),
      );
    }

    Widget mediaWidget;
    if (currentClip.mediaType == MediaType.image &&
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
            gaplessPlayback: true,
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

    if (!cropEditorOpen) {
      return _decorateClipMedia(
        provider,
        currentClip,
        mediaWidget,
        isPreviewMode: isPreviewMode,
      );
    }

    final filteredMedia = _decorateClipMedia(
      provider,
      currentClip,
      mediaWidget,
      isPreviewMode: isPreviewMode,
      applyCrop: false,
    );

    VideoClip? clipForCrop;
    if (provider.selectedVideoClipId != null &&
        provider.currentProject != null) {
      try {
        clipForCrop = provider.currentProject!.videoClips.firstWhere(
          (c) => c.id == provider.selectedVideoClipId,
        );
      } catch (_) {
        clipForCrop = currentClip;
      }
    } else {
      clipForCrop = currentClip;
    }
    final cropRect = clipForCrop.cropRect ?? const Rect.fromLTWH(0, 0, 1, 1);

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
  }

  /// Applies one clip's own look (mirror, rotation, color filter, chroma key
  /// and crop) to [media]. Normal playback decorates the clip at the
  /// playhead; a transition decorates each of its two clips separately.
  Widget _decorateClipMedia(
    VideoEditorProvider provider,
    VideoClip clip,
    Widget media, {
    required bool isPreviewMode,
    bool applyCrop = true,
  }) {
    // Use per-clip filter if available, otherwise fall back to the
    // project-wide filter (same fallback as the exporter).
    final ColorFilter colorFilter;
    final clipFilter = provider.clipColorFilters[clip.id];
    if (clipFilter != null && clipFilter.hasFilters) {
      colorFilter = clipFilter;
    } else {
      colorFilter =
          provider.currentProject?.colorFilter ?? const ColorFilter();
    }
    final selectedClipId = provider.selectedVideoClipId;

    // Each clip keeps its own independent rotation.
    final double rotation = isPreviewMode ? 0.0 : clip.rotation;
    final bool isMirrored = !isPreviewMode && clip.isMirrored;

    Widget mediaWidget = media;

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

    // ============ GREEN SCREEN ============
    // While the panel is open on this clip it shows the live draft (and
    // "hold to compare" shows the original).
    final panelOnClip = provider.editorPanelMode == EditorPanelMode.chromaKey &&
        selectedClipId != null &&
        clip.id == selectedClipId;
    final chroma = panelOnClip
        ? provider.currentChromaKeySettings
        : clip.chromaKeySettings;
    final keyed = chroma != null &&
        chroma.enabled &&
        !(panelOnClip && provider.chromaCompare);
    // Same order as the exporter: key, then the colour filter.
    if (keyed) mediaWidget = ChromaComposite.keyOut(chroma, mediaWidget);

    mediaWidget = ColorFiltered(
      colorFilter: ui.ColorFilter.matrix(_calculateColorMatrix(colorFilter)),
      child: mediaWidget,
    );

    if (colorFilter.warmth != 0.0 || colorFilter.tint != 0.0) {
      if (keyed) {
        // Tint only the subject, never the keyed-out (transparent) area.
        mediaWidget = ColorFiltered(
          colorFilter: ui.ColorFilter.mode(
              _getFilterOverlayColor(colorFilter), BlendMode.srcATop),
          child: mediaWidget,
        );
      } else {
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
    }

    if (keyed) {
      mediaWidget = ChromaComposite(
        keyedMedia: mediaWidget,
        settings: chroma,
        localTime: provider.currentPosition - clip.startTime,
        isPlaying: provider.isPlaying,
      );
    }
    // ============ END GREEN SCREEN ============

    final crop = clip.cropRect;
    if (!applyCrop || crop == null) return mediaWidget;

    final filteredMedia = mediaWidget;
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
                ..translate(-originalRect.center.dx, -originalRect.center.dy),
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
                  boxShadow: [
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

/// Small pill shown over the preview while transitions are pre-rendered for
/// smooth playback.
class _TransitionRenderBadge extends StatelessWidget {
  final double progress;
  final int pending;

  const _TransitionRenderBadge({required this.progress, required this.pending});

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).round();
    final label = pending > 1
        ? 'Rendering transitions ($pending) $percent%'
        : 'Rendering transition $percent%';
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress > 0.02 ? progress : null,
                color: AppColors.primary,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransitionFrameRequest {
  final String key;
  final String path;
  final int timeMs;

  const _TransitionFrameRequest({
    required this.key,
    required this.path,
    required this.timeMs,
  });
}

typedef _ClipDecorator = Widget Function(VideoClip clip, Widget media);

/// Live transition preview. The outgoing clip is its frozen last frame and
/// the incoming clip plays live, which is exactly what the exporter renders.
/// Progress is re-evaluated on every vsync from the playback clock, so the
/// animation runs at display rate instead of the 30 Hz timeline timer.
class _TransitionPreview extends StatefulWidget {
  final VideoEditorProvider provider;
  final Transition transition;
  final VideoClip clip1;
  final VideoClip clip2;
  final ui.Image? clip1Frame;
  final ui.Image? clip2Frame;
  final _ClipDecorator decorate;

  const _TransitionPreview({
    required this.provider,
    required this.transition,
    required this.clip1,
    required this.clip2,
    required this.clip1Frame,
    required this.clip2Frame,
    required this.decorate,
  });

  @override
  State<_TransitionPreview> createState() => _TransitionPreviewState();
}

class _TransitionPreviewState extends State<_TransitionPreview>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _TransitionPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final playing = widget.provider.isPlaying;
    if (playing && !_ticker.isActive) {
      _ticker.start();
    } else if (!playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

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

  /// The active controller when it is currently synced to [clip].
  VideoPlayerController? _liveControllerFor(VideoClip clip, VideoClip other) {
    final provider = widget.provider;
    final path = _playbackPath(clip);
    final controller = provider.previewController;
    if (path == null ||
        controller == null ||
        !controller.value.isInitialized ||
        provider.activeFilePath != path) {
      return null;
    }
    // Both sides of a split share one file: trust the decoder only once it
    // has been synced to this side.
    if (path == _playbackPath(other)) {
      return provider.activePreviewClipId == clip.id ? controller : null;
    }
    return controller;
  }

  Widget _buildStill(ui.Image image) {
    return SizedBox.expand(
      child: RawImage(
        image: image,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
      ),
    );
  }

  Widget _buildVideoPlayer(VideoPlayerController controller) {
    var aspectRatio = controller.value.aspectRatio;
    final rotationDeg = controller.value.rotationCorrection;
    if ((rotationDeg % 180) != 0) {
      aspectRatio = 1 / aspectRatio;
    }
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: VideoPlayer(controller, key: ValueKey(controller)),
      ),
    );
  }

  Widget _buildClipChild(VideoClip clip, {required bool isClip1}) {
    Widget content;
    if (clip.mediaType == MediaType.image && clip.imageFile != null) {
      content = SizedBox.expand(
        child: Image.file(
          clip.imageFile!,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          gaplessPlayback: true,
          key: ValueKey(clip.id),
        ),
      );
    } else {
      final other = isClip1 ? widget.clip2 : widget.clip1;
      final still = isClip1 ? widget.clip1Frame : widget.clip2Frame;
      final live = _liveControllerFor(clip, other);
      if (isClip1) {
        // Frozen last frame, like the export. Until it is decoded, fall back
        // to the decoder if it is still parked on the outgoing clip.
        content = still != null
            ? _buildStill(still)
            : (live != null
                ? _buildVideoPlayer(live)
                : const SizedBox.expand());
      } else {
        content = live != null
            ? _buildVideoPlayer(live)
            : (still != null ? _buildStill(still) : const SizedBox.expand());
      }
    }

    return RepaintBoundary(
      child: ColoredBox(
        color: Colors.black,
        child: widget.decorate(clip, content),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = VideoEditorProvider.transitionPreviewProgress(
      widget.provider.smoothPosition,
      widget.transition,
      widget.clip2,
    );

    // Clip so pushes, rotations and scales never paint outside the preview.
    return ClipRect(
      child: TransitionFactory.buildWithCurve(
        type: widget.transition.type,
        linearT: progress,
        childA: _buildClipChild(widget.clip1, isClip1: true),
        childB: _buildClipChild(widget.clip2, isClip1: false),
      ),
    );
  }
}


class _PreviewPulseData {
  final int serial;
  final IconData icon;
  final String? label;
  final Alignment alignment;
  const _PreviewPulseData(this.serial, this.icon, this.label, this.alignment);
}

/// Short "pop" feedback for preview gestures (play, pause, ±2 s).
class _PreviewPulse extends StatelessWidget {
  final ValueNotifier<_PreviewPulseData?> pulse;
  const _PreviewPulse({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<_PreviewPulseData?>(
        valueListenable: pulse,
        builder: (context, data, _) {
          if (data == null) return const SizedBox.shrink();
          return Align(
            alignment: data.alignment,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(data.serial),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              builder: (context, t, child) {
                // Pop in quickly, hold, then fade out.
                final scale = t < 0.25 ? 0.7 + 1.2 * t : 1.0;
                final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4);
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: data.label == null ? 16 : 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(data.icon, color: Colors.white, size: 34),
                    if (data.label != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        data.label!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Fullscreen preview: the same canvas as the editor (media, effects,
/// overlays) on black, with auto-hiding controls, a scrubber, frame
/// stepping and a landscape toggle.
class _FullscreenPreview extends StatefulWidget {
  final Widget Function(VideoEditorProvider) canvasBuilder;
  final ValueNotifier<_PreviewPulseData?> pulse;
  final void Function(VideoEditorProvider) onTogglePlay;
  final Future<void> Function(VideoEditorProvider, int) onStepFrame;
  final String Function(Duration) formatTime;

  const _FullscreenPreview({
    required this.canvasBuilder,
    required this.pulse,
    required this.onTogglePlay,
    required this.onStepFrame,
    required this.formatTime,
  });

  @override
  State<_FullscreenPreview> createState() => _FullscreenPreviewState();
}

class _FullscreenPreviewState extends State<_FullscreenPreview> {
  bool _controlsVisible = true;
  bool _landscape = false;
  bool _scrubbing = false;
  double? _scrubValue;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _scrubbing) return;
      final playing =
          Provider.of<VideoEditorProvider>(context, listen: false).isPlaying;
      if (playing) setState(() => _controlsVisible = false);
    });
  }

  void _poke() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleOrientation() {
    HapticFeedback.selectionClick();
    setState(() => _landscape = !_landscape);
    SystemChrome.setPreferredOrientations(_landscape
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const [DeviceOrientation.portraitUp]);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, p, _) {
        final total = p.totalDuration;
        final totalMs = math.max(1, total.inMilliseconds).toDouble();
        final pos = _scrubValue ??
            p.currentPosition.inMilliseconds.clamp(0, totalMs).toDouble();
        final padding = MediaQuery.of(context).padding;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Listener(
            onPointerDown: (_) => _poke(),
            child: Stack(
              children: [
                Positioned.fill(child: widget.canvasBuilder(p)),
                Positioned.fill(child: _PreviewPulse(pulse: widget.pulse)),
                // Top bar
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  left: 0,
                  right: 0,
                  top: _controlsVisible ? 0 : -(padding.top + 90),
                  child: Container(
                    padding: EdgeInsets.fromLTRB(8, padding.top + 6, 8, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                        ),
                        Expanded(
                          child: Text(
                            p.currentProject?.name ?? 'Preview',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: _landscape ? 'Portrait' : 'Landscape',
                          onPressed: _toggleOrientation,
                          icon: Icon(
                            _landscape
                                ? Icons.stay_current_portrait_rounded
                                : Icons.screen_rotation_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Bottom controls
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  left: 0,
                  right: 0,
                  bottom: _controlsVisible ? 0 : -(padding.bottom + 160),
                  child: Container(
                    padding:
                        EdgeInsets.fromLTRB(16, 24, 16, padding.bottom + 10),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.formatTime(
                                  Duration(milliseconds: pos.round())),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                            Expanded(
                              child: Slider(
                                value: pos,
                                max: totalMs,
                                activeColor: AppColors.primary,
                                inactiveColor: Colors.white24,
                                onChangeStart: (v) {
                                  _scrubbing = true;
                                  p.beginScrub();
                                },
                                onChanged: (v) {
                                  setState(() => _scrubValue = v);
                                  p.seekTo(Duration(milliseconds: v.round()));
                                },
                                onChangeEnd: (v) {
                                  _scrubbing = false;
                                  setState(() => _scrubValue = null);
                                  p.endScrub();
                                  _scheduleHide();
                                },
                              ),
                            ),
                            Text(
                              widget.formatTime(total),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Previous frame',
                              onPressed: () => widget.onStepFrame(p, -1),
                              icon: const Icon(
                                  Icons.keyboard_arrow_left_rounded,
                                  color: Colors.white,
                                  size: 30),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => widget.onTogglePlay(p),
                              child: Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary,
                                ),
                                child: Icon(
                                  p.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: 'Next frame',
                              onPressed: () => widget.onStepFrame(p, 1),
                              icon: const Icon(
                                  Icons.keyboard_arrow_right_rounded,
                                  color: Colors.white,
                                  size: 30),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OverlayTextPainter extends CustomPainter {
  final TextOverlayPainter text;
  final double reveal;
  _OverlayTextPainter(this.text, this.reveal);

  @override
  void paint(Canvas canvas, Size size) =>
      text.paint(canvas, Offset.zero, reveal: reveal);

  @override
  bool shouldRepaint(covariant _OverlayTextPainter old) => true;
}
