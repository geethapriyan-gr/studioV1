import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';
import '../main.dart' show AppColors;
import 'audio_recorder_widget.dart';
import 'length_prompt.dart';

class AudioOverlayEditor extends StatefulWidget {
  const AudioOverlayEditor({super.key});

  @override
  State<AudioOverlayEditor> createState() => _AudioOverlayEditorState();
}

class _AudioOverlayEditorState extends State<AudioOverlayEditor> {
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();

  File? _selectedAudioFile;
  double _volume = 1.0;
  Duration _audioStartOffset = Duration.zero;
  // Exact length of the picked/recorded file.
  Duration? _fileDuration;
  bool _fadeIn = false;
  bool _fadeOut = false;

  String? _lastSelectedId;

  @override
  void dispose() {
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final selectedId = provider.selectedAudioOverlayId;

        if (selectedId != _lastSelectedId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            setState(() {
              _lastSelectedId = selectedId;

              if (selectedId != null) {
                try {
                  final overlay = provider.currentProject!.audioOverlays
                      .firstWhere((o) => o.id == selectedId);
                  _loadOverlayData(overlay);
                } catch (_) {
                  _clearFields();
                }
              } else {
                _clearFields();
                _startTimeController.text =
                    _formatDuration(provider.currentPosition);
              }
            });
          });
        }

        return Container(
          color: AppColors.surface,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(provider),
                const SizedBox(height: 16),
                _buildAudioSelector(provider),
                if (selectedId != null) ...[
                  const SizedBox(height: 16),
                  _buildVolumeSliderContainer(provider),
                  const SizedBox(height: 12),
                  _buildFadeControls(provider),
                  const SizedBox(height: 6),
                  Text(
                    'Fades last up to 1.5 s and play in the preview and export.',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _loadOverlayData(AudioOverlay overlay) {
    _selectedAudioFile = overlay.audioFile;
    _volume = overlay.volume;
    _audioStartOffset = overlay.audioStartOffset;
    _fadeIn = overlay.fadeIn;
    _fadeOut = overlay.fadeOut;
    _startTimeController.text = _formatDuration(overlay.startTime);
    _endTimeController.text = _formatDuration(overlay.endTime);
  }

  /// Applies the volume and fades to the selected audio. Timing is edited on
  /// the timeline, so it is left untouched here (the mm:ss fields used to
  /// round it to whole seconds), and the file is never re-imported. A
  /// slider drag is one undo step.
  void _autoUpdate(VideoEditorProvider provider) {
    final id = provider.selectedAudioOverlayId;
    if (id == null) return;
    provider.updateAudioOverlay(
      id,
      volume: _volume,
      fadeIn: _fadeIn,
      fadeOut: _fadeOut,
      undoKey: 'audio-edit:$id',
    );
  }

  /// Uses a newly picked or recorded file: replaces the selected audio's
  /// file (keeping its place on the timeline), or waits for "Add".
  Future<void> _useNewFile(VideoEditorProvider provider) async {
    final id = provider.selectedAudioOverlayId;
    final file = _selectedAudioFile;
    final length = _fileDuration;
    if (id == null || file == null || length == null) return;
    AudioOverlay? overlay;
    for (final a in provider.currentProject?.audioOverlays ??
        const <AudioOverlay>[]) {
      if (a.id == id) overlay = a;
    }
    if (overlay == null) return;
    final before = provider.totalDuration;
    await provider.updateAudioOverlay(
      id,
      audioFile: file,
      endTime: overlay.startTime + length,
      audioStartOffset: Duration.zero,
    );
    if (mounted) {
      LengthPrompt.afterStretch(context, provider, before);
    }
  }

  Widget _buildHeader(VideoEditorProvider provider) {
    final isEditing = provider.selectedAudioOverlayId != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Audio Editor',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEditing)
              IconButton(
                onPressed: () => _deleteSelectedOverlay(provider),
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 18),
                tooltip: 'Delete',
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            if (!isEditing) ...[
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: () => _addAudioOverlay(provider),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Add', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        )
      ],
    );
  }

  Widget _buildAudioSelector(VideoEditorProvider provider) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildBigSquareButton(
                icon: Icons.library_music_rounded,
                iconColor: const Color(0xFFC4A1FF),
                iconBgColor: const Color(0xFFC4A1FF).withOpacity(0.15),
                label: 'Select Track',
                onTap: () => _selectAudioFile(provider),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildBigSquareButton(
                icon: Icons.mic_rounded,
                iconColor: const Color(0xFFFF8FA3),
                iconBgColor: const Color(0xFFFF8FA3).withOpacity(0.15),
                label: 'Record Audio',
                onTap: () => _showAudioRecorder(provider),
              ),
            ),
          ],
        ),
        if (_selectedAudioFile != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.music_note_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedAudioFile!.path.split('/').last,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBigSquareButton({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioRecorder(VideoEditorProvider provider) {
    showAudioRecorderSheet(
      context,
      onRecordingComplete: (File recordedFile) async {
        setState(() => _selectedAudioFile = recordedFile);

        // Get audio duration and set end time
        await _getAudioDuration(recordedFile.path);
        await _useNewFile(provider);
      },
    );
  }

  Future<void> _getAudioDuration(String filePath) async {
    final player = AudioPlayer();
    _fileDuration = null;
    try {
      await player.setFilePath(filePath);
      if (player.duration != null) {
        final audioDuration = player.duration!;
        _fileDuration = audioDuration;

        final start = _startTimeController.text.isNotEmpty
            ? _parseDuration(_startTimeController.text)
            : Duration.zero;
        final end = start + audioDuration;

        setState(() {
          _startTimeController.text = _formatDuration(start);
          _endTimeController.text = _formatDuration(end);
        });
      }
    } catch (_) {
    } finally {
      await player.dispose();
    }
  }

  Widget _buildVolumeSliderContainer(VideoEditorProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volume_up_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Master Volume',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(_volume * 100).toInt()}%',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primary.withOpacity(0.2),
              thumbColor: Colors.white,
              overlayColor: AppColors.primary.withOpacity(0.15),
            ),
            child: Slider(
              // 0..100%: the preview player cannot play louder, so the
              // export does not either.
              value: _volume.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              onChanged: (v) {
                setState(() => _volume = v);
                _autoUpdate(provider);
              },
              onChangeEnd: (_) => provider.sealUndo(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFadeControls(VideoEditorProvider provider) {
    return Row(
      children: [
        _buildToggle('Fade In', _fadeIn, (v) {
          setState(() => _fadeIn = v);
          _autoUpdate(provider);
        }),
        const SizedBox(width: 12),
        _buildToggle('Fade Out', _fadeOut, (v) {
          setState(() => _fadeOut = v);
          _autoUpdate(provider);
        }),
      ],
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: value
                ? AppColors.audioTrack.withOpacity(0.15)
                : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: value ? AppColors.audioTrack : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: value ? AppColors.audioTrack : AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (value) ...[
                const SizedBox(width: 4),
                Icon(Icons.check, size: 12, color: AppColors.audioTrack),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectAudioFile(VideoEditorProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result != null && result.files.single.path != null) {
        setState(() => _selectedAudioFile = File(result.files.single.path!));
        await _getAudioDuration(_selectedAudioFile!.path);
        await _useNewFile(provider);
      }
    } catch (e) {
      _showErrorDialog('Failed to select file: $e');
    }
  }

  Future<void> _addAudioOverlay(VideoEditorProvider provider) async {
    if (_selectedAudioFile == null) {
      _showErrorDialog('Please select an audio file');
      return;
    }

    // Get audio duration first
    final player = AudioPlayer();
    Duration audioDuration = Duration.zero;
    try {
      await player.setFilePath(_selectedAudioFile!.path);
      audioDuration = player.duration ?? Duration.zero;
    } catch (e) {
      _showErrorDialog('Failed to read audio file');
      await player.dispose();
      return;
    } finally {
      await player.dispose();
    }

    if (audioDuration == Duration.zero) {
      _showErrorDialog('Could not determine audio duration');
      return;
    }

    // New items go where the playhead is.
    final start = provider.currentPosition;
    final end = start + audioDuration;
    final before = provider.totalDuration;

    final id = await provider.addAudioOverlay(
      audioFile: _selectedAudioFile!,
      startTime: start,
      endTime: end,
      audioStartOffset: _audioStartOffset,
      volume: _volume.clamp(0.0, 1.0),
      fadeIn: _fadeIn,
      fadeOut: _fadeOut,
      trackIndex: provider.selectedAudioTrackIndex,
    );

    _clearFields();
    if (mounted) {
      // A long song on a short video: ask before making the video longer.
      await LengthPrompt.afterAdd(
          context, provider, before, TimelineItemKind.audio, id);
    }
    if (id != null) provider.selectAudioOverlay(id);
    provider.toggleTimeline();
  }

  Future<void> _deleteSelectedOverlay(VideoEditorProvider provider) async {
    if (provider.selectedAudioOverlayId != null) {
      await provider.removeAudioOverlay(provider.selectedAudioOverlayId!);
      _clearFields();
    }
  }

  void _clearFields() {
    _startTimeController.clear();
    _endTimeController.clear();
    setState(() {
      _selectedAudioFile = null;
      _volume = 1.0;
      _audioStartOffset = Duration.zero;
      _fadeIn = false;
      _fadeOut = false;
      _lastSelectedId = null;
    });
  }

  Duration _parseDuration(String timeString) {
    final parts = timeString.split(':');
    if (parts.length != 2) return Duration.zero;
    return Duration(
      minutes: int.tryParse(parts[0]) ?? 0,
      seconds: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _formatDuration(Duration d) {
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
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
        content: Text(message,
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
