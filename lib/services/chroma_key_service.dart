import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/video_project.dart';
import '../models/chroma_key_settings.dart';

/// Result class for chroma key processing
class ChromaKeyResult {
  final bool success;
  final String? outputPath;
  final String? errorMessage;

  ChromaKeyResult({
    required this.success,
    this.outputPath,
    this.errorMessage,
  });

  factory ChromaKeyResult.success(String outputPath) {
    return ChromaKeyResult(success: true, outputPath: outputPath);
  }

  factory ChromaKeyResult.failure(String errorMessage) {
    return ChromaKeyResult(success: false, errorMessage: errorMessage);
  }
}

/// Modular service for chroma key (green screen) video processing
class ChromaKeyService {
  static FFmpegSession? _currentSession;

  /// Process a video clip with chroma key effect
  static Future<ChromaKeyResult> processClip({
    required VideoClip clip,
    required ChromaKeySettings settings,
    Function(double)? onProgress,
  }) async {
    try {
      // Validate inputs
      final inputPath = _resolveInputPath(clip);
      if (inputPath == null) {
        return ChromaKeyResult.failure('No input video file found');
      }
      if (!await File(inputPath).exists()) {
        return ChromaKeyResult.failure('Input video file is missing');
      }

      if (!settings.enabled || settings.backgroundPath == null) {
        return ChromaKeyResult.failure(
            'Chroma key is not enabled or no background set');
      }

      final backgroundPath = settings.backgroundPath!;
      if (!await File(backgroundPath).exists()) {
        return ChromaKeyResult.failure('Chroma key background file is missing');
      }
      final isBackgroundVideo =
          _isVideoExtension(backgroundPath.split('.').last);

      // Use parameters directly (allow higher similarity for better keying)
      double safeSimilarity = settings.similarity.clamp(0.0, 0.6);
      double safeBlend = settings.blend.clamp(0.0, 0.5);

      final sourceStart = _effectiveSourceStart(clip);
      final sourceDuration = _effectiveSourceDuration(clip, sourceStart);
      if (sourceDuration <= Duration.zero) {
        return ChromaKeyResult.failure('Clip duration is invalid');
      }

      final startSeconds = sourceStart.inMilliseconds / 1000.0;
      final durationSeconds = sourceDuration.inMilliseconds / 1000.0;
      final hasAudio = !clip.isMuted && await _hasAudioStream(inputPath);
      final canvasSize = await _getVideoCanvasSize(inputPath);

      // Create output path
      final cacheDir = await getTemporaryDirectory();
      final outputDir = Directory(path.join(cacheDir.path, 'chroma_key'));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final outputPath = path.join(outputDir.path,
          'chroma_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // Build FFmpeg command
      String command;
      if (isBackgroundVideo) {
        command = _buildVideoCommand(
          foregroundPath: inputPath,
          backgroundPath: backgroundPath,
          outputPath: outputPath,
          startSeconds: startSeconds,
          durationSeconds: durationSeconds,
          keyColor: settings.keyColorHex,
          similarity: safeSimilarity,
          blend: safeBlend,
          isMuted: clip.isMuted,
          hasAudio: hasAudio,
          volume: clip.volume,
          position: settings.position,
          scale: settings.scale,
          canvasSize: canvasSize,
        );
      } else {
        command = _buildImageCommand(
          foregroundPath: inputPath,
          backgroundPath: backgroundPath,
          outputPath: outputPath,
          startSeconds: startSeconds,
          durationSeconds: durationSeconds,
          keyColor: settings.keyColorHex,
          similarity: safeSimilarity,
          blend: safeBlend,
          isMuted: clip.isMuted,
          hasAudio: hasAudio,
          volume: clip.volume,
          position: settings.position,
          scale: settings.scale,
          canvasSize: canvasSize,
        );
      }

      // Execute FFmpeg
      final session = await _executeChromaCommand(
        command,
        durationSeconds,
        onProgress,
      );
      final returnCode = await session.getReturnCode();

      // Check output
      final outputFile = File(outputPath);
      if (ReturnCode.isSuccess(returnCode) && await outputFile.exists()) {
        final fileSize = await outputFile.length();
        if (fileSize > 10000) {
          onProgress?.call(1.0);
          return ChromaKeyResult.success(outputPath);
        }
      }

      final logs = await session.getAllLogsAsString() ?? '';
      return ChromaKeyResult.failure(
          'FFmpeg failed: ${_summarizeFfmpegError(logs)}');
    } catch (e) {
      return ChromaKeyResult.failure('Error: $e');
    }
  }

  static String? _resolveInputPath(VideoClip clip) {
    final reversedPath = clip.reversedFilePath;
    if (clip.isReversed &&
        reversedPath != null &&
        File(reversedPath).existsSync()) {
      return reversedPath;
    }
    return clip.videoFile?.path ?? clip.imageFile?.path;
  }

  static Duration _effectiveSourceStart(VideoClip clip) {
    if (clip.trimStart > Duration.zero) return clip.trimStart;
    return clip.sourceStart;
  }

  static Duration _effectiveSourceDuration(VideoClip clip, Duration start) {
    final end = clip.trimEnd > start ? clip.trimEnd : clip.sourceEnd;
    final duration = end - start;
    if (duration > Duration.zero) return duration;
    if (clip.trimmedDuration > Duration.zero) return clip.trimmedDuration;
    return clip.duration;
  }

  /// Build the shared filter_complex string used by both video and image backgrounds.
  ///
  /// KEY DESIGN DECISIONS:
  /// 1. chromakey receives raw YUV input — NOT format=rgba. The chromakey filter
  ///    is a YUV-space filter; feeding it RGBA causes wrong color matching because
  ///    FFmpeg then interprets R/G/B/A channels as Y/U/V/A instead of comparing
  ///    them in the correct colorspace.
  /// 2. Spill suppression (colorbalance/hue) is applied BEFORE chromakey so the
  ///    green fringe is desaturated first, yielding a cleaner key without those
  ///    filters accidentally touching the alpha channel produced by chromakey.
  /// 3. format=yuv420p is added at the very end (after overlay) so the final
  ///    H.264 encoder receives a format it can directly accept. H.264/MP4 has no
  ///    alpha; the overlay filter composites the keyed foreground onto the
  ///    background and the alpha is consumed there.
  /// 4. -ss is placed BEFORE the corresponding -i flag (input seek) rather than
  ///    after all inputs (output seek) for accurate, faster frame seeking.
  static String _buildFilterComplex({
    required String keyColor,
    required double similarity,
    required double blend,
    required double scaleValue,
    required Offset pos,
    required Size canvasSize,
  }) {
    final canvasWidth = _evenDimension(canvasSize.width.round());
    final canvasHeight = _evenDimension(canvasSize.height.round());

    // Step A: fit the background to the foreground video canvas without
    //         distorting its aspect ratio. It may crop, but it will not stretch.
    // Step B: apply light spill suppression on the raw YUV foreground
    //         (reduces green contamination before keying)
    // Step C: chromakey on the corrected YUV → produces YUVA (with alpha)
    // Step D: scale the keyed foreground
    // Step E: overlay keyed foreground onto that fixed canvas.
    return '[1:v]'
        'scale=$canvasWidth:$canvasHeight:force_original_aspect_ratio=increase,'
        'crop=$canvasWidth:$canvasHeight,setsar=1[ck_bg];'
        '[0:v]'
        'colorbalance=rs=0.1:gs=-0.15:bs=0.1,' // mild spill suppression
        'hue=s=0.9,' // slight desaturation of green
        'chromakey=0x$keyColor:$similarity:$blend,'
        'scale=iw*$scaleValue:ih*$scaleValue[ck_fg];'
        '[ck_bg][ck_fg]overlay=(W-w)*${pos.dx}:(H-h)*${pos.dy}:shortest=1,'
        'format=yuv420p[outv]';
  }

  /// Build command for video background
  static String _buildVideoCommand({
    required String foregroundPath,
    required String backgroundPath,
    required String outputPath,
    required double startSeconds,
    required double durationSeconds,
    required String keyColor,
    required double similarity,
    required double blend,
    required bool isMuted,
    required bool hasAudio,
    required double volume,
    Offset? position,
    double? scale,
    required Size canvasSize,
  }) {
    final String nullAudio =
        '-f lavfi -t $durationSeconds -i anullsrc=channel_layout=stereo:sample_rate=44100';
    final String audioMap = isMuted
        ? '-an'
        : hasAudio
            ? '-map 0:a'
            : '-map 2:a';
    final String audioFilter =
        (!isMuted && hasAudio && volume != 1.0) ? '-af volume=$volume' : '';
    final pos = position ?? const Offset(0.5, 0.5);
    final double scaleValue = (scale ?? 1.0).clamp(0.1, 3.0);

    final String filterComplex = _buildFilterComplex(
      keyColor: keyColor,
      similarity: similarity,
      blend: blend,
      scaleValue: scaleValue,
      pos: pos,
      canvasSize: canvasSize,
    );

    // -ss before -i for fast input seek
    return '-y '
        '-ss $startSeconds -t $durationSeconds -i "$foregroundPath" '
        '-stream_loop -1 -t $durationSeconds -i "$backgroundPath" '
        '$nullAudio '
        '-filter_complex "$filterComplex" '
        '-map "[outv]" $audioMap $audioFilter '
        '-r 30 -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p '
        '-c:a aac -b:a 128k '
        '-shortest "$outputPath"';
  }

  /// Build command for image background
  static String _buildImageCommand({
    required String foregroundPath,
    required String backgroundPath,
    required String outputPath,
    required double startSeconds,
    required double durationSeconds,
    required String keyColor,
    required double similarity,
    required double blend,
    required bool isMuted,
    required bool hasAudio,
    required double volume,
    Offset? position,
    double? scale,
    required Size canvasSize,
  }) {
    final String nullAudio =
        '-f lavfi -t $durationSeconds -i anullsrc=channel_layout=stereo:sample_rate=44100';
    final String audioMap = isMuted
        ? '-an'
        : hasAudio
            ? '-map 0:a'
            : '-map 2:a';
    final String audioFilter =
        (!isMuted && hasAudio && volume != 1.0) ? '-af volume=$volume' : '';
    final pos = position ?? const Offset(0.5, 0.5);
    final double scaleValue = (scale ?? 1.0).clamp(0.1, 3.0);

    final String filterComplex = _buildFilterComplex(
      keyColor: keyColor,
      similarity: similarity,
      blend: blend,
      scaleValue: scaleValue,
      pos: pos,
      canvasSize: canvasSize,
    );

    // -loop 1 loops the still image; -t limits its duration
    return '-y '
        '-ss $startSeconds -t $durationSeconds -i "$foregroundPath" '
        '-loop 1 -t $durationSeconds -i "$backgroundPath" '
        '$nullAudio '
        '-filter_complex "$filterComplex" '
        '-map "[outv]" $audioMap $audioFilter '
        '-r 30 -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p '
        '-c:a aac -b:a 128k '
        '-shortest "$outputPath"';
  }

  /// Check if extension is video
  static bool _isVideoExtension(String ext) {
    final e = ext.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].contains(e);
  }

  static Future<FFmpegSession> _executeChromaCommand(
    String command,
    double durationSeconds,
    Function(double)? onProgress,
  ) async {
    final completer = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeAsync(
      command,
      (completedSession) {
        if (!completer.isCompleted) {
          completer.complete(completedSession);
        }
      },
      null,
      (statistics) {
        if (onProgress == null || durationSeconds <= 0) return;
        final progress =
            (statistics.getTime() / 1000.0 / durationSeconds).clamp(0.0, 0.98);
        onProgress(progress);
      },
    );
    _currentSession = session;

    try {
      return await completer.future.timeout(
        const Duration(minutes: 4),
        onTimeout: () async {
          await session.cancel();
          throw TimeoutException('Chroma key processing timed out');
        },
      );
    } finally {
      if (identical(_currentSession, session)) {
        _currentSession = null;
      }
    }
  }

  static Future<Size> _getVideoCanvasSize(String inputPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final info = session.getMediaInformation();
      final streams = info?.getStreams() ?? [];
      for (final stream in streams) {
        final props = stream.getAllProperties();
        final isVideo = stream.getType() == 'video' ||
            (props != null && props['codec_type'] == 'video');
        if (!isVideo) continue;

        var width = stream.getWidth()?.toDouble();
        var height = stream.getHeight()?.toDouble();
        if (width != null && height != null && width > 0 && height > 0) {
          final rotation = _extractRotationDegrees(props);
          if ((rotation.abs() % 180).round() != 0) {
            final oldWidth = width;
            width = height;
            height = oldWidth;
          }
          return Size(width, height);
        }
      }
    } catch (_) {}
    return const Size(1080, 1920);
  }

  static int _evenDimension(int value) {
    if (value <= 2) return 2;
    return value.isEven ? value : value - 1;
  }

  static double _extractRotationDegrees(Map<dynamic, dynamic>? props) {
    if (props == null) return 0;

    final tags = props['tags'];
    if (tags is Map && tags['rotate'] != null) {
      return double.tryParse(tags['rotate'].toString()) ?? 0;
    }

    final sideData = props['side_data_list'];
    if (sideData is List) {
      for (final entry in sideData) {
        if (entry is! Map) continue;
        final rotation = entry['rotation'];
        if (rotation != null) {
          return double.tryParse(rotation.toString()) ?? 0;
        }
        final displayMatrix = entry['displaymatrix'];
        if (displayMatrix is String) {
          final match = RegExp(r'rotation of ([\-0-9.]+) degrees')
              .firstMatch(displayMatrix);
          if (match != null) {
            return double.tryParse(match.group(1) ?? '') ?? 0;
          }
        }
      }
    }

    return 0;
  }

  static Future<bool> _hasAudioStream(String inputPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final info = session.getMediaInformation();
      final streams = info?.getStreams() ?? [];
      for (final stream in streams) {
        final props = stream.getAllProperties();
        if (props != null && props['codec_type'] == 'audio') {
          return true;
        }
        if (stream.getType() == 'audio') return true;
      }
    } catch (_) {}
    return false;
  }

  static String _summarizeFfmpegError(String logs) {
    if (logs.trim().isEmpty) return 'no FFmpeg logs were returned';

    final lines = logs
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final important = lines.where((line) {
      final lower = line.toLowerCase();
      return lower.contains('error') ||
          lower.contains('failed') ||
          lower.contains('invalid') ||
          lower.contains('no such') ||
          lower.contains('matches no streams') ||
          lower.contains('stream map') ||
          lower.contains('unable') ||
          lower.contains('not found');
    }).toList();

    final selected = important.isNotEmpty
        ? important
        : lines.length > 12
            ? lines.sublist(lines.length - 12)
            : lines;
    final summary = selected.join('\n');
    if (summary.length <= 1200) return summary;
    return summary.substring(summary.length - 1200);
  }

  /// Cancel ongoing processing
  static Future<bool> cancel() async {
    try {
      final session = _currentSession;
      if (session == null) return false;
      await session.cancel();
      _currentSession = null;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Apply chroma key effect using CPU rendering (fallback method)
  Future<Image?> applyChromaKeyCPU(
    Image foreground,
    Image background,
    ChromaKeySettings settings,
  ) async {
    // This method is a fallback if the GPU shader fails
    // For now, we'll just return the foreground image
    // TODO: Implement CPU-based chroma key
    return foreground;
  }
}
