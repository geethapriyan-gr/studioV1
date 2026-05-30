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

      // Execute FFmpeg
      final session = await FFmpegKit.execute(command);
      await session.getReturnCode();

      // Check output
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        final fileSize = await outputFile.length();
        if (fileSize > 10000) {
          onProgress?.call(1.0);
          return ChromaKeyResult.success(outputPath);
        }
      }

      final logs = await session.getAllLogsAsString() ?? '';
      return ChromaKeyResult.failure('FFmpeg failed: $logs');
    } catch (e) {
      return ChromaKeyResult.failure('Error: $e');
    }
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
  }) {
    // Step A: apply light spill suppression on the raw YUV foreground
    //         (reduces green contamination before keying)
    // Step B: chromakey on the corrected YUV → produces YUVA (with alpha)
    // Step C: scale the keyed foreground
    // Step D: scale background to fill canvas
    // Step E: overlay keyed foreground onto background → format=yuv420p
    return '[0:v]'
        'colorbalance=rs=0.1:gs=-0.15:bs=0.1,'  // mild spill suppression
        'hue=s=0.9,'                              // slight desaturation of green
        'chromakey=0x$keyColor:$similarity:$blend,'
        'scale=iw*$scaleValue:ih*$scaleValue[ck_fg];'
        '[1:v]scale=iw:ih[ck_bg];'
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
    required double volume,
    Offset? position,
    double? scale,
  }) {
    final String audioMap = isMuted ? '-an' : '-map 0:a';
    final String audioFilter =
        (!isMuted && volume != 1.0) ? '-af volume=$volume' : '';
    final pos = position ?? const Offset(0.5, 0.5);
    final double scaleValue = (scale ?? 1.0).clamp(0.1, 3.0);

    final String filterComplex = _buildFilterComplex(
      keyColor: keyColor,
      similarity: similarity,
      blend: blend,
      scaleValue: scaleValue,
      pos: pos,
    );

    // -ss before -i for fast input seek
    return '-y '
        '-ss $startSeconds -t $durationSeconds -i "$foregroundPath" '
        '-i "$backgroundPath" '
        '-filter_complex "$filterComplex" '
        '-map "[outv]" $audioMap $audioFilter '
        '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p '
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
    required double volume,
    Offset? position,
    double? scale,
  }) {
    final String audioMap = isMuted ? '-an' : '-map 0:a';
    final String audioFilter =
        (!isMuted && volume != 1.0) ? '-af volume=$volume' : '';
    final pos = position ?? const Offset(0.5, 0.5);
    final double scaleValue = (scale ?? 1.0).clamp(0.1, 3.0);

    final String filterComplex = _buildFilterComplex(
      keyColor: keyColor,
      similarity: similarity,
      blend: blend,
      scaleValue: scaleValue,
      pos: pos,
    );

    // -loop 1 loops the still image; -t limits its duration
    return '-y '
        '-ss $startSeconds -t $durationSeconds -i "$foregroundPath" '
        '-loop 1 -t $durationSeconds -i "$backgroundPath" '
        '-filter_complex "$filterComplex" '
        '-map "[outv]" $audioMap $audioFilter '
        '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p '
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
