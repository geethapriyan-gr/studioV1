import 'dart:io';
import 'dart:ui';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
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
  /// Process a video clip with chroma key effect
  static Future<ChromaKeyResult> processClip({
    required VideoClip clip,
    required ChromaKeySettings settings,
    Function(double)? onProgress,
  }) async {
    try {
      // Validate inputs
      final inputPath = clip.videoFile?.path ?? clip.imageFile?.path;
      if (inputPath == null) {
        return ChromaKeyResult.failure('No input video file found');
      }

      if (!settings.enabled || settings.backgroundPath == null) {
        return ChromaKeyResult.failure(
            'Chroma key is not enabled or no background set');
      }

      final backgroundPath = settings.backgroundPath!;
      final isBackgroundVideo =
          _isVideoExtension(backgroundPath.split('.').last);

      // Use parameters directly (allow higher similarity for better keying)
      double safeSimilarity = settings.similarity.clamp(0.0, 0.6);
      double safeBlend = settings.blend.clamp(0.0, 0.5);

      // Get trim parameters
      final trimStartMs = (clip.sourceStart + clip.trimStart).inMilliseconds;
      final durationMs = clip.trimmedDuration.inMilliseconds;

      final startSeconds = trimStartMs / 1000.0;
      final durationSeconds = durationMs / 1000.0;

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
          volume: clip.volume,
          position: settings.position,
          scale: settings.scale,
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
          volume: clip.volume,
          position: settings.position,
          scale: settings.scale,
        );
      }

      print('ChromaKeyService: Running FFmpeg...');

      // Execute FFmpeg
      final session = await FFmpegKit.execute(command);
      await session.getReturnCode();

      // Check output
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        final fileSize = await outputFile.length();
        print('ChromaKeyService: Output file size: $fileSize bytes');

        if (fileSize > 10000) {
          // At least 10KB for valid video
          onProgress?.call(1.0);
          return ChromaKeyResult.success(outputPath);
        }
      }

      // If we get here, something went wrong
      final logs = await session.getAllLogsAsString() ?? '';
      const errorMsg = 'FFmpeg failed. Check logs.';
      print('ChromaKeyService FFmpeg error: $logs');
      return ChromaKeyResult.failure(errorMsg);
    } catch (e) {
      print('ChromaKeyService error: $e');
      return ChromaKeyResult.failure('Error: $e');
    }
  }

  /// Build command for video background - aggressive chroma key with complete spill suppression and shadow removal
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
    required double volume,
    Offset? position,
    double? scale,
  }) {
    String audioMap = isMuted ? '-an' : '-map 0:a';
    String audioFilter = '';
    if (!isMuted && volume != 1.0) {
      audioFilter = '-af volume=$volume';
    }

    final pos = position ?? const Offset(0.5, 0.5);
    final scaleValue = scale ?? 1.0;

    // Aggressive chroma key with strong spill suppression using multiple filters
    return '-y '
        '-i "$foregroundPath" '
        '-i "$backgroundPath" '
        '-ss $startSeconds -t $durationSeconds '
        '-filter_complex "[0:v]format=rgba,chromakey=0x$keyColor:$similarity:$blend,'
        'colorbalance=rs=0.15:gs=-0.2:bs=0.15,' // Strong green spill reduction
        'hue=s=0.85,' // Desaturate to reduce green tint
        'eq=gamma_r=1.1:gamma_b=1.1:contrast=1.05,' // Enhance red/blue and contrast
        'scale=iw*$scaleValue:ih*$scaleValue[fg];'
        '[1:v]scale=iw:ih[bg];'
        '[bg][fg]overlay=(W-w)*${pos.dx}:(H-h)*${pos.dy}:shortest=1[outv]" '
        '-map "[outv]" $audioMap $audioFilter '
        '-c:v libx264 -preset fast -crf 23 '
        '-c:a aac -b:a 128k '
        '-shortest "$outputPath"';
  }

  /// Build command for image background - aggressive chroma key with complete spill suppression and shadow removal
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
    required double volume,
    Offset? position,
    double? scale,
  }) {
    String audioMap = isMuted ? '-an' : '-map 0:a';
    String audioFilter = '';
    if (!isMuted && volume != 1.0) {
      audioFilter = '-af volume=$volume';
    }

    final pos = position ?? const Offset(0.5, 0.5);
    final scaleValue = scale ?? 1.0;

    // Aggressive chroma key with strong spill suppression using multiple filters
    return '-y '
        '-i "$foregroundPath" '
        '-loop 1 -i "$backgroundPath" '
        '-ss $startSeconds -t $durationSeconds '
        '-filter_complex "[0:v]format=rgba,chromakey=0x$keyColor:$similarity:$blend,'
        'colorbalance=rs=0.15:gs=-0.2:bs=0.15,' // Strong green spill reduction
        'hue=s=0.85,' // Desaturate to reduce green tint
        'eq=gamma_r=1.1:gamma_b=1.1:contrast=1.05,' // Enhance red/blue and contrast
        'scale=iw*$scaleValue:ih*$scaleValue[fg];'
        '[1:v]scale=iw:ih[bg];'
        '[bg][fg]overlay=(W-w)*${pos.dx}:(H-h)*${pos.dy}:shortest=1[outv]" '
        '-map "[outv]" $audioMap $audioFilter '
        '-c:v libx264 -preset fast -crf 23 '
        '-c:a aac -b:a 128k '
        '-shortest "$outputPath"';
  }

  /// Check if extension is video
  static bool _isVideoExtension(String ext) {
    final e = ext.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].contains(e);
  }

  /// Cancel ongoing processing
  static Future<bool> cancel() async {
    return false; // Placeholder - actual cancellation would need session tracking
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
