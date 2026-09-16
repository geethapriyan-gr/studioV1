import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/video_project.dart';
import '../main.dart' show AppColors;

class DraggableMediaOverlay extends StatefulWidget {
  final VideoClip overlayClip;
  final Size parentSize;
  final VideoPlayerController? previewController;
  final VoidCallback onPositionChanged;
  final Function(Offset newPosition) onUpdatePosition;
  final Function(Size newSize) onUpdateSize;
  final VoidCallback onSelected;
  final VoidCallback onDelete;
  final bool isSelected;

  const DraggableMediaOverlay({
    super.key,
    required this.overlayClip,
    required this.parentSize,
    this.previewController,
    required this.onPositionChanged,
    required this.onUpdatePosition,
    required this.onUpdateSize,
    required this.onSelected,
    required this.onDelete,
    this.isSelected = false,
  });

  @override
  State<DraggableMediaOverlay> createState() => _DraggableMediaOverlayState();
}

class _DraggableMediaOverlayState extends State<DraggableMediaOverlay> {
  late Offset _currentPosition;
  late Size _currentSize;
  VideoPlayerController? _localController;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.overlayClip.overlayPosition;
    _currentSize = widget.overlayClip.overlaySize;
    _initController();
    _addPreviewControllerListener();
  }

  @override
  void didUpdateWidget(DraggableMediaOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlayClip.id != widget.overlayClip.id) {
      _currentPosition = widget.overlayClip.overlayPosition;
      _currentSize = widget.overlayClip.overlaySize;
      _disposeController();
      _initController();
    } else {
      if (oldWidget.overlayClip.volume != widget.overlayClip.volume ||
          oldWidget.overlayClip.isMuted != widget.overlayClip.isMuted) {
        final targetVol = widget.overlayClip.isMuted
            ? 0.0
            : widget.overlayClip.volume.clamp(0.0, 1.0);
        _localController?.setVolume(targetVol);
      }
    }
    if (oldWidget.previewController != widget.previewController) {
      _removePreviewControllerListener(oldWidget.previewController);
      _addPreviewControllerListener();
    }
  }

  void _addPreviewControllerListener() {
    widget.previewController?.addListener(_syncWithPreview);
  }

  void _removePreviewControllerListener(VideoPlayerController? oldController) {
    oldController?.removeListener(_syncWithPreview);
  }

  void _initController() {
    if (widget.overlayClip.mediaType == MediaType.video &&
        widget.overlayClip.videoFile != null) {
      _localController = VideoPlayerController.file(
        widget.overlayClip.videoFile!,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      )
        ..setLooping(true)
        ..initialize().then((_) {
          if (mounted) {
            final targetVol = widget.overlayClip.isMuted
                ? 0.0
                : widget.overlayClip.volume.clamp(0.0, 1.0);
            _localController?.setVolume(targetVol);
            setState(() {});
            // Don't auto-play, wait for sync
            _syncWithPreview();
          }
        });
    }
  }

  // No sync during playback - maximum performance
  bool _isOverlayPlaying = false;
  void _syncWithPreview() {
    if (_localController == null || widget.previewController == null) return;
    if (!_localController!.value.isInitialized ||
        !widget.previewController!.value.isInitialized) {
      return;
    }

    final mainPos = widget.previewController!.value.position;
    final overlayStart = widget.overlayClip.startTime;
    final overlayEnd = widget.overlayClip.endTime;
    final trimStart = widget.overlayClip.trimStart;
    final trimEnd = widget.overlayClip.trimEnd;

    // Only sync playback state - NO position sync at all during playback
    if (widget.previewController!.value.isPlaying) {
      if (mainPos >= overlayStart && mainPos < overlayEnd) {
        if (!_isOverlayPlaying) {
          _isOverlayPlaying = true;
          // Calculate position within the trimmed overlay
          final posInOverlay = mainPos - overlayStart;
          final trimmedPos = trimStart + posInOverlay;

          // Ensure we don't go beyond the trimmed bounds
          if (trimmedPos >= trimStart && trimmedPos < trimEnd) {
            _localController!.seekTo(trimmedPos);
            _localController!.play();
          }
        }
      } else {
        if (_isOverlayPlaying) {
          _isOverlayPlaying = false;
          _localController!.pause();
        }
      }
    } else {
      if (_isOverlayPlaying) {
        _isOverlayPlaying = false;
        _localController!.pause();
      }
      // Only sync position when paused
      if (mainPos >= overlayStart && mainPos < overlayEnd) {
        final posInOverlay = mainPos - overlayStart;
        final trimmedPos = trimStart + posInOverlay;

        // Ensure we don't go beyond the trimmed bounds
        if (trimmedPos >= trimStart && trimmedPos < trimEnd) {
          _localController!.seekTo(trimmedPos);
        }
      }
    }
  }

  void _disposeController() {
    _localController?.pause();
    _localController?.dispose();
    _localController = null;
  }

  Widget _buildMediaContent() {
    if (widget.overlayClip.mediaType == MediaType.image &&
        widget.overlayClip.imageFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FittedBox(
          fit: BoxFit.contain,
          child: Image.file(
            widget.overlayClip.imageFile!,
          ),
        ),
      );
    } else if (widget.overlayClip.mediaType == MediaType.video &&
        _localController != null &&
        _localController!.value.isInitialized) {
      double videoWidth = _localController!.value.size.width;
      double videoHeight = _localController!.value.size.height;
      final rot = _localController!.value.rotationCorrection;
      if ((rot % 180) != 0) {
        videoWidth = _localController!.value.size.height;
        videoHeight = _localController!.value.size.width;
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: videoWidth,
            height: videoHeight,
            child: VideoPlayer(
              _localController!,
              key: ValueKey(_localController),
            ),
          ),
        ),
      );
    }
    return Container(
      color: AppColors.surface,
      child: const Center(
        child: Icon(Icons.videocam_outlined, color: AppColors.textTertiary),
      ),
    );
  }


  void _updatePosition(Offset deltaOffset) {
    double newDx =
        _currentPosition.dx + deltaOffset.dx / widget.parentSize.width;
    double newDy =
        _currentPosition.dy + deltaOffset.dy / widget.parentSize.height;

    // Constrain position to parent bounds
    newDx = newDx.clamp(0.0, 1.0 - _currentSize.width);
    newDy = newDy.clamp(0.0, 1.0 - _currentSize.height);

    setState(() {
      _currentPosition = Offset(newDx, newDy);
    });
    widget.onUpdatePosition(_currentPosition);
    widget.onPositionChanged();
  }

  void _updateSize(Offset deltaOffset) {
    // Maintain the original aspect ratio strictly
    final aspectRatio = _currentSize.width / _currentSize.height;
    final maxWidth = 1.0 - _currentPosition.dx;
    final maxHeight = 1.0 - _currentPosition.dy;

    // Calculate new width from horizontal drag
    double newWidth =
        (_currentSize.width + deltaOffset.dx / widget.parentSize.width)
            .clamp(0.05, maxWidth);
    double newHeight = newWidth / aspectRatio;

    // If height violates bounds, use height as the primary dimension instead
    if (newHeight < 0.05 || newHeight > maxHeight) {
      newHeight =
          (_currentSize.height + deltaOffset.dy / widget.parentSize.height)
              .clamp(0.05, maxHeight);
      newWidth = newHeight * aspectRatio;
      // Re-clamp width if needed
      newWidth = newWidth.clamp(0.05, maxWidth);
    }

    setState(() {
      _currentSize = Size(newWidth, newHeight);
    });
    widget.onUpdateSize(_currentSize);
    widget.onPositionChanged();
  }

  @override
  void dispose() {
    _removePreviewControllerListener(widget.previewController);
    _disposeController();
    super.dispose();
  }

  // Pinch-to-zoom state
  Size? _scaleStartSize;
  Offset? _scaleStartPosition;
  int _activePointers = 0;

  void _onScaleStart(ScaleStartDetails details) {
    _scaleStartSize = _currentSize;
    _scaleStartPosition = _currentPosition;
    _activePointers = details.pointerCount;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _activePointers = details.pointerCount;

    if (_activePointers >= 2 && _scaleStartSize != null) {
      // --- Pinch to zoom: resize while keeping aspect ratio ---
      final aspectRatio = _scaleStartSize!.width / _scaleStartSize!.height;
      final scaleFactor = details.scale.clamp(0.3, 5.0);

      double newWidth = (_scaleStartSize!.width * scaleFactor).clamp(0.05, 1.0);
      double newHeight = newWidth / aspectRatio;

      // Clamp height and re-derive width if needed
      if (newHeight > 1.0) {
        newHeight = 1.0;
        newWidth = newHeight * aspectRatio;
      }
      if (newHeight < 0.05) {
        newHeight = 0.05;
        newWidth = newHeight * aspectRatio;
      }

      // Adjust position so the overlay stays centred around the pinch focal point
      final dw = newWidth - _currentSize.width;
      final dh = newHeight - _currentSize.height;
      double newDx = (_currentPosition.dx - dw / 2).clamp(0.0, 1.0 - newWidth);
      double newDy = (_currentPosition.dy - dh / 2).clamp(0.0, 1.0 - newHeight);

      setState(() {
        _currentSize = Size(newWidth, newHeight);
        _currentPosition = Offset(newDx, newDy);
      });
      widget.onUpdateSize(_currentSize);
      widget.onUpdatePosition(_currentPosition);
      widget.onPositionChanged();
    } else {
      // --- Single-finger drag: move the overlay ---
      _updatePosition(details.focalPointDelta);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _scaleStartSize = null;
    _scaleStartPosition = null;
    _activePointers = 0;
  }

  @override
  Widget build(BuildContext context) {
    // Sync on every build when main video changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWithPreview();
    });

    final absoluteLeft = _currentPosition.dx * widget.parentSize.width;
    final absoluteTop = _currentPosition.dy * widget.parentSize.height;
    final absoluteWidth = _currentSize.width * widget.parentSize.width;
    final absoluteHeight = _currentSize.height * widget.parentSize.height;

    return Positioned(
      left: absoluteLeft,
      top: absoluteTop,
      width: absoluteWidth,
      height: absoluteHeight,
      child: GestureDetector(
        onTap: widget.onSelected,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: widget.isSelected
                ? Border.all(color: AppColors.primary, width: 3)
                : Border.all(color: Colors.transparent, width: 3),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Main media content (with opacity)
              Opacity(
                opacity: widget.overlayClip.overlayOpacity.clamp(0.0, 1.0),
                child: _buildMediaContent(),
              ),
              // Close button (top-right corner) - shown when selected
              if (widget.isSelected)
                Positioned(
                  right: 4,
                  top: 4,
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.85),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 28,
                        color: Colors.white,
                      ),
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
