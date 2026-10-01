import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../main.dart' show AppColors;

/// A widget that provides real-time audio recording functionality
/// for the video editor app. Users can record voice/audio and use
/// it as an audio overlay in their video projects.
class AudioRecorderWidget extends StatefulWidget {
  /// Callback when recording is complete, provides the recorded audio file
  final Function(File audioFile)? onRecordingComplete;

  /// Callback when recording is cancelled
  final VoidCallback? onCancel;

  const AudioRecorderWidget({
    super.key,
    this.onRecordingComplete,
    this.onCancel,
  });

  @override
  State<AudioRecorderWidget> createState() => _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends State<AudioRecorderWidget> {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _hasPermission = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _timer;
  String? _recordedFilePath;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      setState(() => _hasPermission = true);
    } else {
      final result = await Permission.microphone.request();
      setState(() => _hasPermission = result.isGranted);
    }
  }

  Future<void> _startRecording() async {
    if (!_hasPermission) {
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        if (mounted) {
          _showError('Microphone permission is required to record audio');
        }
        return;
      }
      setState(() => _hasPermission = true);
    }

    try {
      // Get the app documents directory for storing recordings
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath =
          p.join(directory.path, 'recordings', 'recording_$timestamp.m4a');

      // Ensure the recordings directory exists
      final recordingsDir = Directory(p.join(directory.path, 'recordings'));
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      // Configure and start recording
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      await _recorder.start(config, path: filePath);

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
        _recordedFilePath = filePath;
      });

      // Start the timer to track recording duration
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      });
    } catch (e) {
      if (mounted) {
        _showError('Failed to start recording: $e');
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      _timer?.cancel();
      final path = await _recorder.stop();

      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      if (path != null && mounted) {
        final recordedFile = File(path);

        // Check if file exists
        if (await recordedFile.exists()) {
          widget.onRecordingComplete?.call(recordedFile);
        } else {
          _showError('Recording file not found');
        }
      }

      setState(() {
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
      if (mounted) {
        _showError('Failed to stop recording: $e');
      }
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    if (_isRecording) {
      await _recorder.stop();
    }

    // Delete the recorded file if it exists
    if (_recordedFilePath != null) {
      final file = File(_recordedFilePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    widget.onCancel?.call();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Record Audio',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!_isRecording)
                IconButton(
                  onPressed: _cancelRecording,
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.textTertiary,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Recording indicator
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecording
                  ? AppColors.error.withOpacity(0.15)
                  : AppColors.audioTrack.withOpacity(0.15),
              border: Border.all(
                color: _isRecording ? AppColors.error : AppColors.audioTrack,
                width: 3,
              ),
            ),
            child: _isProcessing
                ? Center(
                    child: CircularProgressIndicator(
                      color: AppColors.audioTrack,
                      strokeWidth: 2,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        size: 40,
                        color: _isRecording
                            ? AppColors.error
                            : AppColors.audioTrack,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isRecording ? 'Recording' : 'Tap to start',
                        style: TextStyle(
                          color: _isRecording
                              ? AppColors.error
                              : AppColors.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // Timer display
          Text(
            _formatDuration(_recordingDuration),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w300,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 20),

          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isRecording) ...[
                // Start recording button
                ElevatedButton.icon(
                  onPressed:
                      _hasPermission ? _startRecording : _checkPermission,
                  icon: Icon(
                    _hasPermission ? Icons.fiber_manual_record : Icons.mic_off,
                    size: 16,
                  ),
                  label: Text(
                      _hasPermission ? 'Start Recording' : 'Grant Permission'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.audioTrack,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ] else ...[
                // Cancel button
                OutlinedButton(
                  onPressed: _cancelRecording,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textTertiary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                // End recording button
                ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('End'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ],
          ),

          // Help text
          if (!_isRecording) ...[
            const SizedBox(height: 12),
            Text(
              ' buttonTap the above to start recording your voice or audio',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows the audio recorder as a bottom sheet modal
Future<void> showAudioRecorderSheet(
  BuildContext context, {
  required Function(File audioFile) onRecordingComplete,
}) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => AudioRecorderWidget(
      onRecordingComplete: (file) {
        Navigator.of(context).pop();
        onRecordingComplete(file);
      },
      onCancel: () => Navigator.of(context).pop(),
    ),
  );
}
