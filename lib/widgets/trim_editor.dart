import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';
import '../main.dart' show AppColors;

class TrimEditor extends StatefulWidget {
  const TrimEditor({super.key});

  @override
  State<TrimEditor> createState() => _TrimEditorState();
}

class _TrimEditorState extends State<TrimEditor> {
  double _trimStartPosition = 0.0; // 0.0 to 1.0
  double _trimEndPosition = 1.0; // 0.0 to 1.0
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromProvider();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _syncFromProvider();
    }
  }

  void _syncFromProvider() {
    final provider = Provider.of<VideoEditorProvider>(context);
    final clipId = provider.selectedVideoClipId;

    if (clipId != null && provider.currentProject != null) {
      try {
        final clip = provider.currentProject!.videoClips
            .firstWhere((c) => c.id == clipId);

        final totalDuration = clip.sourceEnd - clip.sourceStart;
        if (totalDuration.inMilliseconds > 0) {
          final startMs = (clip.trimStart - clip.sourceStart).inMilliseconds;
          final endMs = (clip.trimEnd - clip.sourceStart).inMilliseconds;
          final totalMs = totalDuration.inMilliseconds;

          setState(() {
            _trimStartPosition = (startMs / totalMs).clamp(0.0, 1.0);
            _trimEndPosition = (endMs / totalMs).clamp(0.0, 1.0);
            _isInitialized = true;
          });
        }
      } catch (_) {
        _isInitialized = true;
      }
    } else {
      _isInitialized = true;
    }
  }

  void _applyLeftTrim(VideoClip clip) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);

    // Calculate the trim position based on the handle
    final totalDuration = clip.sourceEnd - clip.sourceStart;
    final trimMs = (_trimStartPosition * totalDuration.inMilliseconds).round();
    final trimPosition = clip.startTime + Duration(milliseconds: trimMs);

    provider.applyLeftTrim(clip.id, trimPosition);

    // Close the trim editor after applying
    provider.toggleTrimEditor();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Left trim applied - left portion deleted')),
    );
  }

  void _applyRightTrim(VideoClip clip) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);

    // Calculate the trim position based on the handle
    final totalDuration = clip.sourceEnd - clip.sourceStart;
    final trimMs = (_trimEndPosition * totalDuration.inMilliseconds).round();
    final trimPosition = clip.startTime + Duration(milliseconds: trimMs);

    provider.applyRightTrim(clip.id, trimPosition);

    // Close the trim editor after applying
    provider.toggleTrimEditor();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Right trim applied - right portion deleted')),
    );
  }

  void _applyTrimSplit(VideoClip clip) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);

    // Calculate trim positions
    final totalDuration = clip.sourceEnd - clip.sourceStart;
    final startTrimMs =
        (_trimStartPosition * totalDuration.inMilliseconds).round();
    final endTrimMs = (_trimEndPosition * totalDuration.inMilliseconds).round();

    final startTrim = clip.startTime + Duration(milliseconds: startTrimMs);
    final endTrim = clip.startTime + Duration(milliseconds: endTrimMs);

    provider.applyTrimSplit(clip.id, startTrim, endTrim);

    // Close the trim editor after applying
    provider.toggleTrimEditor();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Video split into two clips')),
    );
  }

  void _resetTrim() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final clipId = provider.selectedVideoClipId;

    if (clipId != null && provider.currentProject != null) {
      try {
        final clip = provider.currentProject!.videoClips
            .firstWhere((c) => c.id == clipId);

        provider.trimVideoClip(clip.id, clip.sourceStart, clip.sourceEnd);

        setState(() {
          _trimStartPosition = 0.0;
          _trimEndPosition = 1.0;
        });
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final clipId = provider.selectedVideoClipId;
        final trimMode = provider.trimMode;

        if (clipId == null) {
          return const Center(
            child: Text(
              "Select a video clip to enable trimming",
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          );
        }

        VideoClip? clip;
        try {
          clip = provider.currentProject!.videoClips
              .firstWhere((c) => c.id == clipId);
        } catch (_) {
          return const Center(
            child: Text(
              "Select a video clip to enable trimming",
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          );
        }

        return Container(
          color: AppColors.surface,
          child: Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Trim",
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildModeChip("Left", trimMode == 'left', () {
                          provider.setTrimMode('left');
                        }),
                        const SizedBox(width: 4),
                        _buildModeChip("Right", trimMode == 'right', () {
                          provider.setTrimMode('right');
                        }),
                        const SizedBox(width: 4),
                        _buildModeChip("Trim", trimMode == 'both', () {
                          provider.setTrimMode('both');
                        }),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          color: AppColors.textTertiary, size: 18),
                      onPressed: _resetTrim,
                      tooltip: "Reset",
                      padding: const EdgeInsets.all(6),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    )
                  ],
                ),
              ),

              // Trim Timeline
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Time indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_getTrimStartDuration(clip)),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            "Duration: ${_formatDuration(_getTrimDuration(clip))}",
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _formatDuration(_getTrimEndDuration(clip)),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Trim slider visualization
                      _buildTrimSlider(clip, trimMode),

                      const SizedBox(height: 16),

                      // Instructions
                      Text(
                        _getInstructionText(trimMode),
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const Spacer(),

                      // Apply button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (trimMode == 'left') {
                              _applyLeftTrim(clip!);
                            } else if (trimMode == 'right') {
                              _applyRightTrim(clip!);
                            } else {
                              _applyTrimSplit(clip!);
                            }
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(_getApplyButtonText(trimMode)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getApplyButtonText(String trimMode) {
    switch (trimMode) {
      case 'left':
        return 'Apply Left Trim';
      case 'right':
        return 'Apply Right Trim';
      case 'both':
      default:
        return 'Split Video';
    }
  }

  Widget _buildModeChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildTrimSlider(VideoClip clip, String trimMode) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 48.0;

        // Calculate handle positions
        final leftHandleX = _trimStartPosition * width;
        final rightHandleX = _trimEndPosition * width;

        return SizedBox(
          height: height + 24,
          child: Stack(
            children: [
              // Background track
              Positioned(
                left: 0,
                right: 0,
                top: 12,
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                ),
              ),

              // Selected region (trimmed area)
              if (trimMode != 'right')
                Positioned(
                  left: leftHandleX,
                  top: 12,
                  child: Container(
                    width:
                        (rightHandleX - leftHandleX).clamp(0, double.infinity),
                    height: height,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.3),
                      border: const Border(
                        top: BorderSide(color: AppColors.primary, width: 2),
                        bottom: BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                ),

              // Left handle (trim start)
              if (trimMode != 'right')
                Positioned(
                  left: leftHandleX - 12,
                  top: 0,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      final newPosition =
                          (leftHandleX + details.delta.dx) / width;
                      final clampedPosition =
                          newPosition.clamp(0.0, _trimEndPosition - 0.05);
                      setState(() {
                        _trimStartPosition = clampedPosition;
                      });
                    },
                    child: SizedBox(
                      width: 24,
                      height: height + 24,
                      child: Stack(
                        children: [
                          // Handle bar
                          Positioned(
                            left: 8,
                            top: 12,
                            bottom: 12,
                            child: Container(
                              width: 8,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          // Handle grip
                          Positioned(
                            left: 10,
                            top: (height + 24) / 2 - 8,
                            child: Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppColors.textPrimary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Right handle (trim end)
              if (trimMode != 'left')
                Positioned(
                  left: rightHandleX - 12,
                  top: 0,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      final newPosition =
                          (rightHandleX + details.delta.dx) / width;
                      final clampedPosition =
                          newPosition.clamp(_trimStartPosition + 0.05, 1.0);
                      setState(() {
                        _trimEndPosition = clampedPosition;
                      });
                    },
                    child: SizedBox(
                      width: 24,
                      height: height + 24,
                      child: Stack(
                        children: [
                          // Handle bar
                          Positioned(
                            left: 8,
                            top: 12,
                            bottom: 12,
                            child: Container(
                              width: 8,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          // Handle grip
                          Positioned(
                            left: 10,
                            top: (height + 24) / 2 - 8,
                            child: Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppColors.textPrimary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Start marker
              Positioned(
                left: leftHandleX - 1,
                top: 8,
                child: Container(
                  width: 2,
                  height: height + 8,
                  color: AppColors.primary,
                ),
              ),

              // End marker
              Positioned(
                left: rightHandleX - 1,
                top: 8,
                child: Container(
                  width: 2,
                  height: height + 8,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getInstructionText(String trimMode) {
    switch (trimMode) {
      case 'left':
        return 'Drag the handle to set trim point - left portion will be deleted';
      case 'right':
        return 'Drag the handle to set trim point - right portion will be deleted';
      case 'both':
      default:
        return 'Drag both handles to set start and end points - video will be split';
    }
  }

  Duration _getTrimStartDuration(VideoClip clip) {
    final totalDuration = clip.sourceEnd - clip.sourceStart;
    return clip.sourceStart +
        Duration(
          milliseconds:
              (_trimStartPosition * totalDuration.inMilliseconds).round(),
        );
  }

  Duration _getTrimEndDuration(VideoClip clip) {
    final totalDuration = clip.sourceEnd - clip.sourceStart;
    return clip.sourceStart +
        Duration(
          milliseconds:
              (_trimEndPosition * totalDuration.inMilliseconds).round(),
        );
  }

  Duration _getTrimDuration(VideoClip clip) {
    return _getTrimEndDuration(clip) - _getTrimStartDuration(clip);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final milliseconds = (duration.inMilliseconds % 1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(2, '0')}';
  }
}
