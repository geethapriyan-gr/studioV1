import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide ColorFilter;
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import '../models/video_project.dart';
import '../models/chroma_key_settings.dart';
import '../models/transition.dart';
import '../models/video_effect.dart';

class ExportService {
  static Future<double> _getClipAspectRatio(VideoProject project, Duration time) async {
    VideoClip? clip;
    for (final c in project.videoClips) {
      if (c.startTime <= time && c.endTime > time) {
        clip = c;
        break;
      }
    }
    clip ??= project.videoClips.firstOrNull;
    final path = clip?.videoFile?.path;
    if (path != null) {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = await session.getMediaInformation();
      if (info != null) {
        final streams = info.getStreams();
        for (final s in streams) {
          if (s.getProperty('codec_type') == 'video' || s.getType() == 'video') {
            num w = s.getWidth() ?? 1080;
            num h = s.getHeight() ?? 1920;
            final rotMap = s.getAllProperties();
            double rot = 0;
            if (rotMap != null && rotMap['tags'] != null && rotMap['tags']['rotate'] != null) {
              rot = double.tryParse(rotMap['tags']['rotate'].toString()) ?? 0;
            }
            if ((rot % 180) != 0) {
              final temp = w; w = h; h = temp;
            }
            return (w / h).toDouble();
          }
        }
      }
    }
    return 1080.0 / 1920.0;
  }

  static Future<double> _getOverlayAspectRatio(
    VideoProject project,
    Duration time,
    int targetWidth,
    int targetHeight,
  ) async {
    final clipAspect = await _getClipAspectRatio(project, time);
    final targetAspect = targetWidth / targetHeight;

    final clipPortrait = clipAspect < 1.0;
    final targetPortrait = targetAspect < 1.0;

    if (clipPortrait != targetPortrait) {
      return targetAspect;
    }

    return clipAspect;
  }

  static Future<double?> _getMediaDuration(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = await session.getMediaInformation();
      if (info != null) {
        final durationStr = info.getDuration();
        if (durationStr != null) {
          return double.parse(durationStr);
        }
      }
    } catch (_) {}
    return null;
  }

  static dynamic _currentSession;
  static const int _defaultTargetWidth = 1920;
  static const int _defaultTargetHeight = 1080;
  static const double _defaultTargetFps = 30.0;

  static Future<String?> exportProject(
    VideoProject project,
    String outputPath, {
    void Function(double progress)? onProgress,
    int crf = 23,
    String preset = 'ultrafast',
    double videoMasterVolume = 1.0,
    double audioMasterVolume = 1.0,
    Map<String, ColorFilter>? clipColorFilters,
  }) async {
    try {
      print('Starting comprehensive export for project: ${project.name}');
      if (project.videoClips.isEmpty) {
        throw Exception('No video clips to export');
      }

      final tempDir = await getTemporaryDirectory();
      final workDir = Directory(path.join(
          tempDir.path, 'export_${DateTime.now().millisecondsSinceEpoch}'));
      await workDir.create(recursive: true);

      try {
        final outDir = Directory(path.dirname(outputPath));
        if (!await outDir.exists()) {
          await outDir.create(recursive: true);
        }
      } catch (e) {
        print('Failed to prepare output directory: $e');
      }

      String? result;

      try {
        result = await _exportComprehensiveTimeline(
          project,
          outputPath,
          workDir,
          onProgress,
          crf: crf,
          preset: preset,
          videoMasterVolume: videoMasterVolume,
          audioMasterVolume: audioMasterVolume,
          clipColorFilters: clipColorFilters,
        );
      } finally {
        try {
          await workDir.delete(recursive: true);
        } catch (e) {
          print('Cleanup warning: $e');
        }
      }

      return result;
    } catch (e) {
      print('Export failed: $e');
      throw Exception('Export failed: $e');
    }
  }

  static Future<String?> _exportComprehensiveTimeline(
      VideoProject project,
      String outputPath,
      Directory workDir,
      void Function(double progress)? onProgress,
      {int crf = 23,
      String preset = 'ultrafast',
      double videoMasterVolume = 1.0,
      double audioMasterVolume = 1.0,
      Map<String, ColorFilter>? clipColorFilters}) async {
    try {
      print('Starting comprehensive timeline export...');
      int targetW = project.outputResolution.width.toInt();
      int targetH = project.outputResolution.height.toInt();

      if (targetW == 0) targetW = _defaultTargetWidth;
      if (targetH == 0) targetH = _defaultTargetHeight;

      // Ensure even dimensions
      targetW = (targetW ~/ 2) * 2;
      targetH = (targetH ~/ 2) * 2;

      final targetFps = project.outputFrameRate <= 0
          ? _defaultTargetFps
          : project.outputFrameRate.toDouble();

      // Use software encoder for maximum compatibility
      // Hardware encoders can have stability issues
      String encoder = 'libx264';

      final processedClips = <String>[];
      final totalDuration =
          project.calculateTotalDuration().inSeconds.toDouble();

      // Get per-clip color filters from provider's internal map
      final resolvedClipColorFilters =
          Map<String, ColorFilter>.from(clipColorFilters ?? const {});

      // 1. Process Clips
      for (int i = 0; i < project.videoClips.length; i++) {
        final clip = project.videoClips[i];

        // Use per-clip filter if available, otherwise fall back to project-wide filter
        final ColorFilter clipFilter;
        if (resolvedClipColorFilters.containsKey(clip.id)) {
          clipFilter = resolvedClipColorFilters[clip.id]!;
        } else {
          clipFilter = project.colorFilter;
        }

        final processedPath = await _processClipComprehensive(
            clip, workDir, i, targetW, targetH, targetFps, crf, preset, encoder,
            (p) {
          // 40% of progress allocated to clip processing
          double base = (i / project.videoClips.length) * 0.4;
          onProgress?.call(base + (p * (0.4 / project.videoClips.length)));
        }, colorFilter: clipFilter.hasFilters ? clipFilter : project.colorFilter);

        if (processedPath == null) {
          throw Exception(
              'Failed to process clip $i: ${clip.videoFile?.path ?? clip.imageFile?.path}');
        }
        processedClips.add(processedPath);
      }

      // 2. Stitch Timeline
      final baseVideoPath = await _createTimelineBase(
          project, processedClips, workDir, encoder, (p) {
        onProgress?.call(0.4 + (p * 0.2));
      }, // 40% -> 60%
          duration: totalDuration);
      if (baseVideoPath == null) {
        throw Exception('Failed to create timeline base');
      }

      String currentVideo = baseVideoPath;

      // 3. Apply Filters and Video Effects - Always run, no gate
      final filteredPath = await _applyVideoFiltersAndEffects(
          currentVideo, project, workDir, encoder, (p) {
        onProgress?.call(0.6 + p * 0.1);
      }, // 60% -> 70%
          duration: totalDuration, targetWidth: targetW, targetHeight: targetH);
      if (filteredPath != null) {
        currentVideo = filteredPath;
      } else {
        print('Warning: Filter step returned null, continuing with unfiltered video');
      }

      // 4. Add Text Overlays
      if (project.textOverlays.isNotEmpty) {
        final textVideoPath = await _addTextOverlays(
            currentVideo, project, workDir, (p) {
          onProgress?.call(0.7 + p * 0.05); // adjusted progress range
        },
            targetWidth: targetW,
            targetHeight: targetH,
            duration: totalDuration,
            encoder: encoder,
            targetFps: targetFps);
        if (textVideoPath == null) {
          throw Exception('Failed to add text overlays');
        }
        currentVideo = textVideoPath;
      }

      // 4.5 Add Stickers
      if (project.stickers.isNotEmpty) {
        final withStickersPath = await _addStickers(
            currentVideo, project, workDir, (p) {
          onProgress?.call(0.75 + p * 0.05);
        }, targetWidth: targetW, targetHeight: targetH, duration: totalDuration, encoder: encoder, targetFps: targetFps);
        if (withStickersPath != null) {
          currentVideo = withStickersPath;
        }
      }

      // 5. Add Media Overlays
      if (project.overlayClips.isNotEmpty) {
        final mediaOverlayPath = await _addMediaOverlays(
            currentVideo, project.overlayClips, workDir, (p) {
          onProgress?.call(0.8 + p * 0.1);
        }, // 80% -> 90%
            targetWidth: targetW,
            targetHeight: targetH,
            duration: totalDuration,
            encoder: encoder);
        if (mediaOverlayPath == null) {
          throw Exception('Failed to add media overlays');
        }
        currentVideo = mediaOverlayPath;
      }

      // 6. Finalize Audio
      final finalPath = await _finalizeWithAudio(currentVideo, project,
          outputPath, encoder, videoMasterVolume, audioMasterVolume, (p) {
        onProgress?.call(0.9 + p * 0.1);
      }, // 90% -> 100%
          duration: totalDuration);
      if (finalPath == null) throw Exception('Failed to finalize with audio');

      onProgress?.call(1.0);
      print('Comprehensive export completed successfully');
      return finalPath;
    } catch (e) {
      print('Comprehensive export error: $e');
      rethrow;
    }
  }

  static Future<String?> _processClipComprehensive(
      VideoClip clip,
      Directory workDir,
      int index,
      int targetWidth,
      int targetHeight,
      double targetFps,
      int crf,
      String preset,
      String encoder,
      Function(double) onClipProgress, {ColorFilter? colorFilter}) async {
    final inputPath = clip.videoFile?.path ?? clip.imageFile?.path;
    if (inputPath == null) return null;

    final outputPath = path.join(workDir.path, 'processed_clip_$index.mp4');
    final sourceStartSeconds = (clip.trimStart.inMilliseconds) / 1000.0;
    final durationSeconds = (clip.trimmedDuration.inMilliseconds) / 1000.0;

    // Check for chroma key settings
    final chromaKeySettings = clip.chromaKeySettings;
    final hasChromaKey = chromaKeySettings != null &&
        chromaKeySettings.enabled &&
        chromaKeySettings.backgroundPath != null;

    String? backgroundPath =
        hasChromaKey ? chromaKeySettings.backgroundPath : null;

    // ============ CHROMA KEY WITH BACKGROUND ============
    if (hasChromaKey && backgroundPath != null) {
      return await _processClipWithChromaKey(
          clip,
          workDir,
          index,
          targetWidth,
          targetHeight,
          targetFps,
          encoder,
          onClipProgress,
          sourceStartSeconds,
          durationSeconds,
          chromaKeySettings,
          backgroundPath,
          outputPath);
    }
    // ============ END CHROMA KEY ============

    // Regular processing without chroma key - use the new stable method
    return await _processClipComprehensiveNoChromaKey(
        clip,
        workDir,
        index,
        targetWidth,
        targetHeight,
        targetFps,
        encoder,
        onClipProgress,
        sourceStartSeconds,
        durationSeconds,
        outputPath,
        colorFilter: colorFilter);
  }

  /// Process clip with chroma key (green screen) effect
  /// Uses a two-step approach to avoid complex filter graph crashes
  static Future<String?> _processClipWithChromaKey(
      VideoClip clip,
      Directory workDir,
      int index,
      int targetWidth,
      int targetHeight,
      double targetFps,
      String encoder,
      Function(double) onClipProgress,
      double sourceStartSeconds,
      double durationSeconds,
      ChromaKeySettings chromaKeySettings,
      String backgroundPath,
      String outputPath) async {
    final inputPath = (clip.isReversed && clip.reversedFilePath != null && File(clip.reversedFilePath!).existsSync())
        ? clip.reversedFilePath
        : (clip.videoFile?.path ?? clip.imageFile?.path);
    if (inputPath == null) return null;

    // Skip chroma key processing if disabled
    if (!chromaKeySettings.enabled ||
        chromaKeySettings.backgroundPath == null) {
      return await _processClipComprehensiveNoChromaKey(
          clip,
          workDir,
          index,
          targetWidth,
          targetHeight,
          targetFps,
          encoder,
          onClipProgress,
          sourceStartSeconds,
          durationSeconds,
          outputPath);
    }

    // Use two-step approach to avoid complex filter graph crashes:
    // Step 1: Process foreground video (scale, chromakey)
    // Step 2: Overlay on background

    final tempFgPath = path.join(workDir.path, 'chroma_fg_$index.mp4');
    final tempBgPath = path.join(workDir.path, 'chroma_bg_$index.mp4');

    // Step 1: Process foreground with chromakey
    final keyColorHex = chromaKeySettings.keyColorHex;
    final similarity = chromaKeySettings.similarity
        .clamp(0.0, 0.6)
        .toString(); // Allow up to 0.6
    final blend = chromaKeySettings.blend.toString();
    final scale = chromaKeySettings.scale.toString();

    // Build filter for foreground only
    // 1. Crop
    final r = clip.cropRect;
    String fgFilter = '';
    String currentIn = '[0:v]';
    if (r != null && r.right <= 1.001) {
      fgFilter += '${currentIn}crop=w=trunc(iw*${(r.right - r.left).clamp(0, 1)}/2)*2:h=trunc(ih*${(r.bottom - r.top).clamp(0, 1)}/2)*2:x=trunc(iw*${r.left}):y=trunc(ih*${r.top})[cropped];';
      currentIn = '[cropped]';
    }

    // 2. Mirror
    if (clip.isMirrored) {
      fgFilter += '${currentIn}hflip[mirrored];';
      currentIn = '[mirrored]';
    }

    // 3. Rotation
    if (clip.rotation != 0) {
      final double rot = clip.rotation % 360;
      if ((rot - 90).abs() < 0.1) {
        fgFilter += '${currentIn}transpose=1[rotated];';
      } else if ((rot - 180).abs() < 0.1) {
        fgFilter += '${currentIn}transpose=2,transpose=2[rotated];';
      } else if ((rot - 270).abs() < 0.1) {
        fgFilter += '${currentIn}transpose=2[rotated];';
      } else {
        fgFilter += "${currentIn}rotate=$rot*PI/180:fillcolor=black:ow='hypot(iw,ih)':oh='hypot(iw,ih)'[rotated];";
      }
      currentIn = '[rotated]';
    }

    // 4. Speed
    if (clip.playbackSpeed != 1.0) {
      fgFilter += '${currentIn}setpts=PTS/${clip.playbackSpeed}[speedv];';
      currentIn = '[speedv]';
    }

    fgFilter += '${currentIn}scale=w=$targetWidth:h=$targetHeight:force_original_aspect_ratio=decrease,pad=$targetWidth:$targetHeight:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1';
    fgFilter += ',format=rgba,chromakey=0x$keyColorHex:$similarity:$blend';
    fgFilter += ',scale=iw*$scale:ih*$scale'; // Apply scale
    fgFilter += ',format=yuv420p';

    final double speed = clip.playbackSpeed;
    final totalDurationSeconds = durationSeconds;
    final outputDurationSeconds = durationSeconds / speed;
    final String nullAudio = '-f lavfi -t $outputDurationSeconds -i anullsrc=channel_layout=stereo:sample_rate=44100';

    bool hasAudio = false;
    if (clip.mediaType == MediaType.video && inputPath != null) {
      hasAudio = await _hasAudioStream(inputPath);
    }

    String fgCommand;
    if (clip.mediaType == MediaType.video) {
      String audioMap = clip.isMuted || !hasAudio ? '-map 1:a' : '-map 0:a';
      
      List<String> aFilters = [];
      if (!clip.isMuted && hasAudio) {
        if (clip.volume != 1.0) aFilters.add('volume=${clip.volume}');
        if (speed != 1.0) {
          double tempSpeed = speed;
          while (tempSpeed > 2.0) {
            aFilters.add('atempo=2.0');
            tempSpeed /= 2.0;
          }
          while (tempSpeed < 0.5) {
            aFilters.add('atempo=0.5');
            tempSpeed /= 0.5;
          }
          aFilters.add('atempo=$tempSpeed');
        }
      }
      
      String audioFilter = aFilters.isNotEmpty ? '-af "${aFilters.join(',')}"' : '';

      fgCommand =
          '-y -ss $sourceStartSeconds -t $totalDurationSeconds -i "$inputPath" $nullAudio '
          '-filter_complex "$fgFilter" $audioMap $audioFilter '
          '-c:v $encoder -b:v 5M -c:a aac -ar 44100 -ac 2 -shortest "$tempFgPath"';
    } else {
      fgCommand = '-y -loop 1 -t $outputDurationSeconds -i "$inputPath" $nullAudio '
          '-filter_complex "$fgFilter" '
          '-map 0:v -map 1:a -c:v $encoder -b:v 5M -c:a aac -ar 44100 -ac 2 -shortest "$tempFgPath"';
    }

    print('Chroma Key Step 1 (Foreground): $fgCommand');
    var result = await _executeFFmpeg(fgCommand, null, outputPath: tempFgPath);
    if (result == null) {
      print('Step 1 failed - falling back to regular export');
      return await _processClipComprehensiveNoChromaKey(
          clip,
          workDir,
          index,
          targetWidth,
          targetHeight,
          targetFps,
          encoder,
          onClipProgress,
          sourceStartSeconds,
          durationSeconds,
          outputPath);
    }

    // Step 2: Create background (loop image/video to duration)
    final isBgVideo = _isVideoExtension(backgroundPath.split('.').last);

    String bgCommand;
    if (isBgVideo) {
      // For video background - simplify, no looping needed since we're trimming to duration
      bgCommand =
          '-y -ss $sourceStartSeconds -t $totalDurationSeconds -i "$backgroundPath" '
          '-vf "scale=w=$targetWidth:h=$targetHeight:force_original_aspect_ratio=cover,format=yuv420p" '
          '-c:v $encoder -b:v 5M "$tempBgPath"';
    } else {
      // For image background - loop it
      bgCommand = '-y -loop 1 -t $totalDurationSeconds -i "$backgroundPath" '
          '-vf "scale=w=$targetWidth:h=$targetHeight:force_original_aspect_ratio=cover,format=yuv420p" '
          '-c:v $encoder -b:v 5M "$tempBgPath"';
    }

    print('Chroma Key Step 2 (Background): $bgCommand');
    result = await _executeFFmpeg(bgCommand, null, outputPath: tempBgPath);
    if (result == null) {
      print('Step 2 failed - falling back to regular export');
      return await _processClipComprehensiveNoChromaKey(
          clip,
          workDir,
          index,
          targetWidth,
          targetHeight,
          targetFps,
          encoder,
          onClipProgress,
          sourceStartSeconds,
          durationSeconds,
          outputPath);
    }

    // Step 3: Overlay foreground on background
    final position = chromaKeySettings.position;
    final overlayX = '(W-w)*${position.dx}';
    final overlayY = '(H-h)*${position.dy}';
    final overlayCommand = '-y -i "$tempFgPath" -i "$tempBgPath" '
        '-filter_complex "[0:v][1:v]overlay=$overlayX:$overlayY[out]" '
        '-map "[out]" -map 0:a '
        '-c:v $encoder -b:v 5M -c:a aac -ar 44100 -ac 2 -shortest "$outputPath"';

    print('Chroma Key Step 3 (Overlay): $overlayCommand');
    result = await _executeFFmpeg(overlayCommand, onClipProgress,
        outputPath: outputPath, duration: outputDurationSeconds);

    // Clean up temp files
    try {
      await File(tempFgPath).delete();
      await File(tempBgPath).delete();
    } catch (_) {}

    return result;
  }

  /// Process clip without chroma key - extracted for reuse
  static Future<String?> _processClipComprehensiveNoChromaKey(
      VideoClip clip,
      Directory workDir,
      int index,
      int targetWidth,
      int targetHeight,
      double targetFps,
      String encoder,
      Function(double) onClipProgress,
      double sourceStartSeconds,
      double durationSeconds,
      String outputPath, {
      ColorFilter? colorFilter}) async {
    final inputPath = (clip.isReversed && clip.reversedFilePath != null && File(clip.reversedFilePath!).existsSync())
        ? clip.reversedFilePath
        : (clip.videoFile?.path ?? clip.imageFile?.path);
    if (inputPath == null) return null;

    final filters = <String>[];
    String inputFilter = '[0:v]';

    // Apply crop
    if (clip.cropRect != null) {
      final r = clip.cropRect!;
      if (r.right <= 1.001) {
        filters.add(
            '${inputFilter}crop=w=trunc(iw*${(r.right - r.left).clamp(0, 1)}/2)*2:h=trunc(ih*${(r.bottom - r.top).clamp(0, 1)}/2)*2:x=trunc(iw*${r.left}):y=trunc(ih*${r.top})[cropped]');
        inputFilter = '[cropped]';
      }
    }

    // Apply mirror
    if (clip.isMirrored) {
      filters.add('${inputFilter}hflip[mirrored]');
      inputFilter = '[mirrored]';
    }

    // Apply rotation
    if (clip.rotation != 0) {
      final double rot = clip.rotation % 360;
      if ((rot - 90).abs() < 0.1) {
        filters.add('${inputFilter}transpose=1[rotated]');
      } else if ((rot - 180).abs() < 0.1) {
        filters.add('${inputFilter}transpose=2,transpose=2[rotated]');
      } else if ((rot - 270).abs() < 0.1) {
        filters.add('${inputFilter}transpose=2[rotated]');
      } else {
        filters.add("${inputFilter}rotate=$rot*PI/180:fillcolor=black:ow='hypot(iw,ih)':oh='hypot(iw,ih)'[rotated]");
      }
      inputFilter = '[rotated]';
    }

    // Apply speed
    if (clip.playbackSpeed != 1.0) {
      filters.add('${inputFilter}setpts=PTS/${clip.playbackSpeed}[speedv]');
      inputFilter = '[speedv]';
    }

    // Scale and Pad (preserve user crop by adding black bars instead of zooming in)
    filters.add(
        '${inputFilter}scale=w=$targetWidth:h=$targetHeight:force_original_aspect_ratio=decrease,pad=$targetWidth:$targetHeight:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1[scaled]');
    inputFilter = '[scaled]';


    // === BAKED COLOR FILTERS - matching preview exactly ===
    if (colorFilter != null && colorFilter.hasFilters) {
      final mat = _calculateColorMatrix(colorFilter);

      // Simulate the UI's Stack overlay Container for Warmth/Tint!
      // The preview UI overlays a colored container AFTER the ColorFilter. 
      // We must mathematically blend this into the FFmpeg filters.
      double ovR = 0.5; double ovG = 0.5; double ovB = 0.5;
      if (colorFilter.warmth != 0.0) {
        ovR += colorFilter.warmth * 0.2;
        ovB -= colorFilter.warmth * 0.2;
      }
      if (colorFilter.tint != 0.0) {
        ovG += colorFilter.tint * 0.1;
      }
      ovR = ovR.clamp(0.0, 1.0);
      ovG = ovG.clamp(0.0, 1.0);
      ovB = ovB.clamp(0.0, 1.0);

      double opacity = 0.0;
      if (colorFilter.warmth != 0.0) opacity += colorFilter.warmth.abs() * 0.2;
      if (colorFilter.tint != 0.0) opacity += colorFilter.tint.abs() * 0.2;
      opacity = opacity.clamp(0.0, 0.4);
      final invAlpha = 1.0 - opacity;

      // Channel multipliers → colorchannelmixer (scaled by (1 - opacity))
      final rr = mat[0] * invAlpha; final rg = mat[1] * invAlpha; final rb = mat[2] * invAlpha;
      final gr = mat[5] * invAlpha; final gg = mat[6] * invAlpha; final gb = mat[7] * invAlpha;
      final br = mat[10] * invAlpha; final bg = mat[11] * invAlpha; final bb = mat[12] * invAlpha;

      // Offsets: (originalOffset * invAlpha) + (overlayColorPixels * opacity)
      final roVal = (mat[4] * invAlpha) + (ovR * 255.0 * opacity);
      final goVal = (mat[9] * invAlpha) + (ovG * 255.0 * opacity);
      final boVal = (mat[14] * invAlpha) + (ovB * 255.0 * opacity);

      // FFmpeg Gotcha: colorchannelmixer converts back to input format (yuv420p).
      // Then `geq=r=... g=... b=...` forces output to RGB, BUT it blindly evaluates r(X,Y)
      // from the 0th input plane (Y), g(X,Y) from U, and b(X,Y) from V!
      // This maps Y->Red, U->Green, V->Blue, which creates a massive VIOLET filter.
      // Solution: explicitly format to rgb24 BEFORE applying color multipliers and offsets.
      filters.add('${inputFilter}format=rgb24[rgb_in]');
      inputFilter = '[rgb_in]';

      // Apply color channel mixing (RGB multipliers)
      filters.add('${inputFilter}colorchannelmixer=rr=$rr:rg=$rg:rb=$rb:gr=$gr:gg=$gg:gb=$gb:br=$br:bg=$bg:bb=$bb[ccm_out]');
      inputFilter = '[ccm_out]';

      // Apply color offsets
      if (roVal.abs() > 0.001 || goVal.abs() > 0.001 || boVal.abs() > 0.001) {
        final ro = roVal.toStringAsFixed(4);
        final go = goVal.toStringAsFixed(4);
        final bo = boVal.toStringAsFixed(4);
        filters.add("${inputFilter}geq=r='clip(r(X,Y)+$ro,0,255)':g='clip(g(X,Y)+$go,0,255)':b='clip(b(X,Y)+$bo,0,255)'[geq_out]");
        inputFilter = '[geq_out]';
      }
    }
    // === END BAKED COLOR FILTERS ===

    // Format final processing back to yuv420p for standard mp4 encoding
    filters.add('${inputFilter}fps=$targetFps,format=yuv420p[final_out]');

    String command;
    final double speed = clip.playbackSpeed;
    final outputDurationSeconds = durationSeconds / speed;
    final totalDurationSeconds = durationSeconds;
    final String nullAudio = '-f lavfi -t $outputDurationSeconds -i anullsrc=channel_layout=stereo:sample_rate=44100';
    
    bool hasAudio = false;
    if (clip.mediaType == MediaType.video && inputPath != null) {
      hasAudio = await _hasAudioStream(inputPath);
    }
    
    if (clip.mediaType == MediaType.video) {
      String audioMap = clip.isMuted || !hasAudio ? '-map 1:a' : '-map 0:a';
      List<String> aFilters = [];
      if (!clip.isMuted && hasAudio) {
        if (clip.volume != 1.0) aFilters.add('volume=${clip.volume}');
        if (speed != 1.0) {
          double tempSpeed = speed;
          while (tempSpeed > 2.0) {
            aFilters.add('atempo=2.0');
            tempSpeed /= 2.0;
          }
          while (tempSpeed < 0.5) {
            aFilters.add('atempo=0.5');
            tempSpeed /= 0.5;
          }
          aFilters.add('atempo=$tempSpeed');
        }
      }
      
      String audioFilter = aFilters.isNotEmpty ? '-af "${aFilters.join(',')}"' : '';

      command =
          '-y -ss $sourceStartSeconds -t $totalDurationSeconds -i "$inputPath" $nullAudio -filter_complex "${filters.join(',')}" -map "[final_out]" $audioMap $audioFilter -c:v $encoder -b:v 5M -c:a aac -ar 44100 -ac 2 -shortest "$outputPath"';
    } else {
      command =
          '-y -loop 1 -t $outputDurationSeconds -i "$inputPath" $nullAudio -filter_complex "${filters.join(',')}" -map "[final_out]" -map 1:a -c:v $encoder -b:v 5M -c:a aac -ar 44100 -ac 2 -shortest "$outputPath"';
    }

    print('Clip $index FFmpeg command: $command');
    return await _executeFFmpeg(command, onClipProgress,
        outputPath: outputPath, duration: outputDurationSeconds);
  }

  static Future<bool> _hasAudioStream(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = await session.getMediaInformation();
      if (info != null) {
        final streams = info.getStreams();
        for (var stream in streams) {
          final props = stream.getAllProperties();
          if (props != null && props['codec_type'] == 'audio') {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Check if extension is a video file
  static bool _isVideoExtension(String ext) {
    final e = ext.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].contains(e);
  }

  static Future<String?> _createTimelineBase(
    VideoProject project,
    List<String> processedClips,
    Directory workDir,
    String encoder,
    Function(double) onProgress, {
    required double duration,
  }) async {
    if (processedClips.isEmpty) return null;

    if (processedClips.length == 1) {
      // Just copy the single clip to the timeline base name
      final outputPath = path.join(workDir.path, 'timeline_base.mp4');
      final command = '-y -i "${processedClips[0]}" -c copy "$outputPath"';
      return await _executeFFmpeg(command, onProgress,
          outputPath: outputPath, duration: duration);
    }

    // If there are transitions, stitch using SEQUENTIAL PAIRWISE xfade.
    // Process 2 clips at a time → temp file → merge with next clip.
    // This keeps ONLY 2 streams in memory at once (no OOM on Android).
    if (project.transitions.isNotEmpty &&
        project.videoClips.length == processedClips.length) {

      // Clip durations in seconds
      final clipDurSec = project.videoClips
          .map((c) => c.trimmedDuration.inMilliseconds / 1000.0)
          .toList();

      // Lookup transition for clip-pair (i → i+1)
      Transition? transitionFor(int i) {
        final c1 = project.videoClips[i];
        final c2 = project.videoClips[i + 1];
        try {
          return project.transitions
              .firstWhere((t) => t.clipId1 == c1.id && t.clipId2 == c2.id);
        } catch (_) {
          return null;
        }
      }

      // Start with clip 0
      String current = processedClips[0];
      double currentDur = clipDurSec[0];

      for (int i = 0; i < processedClips.length - 1; i++) {
        final next = processedClips[i + 1];
        final nextDur = clipDurSec[i + 1];
        final t = transitionFor(i);
        final td = (t?.duration.inMilliseconds ?? 0) / 1000.0;
        final type = t?.type ?? TransitionType.crossfade;
        final xfadeName = _mapToFfmpegXfade(type);

        // Cap to 40% of the shorter clip for a safe blend
        double safeDur = td <= 0 ? 0.0 : td;
        if (safeDur > currentDur * 0.4) safeDur = currentDur * 0.4;
        if (safeDur > nextDur * 0.4) safeDur = nextDur * 0.4;

        final mergedPath = path.join(workDir.path, 'merged_$i.mp4');
        // Duration-preserving: mergedDur = full sum of both clips (no overlap reduction)
        final mergedDur = currentDur + nextDur;

        String command;
        if (safeDur <= 0.0) {
          // Hard cut: simple concat demuxer (no re-encode, very fast)
          final concatFile = File(path.join(workDir.path, 'concat_$i.txt'));
          await concatFile.writeAsString("file '$current'\nfile '$next'");
          command = '-y -f concat -safe 0 -i "${concatFile.path}" -c copy "$mergedPath"';
        } else {
          // DURATION-PRESERVING xfade strategy:
          // Instead of overlapping the clips (which subtracts safeDur from total),
          // we let clip1 play FULLY to its natural end, then freeze its last frame
          // for `safeDur` seconds while blending into clip2's first frame.
          // The entire clip2 then plays from frame 0.
          //
          // Total output = clip1_dur + clip2_dur  (NO reduction!)
          //
          // Visual: ...clip1 content... last frame freezes → blends into → clip2 first
          // frame... clip2 content...
          final currentDurStr = currentDur.toStringAsFixed(6);
          final safeDurStr = safeDur.toStringAsFixed(6);

          // xfade offset = full clip1 duration; transition then occurs over safeDur
          // using clip1's frozen last frame and clip2's start.
          final fc = StringBuffer();
          fc.write('[0:v]setpts=PTS-STARTPTS,fps=30,settb=1/90000,format=rgb24,tpad=stop_mode=clone:stop_duration=$safeDurStr[va];');
          fc.write('[1:v]setpts=PTS-STARTPTS,fps=30,settb=1/90000,format=rgb24[vb];');
          fc.write('[va][vb]xfade=transition=$xfadeName:duration=$safeDurStr:offset=$currentDurStr,format=yuv420p[vout];');
          // Audio: full clip1 audio, then full clip2 audio — no trimming → no loss
          fc.write('[0:a]asetpts=PTS-STARTPTS[a0];');
          fc.write('[1:a]asetpts=PTS-STARTPTS[a1];');
          fc.write('[a0][a1]concat=n=2:v=0:a=1[aout]');
          command =
              '-y -i "$current" -i "$next" '
              '-filter_complex "${fc.toString()}" '
              '-map "[vout]" -map "[aout]" '
              '-c:v $encoder -b:v 2M -c:a aac -ar 44100 -ac 2 "$mergedPath"';
        }

        print('Transition stitch $i → ${i+1}: $command');
        String? result;
        try {
          if (command.startsWith('-y -f concat')) {
            // Hard cut short-circuit logic from above
            result = await _executeFFmpeg(command, onProgress, outputPath: mergedPath, duration: mergedDur);
          } else {
            result = await _executeFFmpeg(command, onProgress, outputPath: mergedPath, duration: mergedDur);
          }
        } catch (e) {
          print('Transition stitch caught error: $e');
          result = null;
        }

        if (result == null) {
          print('Transition stitch failed at $i, falling back to concat');
          // Fallback: just concatenate without transition
          final concatFile = File(path.join(workDir.path, 'fallback_$i.txt'));
          await concatFile.writeAsString("file '$current'\nfile '$next'");
          final fallbackPath = path.join(workDir.path, 'fallback_merged_$i.mp4');
          final fbCmd = '-y -f concat -safe 0 -i "${concatFile.path}" -c:v $encoder -b:v 5M -c:a aac -ar 44100 -ac 2 "$fallbackPath"';
          
          String? fbResult;
          try {
            fbResult = await _executeFFmpeg(fbCmd, null, outputPath: fallbackPath);
          } catch (e) {
            print('Fallback concat caught error: $e');
            fbResult = null;
          }
          
          current = fbResult ?? current;
          final realDur = await _getMediaDuration(current);
          currentDur = realDur ?? (currentDur + nextDur);
        } else {
          current = mergedPath;
          final realDur = await _getMediaDuration(current);
          currentDur = realDur ?? mergedDur;
        }

        onProgress((i + 1) / processedClips.length * 0.8);
      }

      // Copy the final merged result to the expected output path
      final outputPath = path.join(workDir.path, 'timeline_base.mp4');
      if (current == path.join(workDir.path, 'timeline_base.mp4')) {
        return current;
      }
      final cpCmd = '-y -i "$current" -c copy "$outputPath"';
      return await _executeFFmpeg(cpCmd, onProgress,
          outputPath: outputPath, duration: currentDur);
    }


    final concatFile = File(path.join(workDir.path, 'concat_list.txt'));
    final concatContent =
        processedClips.map((clip) => "file '$clip'").join('\n');
    await concatFile.writeAsString(concatContent);

    final outputPath = path.join(workDir.path, 'timeline_base.mp4');
    final command =
        '-y -f concat -safe 0 -i "${concatFile.path}" -c copy "$outputPath"';

    return await _executeFFmpeg(command, onProgress,
        outputPath: outputPath, duration: duration);
  }

  static String _mapToFfmpegXfade(TransitionType type) {
    // Best-effort mapping to FFmpeg xfade transition names.
    // Unsupported transitions fall back to 'fade' for reliability.
    switch (type) {
      case TransitionType.crossfade:
        return 'fade';
      case TransitionType.zoom:
        return 'distance'; // 'zoomin' doesn't exist; distance scales/zooms out and fades
      case TransitionType.black:
        return 'fadeblack'; // typo fixed (was fadablack)
      case TransitionType.white:
        return 'fadewhite';
      case TransitionType.slideLeft:
      case TransitionType.horizontal:
        return 'slideleft';
      case TransitionType.slideRight:
        return 'slideright';
      case TransitionType.slideUp:
      case TransitionType.vertical:
        return 'slideup';
      case TransitionType.slideDown:
        return 'slidedown';
      case TransitionType.push:
        return 'slideleft';
      case TransitionType.pushRight:
        return 'slideright';
      case TransitionType.circle:
        return 'circleopen';
      case TransitionType.rotate1:
      case TransitionType.rotate2:
        return 'radial';
      case TransitionType.shake:
        return 'hblur'; // horizontal blur simulates fast motion shake
      case TransitionType.light:
        return 'fadewhite';
      case TransitionType.pixelate:
        return 'pixelize';
      case TransitionType.blink:
        return 'fadeblack'; // typo fixed
    }
  }

  static bool _hasVideoFilters(VideoProject project) {
    return project.colorFilter.hasFilters;
  }

  static Future<String?> _applyVideoFiltersAndEffects(
      String inputPath,
      VideoProject project,
      Directory workDir,
      String encoder,
      Function(double) onProgress,
      {required double duration,
       required int targetWidth,
       required int targetHeight}) async {
    final cf = project.colorFilter;
    final outputPath = path.join(workDir.path, 'filtered_video_${DateTime.now().millisecondsSinceEpoch}.mp4');

    print('EXPORT DEBUG: colorFilter.hasFilters = ${cf.hasFilters}');
    print('EXPORT DEBUG: brightness=${cf.brightness}, contrast=${cf.contrast}, saturation=${cf.saturation}');
    print('EXPORT DEBUG: warmth=${cf.warmth}, tint=${cf.tint}, temperature=${cf.temperature}');
    print('EXPORT DEBUG: filterPresetMatrices.count = ${cf.filterPresetMatrices.length}');
    print('EXPORT DEBUG: videoEffects.count = ${project.videoEffects.length}');
    List<String> filters = [];

    // --- Video Effects ---
    for (final effect in project.videoEffects) {
      final start = effect.startTime.inMilliseconds / 1000.0;
      final end = (effect.startTime + effect.duration).inMilliseconds / 1000.0;
      if (start >= duration) continue;
      final intensity = effect.intensity.clamp(0.01, 1.0);
      
      switch (effect.type) {
        case VideoEffectType.blur:
          final radius = (intensity * 15).toStringAsFixed(1);
          filters.add("boxblur=luma_radius=$radius:enable='between(t,$start,$end)'");
          break;
        case VideoEffectType.shake:
          filters.add("colorchannelmixer=rr=1.0:rg=0.1:rb=0.0:gr=0.0:gg=1.0:gb=0.1:br=0.1:bg=0.0:bb=1.0:enable='between(t,$start,$end)*lt(mod(t*15,1.0),0.5)'");
          break;
        case VideoEffectType.flash:
          filters.add("colorchannelmixer=rr=1.5:gg=1.5:bb=1.5:enable='between(t,$start,$end)*lt(mod(t-floor(t-$start),0.3),0.15)'");
          break;
        case VideoEffectType.glitch:
          filters.add("noise=alls=15:allf=t+u:enable='between(t,$start,$end)'");
          break;
        case VideoEffectType.grayscale:
          filters.add("colorchannelmixer=rr=0.2126:rg=0.7152:rb=0.0722:gr=0.2126:gg=0.7152:gb=0.0722:br=0.2126:bg=0.7152:bb=0.0722:enable='between(t,$start,$end)'");
          break;
        case VideoEffectType.sepia:
          filters.add("colorchannelmixer=rr=0.393:rg=0.769:rb=0.189:gr=0.349:gg=0.686:gb=0.168:br=0.272:bg=0.534:bb=0.131:enable='between(t,$start,$end)'");
          break;
        default:
          break;
      }
    }

    if (filters.isEmpty) {
      print('EXPORT DEBUG: No filters to apply, returning input path.');
      return inputPath;
    }

    final filterString = filters.join(',');
    print('EXPORT DEBUG: Final filter string: $filterString');

    final command = '-y -i "$inputPath" -vf "$filterString" -c:v $encoder -b:v 5M -c:a copy "$outputPath"';
    print('EXPORT: Running filter command: $command');

    final result = await _executeFFmpeg(command, onProgress,
        outputPath: outputPath, duration: duration);

    if (result == null) {
      print('EXPORT WARNING: Filter apply failed! Returning un-filtered input.');
    }
    return result ?? inputPath;
  }

  // Helper methods for color matrix consolidation (Parity with VideoEditorScreen)
  // Identical to VideoEditorScreen._calculateColorMatrix – kept in sync manually.
  // ALL 20 values use normalized [-2, 2] scale (Flutter ColorFilter.matrix compatible).
  // When passing offsets (col 4) to FFmpeg geq, multiply by 255 to convert to pixel space.
  static List<double> _calculateColorMatrix(ColorFilter filter) {
    List<double> mat = [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ];

    // Apply saturation
    final s = filter.saturation;
    const lumR = 0.2126;
    const lumG = 0.7152;
    const lumB = 0.0722;
    final oneMinusS = 1 - s;
    List<double> satMat = [
      (oneMinusS * lumR) + s, (oneMinusS * lumG), (oneMinusS * lumB), 0, 0,
      (oneMinusS * lumR), (oneMinusS * lumG) + s, (oneMinusS * lumB), 0, 0,
      (oneMinusS * lumR), (oneMinusS * lumG), (oneMinusS * lumB) + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
    mat = _multiplyMatrices(mat, satMat);

    // Apply hue rotation
    if (filter.hue != 0.0) {
      final cosH = math.cos(filter.hue * math.pi / 180);
      final sinH = math.sin(filter.hue * math.pi / 180);
      List<double> hueMat = [
        cosH + (1 - cosH) * lumR, (1 - cosH) * lumG - sinH * 0.168, (1 - cosH) * lumB + sinH, 0, 0,
        (1 - cosH) * lumR + sinH * 0.330, cosH + (1 - cosH) * lumG, (1 - cosH) * lumB - sinH * 0.497, 0, 0,
        (1 - cosH) * lumR - sinH, (1 - cosH) * lumG + sinH * 0.169, cosH + (1 - cosH) * lumB, 0, 0,
        0, 0, 0, 1, 0,
      ];
      mat = _multiplyMatrices(mat, hueMat);
    }

    // Apply exposure
    final expFactor = math.pow(2, filter.exposure).toDouble();
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) mat[i * 5 + j] *= expFactor;
      mat[i * 5 + 4] *= expFactor;
    }

    // Apply highlights, shadows, contrast
    final hGain = 1.0 + (filter.highlights * 0.5);
    final sGain = 1.0 - (filter.shadows * 0.3);
    final c = filter.contrast * hGain;
    final t = 128.0 * (1.0 - c);
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) mat[i * 5 + j] *= c * sGain;
      mat[i * 5 + 4] = mat[i * 5 + 4] * c + t;
    }

    // Apply brightness and shadow lift
    final shadowLift = filter.shadows * 40.0;
    final b = (filter.brightness * 255.0) + shadowLift;
    for (int i = 0; i < 3; i++) mat[i * 5 + 4] += b;

    // Apply warmth
    if (filter.warmth != 0.0) {
      final warmthAmount = filter.warmth * 40.0;
      mat[4] += warmthAmount;
      mat[14] -= warmthAmount * 0.5;
    }

    // Apply tint
    if (filter.tint != 0.0) {
      final tintAmount = filter.tint * 40.0;
      mat[9] += tintAmount;
      mat[4] -= tintAmount * 0.3;
    }

    // Apply opacity/fade
    if (filter.opacity != 1.0) {
      mat[18] *= filter.opacity;
      mat[14] *= filter.opacity;
      mat[9]  *= filter.opacity;
      mat[4]  *= filter.opacity;
    }

    // Apply fade (blend to white)
    if (filter.fade != 0.0) {
      final fadeAmount = filter.fade * 50.0;
      mat[4]  += fadeAmount;
      mat[9]  += fadeAmount;
      mat[14] += fadeAmount;
    }

    // Apply temperature
    if (filter.temperature != 0.0) {
      final tempAmount = filter.temperature * 30.0;
      mat[4]  += tempAmount;
      mat[9]  += tempAmount * 0.3;
      mat[14] -= tempAmount * 0.5;
    }

    // Apply sharpness via matrix (same as preview – NOT via unsharp)
    if (filter.sharpness != 0.0) {
      final sharpnessAmount = filter.sharpness * 0.2;
      mat[0]  += sharpnessAmount * lumR;
      mat[1]  += sharpnessAmount * lumG;
      mat[2]  += sharpnessAmount * lumB;
      mat[5]  += sharpnessAmount * lumR;
      mat[6]  += sharpnessAmount * lumG;
      mat[7]  += sharpnessAmount * lumB;
      mat[10] += sharpnessAmount * lumR;
      mat[11] += sharpnessAmount * lumG;
      mat[12] += sharpnessAmount * lumB;
    }

    // Apply luminance
    if (filter.luminance != 0.0) {
      final lumFactor = 1.0 + filter.luminance;
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 5; j++) {
          mat[i * 5 + j] *= lumFactor;
        }
      }
    }

    // Apply filter preset matrices
    if (filter.filterPresetMatrices.isNotEmpty) {
      for (final presetMatrix in filter.filterPresetMatrices) {
        if (presetMatrix.length == 20) mat = _multiplyMatrices(mat, presetMatrix);
      }
    }

    // Clamp all values
    for (int i = 0; i < mat.length; i++) {
      if (i % 5 == 4) {
        mat[i] = mat[i].clamp(-255.0, 255.0);
      } else {
        mat[i] = mat[i].clamp(-2.0, 2.0);
      }
    }

    return mat;
  }

  static List<double> _multiplyMatrices(List<double> mat1, List<double> mat2) {
    List<double> result = List<double>.filled(20, 0.0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 5; j++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) sum += mat1[i * 5 + k] * mat2[k * 5 + j];
        if (j == 4) sum += mat1[i * 5 + 4];
        result[i * 5 + j] = sum;
      }
    }
    return result;
  }

  static Future<String?> _addStickers(
      String inputPath,
      VideoProject project,
      Directory workDir,
      Function(double) onProgress,
      {required int targetWidth,
      required int targetHeight,
      required double duration,
      required String encoder,
      required double targetFps}) async {
    
    final stickers = project.stickers;
    if (stickers.isEmpty) return inputPath;
    
    String currentInput = inputPath;
    final baseAspect = targetWidth / targetHeight;

    for (int i = 0; i < stickers.length; i++) {
      final sticker = stickers[i];
      final start = sticker.startTime.inMilliseconds / 1000.0;
      final end = sticker.endTime.inMilliseconds / 1000.0;

      final clipAspect = await _getOverlayAspectRatio(project, sticker.startTime, targetWidth, targetHeight);
      
      double clipWidthInsideTarget = clipAspect > baseAspect ? targetWidth.toDouble() : targetHeight * clipAspect;
      double clipHeightInsideTarget = clipAspect > baseAspect ? targetWidth / clipAspect : targetHeight.toDouble();
      
      double padX = (targetWidth - clipWidthInsideTarget) / 2;
      double padY = (targetHeight - clipHeightInsideTarget) / 2;
      
      final previewCanvasWidth = (1920.0 * clipAspect).round().clamp(1, 4096);
      const previewCanvasHeight = 1920.0;
      final tempStickerFile = await _renderStickerOverlayImage(
        sticker: sticker,
        workDir: workDir,
        index: i,
        canvasWidth: previewCanvasWidth.toDouble(),
        canvasHeight: previewCanvasHeight,
      );
      if (tempStickerFile == null) {
        continue;
      }

      final tempOutput = path.join(workDir.path, 'with_sticker_$i.mp4');
      
      final opacity = sticker.opacity.clamp(0.0, 1.0);

      final scaledCanvasWidth = clipWidthInsideTarget.round();
      final scaledCanvasHeight = clipHeightInsideTarget.round();
      final x = padX.round();
      final y = padY.round();

      // Pre-scale RGBA enforcement guarantees FFmpeg doesn't drop the PNG alpha channel
      String opacityFilter = opacity < 1.0 ? ",colorchannelmixer=aa=$opacity" : "";
      String filterComplex = "[0:v]setpts=PTS-STARTPTS[base];"
          "[1:v]fps=$targetFps,setpts=PTS-STARTPTS,format=rgba,scale=$scaledCanvasWidth:$scaledCanvasHeight$opacityFilter[opacity];"
          "[base][opacity]overlay=$x:$y:enable='between(t,$start,$end)':eof_action=pass[out]";
          
      final command =
          '-y -i "$currentInput" -loop 1 -t $duration -i "${tempStickerFile.path}" '
          '-filter_complex "$filterComplex" '
          '-map "[out]" -map 0:a? -c:v $encoder -b:v 5M -r $targetFps -pix_fmt yuv420p -c:a aac -shortest "$tempOutput"';

      final result = await _executeFFmpeg(command, onProgress, outputPath: tempOutput, duration: duration);
      
      if (result != null && currentInput != inputPath) {
        try { await File(currentInput).delete(); } catch (_) {}
      }
      if (result != null) currentInput = tempOutput;
    }
    return currentInput;
  }

  static Future<String?> _addMediaOverlays(String inputPath,
      List<VideoClip> overlays, Directory workDir, Function(double) onProgress,
      {required int targetWidth,
      required int targetHeight,
      required double duration,
      required String encoder}) async {
    // If there are no overlays, just return the input path
    if (overlays.isEmpty) return inputPath;

    // Process each overlay individually to ensure stability
    String currentInput = inputPath;

    for (int i = 0; i < overlays.length; i++) {
      final overlay = overlays[i];
      final start = overlay.startTime.inMilliseconds / 1000.0;
      final end = overlay.endTime.inMilliseconds / 1000.0;
      final overlayFilePath =
          overlay.videoFile?.path ?? overlay.imageFile?.path;

      if (overlayFilePath == null) continue;

      final tempOutput = path.join(workDir.path, 'temp_overlay_$i.mp4');

      // Scale and position
      final width = (overlay.overlaySize.width * targetWidth).toInt();
      final height = (overlay.overlaySize.height * targetHeight).toInt();
      final x = (overlay.overlayPosition.dx * targetWidth).toInt();
      final y = (overlay.overlayPosition.dy * targetHeight).toInt();
      final opacity = overlay.overlayOpacity.clamp(0.0, 1.0);

      // Force format=rgba so PNGs with alpha channels don't render black
      String opacityFilter = opacity < 1.0 ? ",format=rgba,colorchannelmixer=aa=$opacity" : ",format=rgba";

      String command;
      if (overlay.mediaType == MediaType.image) {
        // Image overlay with loop
        command =
            '-y -loop 1 -t $duration -i "$overlayFilePath" -i "$currentInput" '
            '-filter_complex "[0:v]scale=$width:$height:force_original_aspect_ratio=decrease$opacityFilter[opacity];'
            '[1:v][opacity]overlay=$x:$y:enable=\'between(t,$start,$end)\'[out]" '
            '-map "[out]" -map 1:a? -c:v $encoder -b:v 5M -c:a copy -shortest "$tempOutput"';
      } else {
        // Video overlay — use source-relative trim points
        final sourceStartSec = overlay.trimStart.inMilliseconds / 1000.0;
        final overlayDuration =
            overlay.trimmedDuration.inMilliseconds / 1000.0;
        final trimmedOverlay =
            path.join(workDir.path, 'trimmed_overlay_$i.mp4');
        await _executeFFmpeg(
          '-y -ss $sourceStartSec -t $overlayDuration -i "$overlayFilePath" -c copy "$trimmedOverlay"',
          null,
        );

        command = '-y -i "$trimmedOverlay" -i "$currentInput" '
            '-filter_complex "[0:v]scale=$width:$height:force_original_aspect_ratio=decrease$opacityFilter[opacity];'
            '[1:v][opacity]overlay=$x:$y:enable=\'between(t,$start,$end)\'[out]" '
            '-map "[out]" -map 1:a? -c:v $encoder -b:v 5M -c:a copy "$tempOutput"';
      }

      print('Media Overlay $i FFmpeg command: $command');

      final result = await _executeFFmpeg(command, onProgress,
          outputPath: tempOutput, duration: duration);

      // Cleanup intermediate files to free disk space
      if (overlay.mediaType == MediaType.video) {
        try {
          await File(path.join(workDir.path, 'trimmed_overlay_$i.mp4'))
              .delete();
        } catch (_) {}
      }
      // Delete previous intermediate output (no longer needed)
      if (result != null && currentInput != inputPath) {
        try {
          await File(currentInput).delete();
        } catch (_) {}
      }

      if (result != null) {
        currentInput = tempOutput;
      }
    }

    return currentInput;
  }

  static Future<String?> _addTextOverlays(
      String inputPath,
      VideoProject project,
      Directory workDir,
      Function(double) onProgress,
      {required int targetWidth,
      required int targetHeight,
      required double duration,
      required String encoder,
      required double targetFps}) async {
    final overlays = project.textOverlays;
    if (overlays.isEmpty) return inputPath;

    // Pre-calculate aspects for all dynamic scaling coordinates
    final baseAspect = targetWidth / targetHeight;
    String currentInput = inputPath;

    for (int i = 0; i < overlays.length; i++) {
      final overlay = overlays[i];
      final clipAspect = await _getOverlayAspectRatio(project, overlay.startTime, targetWidth, targetHeight);

      // Calculate where the padded clip sits inside targetWidth x targetHeight
      double clipWidthInsideTarget = clipAspect > baseAspect
          ? targetWidth.toDouble()
          : targetHeight * clipAspect;
      double clipHeightInsideTarget = clipAspect > baseAspect
          ? targetWidth / clipAspect
          : targetHeight.toDouble();

      double padX = (targetWidth - clipWidthInsideTarget) / 2;
      double padY = (targetHeight - clipHeightInsideTarget) / 2;

      final start = overlay.startTime.inMilliseconds / 1000.0;
      final end = overlay.endTime.inMilliseconds / 1000.0;
      final previewCanvasWidth = (1920.0 * clipAspect).round().clamp(1, 4096);
      const previewCanvasHeight = 1920.0;

      // UI text size is set based on a fixed 1920 logical container height in VideoEditorScreen
      final fontSize = overlay.fontSize.clamp(1.0, 512.0).toDouble();

      final textImage = await _renderTextOverlayImage(
        overlay: overlay,
        fontSize: fontSize,
        workDir: workDir,
        index: i,
        canvasWidth: previewCanvasWidth.toDouble(),
        canvasHeight: previewCanvasHeight,
      );
      if (textImage == null) {
        continue;
      }

      final opacity = overlay.opacity.clamp(0.0, 1.0);
      final opacityFilter =
          opacity < 1.0 ? ",format=rgba,colorchannelmixer=aa=$opacity" : ",format=rgba";
      final tempOutput = path.join(workDir.path, 'with_text_overlay_$i.mp4');
      final x = padX.round();
      final y = padY.round();
      final scaledCanvasWidth = clipWidthInsideTarget.round();
      final scaledCanvasHeight = clipHeightInsideTarget.round();
      final command =
          '-y -i "$currentInput" -loop 1 -t $duration -i "${textImage.path}" '
          '-filter_complex "[0:v]setpts=PTS-STARTPTS[base];'
          '[1:v]fps=$targetFps,setpts=PTS-STARTPTS,scale=$scaledCanvasWidth:$scaledCanvasHeight$opacityFilter[overlay];'
          '[base][overlay]overlay=$x:$y:enable=\'between(t,$start,$end)\':eof_action=pass[out]" '
          '-map "[out]" -map 0:a? -c:v $encoder -b:v 5M -r $targetFps -pix_fmt yuv420p -c:a aac -shortest "$tempOutput"';

      print('Text Overlay $i Command: $command');
      final result = await _executeFFmpeg(
        command,
        onProgress,
        outputPath: tempOutput,
        duration: duration,
      );

      if (result != null && currentInput != inputPath) {
        try {
          await File(currentInput).delete();
        } catch (_) {}
      }
      if (result != null) {
        currentInput = tempOutput;
      }
    }

    return currentInput;
  }

  static Future<File?> _renderTextOverlayImage({
    required TextOverlay overlay,
    required double fontSize,
    required Directory workDir,
    required int index,
    required double canvasWidth,
    required double canvasHeight,
  }) async {
    try {
      TextStyle style;
      try {
        style = GoogleFonts.getFont(
          overlay.fontFamily,
          fontSize: fontSize,
          color: overlay.color,
          fontWeight: overlay.fontWeight,
          fontStyle: overlay.flutterFontStyle,
          shadows: const [
            Shadow(
              offset: Offset(1, 1),
              color: Colors.black54,
              blurRadius: 2,
            ),
          ],
        );
      } catch (_) {
        style = GoogleFonts.roboto(
          fontSize: fontSize,
          color: overlay.color,
          fontWeight: overlay.fontWeight,
          fontStyle: overlay.flutterFontStyle,
          shadows: const [
            Shadow(
              offset: Offset(1, 1),
              color: Colors.black54,
              blurRadius: 2,
            ),
          ],
        );
      }

      final textPainter = TextPainter(
        text: TextSpan(text: overlay.text, style: style),
        textAlign: overlay.flutterTextAlign,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: canvasWidth);

      final width = canvasWidth.ceil().clamp(1, 4096).toInt();
      final height = canvasHeight.ceil().clamp(1, 4096).toInt();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final x = (overlay.position.dx * canvasWidth).clamp(0.0, canvasWidth);
      final y = (overlay.position.dy * canvasHeight).clamp(0.0, canvasHeight);
      textPainter.paint(canvas, Offset(x, y));

      final image = await recorder.endRecording().toImage(width, height);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return null;
      }

      final file = File(path.join(workDir.path, 'text_overlay_$index.png'));
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return file;
    } catch (e) {
      print('Error rendering text overlay ${overlay.id}: $e');
      return null;
    }
  }

  static Future<File?> _renderStickerOverlayImage({
    required StickerModel sticker,
    required Directory workDir,
    required int index,
    required double canvasWidth,
    required double canvasHeight,
  }) async {
    try {
      final byteData = await rootBundle.load(sticker.assetPath);
      final codec = await ui.instantiateImageCodec(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const previewBaseStickerSize = 400.0;
      final stickerSize =
          (previewBaseStickerSize * sticker.scale).clamp(1.0, canvasHeight);
      final centerX = sticker.position.dx * canvasWidth;
      final centerY = sticker.position.dy * canvasHeight;

      canvas.save();
      canvas.translate(centerX, centerY);
      canvas.rotate(sticker.rotation);
      final dstRect = Rect.fromCenter(
        center: Offset.zero,
        width: stickerSize,
        height: stickerSize,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        dstRect,
        Paint(),
      );
      canvas.restore();

      final overlayImage = await recorder
          .endRecording()
          .toImage(canvasWidth.ceil(), canvasHeight.ceil());
      final pngBytes =
          await overlayImage.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes == null) {
        return null;
      }

      final file = File(path.join(workDir.path, 'sticker_overlay_$index.png'));
      await file.writeAsBytes(pngBytes.buffer.asUint8List());
      return file;
    } catch (e) {
      print('Error rendering sticker overlay ${sticker.id}: $e');
      return null;
    }
  }

  static Future<String?> _finalizeWithAudio(
    String inputPath,
    VideoProject project,
    String outputPath,
    String encoder,
    double videoMasterVolume,
    double audioMasterVolume,
    Function(double) onProgress, {
    required double duration,
  }) async {
    if (project.audioOverlays.isEmpty) {
      // Just volume adjustment
      String af = videoMasterVolume != 1.0 ? '-af "volume=$videoMasterVolume"' : '';
      final command = '-y -i "$inputPath" -c:v $encoder -b:v 5M $af -c:a aac "$outputPath"';
      return await _executeFFmpeg(command, onProgress, outputPath: outputPath, duration: duration);
    }

    // Mix logic using amix and adelay
    final inputs = ['-i "$inputPath"'];
    final fc = StringBuffer();
    final mixInputs = <String>['[a0]'];

    fc.write('[0:a]volume=$videoMasterVolume[a0];');

    for (int i = 0; i < project.audioOverlays.length; i++) {
      final overlay = project.audioOverlays[i];
      final audioInputIdx = i + 1;
      
      final sourceStart = overlay.audioStartOffset.inMilliseconds / 1000.0;
      final overlayDuration = (overlay.endTime - overlay.startTime).inMilliseconds / 1000.0;
      
      // Add input file with seeking to trim the audio
      inputs.add('-ss $sourceStart -t $overlayDuration -i "${overlay.audioFile.path}"');
      
      final delayMs = overlay.startTime.inMilliseconds;
      String filter = '[$audioInputIdx:a]volume=${overlay.volume}';
      if (delayMs > 0) {
        filter += ',adelay=$delayMs|$delayMs';
      }
      filter += '[a$audioInputIdx];';
      fc.write(filter);
      mixInputs.add('[a$audioInputIdx]');
    }

    final inputsConcat = mixInputs.join('');
    fc.write('${inputsConcat}amix=inputs=${mixInputs.length}:duration=first:dropout_transition=0[aout]');

    final command = '-y ${inputs.join(' ')} -filter_complex "$fc" -map 0:v -map "[aout]" -c:v $encoder -b:v 5M -c:a aac "$outputPath"';
    return await _executeFFmpeg(command, onProgress, outputPath: outputPath, duration: duration);
  }

  /// Execute FFmpeg command asynchronously to provide real-time progress
  static Future<String?> _executeFFmpeg(
      String command, Function(double)? onProgress,
      {double? duration, String? outputPath}) async {
    print('Executing FFmpeg: $command');

    try {
      final completer = Completer<String?>();
      
      await FFmpegKit.executeAsync(
        command,
        (session) async {
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            if (onProgress != null) {
              onProgress(1.0);
            }
            completer.complete(outputPath);
          } else {
            final logs = await session.getAllLogsAsString() ?? 'Unknown FFmpeg Error';
            print('FFmpeg Error Length: ${logs.length}');
            final String traceTail = logs.length > 300 ? logs.substring(logs.length - 300) : logs;
            print('FFmpeg Error Tail: $traceTail');
            completer.completeError('FFmpeg Execution Failed! Trace: $traceTail');
          }
        },
        (log) {
          // print(log.getMessage());
        },
        (statistics) {
          if (onProgress != null && duration != null && duration > 0) {
            final timeInMilliseconds = statistics.getTime();
            if (timeInMilliseconds > 0) {
              final progress = (timeInMilliseconds / 1000.0) / duration;
              onProgress(progress.clamp(0.0, 1.0));
            }
          }
        },
      ).then((session) {
        _currentSession = session;
      });

      return await completer.future;
    } catch (e) {
      print('FFmpeg execution error: $e');
      return null;
    }
  }

  static Future<bool> cancelExport() async {
    try {
      if (_currentSession != null) {
        await _currentSession.cancel();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
