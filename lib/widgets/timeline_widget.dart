import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:provider/provider.dart';

import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';
import '../models/transition.dart';
import '../main.dart' show AppColors;
import '../services/video_thumbnail_service.dart';
import '../services/media_picker_service.dart';
import 'waveform_painter.dart';
import '../utils/responsive.dart';
import '../utils/track_allocation.dart';

/// Wrapper class to distinguish overlay clip drags from main video clip drags.
/// This prevents cross-track drag-and-drop interference.
class OverlayClipDragData {
  final VideoClip clip;
  const OverlayClipDragData(this.clip);
}

class TimelineWidget extends StatefulWidget {
  const TimelineWidget({super.key});

  static void showMixerDialog(BuildContext context, VideoEditorProvider provider) {
    final dialogWidth = math.min(ResponsiveUtil.screenWidth * 0.85, 320.0);
    showDialog(
      context: context,
      builder: (context) {
        double videoVol = provider.videoMasterVolume;
        double audioVol = provider.audioMasterVolume;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              title: const Text('Audio Mixer',
                  style: TextStyle(color: AppColors.textPrimary)),
              content: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMixerSlider(
                      label: 'Video Master',
                      value: videoVol,
                      onChanged: (v) {
                        setState(() => videoVol = v);
                        provider.setVideoMasterVolume(v);
                      },
                    ),
                    SizedBox(height: ResponsiveUtil.spacingLarge),
                    _buildMixerSlider(
                      label: 'Audio Master',
                      value: audioVol,
                      onChanged: (v) {
                        setState(() => audioVol = v);
                        provider.setAudioMasterVolume(v);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Widget _buildMixerSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: ResponsiveUtil.fontSizeSmall)),
            Text('${(value * 100).round()}%',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: ResponsiveUtil.fontSizeTiny)),
          ],
        ),
        SizedBox(height: ResponsiveUtil.spacingMedium),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.border,
            thumbColor: AppColors.textPrimary,
            overlayColor: AppColors.primary.withOpacity(0.15),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
            min: 0.0,
            max: 1.0,
            divisions: 100,
          ),
        ),
      ],
    );
  }

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  double _timelineScale = 0.01;
  static const double _timelineHeight = 32.0;
  final GlobalKey _timelineContentKey = GlobalKey();
  final GlobalKey _videoTrackKey = GlobalKey();
  final GlobalKey _textTrackKey = GlobalKey();
  final GlobalKey _stickerTrackKey = GlobalKey();

  // Centered playhead state
  double _viewportWidth = 0;
  bool _isUserScrolling = false;
  Duration? _lastSyncedPosition;

  // Frame thumbnail cache for timeline preview (global, path-based)
  final VideoThumbnailService _thumbnailService = VideoThumbnailService();
  // Track which video paths are currently loading thumbnails
  final Set<String> _loadingVideoPaths = {};
  // Track which video paths have completed full extraction
  final Set<String> _fullyLoadedPaths = {};

  // ─── Manual multi-touch pinch zoom (Listener-based) ─────────
  final Map<int, Offset> _activePointers = {};
  bool _isPinching = false;
  double _previousPinchDistance = 0.0;
  double _pinchBaseScale = 0.01;
  double _targetScale = 0.01;
  double _zoomCenterTimeMs = 0.0;
  late AnimationController _zoomAnimController;
  Animation<double>? _zoomAnimation;

  // Trim handle optimization - throttle provider updates to ~60fps
  static const int _trimUpdateThresholdMs = 16; // ~60fps
  int _textTrimAccumulatedDeltaMs = 0;
  int _audioTrimAccumulatedDeltaMs = 0;

  // Video clip trim throttle
  DateTime? _lastVideoTrimUpdate;
  static const _videoTrimThrottle = Duration(milliseconds: 16);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);

    // Smooth zoom animation controller
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _zoomAnimController.addListener(_onZoomAnimTick);
  }

  /// Get responsive track height
  double get _trackHeight {
    return ResponsiveUtil.trackHeightNormal;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _zoomAnimController.removeListener(_onZoomAnimTick);
    _zoomAnimController.dispose();
    super.dispose();
  }

  // ─── Smooth zoom animation ─────────────────────────────────

  void _onZoomAnimTick() {
    if (_zoomAnimation == null) return;
    final newScale = _zoomAnimation!.value;
    if ((newScale - _timelineScale).abs() > 0.000001) {
      setState(() => _timelineScale = newScale);
      _restoreScrollForZoomCenter();
    }
  }

  void _animateZoomTo(double newScale) {
    newScale = newScale.clamp(0.001, 2.0);
    if ((newScale - _timelineScale).abs() < 0.000001) return;

    _zoomAnimation = Tween<double>(
      begin: _timelineScale,
      end: newScale,
    ).animate(CurvedAnimation(
      parent: _zoomAnimController,
      curve: Curves.easeOutCubic,
    ));
    _zoomAnimController.forward(from: 0);
  }

  /// Capture the time position at viewport center (for playhead preservation)
  void _captureZoomCenter() {
    if (!_scrollController.hasClients) return;
    _zoomCenterTimeMs = _scrollController.offset / _timelineScale;
  }

  /// Restore scroll so the same time position stays at center after zoom
  void _restoreScrollForZoomCenter() {
    if (!_scrollController.hasClients) return;
    final newOffset = _zoomCenterTimeMs * _timelineScale;
    final maxOffset = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(newOffset.clamp(0.0, maxOffset));
  }

  // ─── Pointer-based pinch handlers ──────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.position;

    if (_activePointers.length == 2) {
      // Second finger just arrived — start pinch
      _zoomAnimController.stop();
      _captureZoomCenter();
      _pinchBaseScale = _timelineScale;
      _targetScale = _timelineScale;

      // Calculate initial distance (no jump on first frame)
      final pointers = _activePointers.values.toList();
      _previousPinchDistance = (pointers[0] - pointers[1]).distance;

      setState(() => _isPinching = true);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.position;

    if (_activePointers.length >= 2 && _isPinching) {
      final pointers = _activePointers.values.toList();
      final currentDistance = (pointers[0] - pointers[1]).distance;

      if (_previousPinchDistance > 0 && currentDistance > 0) {
        // Relative scale since pinch began
        final scaleFactor = currentDistance / _previousPinchDistance;
        _targetScale = (_pinchBaseScale * scaleFactor).clamp(0.001, 2.0);

        // Smooth lerp damping — blend 15% toward target each frame
        final smoothed =
            _timelineScale + (_targetScale - _timelineScale) * 0.15;
        final clamped = smoothed.clamp(0.001, 2.0);

        if ((clamped - _timelineScale).abs() > 0.000001) {
          setState(() => _timelineScale = clamped);
          _restoreScrollForZoomCenter();
        }
      }
    }
  }

  void _onPointerUpOrCancel(int pointer) {
    _activePointers.remove(pointer);

    if (_activePointers.length < 2 && _isPinching) {
      // Pinch ended — animate to final target for smooth finish
      _animateZoomTo(_targetScale);
      setState(() => _isPinching = false);
      _previousPinchDistance = 0;
    }

    if (_activePointers.length == 1) {
      // Reset pinch distance so re-adding a finger starts fresh
      _previousPinchDistance = 0;
    }
  }

  // ─── Scroll handlers ───────────────────────────────────────

  void _onScrollChanged() {
    if (_scrollController.hasClients && _isUserScrolling) {
      final scrollOffset = _scrollController.offset;
      final positionMs = (scrollOffset / _timelineScale).round();
      var position = Duration(milliseconds: positionMs);

      final provider = Provider.of<VideoEditorProvider>(context, listen: false);
      if (provider.hasProject) {
        final maxDuration = provider.totalDuration;
        if (position > maxDuration) {
          position = maxDuration;
        }
        provider.seekTo(position);
        _lastSyncedPosition = position;
      }
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _isUserScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _isUserScrolling = false;
    }
    return false;
  }

  void _syncScrollToPosition(Duration position) {
    if (!_scrollController.hasClients || _isUserScrolling) return;

    final targetOffset = position.inMilliseconds * _timelineScale;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxOffset);
    _scrollController.jumpTo(clampedOffset);
  }

  // Helper methods for optimized trim handling
  void _updateTextOverlayTrimStart(String overlayId, Duration currentStart,
      Duration currentEnd, int deltaMs) {
    _textTrimAccumulatedDeltaMs += deltaMs;

    // Only update provider when threshold is reached
    if (_textTrimAccumulatedDeltaMs.abs() >= _trimUpdateThresholdMs) {
      final delta = Duration(milliseconds: _textTrimAccumulatedDeltaMs);
      final newStartTime = currentStart + delta;

      if (newStartTime >= Duration.zero &&
          newStartTime < currentEnd - const Duration(seconds: 1)) {
        final provider =
            Provider.of<VideoEditorProvider>(context, listen: false);
        provider.updateTextOverlay(overlayId,
            startTime: newStartTime, endTime: currentEnd);
      }
      _textTrimAccumulatedDeltaMs = 0;
    }
  }

  void _updateTextOverlayTrimEnd(String overlayId, Duration currentStart,
      Duration currentEnd, int deltaMs) {
    _textTrimAccumulatedDeltaMs += deltaMs;

    // Only update provider when threshold is reached
    if (_textTrimAccumulatedDeltaMs.abs() >= _trimUpdateThresholdMs) {
      final delta = Duration(milliseconds: _textTrimAccumulatedDeltaMs);
      final newEndTime = currentEnd + delta;

      if (newEndTime > currentStart + const Duration(seconds: 1)) {
        final provider =
            Provider.of<VideoEditorProvider>(context, listen: false);
        provider.updateTextOverlay(overlayId,
            startTime: currentStart, endTime: newEndTime);
      }
      _textTrimAccumulatedDeltaMs = 0;
    }
  }

  void _finalizeTextTrim() {
    // Finalize any remaining accumulated delta
    if (_textTrimAccumulatedDeltaMs != 0) {
      _textTrimAccumulatedDeltaMs = 0;
    }
  }

  void _updateAudioOverlayTrimStart(String overlayId, Duration currentStart,
      Duration currentEnd, Duration currentAudioOffset, int deltaMs) {
    _audioTrimAccumulatedDeltaMs += deltaMs;

    // Only update provider when threshold is reached
    if (_audioTrimAccumulatedDeltaMs.abs() >= _trimUpdateThresholdMs) {
      final delta = Duration(milliseconds: _audioTrimAccumulatedDeltaMs);
      final newStartTime = currentStart + delta;
      final newAudioOffset = currentAudioOffset + delta;

      if (newStartTime >= Duration.zero &&
          newStartTime < currentEnd - const Duration(seconds: 1)) {
        final provider =
            Provider.of<VideoEditorProvider>(context, listen: false);
        provider.updateAudioOverlay(
          overlayId,
          startTime: newStartTime,
          endTime: currentEnd,
          audioStartOffset: newAudioOffset,
        );
      }
      _audioTrimAccumulatedDeltaMs = 0;
    }
  }

  void _updateAudioOverlayTrimEnd(String overlayId, Duration currentStart,
      Duration currentEnd, int deltaMs) {
    _audioTrimAccumulatedDeltaMs += deltaMs;

    // Only update provider when threshold is reached
    if (_audioTrimAccumulatedDeltaMs.abs() >= _trimUpdateThresholdMs) {
      final delta = Duration(milliseconds: _audioTrimAccumulatedDeltaMs);
      final newEndTime = currentEnd + delta;

      if (newEndTime > currentStart + const Duration(seconds: 1)) {
        final provider =
            Provider.of<VideoEditorProvider>(context, listen: false);
        provider.updateAudioOverlay(overlayId,
            startTime: currentStart, endTime: newEndTime);
      }
      _audioTrimAccumulatedDeltaMs = 0;
    }
  }

  void _finalizeAudioTrim() {
    // Finalize any remaining accumulated delta
    if (_audioTrimAccumulatedDeltaMs != 0) {
      _audioTrimAccumulatedDeltaMs = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        if (!provider.hasProject) {
          return const Center(
            child: Text(
              'No project loaded',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            _viewportWidth = constraints.maxWidth;
            final bool showHeader = height > 180;
            final bool isCompact = height < 120;

            if (!_isUserScrolling &&
                provider.currentPosition != _lastSyncedPosition) {
              _lastSyncedPosition = provider.currentPosition;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _syncScrollToPosition(provider.currentPosition);
              });
            }

            final textAllocation = computeTrackAllocation<TextOverlay>(
              items: provider.currentProject?.textOverlays ?? [],
              getId: (t) => t.id,
              getStartTime: (t) => t.startTime,
              getEndTime: (t) => t.endTime,
            );

            final stickerAllocation = computeTrackAllocation<StickerModel>(
              items: provider.currentProject?.stickers ?? [],
              getId: (s) => s.id,
              getStartTime: (s) => s.startTime,
              getEndTime: (s) => s.endTime,
            );

            final overlayAllocation = computeTrackAllocation<VideoClip>(
              items: provider.currentProject?.overlayClips ?? [],
              getId: (c) => c.id,
              getStartTime: (c) => c.startTime,
              getEndTime: (c) => c.endTime,
            );

            final audioAllocation = computeTrackAllocation<AudioOverlay>(
              items: provider.currentProject?.audioOverlays ?? [],
              getId: (a) => a.id,
              getStartTime: (a) => a.startTime,
              getEndTime: (a) => a.endTime,
            );

            return Column(
              children: [
                if (!isCompact) _buildTimelineControls(provider),
                Expanded(
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: (e) => _onPointerUpOrCancel(e.pointer),
                    onPointerCancel: (e) => _onPointerUpOrCancel(e.pointer),
                    child: Stack(
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          physics: const ClampingScrollPhysics(),
                          child: Stack(
                            children: [
                              NotificationListener<ScrollNotification>(
                                onNotification: _handleScrollNotification,
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  scrollDirection: Axis.horizontal,
                                  physics: _isPinching
                                      ? const NeverScrollableScrollPhysics()
                                      : const ClampingScrollPhysics(),
                                  child: Container(
                                    key: _timelineContentKey,
                                    width: _getTimelineWidth(
                                            provider.totalDuration >
                                                    Duration.zero
                                                ? provider.totalDuration
                                                : const Duration(seconds: 1)) +
                                        _viewportWidth,
                                    padding: EdgeInsets.only(
                                      left: _viewportWidth / 2,
                                      right: _viewportWidth / 2,
                                    ),
                                    child: RepaintBoundary(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _buildTimeRuler(provider),
                                          for (int i = 0;
                                              i < textAllocation.trackCount;
                                              i++)
                                            _buildTextOverlayTrack(
                                                provider, i, textAllocation),
                                          for (int i = 0;
                                              i < stickerAllocation.trackCount;
                                              i++)
                                            _buildStickerTrack(
                                                provider, i, stickerAllocation),
                                          _buildVideoTracks(provider),
                                          for (int i = 0;
                                              i < overlayAllocation.trackCount;
                                              i++)
                                            _buildOverlayTrack(
                                                provider, i, overlayAllocation),
                                          for (int i = 0;
                                              i < audioAllocation.trackCount;
                                              i++)
                                            _buildAudioOverlayTrack(
                                                provider, i, audioAllocation),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                child: _buildFixedLeftTrackControlsColumn(
                                    provider,
                                    textAllocation,
                                    stickerAllocation,
                                    overlayAllocation,
                                    audioAllocation),
                              ),
                            ],
                          ),
                        ),
                        _buildCenteredPlayhead(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCenteredPlayhead() {
    return Positioned(
      left: _viewportWidth / 2 - 1,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_drop_down,
                color: AppColors.textPrimary,
                size: 10,
              ),
            ),
            Expanded(
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 4,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineHeader(VideoEditorProvider provider) {
    return Container(
      height: ResponsiveUtil.getHeight(40),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: ResponsiveUtil.paddingMedium),
        child: Text(
          'Timeline',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: ResponsiveUtil.fontSizeSmall,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildFixedLeftTrackControlsColumn(
      VideoEditorProvider provider,
      TrackAllocationResult textAllocation,
      TrackAllocationResult stickerAllocation,
      TrackAllocationResult overlayAllocation,
      TrackAllocationResult audioAllocation) {
    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(2, 0),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: _timelineHeight,
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppColors.border, width: 1)),
            ),
          ),
          for (int i = 0; i < textAllocation.trackCount; i++)
            _buildTrackControlPanel(
              textAllocation.trackCount > 1 ? 'Text ${i + 1}' : 'Text',
              Icons.text_fields,
              () => _openTextEditor(provider),
            ),
          for (int i = 0; i < stickerAllocation.trackCount; i++)
            _buildTrackControlPanel(
              stickerAllocation.trackCount > 1 ? 'Sticker ${i + 1}' : 'Stickers',
              Icons.emoji_emotions,
              () => _openStickerPanel(provider),
            ),
          _buildTrackControlPanel('Video', Icons.videocam_outlined,
              () => _openMainVideoPicker(provider)),
          for (int i = 0; i < overlayAllocation.trackCount; i++)
            _buildTrackControlPanel(
              overlayAllocation.trackCount > 1 ? 'Overlay ${i + 1}' : 'Overlay',
              Icons.layers,
              () => _openOverlayPicker(provider),
            ),
          for (int i = 0; i < audioAllocation.trackCount; i++)
            _buildTrackControlPanel(
              audioAllocation.trackCount > 1 ? 'Audio ${i + 1}' : 'Audio',
              Icons.music_note,
              () => _openAudioEditor(provider),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackControlPanel(
      String title, IconData icon, VoidCallback? onAdd) {
    return Container(
      height: _trackHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: AppColors.border.withOpacity(0.5), width: 1),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onAdd,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: AppColors.textTertiary),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (onAdd != null) ...[
                const SizedBox(height: 4),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 12,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMainVideoPicker(VideoEditorProvider provider) async {
    try {
      final medias = await MediaPickerService.openMultiple(context);
      if (medias != null) {
        for (final media in medias) {
          final file = await media.getFile();
          if (media.isVideo) {
            await provider.loadVideoFile(file);
          } else {
            await provider.loadImageFile(file);
          }
        }
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _openOverlayPicker(VideoEditorProvider provider,
      {int trackIndex = 0}) async {
    try {
      final media = await MediaPickerService.open(context);
      if (media != null) {
        final file = await media.getFile();
        await provider.addOverlayClip(file, trackIndex: trackIndex);
      }
    } catch (e) {
      // ignore for now
    }
  }

  void _openAudioEditor(VideoEditorProvider provider, {int trackIndex = 0}) {
    // Track which audio track was selected for adding new audio overlays
    provider.selectAudioTrack(trackIndex);
    if (!provider.showAudioEditor) {
      provider.toggleAudioEditor();
    }
  }

  void _openStickerPanel(VideoEditorProvider provider) {
    if (!provider.showStickerPanel) {
      provider.toggleStickerPanel();
    }
  }

  void _openTextEditor(VideoEditorProvider provider) {
    if (!provider.showTextEditor) {
      provider.toggleTextEditor();
    }
  }

  Widget _buildCanvaPlusButton({required VoidCallback onTap, String? tooltip}) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.primaryLight,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.add, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildTimeRuler(VideoEditorProvider provider) {
    final duration = provider.totalDuration;
    // Ensure minimum duration for display purposes
    final displayDuration =
        duration.inMilliseconds > 0 ? duration : const Duration(seconds: 1);

    return Container(
      height: _timelineHeight,
      decoration: const BoxDecoration(
        color: AppColors.surfaceLight,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: CustomPaint(
        painter: TimeRulerPainter(
          duration: displayDuration,
          scale: _timelineScale,
          currentPosition: provider.currentPosition,
        ),
        size: Size(_getTimelineWidth(displayDuration), _timelineHeight),
      ),
    );
  }

  Widget _buildVideoTracks(VideoEditorProvider provider) {
    return DragTarget<VideoClip>(
      key: _videoTrackKey,
      onWillAcceptWithDetails: (_) {
        return true;
      },
      onAcceptWithDetails: (details) {
        // Get the source clip from the drag data
        final draggedClip = details.data;
        final sourceIndex = provider.getClipIndexById(draggedClip.id);

        if (sourceIndex == null) return;

        // Calculate drop time from the drop offset
        final dropTime =
            _calculateDropTime(details.offset, provider.totalDuration);

        // Find which clip this drop position falls into
        final targetIndex =
            _findTargetClipIndex(provider, dropTime, sourceIndex);

        if (targetIndex != null && targetIndex != sourceIndex) {
          // Reorder clips instead of just moving the start time
          provider.reorderVideoClips(sourceIndex, targetIndex);
        } else {
          // Fallback to original behavior if no target found
          provider.moveVideoClip(draggedClip.id, dropTime);
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: _trackHeight,
          color: candidateData.isNotEmpty
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.surface,
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                height: _trackHeight,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: AppColors.border.withOpacity(0.5), width: 1),
                  ),
                ),
                child: const SizedBox.shrink(),
              ),
              // Show drop zone indicators when dragging
              if (candidateData.isNotEmpty)
                ..._buildDropZoneIndicators(provider),
              ...provider.currentProject!.videoClips
                  .map((clip) => _buildVideoClipWidget(clip, provider)),
              ..._buildBlackSections(provider),
            ],
          ),
        );
      },
    );
  }

  /// Build visual indicators for drop zones between clips
  List<Widget> _buildDropZoneIndicators(VideoEditorProvider provider) {
    if (provider.currentProject == null ||
        provider.currentProject!.videoClips.isEmpty) {
      return [];
    }

    final indicators = <Widget>[];
    final clips = provider.currentProject!.videoClips;

    // Add indicator before first clip
    if (clips.isNotEmpty) {
      final firstClipStart = _durationToPixels(clips.first.startTime);
      indicators.add(
        Positioned(
          left: firstClipStart - 2,
          top: 0,
          bottom: 0,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.6),
              border: Border.all(color: AppColors.accent, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }

    // Add indicators between clips
    for (int i = 0; i < clips.length - 1; i++) {
      final gapStart = _durationToPixels(clips[i].endTime);
      indicators.add(
        Positioned(
          left: gapStart - 2,
          top: 0,
          bottom: 0,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.6),
              border: Border.all(color: AppColors.accent, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }

    // Add indicator after last clip
    if (clips.isNotEmpty) {
      final lastClipEnd = _durationToPixels(clips.last.endTime);
      indicators.add(
        Positioned(
          left: lastClipEnd - 2,
          top: 0,
          bottom: 0,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.6),
              border: Border.all(color: AppColors.accent, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }

    return indicators;
  }

  Widget _buildTextOverlayTrack(
      VideoEditorProvider provider, int trackIndex, TrackAllocationResult textAllocation) {
    return DragTarget<TextOverlay>(
      key: ValueKey('text_track_$trackIndex'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final dropTime =
            _calculateDropTime(details.offset, provider.videoClipsDuration);
        provider.moveTextOverlay(details.data.id, dropTime);
      },
      builder: (context, candidateData, rejectedData) {
        // Determine track color based on drag state
        Color trackColor;
        if (rejectedData.isNotEmpty) {
          trackColor = AppColors.error.withOpacity(0.15); // Red for invalid
        } else if (candidateData.isNotEmpty) {
          trackColor = AppColors.textTrack.withOpacity(0.15); // Green for valid
        } else {
          trackColor = AppColors.surface;
        }

        final trackOverlays = (provider.currentProject?.textOverlays ?? [])
            .where((overlay) =>
                (textAllocation.itemToTrackMap[overlay.id] ?? 0) == trackIndex)
            .toList();

        return Container(
          height: _trackHeight,
          color: trackColor,
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                height: _trackHeight,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: AppColors.border.withOpacity(0.5), width: 1),
                  ),
                ),
                child: const SizedBox.shrink(),
              ),
              ...trackOverlays
                  .map((overlay) => _buildTextOverlayWidget(overlay, provider)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverlayTrack(
      VideoEditorProvider provider, int trackIndex, TrackAllocationResult overlayAllocation) {
    return DragTarget<OverlayClipDragData>(
      key: ValueKey('overlay_track_$trackIndex'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final draggedClip = details.data.clip;
        // Simply move the overlay clip to the drop position (free positioning like text/audio)
        final dropTime =
            _calculateDropTime(details.offset, provider.totalDuration);
        provider.moveOverlayClip(draggedClip.id, dropTime);
      },
      builder: (context, candidateData, rejectedData) {
        // Determine track color based on drag state
        Color trackColor;
        if (rejectedData.isNotEmpty) {
          trackColor = AppColors.error.withOpacity(0.15);
        } else if (candidateData.isNotEmpty) {
          trackColor = AppColors.primary.withOpacity(0.15);
        } else {
          trackColor = AppColors.surface;
        }

        final trackClips = (provider.currentProject?.overlayClips ?? [])
            .where((clip) =>
                (overlayAllocation.itemToTrackMap[clip.id] ?? 0) == trackIndex)
            .toList();

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _openOverlayPicker(provider),
          child: Container(
            height: _trackHeight,
            color: trackColor,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: _trackHeight,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: AppColors.border.withOpacity(0.5), width: 1),
                    ),
                  ),
                  child: const SizedBox.shrink(),
                ),
                ...trackClips
                    .map((clip) => _buildOverlayClipWidget(clip, provider)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStickerTrack(
      VideoEditorProvider provider, int trackIndex, TrackAllocationResult stickerAllocation) {
    return DragTarget<StickerModel>(
      key: ValueKey('sticker_track_$trackIndex'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final dropTime =
            _calculateDropTime(details.offset, provider.totalDuration);
        provider.moveSticker(details.data.id, dropTime);
      },
      builder: (context, candidateData, rejectedData) {
        Color trackColor;
        if (rejectedData.isNotEmpty) {
          trackColor = AppColors.error.withOpacity(0.15);
        } else if (candidateData.isNotEmpty) {
          trackColor = AppColors.primary.withOpacity(0.15);
        } else {
          trackColor = AppColors.surface;
        }

        final trackStickers = (provider.currentProject?.stickers ?? [])
            .where((sticker) =>
                (stickerAllocation.itemToTrackMap[sticker.id] ?? 0) == trackIndex)
            .toList();

        return Container(
          height: _trackHeight,
          color: trackColor,
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                height: _trackHeight,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: AppColors.border.withOpacity(0.5), width: 1),
                  ),
                ),
                child: const SizedBox.shrink(),
              ),
              ...trackStickers
                  .map((sticker) => _buildStickerWidget(sticker, provider)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStickerWidget(
      StickerModel sticker, VideoEditorProvider provider) {
    final left = _durationToPixels(sticker.startTime);
    final width = _durationToPixels(sticker.endTime - sticker.startTime);
    final isSelected = provider.selectedStickerId == sticker.id;

    return Positioned(
      left: left,
      top: 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          LongPressDraggable<StickerModel>(
            data: sticker,
            axis: Axis.horizontal,
            dragAnchorStrategy: (draggable, context, position) {
              final RenderBox renderBox =
                  context.findRenderObject() as RenderBox;
              final localPosition = renderBox.globalToLocal(position);
              return localPosition;
            },
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    'Sticker',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            childWhenDragging: Container(
              width: width,
              height: _trackHeight - 12,
              decoration: BoxDecoration(
                color: AppColors.border.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: GestureDetector(
              onTap: () => provider.selectSticker(
                  provider.selectedStickerId == sticker.id ? null : sticker.id),
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.primary.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                  border: isSelected
                      ? Border.all(color: AppColors.textPrimary, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Sticker',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          if (isSelected) ...[
            // Left trim handle
            Positioned(
              left: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  final delta = Duration(milliseconds: deltaMs);
                  final newStartTime = sticker.startTime + delta;

                  if (newStartTime >= Duration.zero &&
                      newStartTime <
                          sticker.endTime - const Duration(seconds: 1)) {
                    provider.updateSticker(sticker.id, startTime: newStartTime);
                  }
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(left: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_left,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
            // Right trim handle
            Positioned(
              right: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  final delta = Duration(milliseconds: deltaMs);
                  final newEndTime = sticker.endTime + delta;

                  if (newEndTime >
                      sticker.startTime + const Duration(seconds: 1)) {
                    provider.updateSticker(sticker.id, endTime: newEndTime);
                  }
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_right,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioOverlayTrack(
      VideoEditorProvider provider, int trackIndex, TrackAllocationResult audioAllocation) {
    return DragTarget<AudioOverlay>(
      key: ValueKey('audio_track_$trackIndex'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        // Use totalDuration for audio to allow extending beyond video
        final dropTime =
            _calculateDropTime(details.offset, provider.totalDuration);
        provider.moveAudioOverlay(details.data.id, dropTime);
      },
      builder: (context, candidateData, rejectedData) {
        // Determine track color based on drag state
        Color trackColor;
        if (rejectedData.isNotEmpty) {
          trackColor = AppColors.error.withOpacity(0.15); // Red for invalid
        } else if (candidateData.isNotEmpty) {
          trackColor =
              AppColors.audioTrack.withOpacity(0.15); // Green for valid
        } else {
          trackColor = AppColors.surface;
        }

        final trackAudios = (provider.currentProject?.audioOverlays ?? [])
            .where((overlay) =>
                (audioAllocation.itemToTrackMap[overlay.id] ?? 0) == trackIndex)
            .toList();

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            _openAudioEditor(provider);
          },
          child: Container(
            height: _trackHeight,
            color: trackColor,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: _trackHeight,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: AppColors.border.withOpacity(0.5), width: 1),
                    ),
                  ),
                  child: const SizedBox.shrink(),
                ),
                ...trackAudios
                    .map(
                        (overlay) => _buildAudioOverlayWidget(overlay, provider)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlayClipWidget(VideoClip clip, VideoEditorProvider provider) {
    final left = _durationToPixels(clip.startTime);
    final width = _durationToPixels(clip.duration);
    final isSelected = provider.selectedOverlayClipId == clip.id;

    return Positioned(
      left: left,
      top: 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          LongPressDraggable<OverlayClipDragData>(
            data: OverlayClipDragData(clip),
            // Use child anchor strategy to preserve relative touch position
            dragAnchorStrategy: (draggable, context, position) {
              // Get the render box of the child widget
              final RenderBox renderBox =
                  context.findRenderObject() as RenderBox;
              // Get the local position within the child
              final localPosition = renderBox.globalToLocal(position);
              // Return the offset relative to the child's origin
              return localPosition;
            },
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primaryLight, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.5),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.open_with,
                              color: AppColors.textPrimary, size: 18),
                          SizedBox(height: 2),
                          Text(
                            'Move',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            childWhenDragging: Container(
              width: width,
              height: _trackHeight - 12,
              decoration: BoxDecoration(
                color: AppColors.border.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: GestureDetector(
              onTap: () => provider.selectOverlayClip(
                  provider.selectedOverlayClipId == clip.id ? null : clip.id),
              onDoubleTap: () =>
                  _showVideoClipContextMenu(context, clip, provider),
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: isSelected
                      ? Border.all(color: AppColors.textPrimary, width: 2)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isSelected ? 2 : 4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Thumbnail strip (same as main video clips)
                      _buildClipThumbnailStrip(clip, width),

                      // Gradient overlay for readability
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.55),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Overlay label + icons
                      Positioned(
                        left: 4,
                        top: 2,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.layers,
                                color: AppColors.textPrimary, size: 9),
                            const SizedBox(width: 2),
                            Text(
                              (clip.mediaType == MediaType.image ||
                                      clip.imageFile != null)
                                  ? 'Image'
                                  : 'Video',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(blurRadius: 2, color: Colors.black),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (clip.isMuted) ...[
                              const SizedBox(width: 3),
                              const Icon(Icons.volume_off,
                                  color: AppColors.error, size: 10),
                            ],
                            if (clip.chromaKeySettings?.enabled == true) ...[
                              const SizedBox(width: 3),
                              const Icon(Icons.auto_fix_high,
                                  color: Colors.greenAccent, size: 10),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isSelected) ...[
            Positioned(
              left: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  final delta = Duration(milliseconds: deltaMs);
                  final isImage = clip.mediaType == MediaType.image || clip.imageFile != null;
                  
                  if (isImage) {
                    final newStartTime = clip.startTime + delta;
                    if (newStartTime < Duration.zero ||
                        newStartTime >= clip.endTime - const Duration(milliseconds: 100)) {
                      return;
                    }
                    provider.trimOverlayClip(clip.id, delta, clip.trimEnd);
                  } else {
                    final newTrimStart = clip.trimStart + delta;
                    if (newTrimStart < clip.sourceStart ||
                        newTrimStart >= clip.trimEnd - const Duration(milliseconds: 100)) {
                      return;
                    }
                    provider.trimOverlayClip(clip.id, newTrimStart, clip.trimEnd);
                  }
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(left: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_left,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
            Positioned(
              right: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  final delta = Duration(milliseconds: deltaMs);
                  final isImage = clip.mediaType == MediaType.image || clip.imageFile != null;
                  
                  final newTrimEnd = clip.trimEnd + delta;
                  if (newTrimEnd <= clip.trimStart + const Duration(milliseconds: 100)) {
                    return;
                  }
                  if (!isImage && newTrimEnd > clip.sourceEnd) {
                    return;
                  }
                  provider.trimOverlayClip(clip.id, clip.trimStart, newTrimEnd);
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_right,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoClipWidget(VideoClip clip, VideoEditorProvider provider) {
    final left = _durationToPixels(clip.startTime);
    final width = _durationToPixels(clip.duration);
    final isSelected = provider.selectedVideoClipId == clip.id;
    final project = provider.currentProject;
    final clipIndex =
        project?.videoClips.indexWhere((c) => c.id == clip.id) ?? -1;
    final bool hasNextClip = project != null &&
        clipIndex >= 0 &&
        clipIndex < project.videoClips.length - 1;
    final nextClip = hasNextClip ? project.videoClips[clipIndex + 1] : null;
    Transition? appliedTransition;
    if (nextClip != null && project != null) {
      for (final transition in project.transitions) {
        if (transition.clipId1 == clip.id &&
            transition.clipId2 == nextClip.id) {
          appliedTransition = transition;
          break;
        }
      }
    }

    return Positioned(
      left: left,
      top: 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          LongPressDraggable<VideoClip>(
            data: clip,
            axis: Axis.horizontal,
            // Use child anchor strategy to preserve relative touch position
            dragAnchorStrategy: (draggable, context, position) {
              // Get the render box of the child widget
              final RenderBox renderBox =
                  context.findRenderObject() as RenderBox;
              // Get the local position within the child
              final localPosition = renderBox.globalToLocal(position);
              // Return the offset relative to the child's origin
              return localPosition;
            },
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primaryLight, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.5),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.open_in_full,
                              color: AppColors.textPrimary, size: 18),
                          SizedBox(height: 2),
                          Text(
                            'Reorder',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            childWhenDragging: Container(
              width: width,
              height: _trackHeight - 12,
              decoration: BoxDecoration(
                color: AppColors.border.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: GestureDetector(
              onTap: () => provider.selectVideoClip(
                  provider.selectedVideoClipId == clip.id ? null : clip.id),
              onDoubleTap: () =>
                  _showVideoClipContextMenu(context, clip, provider),
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: isSelected
                      ? Border.all(color: AppColors.textPrimary, width: 2)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isSelected ? 2 : 4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Thumbnail strip or fallback
                      _buildClipThumbnailStrip(clip, width),

                      // Gradient overlay for readability
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.55),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Clip label + mute icon
                      Positioned(
                        left: 4,
                        top: 2,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              (clip.mediaType == MediaType.image ||
                                      clip.imageFile != null)
                                  ? 'Image'
                                  : 'Video',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(blurRadius: 2, color: Colors.black),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (clip.isMuted) ...[
                              const SizedBox(width: 3),
                              const Icon(Icons.volume_off,
                                  color: AppColors.error, size: 10),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // VN-style transition button centered on clip boundary.
          if (hasNextClip)
            Positioned(
              right: -12,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openTransitionPicker(context, provider, clip),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: appliedTransition == null
                            ? Colors.white
                            : AppColors.primary,
                        shape: BoxShape.circle,
                        border: appliedTransition == null
                            ? null
                            : Border.all(
                                color: AppColors.textPrimary,
                                width: 1.5,
                              ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(
                        appliedTransition == null
                            ? Icons.add
                            : appliedTransition.getIcon(),
                        size: appliedTransition == null ? 16 : 14,
                        color: appliedTransition == null
                            ? Colors.black87
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (appliedTransition != null)
            Positioned(
              right: -28,
              bottom: -14,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 56),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.textPrimary, width: 1),
                  ),
                  child: Text(
                    '${appliedTransition.duration.inMilliseconds}ms',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          if (isSelected) ...[
            Positioned(
              left: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  if (deltaMs == 0) return;

                  final now = DateTime.now();
                  if (_lastVideoTrimUpdate != null &&
                      now.difference(_lastVideoTrimUpdate!) <
                          _videoTrimThrottle) {
                    return;
                  }
                  _lastVideoTrimUpdate = now;

                  final delta = Duration(milliseconds: deltaMs);
                  final newTrimStart = clip.trimStart + delta;
                  if (newTrimStart < clip.sourceStart ||
                      newTrimStart >=
                          clip.trimEnd - const Duration(milliseconds: 100)) {
                    return;
                  }
                  provider.trimVideoClip(clip.id, newTrimStart, clip.trimEnd);
                },
                onHorizontalDragEnd: (_) {
                  provider.recordUndo();
                  _lastVideoTrimUpdate = null;
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(left: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_left,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
            Positioned(
              right: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  if (deltaMs == 0) return;

                  // Throttle to ~60fps to keep drag smooth
                  final now = DateTime.now();
                  if (_lastVideoTrimUpdate != null &&
                      now.difference(_lastVideoTrimUpdate!) <
                          _videoTrimThrottle) {
                    return;
                  }
                  _lastVideoTrimUpdate = now;

                  final delta = Duration(milliseconds: deltaMs);
                  final newTrimEnd = clip.trimEnd + delta;

                  if (newTrimEnd <=
                      clip.trimStart + const Duration(milliseconds: 100)) {
                    return;
                  }

                  if (clip.mediaType == MediaType.image) {
                    // Image clips can be extended freely — no source-end cap
                    provider.extendImageClipDuration(clip.id, newTrimEnd);
                  } else {
                    if (newTrimEnd > clip.sourceEnd) return;
                    provider.trimVideoClip(clip.id, clip.trimStart, newTrimEnd);
                  }
                },
                onHorizontalDragEnd: (_) {
                  // Commit undo record on drag end (not during drag)
                  provider.recordUndo();
                  _lastVideoTrimUpdate = null;
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_right,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openTransitionPicker(
    BuildContext context,
    VideoEditorProvider provider,
    VideoClip clip,
  ) {
    final project = provider.currentProject;
    if (project == null) return;
    final idx = project.videoClips.indexWhere((c) => c.id == clip.id);
    if (idx == -1 || idx >= project.videoClips.length - 1) return;
    final nextClip = project.videoClips[idx + 1];

    final existing = project.transitions
        .where((t) => t.clipId1 == clip.id && t.clipId2 == nextClip.id)
        .toList();
    final Transition? existingTransition =
        existing.isNotEmpty ? existing.first : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        TransitionType selectedType =
            existingTransition?.type ?? TransitionType.crossfade;
        Duration selectedDuration =
            existingTransition?.duration ?? const Duration(milliseconds: 500);

        return StatefulBuilder(
          builder: (ctx, setState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.swap_horiz,
                              color: AppColors.textPrimary, size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Transitions',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (existingTransition != null)
                          TextButton(
                            onPressed: () async {
                              await provider
                                  .removeTransition(existingTransition.id);
                              if (context.mounted) Navigator.pop(context);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.error,
                            ),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _transitionMenuTypes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (ctx, i) {
                          final type = _transitionMenuTypes[i];
                          final isSel = type == selectedType;
                          return InkWell(
                            onTap: () => setState(() => selectedType = type),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 82,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? AppColors.primary.withOpacity(0.2)
                                    : AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSel
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: isSel ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Transition(
                                            id: '',
                                            clipId1: '',
                                            clipId2: '',
                                            startTime: Duration.zero,
                                            type: type)
                                        .getIcon(),
                                    color: AppColors.textPrimary,
                                    size: 20,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    Transition(
                                            id: '',
                                            clipId1: '',
                                            clipId2: '',
                                            startTime: Duration.zero,
                                            type: type)
                                        .getDisplayName(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Duration',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${selectedDuration.inMilliseconds}ms',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: AppColors.border,
                        thumbColor: AppColors.textPrimary,
                        overlayColor: AppColors.primary.withOpacity(0.15),
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: selectedDuration.inMilliseconds.toDouble(),
                        min: 100,
                        max: 2000,
                        divisions: 19,
                        onChanged: (v) => setState(() => selectedDuration =
                            Duration(milliseconds: v.round())),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          var safeDuration = selectedDuration;
                          final clipLimit = Duration(
                            milliseconds:
                                (clip.duration.inMilliseconds * 0.4).floor(),
                          );
                          final nextLimit = Duration(
                            milliseconds:
                                (nextClip.duration.inMilliseconds * 0.4)
                                    .floor(),
                          );
                          if (safeDuration > clipLimit) {
                            safeDuration = clipLimit;
                          }
                          if (safeDuration > nextLimit) {
                            safeDuration = nextLimit;
                          }
                          if (safeDuration <
                              const Duration(milliseconds: 100)) {
                            safeDuration = const Duration(milliseconds: 100);
                          }

                          final start = (clip.endTime - safeDuration);
                          final startTime =
                              start.isNegative ? Duration.zero : start;

                          if (existingTransition == null) {
                            final t = Transition(
                              id: DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              clipId1: clip.id,
                              clipId2: nextClip.id,
                              type: selectedType,
                              duration: safeDuration,
                              startTime: startTime,
                            );
                            await provider.addTransition(t);
                          } else {
                            final updated = existingTransition.copyWith(
                              type: selectedType,
                              duration: safeDuration,
                              startTime: startTime,
                            );
                            await provider.updateTransition(
                                existingTransition.id, updated);
                          }

                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Apply Transition'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static const List<TransitionType> _transitionMenuTypes = [
    TransitionType.zoom,
    TransitionType.black,
    TransitionType.white,
    TransitionType.shake,
    TransitionType.light,
    TransitionType.pixelate,
    TransitionType.circle,
    TransitionType.push,
    TransitionType.pushRight,
    TransitionType.rotate1,
    TransitionType.rotate2,
    TransitionType.blink,
    TransitionType.vertical,
    TransitionType.horizontal,
  ];

  // ─── Universal Thumbnail System (instant first-frame + background fill) ────

  /// Kicks off background thumbnail generation for a video clip.
  ///
  /// Phase 1: The provider already extracted the first frame at upload time,
  /// so _buildClipThumbnailStrip can tile it instantly on the first build.
  ///
  /// Phase 2: This method generates all remaining frames in parallel batches
  /// in the background, calling setState periodically so frames appear
  /// progressively (but the clip is never blank — the first frame tiles).
  void _ensureThumbnailsForVideo(VideoClip clip) {
    if (clip.mediaType != MediaType.video || clip.videoFile == null) return;

    final path = clip.videoFile!.path;

    // Already fully done
    if (_fullyLoadedPaths.contains(path)) return;
    // Already in-progress
    if (_loadingVideoPaths.contains(path)) return;

    // Check if the service already has all frames
    if (_thumbnailService.isPreGenerated(path)) {
      _fullyLoadedPaths.add(path);
      return;
    }

    // Check if all frames are already in cache (still based on time intervals)
    final sourceStartMs = clip.sourceStart.inMilliseconds;
    final sourceEndMs = clip.sourceEnd.inMilliseconds;
    final totalExpected =
        math.max(1, ((sourceEndMs - sourceStartMs) / 3000).ceil());
    final cachedCount = _thumbnailService.getCachedFrameCount(
      videoPath: path,
      startMs: sourceStartMs,
      endMs: sourceEndMs,
    );
    if (cachedCount >= totalExpected) {
      _fullyLoadedPaths.add(path);
      _thumbnailService.markFullyGenerated(path);
      return;
    }

    // Start background generation with periodic UI updates
    _loadingVideoPaths.add(path);
    _backgroundGenerateFrames(
      path: path,
      startMs: sourceStartMs,
      endMs: sourceEndMs,
    );
  }

  /// Generates frames in parallel batches in the background.
  /// Calls setState after each batch so frames appear progressively,
  /// but the first frame is already tiled across the strip — never blank.
  Future<void> _backgroundGenerateFrames({
    required String path,
    required int startMs,
    required int endMs,
  }) async {
    // Build list of timestamps we still need
    final times = <int>[];
    for (int t = startMs; t < endMs; t += 3000) {
      if (_thumbnailService.getCached(path, t) == null) {
        times.add(t);
      }
    }

    if (times.isEmpty) {
      if (mounted) {
        setState(() {
          _fullyLoadedPaths.add(path);
          _loadingVideoPaths.remove(path);
        });
      }
      return;
    }

    // Extract in parallel batches of 6, setState after each batch
    const batchSize = 6;
    for (int i = 0; i < times.length; i += batchSize) {
      if (!mounted) return;

      final batch = times.skip(i).take(batchSize);
      await Future.wait(
        batch.map((t) => _thumbnailService.getThumbnail(
              videoPath: path,
              timeMs: t,
              maxHeight: 120,
              quality: 50,
            )),
        eagerError: false,
      );

      // Update UI after each batch so frames appear progressively
      if (mounted) {
        setState(() {});
      }
    }

    // All done
    if (mounted) {
      setState(() {
        _fullyLoadedPaths.add(path);
        _loadingVideoPaths.remove(path);
      });
    }
    _thumbnailService.markFullyGenerated(path);
  }

  /// Universal thumbnail strip renderer — works for any VideoClip type.
  ///
  /// **Instant appearance strategy:**
  /// - If 1+ frames are cached, render them immediately
  /// - If fewer frames than expected, TILE the available frames to fill
  ///   the entire strip width — no blank spaces, no spinner
  /// - As background generation adds more frames, the strip updates
  ///   seamlessly via gaplessPlayback
  Widget _buildClipThumbnailStrip(VideoClip clip, double totalWidth) {
    // 1. Handle actual Image clips
    if (clip.mediaType == MediaType.image && clip.imageFile != null) {
      return Image.file(
        clip.imageFile!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    // 2. Video clips
    if (clip.videoFile == null) {
      return Container(color: AppColors.videoTrack.withOpacity(0.7));
    }

    // Kick off background generation (non-blocking, instant return)
    _ensureThumbnailsForVideo(clip);

    final path = clip.videoFile!.path;
    final trimStartMs = clip.trimStart.inMilliseconds;
    final trimEndMs = clip.trimEnd.inMilliseconds;
    final trimDurationMs = trimEndMs - trimStartMs;

    // Fixed frame width in pixels (appears same size regardless of zoom)
    const double fixedFrameWidth = 40.0; // 40px per frame

    // Calculate how many frames fit into the total width
    final expectedFrameCount =
        math.max(1, (totalWidth / fixedFrameWidth).ceil());

    // Get whatever frames are cached right now for the trimmed range
    final thumbs = _thumbnailService.getFramesForRange(
      videoPath: path,
      startMs: trimStartMs,
      endMs: trimEndMs,
    );

    // If we have zero frames for the trimmed range, try the first frame
    // (extracted at upload time — always at timeMs=0)
    if (thumbs.isEmpty) {
      final firstFrame = _thumbnailService.getCached(path, 0);
      if (firstFrame != null) {
        // Tile the first frame across the entire strip
        return RepaintBoundary(
          child:
              _buildTiledFrameStrip(firstFrame, totalWidth, expectedFrameCount),
        );
      }
      // Truly nothing yet — solid color placeholder (shouldn't happen normally)
      return Container(color: AppColors.videoTrack.withOpacity(0.7));
    }

    // We have some real frames — render them
    final double frameWidth = totalWidth / math.max(1, expectedFrameCount);

    // If we have fewer frames than expected, fill remaining with the last frame
    return RepaintBoundary(
      child: SizedBox(
        width: totalWidth,
        height: double.infinity,
        child: Row(
          children: List.generate(expectedFrameCount, (index) {
            // Use the real frame if available, otherwise tile the last available one
            final frameData =
                index < thumbs.length ? thumbs[index] : thumbs.last;

            final isLast = index == expectedFrameCount - 1;
            if (isLast) {
              // Use Expanded for the last tile so floating-point rounding never
              // causes the Row to overflow its container.
              return Expanded(
                child: SizedBox.expand(
                  child: Image.memory(
                    frameData,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              );
            }
            return SizedBox(
              width: frameWidth,
              height: double.infinity,
              child: Image.memory(
                frameData,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Tiles a single frame image across the full strip width.
  /// Used when only the first frame is available (instant visual on upload).
  Widget _buildTiledFrameStrip(
      Uint8List frameData, double totalWidth, int tileCount) {
    final double tileWidth = totalWidth / math.max(1, tileCount);
    return SizedBox(
      width: totalWidth,
      height: double.infinity,
      child: Row(
        children: List.generate(tileCount, (index) {
          final isLast = index == tileCount - 1;
          if (isLast) {
            return Expanded(
              child: SizedBox.expand(
                child: Image.memory(
                  frameData,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            );
          }
          return SizedBox(
            width: tileWidth,
            height: double.infinity,
            child: Image.memory(
              frameData,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTextOverlayWidget(
      TextOverlay overlay, VideoEditorProvider provider) {
    final left = _durationToPixels(overlay.startTime);
    final width = _durationToPixels(overlay.endTime - overlay.startTime);
    final isSelected = provider.selectedTextOverlayId == overlay.id;

    return Positioned(
      left: left,
      top: 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          LongPressDraggable<TextOverlay>(
            data: overlay,
            axis: Axis.horizontal,
            // Use child anchor strategy to preserve relative touch position
            dragAnchorStrategy: (draggable, context, position) {
              // Get the render box of the child widget
              final RenderBox renderBox =
                  context.findRenderObject() as RenderBox;
              // Get the local position within the child
              final localPosition = renderBox.globalToLocal(position);
              // Return the offset relative to the child's origin
              return localPosition;
            },
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  color: AppColors.textTrack.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    overlay.text,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            childWhenDragging: Container(
              width: width,
              height: _trackHeight - 12,
              decoration: BoxDecoration(
                color: AppColors.border.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: GestureDetector(
              onTap: () => provider.selectTextOverlay(
                  provider.selectedTextOverlayId == overlay.id
                      ? null
                      : overlay.id),
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.textTrack
                      : AppColors.textTrack.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                  border: isSelected
                      ? Border.all(color: AppColors.textPrimary, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    overlay.text,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          if (isSelected) ...[
            // Left trim handle
            Positioned(
              left: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) {
                  _textTrimAccumulatedDeltaMs = 0;
                },
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  _updateTextOverlayTrimStart(
                    overlay.id,
                    overlay.startTime,
                    overlay.endTime,
                    deltaMs,
                  );
                },
                onHorizontalDragEnd: (_) {
                  _finalizeTextTrim();
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(left: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_left,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
            // Right trim handle
            Positioned(
              right: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) {
                  _textTrimAccumulatedDeltaMs = 0;
                },
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  _updateTextOverlayTrimEnd(
                    overlay.id,
                    overlay.startTime,
                    overlay.endTime,
                    deltaMs,
                  );
                },
                onHorizontalDragEnd: (_) {
                  _finalizeTextTrim();
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_right,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioOverlayWidget(
      AudioOverlay overlay, VideoEditorProvider provider) {
    final left = _durationToPixels(overlay.startTime);
    final width = _durationToPixels(overlay.endTime - overlay.startTime);
    final isSelected = provider.selectedAudioOverlayId == overlay.id;

    return Positioned(
      left: left,
      top: 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          LongPressDraggable<AudioOverlay>(
            data: overlay,
            // Use child anchor strategy to preserve relative touch position
            dragAnchorStrategy: (draggable, context, position) {
              // Get the render box of the child widget
              final RenderBox renderBox =
                  context.findRenderObject() as RenderBox;
              // Get the local position within the child
              final localPosition = renderBox.globalToLocal(position);
              // Return the offset relative to the child's origin
              return localPosition;
            },
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  color: AppColors.audioTrack.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: WaveformWidget(
                  waveformData: List<double>.filled(100, 0.3),
                  scale: _timelineScale,
                  isSelected: isSelected,
                  height: _trackHeight - 12,
                ),
              ),
            ),
            childWhenDragging: Container(
              width: width,
              height: _trackHeight - 12,
              decoration: BoxDecoration(
                color: AppColors.border.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: GestureDetector(
              onTap: () => provider.selectAudioOverlay(
                  provider.selectedAudioOverlayId == overlay.id
                      ? null
                      : overlay.id),
              child: Container(
                width: width,
                height: _trackHeight - 12,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.audioTrack
                      : AppColors.audioTrack.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                  border: isSelected
                      ? Border.all(color: AppColors.textPrimary, width: 2)
                      : null,
                ),
                child: FutureBuilder<List<double>>(
                  future: provider.getWaveformData(overlay.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return WaveformWidget(
                        waveformData: snapshot.data!,
                        scale: _timelineScale,
                        isSelected: isSelected,
                        height: _trackHeight - 12,
                      );
                    } else {
                      return const Center(
                        child: Icon(Icons.audiotrack,
                            size: 14, color: AppColors.textPrimary),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
          if (isSelected) ...[
            // Left trim handle
            Positioned(
              left: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) {
                  _audioTrimAccumulatedDeltaMs = 0;
                },
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  _updateAudioOverlayTrimStart(
                    overlay.id,
                    overlay.startTime,
                    overlay.endTime,
                    overlay.audioStartOffset,
                    deltaMs,
                  );
                },
                onHorizontalDragEnd: (_) {
                  _finalizeAudioTrim();
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(left: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_left,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
            // Right trim handle
            Positioned(
              right: -12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) {
                  _audioTrimAccumulatedDeltaMs = 0;
                },
                onHorizontalDragUpdate: (details) {
                  final deltaMs = (details.delta.dx / _timelineScale).round();
                  _updateAudioOverlayTrimEnd(
                    overlay.id,
                    overlay.startTime,
                    overlay.endTime,
                    deltaMs,
                  );
                },
                onHorizontalDragEnd: (_) {
                  _finalizeAudioTrim();
                },
                child: Container(
                  width: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius:
                        BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                  child: const Icon(Icons.chevron_right,
                      size: 8, color: AppColors.background),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineControls(VideoEditorProvider provider) {
    final bool hasVideoSelection = provider.selectedVideoClipId != null;
    bool isClipMuted = false;

    if (hasVideoSelection) {
      try {
        final clip = provider.currentProject!.videoClips
            .firstWhere((c) => c.id == provider.selectedVideoClipId);
        isClipMuted = clip.isMuted;
      } catch (_) {}
    }

    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: Icons.undo,
            onPressed: provider.canUndo ? () => provider.undo() : null,
            tooltip: 'Undo',
          ),
          _buildControlButton(
            icon: Icons.content_cut_outlined,
            onPressed: (provider.selectedVideoClipId != null ||
                    provider.selectedAudioOverlayId != null ||
                    provider.selectedOverlayClipId != null)
                ? () {
                    if (provider.selectedVideoClipId != null) {
                      provider.cutVideoClip(provider.selectedVideoClipId!);
                    } else if (provider.selectedAudioOverlayId != null) {
                      provider
                          .cutAudioOverlay(provider.selectedAudioOverlayId!);
                    } else if (provider.selectedOverlayClipId != null) {
                      provider.cutOverlayClip(provider.selectedOverlayClipId!);
                    }
                  }
                : null,
            tooltip: 'Cut',
          ),
          _buildCanvaPlusButton(
            onTap: _importMediaFromTimeline,
            tooltip: 'Add Media',
          ),
          _buildControlButton(
            icon: Icons.delete_outline,
            onPressed: (provider.selectedVideoClipId != null ||
                    provider.selectedAudioOverlayId != null ||
                    provider.selectedStickerId != null ||
                    provider.selectedTextOverlayId != null ||
                    provider.selectedOverlayClipId != null)
                ? () => _showDeleteDialog(context, provider)
                : null,
            tooltip: 'Delete',
          ),
          _buildControlButton(
            icon: Icons.redo,
            onPressed: provider.canRedo ? () => provider.redo() : null,
            tooltip: 'Redo',
          ),
          if (hasVideoSelection) ...[
            _buildControlButton(
              icon: isClipMuted
                  ? Icons.volume_off_outlined
                  : Icons.volume_up_outlined,
              onPressed: () =>
                  provider.toggleVideoClipMute(provider.selectedVideoClipId!),
              tooltip: isClipMuted ? 'Unmute' : 'Mute',
              color: isClipMuted ? AppColors.error : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    Color? color,
  }) {
    final isEnabled = onPressed != null;
    final iconColor = isEnabled ? (color ?? AppColors.textSecondary) : AppColors.textTertiary;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isEnabled
                ? AppColors.surfaceLight
                : AppColors.surfaceLight.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isEnabled
                  ? AppColors.border
                  : AppColors.border.withOpacity(0.4),
              width: 1,
            ),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }

  double _getTimelineWidth(Duration duration) {
    // Use the actual content duration
    final raw = duration.inMilliseconds * _timelineScale;
    // Minimum width for visibility, but don't add extra padding beyond content
    return math.max(200.0, raw);
  }

  double _durationToPixels(Duration duration) {
    return duration.inMilliseconds * _timelineScale;
  }

  /// Calculates the drop time from a global offset position.
  /// This properly accounts for scroll position and viewport padding.
  /// Clamps the result to the video duration bounds.
  Duration _calculateDropTime(Offset globalOffset, Duration maxDuration) {
    final RenderBox? timelineContentRenderBox =
        _timelineContentKey.currentContext?.findRenderObject() as RenderBox?;

    if (timelineContentRenderBox == null) {
      return Duration.zero;
    }

    // Convert global offset to local position within the timeline content
    final localPosition = timelineContentRenderBox.globalToLocal(globalOffset);

    // The timeline content has padding of _viewportWidth / 2 on each side
    // We need to account for this when calculating the actual timeline position
    final viewportPadding = _viewportWidth / 2;

    // Calculate the actual x position on the timeline
    // localPosition.dx is relative to the padded content area
    // We subtract the viewport padding to get the position relative to the timeline start
    // This ensures the drop position is always exactly where the finger was released
    final timelineX = localPosition.dx - viewportPadding;

    print('DEBUG: _calculateDropTime - localPosition.dx: ${localPosition.dx}');
    print('DEBUG: _calculateDropTime - viewportPadding: $viewportPadding');
    print('DEBUG: _calculateDropTime - timelineX: $timelineX');
    print('DEBUG: _calculateDropTime - _timelineScale: $_timelineScale');

    // Convert to duration and clamp to video duration bounds
    final dropTimeMs = (timelineX / _timelineScale).round();
    final maxMs = maxDuration.inMilliseconds;
    final result = Duration(milliseconds: dropTimeMs.clamp(0, maxMs));
    print('DEBUG: _calculateDropTime - result: $result');

    return result;
  }

  /// Finds the target index for reordering based on drop position
  /// Returns the index where the clip should be swapped with if dropped over another clip
  int? _findTargetClipIndex(
      VideoEditorProvider provider, Duration dropTime, int sourceIndex) {
    if (provider.currentProject == null ||
        provider.currentProject!.videoClips.isEmpty) {
      return null;
    }

    final clips = provider.currentProject!.videoClips;

    // Find if the drop point (center of dragged clip) falls within any other clip's bounds
    // This allows simple "place over" swapping without requiring complete drag across
    for (int i = 0; i < clips.length; i++) {
      if (i == sourceIndex) continue; // Skip the source clip itself

      final clip = clips[i];

      // Check if the drop time falls anywhere within this clip's bounds
      // This creates a more intuitive swap: just drop over a clip and it swaps
      if (dropTime >= clip.startTime && dropTime <= clip.endTime) {
        return i;
      }
    }

    // If drop is outside all clips, find the closest clip
    // This ensures clips near the drop position get swapped
    int closestIndex = -1;
    Duration closestDistance =
        const Duration(hours: 24); // Large initial distance

    for (int i = 0; i < clips.length; i++) {
      if (i == sourceIndex) continue;

      final clip = clips[i];
      // Calculate distance to the nearest edge of this clip
      Duration distance;
      if (dropTime < clip.startTime) {
        distance = clip.startTime - dropTime;
      } else if (dropTime > clip.endTime) {
        distance = dropTime - clip.endTime;
      } else {
        // Already handled above, but just in case
        distance = Duration.zero;
      }

      // Only consider clips within a reasonable threshold (e.g., 40% of average clip duration)
      int totalClipDurationMs =
          clips.fold<int>(0, (sum, c) => sum + c.duration.inMilliseconds);
      int avgClipDurationMs = totalClipDurationMs ~/ clips.length;
      final threshold =
          Duration(milliseconds: (avgClipDurationMs * 0.4).round());

      if (distance < closestDistance && distance <= threshold) {
        closestDistance = distance;
        closestIndex = i;
      }
    }

    return closestIndex >= 0 ? closestIndex : null;
  }

  Future<void> _importMediaFromTimeline() async {
    // Capture provider before async gap to satisfy use_build_context_synchronously
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    try {
      final medias = await MediaPickerService.openMultiple(context);
      if (medias != null && mounted) {
        for (final media in medias) {
          final file = await media.getFile();
          if (media.isVideo) {
            await provider.loadVideoFile(file);
          } else {
            await provider.loadImageFile(file);
          }
        }
      }
    } catch (_) {}
  }

  List<Widget> _buildBlackSections(VideoEditorProvider provider) {
    if (provider.currentProject == null ||
        provider.currentProject!.videoClips.isEmpty) {
      return [];
    }

    final clips = List<VideoClip>.from(provider.currentProject!.videoClips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final blackSections = <Widget>[];

    if (clips.first.startTime > Duration.zero) {
      final width = _durationToPixels(clips.first.startTime);
      blackSections.add(
        Positioned(
          left: 0,
          top: 12,
          child: Container(
            width: width,
            height: _trackHeight - 12,
            decoration: BoxDecoration(
              color: AppColors.border.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
            child: const Center(
              child: Icon(Icons.block, color: AppColors.textTertiary, size: 10),
            ),
          ),
        ),
      );
    }

    for (int i = 0; i < clips.length - 1; i++) {
      final currentClip = clips[i];
      final nextClip = clips[i + 1];

      if (currentClip.endTime < nextClip.startTime) {
        final left = _durationToPixels(currentClip.endTime);
        final width =
            _durationToPixels(nextClip.startTime - currentClip.endTime);

        blackSections.add(
          Positioned(
            left: left,
            top: 12,
            child: Container(
              width: width,
              height: _trackHeight - 12,
              decoration: BoxDecoration(
                color: AppColors.border.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Center(
                child:
                    Icon(Icons.block, color: AppColors.textTertiary, size: 10),
              ),
            ),
          ),
        );
      }
    }

    return blackSections;
  }

  void _showVideoClipContextMenu(
      BuildContext context, VideoClip clip, VideoEditorProvider provider) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        offset.dy + button.size.height + 200,
      ),
      items: [
        const PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.content_copy,
                  size: 16, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text('Duplicate', style: TextStyle(color: AppColors.textPrimary)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'extract_audio',
          child: Row(
            children: [
              Icon(Icons.audiotrack, size: 16, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text('Extract Audio',
                  style: TextStyle(color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
    ).then((value) {
      if (value == 'duplicate') {
        provider.duplicateVideoClip(clip.id);
      } else if (value == 'extract_audio') {
        provider.extractAudioFromVideoClip(clip.id);
      }
    });
  }

  void _showDeleteDialog(BuildContext context, VideoEditorProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete Item',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to delete the selected item?',
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
              if (provider.selectedVideoClipId != null) {
                provider.deleteVideoClip(provider.selectedVideoClipId!);
              } else if (provider.selectedAudioOverlayId != null) {
                provider.removeAudioOverlay(provider.selectedAudioOverlayId!);
              } else if (provider.selectedStickerId != null) {
                provider.removeSticker(provider.selectedStickerId!);
              } else if (provider.selectedTextOverlayId != null) {
                provider.removeTextOverlay(provider.selectedTextOverlayId!);
              } else if (provider.selectedOverlayClipId != null) {
                provider.removeOverlayClip(provider.selectedOverlayClipId!);
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class TimeRulerPainter extends CustomPainter {
  final Duration duration;
  final double scale;
  final Duration currentPosition;

  TimeRulerPainter({
    required this.duration,
    required this.scale,
    required this.currentPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double pxPerMs = scale;

    // Available time intervals for major ticks (in milliseconds)
    final List<int> majorIntervals = [
      60000, // 1 min
      30000, // 30s
      10000, // 10s
      5000,  // 5s
      2000,  // 2s
      1000,  // 1s
      500,   // 500ms
      200,   // 200ms
      100,   // 100ms
      50,    // 50ms
      20,    // 20ms
      10,    // 10ms
      5,     // 5ms
      2,     // 2ms
      1,     // 1ms
    ];

    // Find the smallest major interval that is >= 60 pixels wide
    int majorMs = 60000;
    for (final ms in majorIntervals) {
      if (ms * pxPerMs >= 60.0) {
        majorMs = ms;
      } else {
        break;
      }
    }

    // Determine sub-division divisor for minor ticks
    int divisor = 1;
    if ((majorMs / 10) * pxPerMs >= 4.0) {
      divisor = 10;
    } else if ((majorMs / 5) * pxPerMs >= 4.0) {
      divisor = 5;
    } else if ((majorMs / 2) * pxPerMs >= 4.0) {
      divisor = 2;
    }

    final double minorMs = majorMs / divisor;
    final int totalMs = duration.inMilliseconds;

    final Paint majorPaint = Paint()
      ..color = AppColors.textTertiary
      ..strokeWidth = 1.2;

    final Paint minorPaint = Paint()
      ..color = AppColors.textTertiary.withOpacity(0.4)
      ..strokeWidth = 0.8;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw ticks
    for (double ms = 0; ms <= totalMs; ms += minorMs) {
      final double x = ms * pxPerMs;
      final int msInt = ms.round();
      final bool isMajor = msInt % majorMs == 0;
      final bool isMedium = divisor == 10 && (msInt % (majorMs ~/ 2) == 0) && !isMajor;

      if (isMajor) {
        canvas.drawLine(
          Offset(x, size.height - 12),
          Offset(x, size.height),
          majorPaint,
        );

        final minutes = msInt ~/ 60000;
        final seconds = (msInt % 60000) ~/ 1000;
        final remainingMs = msInt % 1000;

        String timeText;
        if (majorMs < 1000) {
          timeText = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${remainingMs.toString().padLeft(3, '0')}';
        } else if (remainingMs > 0) {
          timeText = '${seconds.toString()}.${(remainingMs ~/ 100).toString()}s';
        } else {
          timeText = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        }

        textPainter.text = TextSpan(
          text: timeText,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        );
        textPainter.layout();

        final labelX = (x - textPainter.width / 2)
            .clamp(0.0, size.width - textPainter.width);
        textPainter.paint(
          canvas,
          Offset(labelX, size.height - 24),
        );
      } else {
        final double tickHeight = isMedium ? 8 : 5;
        canvas.drawLine(
          Offset(x, size.height - tickHeight),
          Offset(x, size.height),
          minorPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(TimeRulerPainter oldDelegate) {
    return oldDelegate.currentPosition != currentPosition ||
        oldDelegate.duration != duration ||
        oldDelegate.scale != scale;
  }
}
