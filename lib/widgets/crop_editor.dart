import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';
import '../main.dart' show AppColors;
import 'modern_slider.dart';

class CropEditor extends StatefulWidget {
  const CropEditor({super.key});

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  double _cropLeft = 0.0;
  double _cropTop = 0.0;
  double _cropRight = 1.0;
  double _cropBottom = 1.0;
  bool _isAspectRatioLocked = false;
  double _targetAspectRatio = 16 / 9;

  // Rotation state
  double _currentRotation = 0.0;
  bool _currentMirrored = false;

  // Playback speed state
  double _currentPlaybackSpeed = 1.0;
  static const List<double> _speedOptions = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0
  ];

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
    _syncFromProvider();
  }

  void _syncFromProvider() {
    final provider = Provider.of<VideoEditorProvider>(context);
    final clipId = provider.selectedVideoClipId;

    if (clipId != null && provider.currentProject != null) {
      try {
        final clip = provider.currentProject!.videoClips
            .firstWhere((c) => c.id == clipId);
        if (clip.cropRect != null) {
          final r = clip.cropRect!;
          if ((_cropLeft - r.left).abs() > 0.001 ||
              (_cropTop - r.top).abs() > 0.001 ||
              (_cropRight - r.right).abs() > 0.001 ||
              (_cropBottom - r.bottom).abs() > 0.001) {
            setState(() {
              _cropLeft = r.left;
              _cropTop = r.top;
              _cropRight = r.right;
              _cropBottom = r.bottom;
            });
          }
        }
        // Sync rotation, mirror, speed, and reversed state
        setState(() {
          _currentRotation = clip.rotation;
          _currentMirrored = clip.isMirrored;
          _currentPlaybackSpeed = clip.playbackSpeed;
        });
      } catch (_) {}
    }
  }

  void _updateCrop() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    if (provider.selectedVideoClipId != null) {
      provider.cropVideoClip(provider.selectedVideoClipId!,
          Rect.fromLTRB(_cropLeft, _cropTop, _cropRight, _cropBottom));
    }
  }

  void _resetCrop() {
    setState(() {
      _cropLeft = 0.0;
      _cropTop = 0.0;
      _cropRight = 1.0;
      _cropBottom = 1.0;
      _isAspectRatioLocked = false;
    });
    _updateCrop();
  }

  void _resetRotation() {
    setState(() {
      _currentRotation = 0.0;
    });
    _applyRotation(0.0);
  }

  void _setPlaybackSpeed(double speed) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final selectedClipId = provider.selectedVideoClipId;
    if (selectedClipId != null) {
      provider.setVideoClipPlaybackSpeed(selectedClipId, speed);
      setState(() {
        _currentPlaybackSpeed = speed;
      });
    }
  }

  void _applyRotation(double rotation, {bool skipUndo = false}) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final selectedClipId = provider.selectedVideoClipId;

    if (selectedClipId != null) {
      provider.rotateVideoClip(selectedClipId, rotation, skipUndo: skipUndo);
    }
  }

  void _rotateBy90Degrees(bool clockwise) {
    final newRotation = clockwise
        ? (_currentRotation + 90) % 360
        : (_currentRotation - 90) % 360;

    setState(() {
      _currentRotation = newRotation < 0 ? newRotation + 360 : newRotation;
    });
    _applyRotation(_currentRotation);
  }

  void _toggleMirror() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final selectedClipId = provider.selectedVideoClipId;
    if (selectedClipId != null) {
      provider.toggleVideoClipMirror(selectedClipId);
      setState(() {
        _currentMirrored = !_currentMirrored;
      });
    }
  }

  void _setAspectRatio(double? targetRatio) {
    if (targetRatio == null) {
      setState(() => _isAspectRatioLocked = false);
      return;
    }

    final provider = Provider.of<VideoEditorProvider>(context, listen: false);

    double videoRatio = 1.0;
    if (provider.previewController != null &&
        provider.previewController!.value.isInitialized) {
      videoRatio = provider.previewController!.value.aspectRatio;
    }

    double ratioFactor = targetRatio / videoRatio;
    double newW = 1.0;
    double newH = 1.0;

    if (ratioFactor < 1.0) {
      newH = 1.0;
      newW = ratioFactor;
    } else {
      newW = 1.0;
      newH = 1.0 / ratioFactor;
    }

    setState(() {
      _isAspectRatioLocked = true;
      _targetAspectRatio = targetRatio;

      _cropLeft = (1.0 - newW) / 2;
      _cropRight = _cropLeft + newW;
      _cropTop = (1.0 - newH) / 2;
      _cropBottom = _cropTop + newH;
    });

    _updateCrop();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final clipId = provider.selectedVideoClipId;
        if (clipId == null) {
          return Center(
            child: Text(
              "Select a video clip to enable cropping",
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
                    Text(
                      "Crop & Rotate",
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh,
                          color: AppColors.textTertiary, size: 18),
                      onPressed: () {
                        _resetCrop();
                        _resetRotation();
                      },
                      tooltip: "Reset",
                      padding: const EdgeInsets.all(6),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    )
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ============ ROTATION CONTROLS SECTION ============

                      // Quick Actions - Rotate & Mirror
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildModernActionButton(
                            'Left 90°',
                            Icons.rotate_left_outlined,
                            () => _rotateBy90Degrees(false),
                          ),
                          _buildModernActionButton(
                            'Right 90°',
                            Icons.rotate_right_outlined,
                            () => _rotateBy90Degrees(true),
                          ),
                          _buildModernActionButton(
                            _currentMirrored ? 'Un-Mirror' : 'Mirror',
                            Icons.flip_outlined,
                            _toggleMirror,
                            isActive: _currentMirrored,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Fine Rotation Control
                      Text(
                        'Rotation',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      ModernSlider(
                        value: _currentRotation,
                        min: 0.0,
                        max: 360.0,
                        divisions: 360,
                        unit: '°',
                        onChanged: (value) {
                          setState(() {
                            _currentRotation = value;
                          });
                        },
                        onChangeEnd: (value) {
                          _applyRotation(value, skipUndo: false);
                        },
                      ),
                      const SizedBox(height: 12),

                      // Rotation Preview
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.rotationZ(
                                    _currentRotation * (3.14159 / 180))
                                  ..scale(_currentMirrored ? -1.0 : 1.0, 1.0),
                                child: Container(
                                  margin: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.primary,
                                        AppColors.accent
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "F",
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Angle: ${_currentRotation.toInt()}°',
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _currentMirrored
                                        ? 'Mirrored'
                                        : 'Normal',
                                    style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      Container(height: 1, color: AppColors.border),
                      const SizedBox(height: 16),

                      // ============ PLAYBACK SPEED SECTION ============

                      Text(
                        'Playback Speed',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _speedOptions.map((speed) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _buildModernSpeedButton(speed),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Container(height: 1, color: AppColors.border),
                      const SizedBox(height: 16),

                      // ============ CROP CONTROLS SECTION ============

                      // Ratio Buttons
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildModernRatioButton("Free", null),
                            _buildModernRatioButton("16:9", 16 / 9),
                            _buildModernRatioButton("9:16", 9 / 16),
                            _buildModernRatioButton("4:3", 4 / 3),
                            _buildModernRatioButton("3:4", 3 / 4),
                            _buildModernRatioButton("1:1", 1.0),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Fine-tune Sliders
                      _buildModernCropSlider("Left", _cropLeft, (v) {
                        setState(
                            () => _cropLeft = v.clamp(0.0, _cropRight - 0.05));
                        _updateCrop();
                      }),
                      const SizedBox(height: 10),
                      _buildModernCropSlider("Right", _cropRight, (v) {
                        setState(
                            () => _cropRight = v.clamp(_cropLeft + 0.05, 1.0));
                        _updateCrop();
                      }),
                      const SizedBox(height: 10),
                      _buildModernCropSlider("Top", _cropTop, (v) {
                        setState(
                            () => _cropTop = v.clamp(0.0, _cropBottom - 0.05));
                        _updateCrop();
                      }),
                      const SizedBox(height: 10),
                      _buildModernCropSlider("Bottom", _cropBottom, (v) {
                        setState(
                            () => _cropBottom = v.clamp(_cropTop + 0.05, 1.0));
                        _updateCrop();
                      }),
                      const SizedBox(height: 16),

                      // ============ REVERSE SECTION ============

                      Text(
                        'Reverse Playback',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      _buildModernReverseButton(),

                      const SizedBox(height: 16),
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

  Widget _buildReverseButton() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final clipId = provider.selectedVideoClipId;

    bool isReversed = false;

    if (clipId != null && provider.currentProject != null) {
      try {
        final clip = provider.currentProject!.videoClips
            .firstWhere((c) => c.id == clipId);
        isReversed = clip.isReversed;
        // Check if reversed file exists but not yet enabled
        if (!isReversed &&
            clip.reversedFilePath != null &&
            File(clip.reversedFilePath!).existsSync()) {
          isReversed = true; // Show as reversed if file exists
        }
      } catch (_) {}
    }

    return GestureDetector(
      onTap: () {
        if (clipId != null) {
          // Show feedback that something is happening
          provider.toggleVideoClipReverse(clipId);
          setState(() {});
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isReversed ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isReversed ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.replay,
              size: 18,
              color:
                  isReversed ? AppColors.textPrimary : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              isReversed ? 'Reversed' : 'Reverse Video',
              style: TextStyle(
                color: isReversed
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isReversed ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatioBtn(String title, double? ratio) {
    bool isSelected = (ratio == null && !_isAspectRatioLocked) ||
        (ratio != null &&
            _isAspectRatioLocked &&
            (_targetAspectRatio - ratio).abs() < 0.01);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => _setAspectRatio(ratio),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color:
                  isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(
      String label, double val, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.textPrimary,
              overlayColor: AppColors.primary.withOpacity(0.15),
            ),
            child: Slider(
              value: val,
              min: 0.0,
              max: 1.0,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickRotateButton(
      String label, IconData icon, VoidCallback onPressed,
      {bool isActive = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isActive ? AppColors.primary : AppColors.surfaceLight,
            foregroundColor: AppColors.textPrimary,
            padding: const EdgeInsets.symmetric(vertical: 8),
            minimumSize: const Size(0, 36),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(
                color: isActive ? AppColors.primary : AppColors.border,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14),
              const SizedBox(height: 2),
              Text(
                label,
                style:
                    const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernActionButton(
    String label,
    IconData icon,
    VoidCallback onPressed, {
    bool isActive = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? AppColors.primary : AppColors.border,
                width: 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withOpacity(0.2)
                        : AppColors.border.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedButton(double speed) {
    final isSelected = (_currentPlaybackSpeed - speed).abs() < 0.01;
    return GestureDetector(
      onTap: () => _setPlaybackSpeed(speed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          '${speed}x',
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildModernSpeedButton(double speed) {
    final isSelected = (_currentPlaybackSpeed - speed).abs() < 0.01;
    return GestureDetector(
      onTap: () => _setPlaybackSpeed(speed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          '${speed}x',
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildModernRatioButton(String title, double? ratio) {
    bool isSelected = (ratio == null && !_isAspectRatioLocked) ||
        (ratio != null &&
            _isAspectRatioLocked &&
            (_targetAspectRatio - ratio).abs() < 0.01);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _setAspectRatio(ratio),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            title,
            style: TextStyle(
              color:
                  isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernCropSlider(
      String label, double val, ValueChanged<double> onChanged) {
    return ModernSlider(
      value: val,
      min: 0.0,
      max: 1.0,
      divisions: 100,
      label: label,
      showValue: true,
      onChanged: onChanged,
    );
  }

  Widget _buildModernReverseButton() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final clipId = provider.selectedVideoClipId;

    bool isReversed = false;

    if (clipId != null && provider.currentProject != null) {
      try {
        final clip = provider.currentProject!.videoClips
            .firstWhere((c) => c.id == clipId);
        isReversed = clip.isReversed;
        if (!isReversed &&
            clip.reversedFilePath != null &&
            File(clip.reversedFilePath!).existsSync()) {
          isReversed = true;
        }
      } catch (_) {}
    }

    return GestureDetector(
      onTap: () {
        if (clipId != null) {
          provider.toggleVideoClipReverse(clipId);
          setState(() {});
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isReversed ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isReversed ? AppColors.primary : AppColors.border,
            width: 1,
          ),
          boxShadow: isReversed
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.replay,
              size: 20,
              color:
                  isReversed ? AppColors.textPrimary : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              isReversed ? 'Reversed' : 'Reverse Video',
              style: TextStyle(
                color: isReversed
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: isReversed ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
