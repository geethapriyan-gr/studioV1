import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';
import '../main.dart' show AppColors;

class RotateEditor extends StatefulWidget {
  const RotateEditor({super.key});

  @override
  State<RotateEditor> createState() => _RotateEditorState();
}

class _RotateEditorState extends State<RotateEditor> {
  double _currentRotation = 0.0;
  bool _currentMirrored = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentState();
  }

  void _loadCurrentState() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final selectedClipId = provider.selectedVideoClipId;

    if (selectedClipId != null && provider.currentProject != null) {
      final clips = provider.currentProject!.videoClips;
      final match = clips.where((c) => c.id == selectedClipId);
      if (match.isNotEmpty) {
        final clip = match.first;
        setState(() {
          _currentRotation = clip.rotation;
          _currentMirrored = clip.isMirrored;
        });
      }
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

  void _resetRotation() {
    setState(() {
      _currentRotation = 0.0;
    });
    _applyRotation(0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final selectedClipId = provider.selectedVideoClipId;

        if (selectedClipId == null) {
          return const Center(
            child: Text(
              'Select a video clip to rotate',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          );
        }

        final clips = provider.currentProject?.videoClips ?? const [];
        final found = clips.where((c) => c.id == selectedClipId);
        if (found.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            provider.selectVideoClip(null);
          });
          return const Center(
            child: Text(
              'Select a video clip to rotate',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          );
        }

        return Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.rotate_right,
                        color: AppColors.textSecondary, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Rotate & Mirror',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          color: AppColors.textTertiary, size: 18),
                      onPressed: _resetRotation,
                      tooltip: 'Reset Rotation',
                      padding: const EdgeInsets.all(6),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Quick Actions
                const Text(
                  'Quick Actions',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildQuickRotateButton(
                      'Left 90°',
                      Icons.rotate_left_outlined,
                      () => _rotateBy90Degrees(false),
                    ),
                    _buildQuickRotateButton(
                      'Right 90°',
                      Icons.rotate_right_outlined,
                      () => _rotateBy90Degrees(true),
                    ),
                    _buildQuickRotateButton(
                      _currentMirrored ? 'Un-Mirror' : 'Mirror H',
                      Icons.flip_outlined,
                      _toggleMirror,
                      isActive: _currentMirrored,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Fine Rotation Control
                const Text(
                  'Fine Rotation',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(
                      width: 44,
                      child: Text(
                        'Angle',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: AppColors.border,
                          thumbColor: AppColors.textPrimary,
                          overlayColor: AppColors.primary.withOpacity(0.15),
                        ),
                        child: Slider(
                          value: _currentRotation,
                          min: 0.0,
                          max: 360.0,
                          divisions: 360,
                          onChanged: (value) {
                            setState(() {
                              _currentRotation = value;
                            });
                            // Apply rotation dynamically during drag (skip undo to avoid flooding stack)
                            _applyRotation(value, skipUndo: true);
                          },
                          onChangeEnd: (value) {
                            // Record undo when user releases the slider
                            _applyRotation(value, skipUndo: false);
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${_currentRotation.toInt()}°',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Rotation Preview
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      // Visual rotation indicator
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationZ(
                              _currentRotation * (3.14159 / 180))
                            ..scale(_currentMirrored ? -1.0 : 1.0, 1.0),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                              gradient: const LinearGradient(
                                colors: [AppColors.primary, AppColors.accent],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                "F",
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
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
                              'Rotation: ${_currentRotation.toInt()}°',
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 11),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _currentMirrored
                                  ? 'Mirrored (Horizontal Flip)'
                                  : 'Normal Orientation',
                              style: const TextStyle(
                                  color: AppColors.textTertiary, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
}
