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

/// Holds the rendered PNG file and metadata for a single overlay.
class _RenderedOverlay {
  final int index;
  final File file;
  final TextOverlay overlay;
  final double clipAspect;

  _RenderedOverlay({
    required this.index,
    required this.file,
    required this.overlay,
    required this.clipAspect,
  });
}

/// Holds the rendered PNG file and metadata for a single sticker.
class _RenderedSticker {
  final File file;
  final StickerModel sticker;
  final int scaledWidth;
  final int scaledHeight;
  final int x;
  final int y;

  _RenderedSticker({
    required this.file,
    required this.sticker,
    required this.scaledWidth,
    required this.scaledHeight,
    required this.x,
    required this.y,
  });
}

/// A pre-rendered, tightly cropped overlay image and its position in the
/// output frame.
class _LayerPng {
  final File file;
  final int x;
  final int y;

  const _LayerPng(this.file, this.x, this.y);
}

enum _ComposeLayerKind { png, rawImage, video }

/// One visual layer drawn on top of the base timeline during export.
class _ComposeLayer {
  final _ComposeLayerKind kind;
  final _LayerPng? png;
  final String? path;
  final Rect? box;
  final double opacity;
  final double start;
  final double end;
  final double trimStart;
  final double trimDuration;
  final bool withAudio;
  final double volume;

  _ComposeLayer._(
    this.kind, {
    this.png,
    this.path,
    this.box,
    this.opacity = 1.0,
    required this.start,
    required this.end,
    this.trimStart = 0,
    this.trimDuration = 0,
    this.withAudio = false,
    this.volume = 1.0,
  });

  factory _ComposeLayer.png(_LayerPng png, double start, double end) =>
      _ComposeLayer._(_ComposeLayerKind.png,
          png: png, start: start, end: end);

  factory _ComposeLayer.rawImage(
          String path, Rect box, double opacity, double start, double end) =>
      _ComposeLayer._(_ComposeLayerKind.rawImage,
          path: path, box: box, opacity: opacity, start: start, end: end);

  factory _ComposeLayer.video(
    String path,
    Rect box,
    double opacity,
    double start,
    double end, {
    required double trimStart,
    required double trimDuration,
    required bool withAudio,
    required double volume,
  }) =>
      _ComposeLayer._(_ComposeLayerKind.video,
          path: path,
          box: box,
          opacity: opacity,
          start: start,
          end: end,
          trimStart: trimStart,
          trimDuration: trimDuration,
          withAudio: withAudio,
          volume: volume);
}

/// Transition into a clip: blend [seconds] from the previous clip's last frame.
class _TransitionPlan {
  final int fromIndex;
  final double seconds;
  final TransitionType type;

  const _TransitionPlan(this.fromIndex, this.seconds, this.type);
}

class ExportService {
  // Per-export caches so the same file is not probed over and over.
  static final Map<String, double> _aspectCache = {};
  static final Map<String, bool> _audioStreamCache = {};
  static bool _cancelled = false;

  /// True when the last export was stopped by [cancelExport].
  static bool get wasCancelled => _cancelled;

  static void _throwIfCancelled() {
    if (_cancelled) throw Exception('Export cancelled');
  }

  static Future<double> _getClipAspectRatio(VideoProject project, Duration time) async {
    VideoClip? clip;
    for (final c in project.videoClips) {
      if (c.startTime <= time && c.endTime > time) {
        clip = c;
        break;
      }
    }
    clip ??= project.videoClips.firstOrNull;

    // The preview shows image clips in a box with the project's output aspect.
    if (clip != null && clip.mediaType == MediaType.image) {
      final res = project.outputResolution;
      if (res.width > 0 && res.height > 0) return res.width / res.height;
    }

    final path = clip?.videoFile?.path;
    if (path != null) {
      final cached = _aspectCache[path];
      if (cached != null) return cached;
      final session = await FFprobeKit.getMediaInformation(path);
      final info = await session.getMediaInformation();
      if (info != null) {
        final streams = info.getStreams();
        for (final s in streams) {
          if (s.getProperty('codec_type') == 'video' || s.getType() == 'video') {
            num w = s.getWidth() ?? 1080;
            num h = s.getHeight() ?? 1920;
            final props = s.getAllProperties();
            double rot = 0;
            if (props != null && props['tags'] != null && props['tags']['rotate'] != null) {
              rot = double.tryParse(props['tags']['rotate'].toString()) ?? 0;
            }
            // FFmpeg 6+ reports rotation in the display matrix side data
            // instead of the 'rotate' tag (portrait phone recordings).
            final sideData = props?['side_data_list'];
            if (rot == 0 && sideData is List) {
              for (final sd in sideData) {
                if (sd is Map && sd['rotation'] != null) {
                  rot = double.tryParse(sd['rotation'].toString()) ?? 0;
                  break;
                }
              }
            }
            if ((rot % 180) != 0) {
              final temp = w; w = h; h = temp;
            }
            final aspect = (w / h).toDouble();
            _aspectCache[path] = aspect;
            return aspect;
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
    // The preview always lays overlays out relative to the clip's own box,
    // so the export uses the clip's aspect ratio as well.
    return _getClipAspectRatio(project, time);
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

  // ─── Encoder selection ────────────────────────────────────────────────────
  // Always use libx264 for maximum compatibility with complex filter graphs.
  // h264_mediacodec is a decoder-only in most ffmpeg-kit builds and cannot
  // accept YUVA/RGBA intermediate frames produced by chromakey/overlay chains.
  static const String _softwareEncoder = 'libx264';

  static Future<String> _pickBestEncoder({bool needsAlphaSupport = false}) async {
    // Chroma key and overlay filters produce YUVA frames that hardware encoders
    // cannot accept. Always use the software encoder for those paths.
    if (needsAlphaSupport) return _softwareEncoder;
    return _softwareEncoder;
  }

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
    _cancelled = false;
    _aspectCache.clear();
    _audioStreamCache.clear();
    try {
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
        }
      }

      return result;
    } catch (e) {
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

      // Pick the best available encoder (hardware preferred)
      String encoder = await _pickBestEncoder();

      // Full timeline length, exactly as long as the preview timeline
      // (previously truncated to whole seconds and limited to video clips).
      final totalDuration = _timelineTotalSeconds(project);

      // Get per-clip color filters from provider's internal map
      final resolvedClipColorFilters =
          Map<String, ColorFilter>.from(clipColorFilters ?? const {});

      // Clips in timeline order (the preview plays by timeline position)
      final order = List<int>.generate(project.videoClips.length, (i) => i);
      order.sort((a, b) {
        final c = project.videoClips[a].startTime
            .compareTo(project.videoClips[b].startTime);
        return c != 0 ? c : a.compareTo(b);
      });

      // Transitions between consecutive clips: blend window at the start of
      // the incoming clip, the same window the preview animates.
      final incoming = <int, _TransitionPlan>{};
      for (int j = 1; j < order.length; j++) {
        final prev = project.videoClips[order[j - 1]];
        final cur = project.videoClips[order[j]];
        Transition? t;
        for (final tr in project.transitions) {
          if (tr.clipId1 == prev.id && tr.clipId2 == cur.id) {
            t = tr;
            break;
          }
        }
        if (t == null) continue;
        final curLen = (cur.endTime - cur.startTime).inMilliseconds / 1000.0;
        var sd = t.duration.inMilliseconds / 1000.0;
        final maxSd = curLen - 2.0 / targetFps;
        if (sd > maxSd) sd = maxSd;
        sd = (sd * targetFps).floor() / targetFps; // whole frames
        if (sd < 1.0 / targetFps) continue;
        incoming[order[j]] = _TransitionPlan(order[j - 1], sd, t.type);
      }

      final processedClips = <String>[];

      // 1. Process Clips
      for (int i = 0; i < project.videoClips.length; i++) {
        _throwIfCancelled();
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
        },
            colorFilter: clipFilter.hasFilters ? clipFilter : project.colorFilter,
            forceKeyFrameAt: incoming[i]?.seconds);

        if (processedPath == null) {
          _throwIfCancelled();
          throw Exception(
              'Failed to process clip $i: ${clip.videoFile?.path ?? clip.imageFile?.path}');
        }
        processedClips.add(processedPath);
      }

      // 2. Stitch Timeline (gaps, transitions, trailing black) — 40% -> 60%
      _throwIfCancelled();
      String? baseVideoPath = await _stitchTimeline(
        project: project,
        order: order,
        processed: processedClips,
        incoming: incoming,
        workDir: workDir,
        targetWidth: targetW,
        targetHeight: targetH,
        targetFps: targetFps,
        timelineTotal: totalDuration,
        encoder: encoder,
        preset: preset,
        onProgress: (p) => onProgress?.call(0.4 + (p * 0.2)),
      );
      if (baseVideoPath == null) {
        _throwIfCancelled();
        // Fallback: previous stitching implementation
        baseVideoPath = await _createTimelineBase(
            project, processedClips, workDir, encoder, (p) {
          onProgress?.call(0.4 + (p * 0.2));
        }, duration: totalDuration, preset: preset);
      }
      if (baseVideoPath == null) {
        _throwIfCancelled();
        throw Exception('Failed to create timeline base');
      }

      String currentVideo = baseVideoPath;

      // 3. Effects, media overlays, text and stickers — 60% -> 90%
      _throwIfCancelled();
      final composed = await _composeLayers(
        project: project,
        basePath: currentVideo,
        workDir: workDir,
        targetWidth: targetW,
        targetHeight: targetH,
        targetFps: targetFps,
        duration: totalDuration,
        encoder: encoder,
        preset: preset,
        onProgress: (p) => onProgress?.call(0.6 + p * 0.3),
      );
      if (composed != null) {
        currentVideo = composed;
      } else {
        _throwIfCancelled();
        // Fallback: previous multi-pass implementation
        if (project.videoEffects.isNotEmpty ||
            project.textOverlays.isNotEmpty ||
            project.stickers.isNotEmpty) {
          final combinedPath = await _applyEffectsAndOverlaysInOnePass(
              currentVideo, project, workDir, encoder, (p) {
            onProgress?.call(0.6 + p * 0.2);
          },
              duration: totalDuration,
              targetWidth: targetW,
              targetHeight: targetH,
              targetFps: targetFps,
              preset: preset);
          if (combinedPath != null) {
            currentVideo = combinedPath;
          }
        }
        if (project.overlayClips.isNotEmpty) {
          _throwIfCancelled();
          final mediaOverlayPath = await _addMediaOverlays(
              currentVideo, project.overlayClips, workDir, (p) {
            onProgress?.call(0.8 + p * 0.1);
          },
              targetWidth: targetW,
              targetHeight: targetH,
              duration: totalDuration,
              encoder: encoder,
              preset: preset);
          if (mediaOverlayPath == null) {
            throw Exception('Failed to add media overlays');
          }
          currentVideo = mediaOverlayPath;
        }
      }

      // 4. Finalize Audio — 90% -> 100%
      _throwIfCancelled();
      final finalPath = await _finalizeWithAudio(currentVideo, project,
          outputPath, encoder, videoMasterVolume, audioMasterVolume, (p) {
        onProgress?.call(0.9 + p * 0.1);
      }, duration: totalDuration);
      if (finalPath == null) {
        _throwIfCancelled();
        throw Exception('Failed to finalize with audio');
      }

      onProgress?.call(1.0);
      return finalPath;
    } catch (e) {
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
      Function(double) onClipProgress,
      {ColorFilter? colorFilter, double? forceKeyFrameAt}) async {
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
          outputPath,
          forceKeyFrameAt: forceKeyFrameAt);
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
        colorFilter: colorFilter,
        preset: preset,
        forceKeyFrameAt: forceKeyFrameAt);
  }

  /// Process clip with chroma key (green screen) effect using a SINGLE FFmpeg pass.
  ///
  /// WHY single pass: H.264/MP4 does not support alpha channels, so the old
  /// 3-step approach (key → save → overlay) silently dropped the alpha channel
  /// when writing the intermediate .mp4, making keyed pixels opaque black and
  /// fully covering the background in step 3.
  ///
  /// WHY libx264 only: hardware encoders (h264_mediacodec) cannot accept the
  /// YUVA frames that chromakey produces. libx264 accepts any pixel format and
  /// will receive a composed yuv420p stream from the overlay filter.
  ///
  /// CORRECT filter chain:
  ///   [fg]  apply transforms → chromakey (on raw YUV – NO format=rgba) → [fg_keyed]
  ///   [bg]  scale/crop → [bg_ready]
  ///   [bg_ready][fg_keyed] overlay → format=yuv420p → [out]
  static Future<String?> _processClipWithChromaKey(
      VideoClip clip,
      Directory workDir,
      int index,
      int targetWidth,
      int targetHeight,
      double targetFps,
      String encoder, // ignored — always libx264 for chroma key
      Function(double) onClipProgress,
      double sourceStartSeconds,
      double durationSeconds,
      ChromaKeySettings chromaKeySettings,
      String backgroundPath,
      String outputPath,
      {double? forceKeyFrameAt}) async {
    final inputPath = (clip.isReversed &&
                clip.reversedFilePath != null &&
                File(clip.reversedFilePath!).existsSync())
        ? clip.reversedFilePath
        : (clip.videoFile?.path ?? clip.imageFile?.path);
    if (inputPath == null) return null;

    // If chroma key is disabled fall through to normal processing
    if (!chromaKeySettings.enabled ||
        chromaKeySettings.backgroundPath == null) {
      return _processClipComprehensiveNoChromaKey(
          clip, workDir, index, targetWidth, targetHeight, targetFps,
          _softwareEncoder, onClipProgress, sourceStartSeconds, durationSeconds,
          outputPath, preset: 'ultrafast', forceKeyFrameAt: forceKeyFrameAt);
    }

    final keyColorHex = chromaKeySettings.keyColorHex;
    final similarity = chromaKeySettings.similarity.clamp(0.0, 0.6);
    final blend = chromaKeySettings.blend.clamp(0.0, 0.5);
    final scale = chromaKeySettings.scale.clamp(0.1, 3.0);
    final position = chromaKeySettings.position;

    final double speed = clip.playbackSpeed;
    final double outputDurationSeconds = durationSeconds / speed;
    final bool isBgVideo =
        _isVideoExtension(backgroundPath.split('.').last);
    final bool isFgImage = clip.mediaType == MediaType.image;

    // ── Build inputs ────────────────────────────────────────────────────────
    // Input 0: foreground (green-screen clip)
    // Input 1: background (image or video)
    final String fgInput = isFgImage
        ? '-loop 1 -t $outputDurationSeconds -i "$inputPath"'
        : '-ss $sourceStartSeconds -t $durationSeconds -i "$inputPath"';

    final String bgInput = isBgVideo
        ? '-ss $sourceStartSeconds -t $durationSeconds -i "$backgroundPath"'
        : '-loop 1 -t $outputDurationSeconds -i "$backgroundPath"';

    // Input 2: silent audio (fallback when clip has no audio or is muted)
    final String nullAudio =
        '-f lavfi -t $outputDurationSeconds -i anullsrc=channel_layout=stereo:sample_rate=44100';

    final bool hasAudio = clip.mediaType == MediaType.video &&
        await _hasAudioStream(inputPath);

    // ── Build filtergraph ───────────────────────────────────────────────────
    final parts = <String>[];
    String cur = '[0:v]';

    // Crop (if specified)
    if (clip.cropRect != null) {
      final r = clip.cropRect!;
      if (r.right <= 1.001) {
        final w = (r.right - r.left).clamp(0.0, 1.0);
        final h = (r.bottom - r.top).clamp(0.0, 1.0);
        parts.add('${cur}crop=w=trunc(iw*$w/2)*2:h=trunc(ih*$h/2)*2'
            ':x=trunc(iw*${r.left}):y=trunc(ih*${r.top})[ck_cropped]');
        cur = '[ck_cropped]';
      }
    }

    // Mirror
    if (clip.isMirrored) {
      parts.add('${cur}hflip[ck_mirrored]');
      cur = '[ck_mirrored]';
    }

    // Rotation
    if (clip.rotation != 0) {
      final rot = clip.rotation % 360;
      if ((rot - 90).abs() < 0.1) {
        parts.add('${cur}transpose=1[ck_rot]');
      } else if ((rot - 180).abs() < 0.1) {
        parts.add('${cur}transpose=2,transpose=2[ck_rot]');
      } else if ((rot - 270).abs() < 0.1) {
        parts.add('${cur}transpose=2[ck_rot]');
      } else {
        parts.add("${cur}rotate=$rot*PI/180:fillcolor=black"
            ":ow='hypot(iw,ih)':oh='hypot(iw,ih)'[ck_rot]");
      }
      cur = '[ck_rot]';
    }

    // Speed
    if (speed != 1.0 && !isFgImage) {
      parts.add('${cur}setpts=PTS/$speed[ck_speed]');
      cur = '[ck_speed]';
    }

    // Scale foreground to fit canvas, applying the user-specified scale factor
    final int scaledW = (targetWidth * scale).round();
    final int scaledH = (targetHeight * scale).round();
    parts.add('${cur}scale=w=$scaledW:h=$scaledH'
        ':force_original_aspect_ratio=decrease'
        ',pad=$scaledW:$scaledH:(ow-iw)/2:(oh-ih)/2:color=black@0'
        ',setsar=1[ck_scaled]');
    cur = '[ck_scaled]';

    // Apply chromakey on YUV input (correct — no format=rgba before this)
    parts.add('${cur}chromakey=0x$keyColorHex:$similarity:$blend[ck_keyed]');

    // Background: scale to fill the full canvas
    parts.add('[1:v]scale=w=$targetWidth:h=$targetHeight'
        ':force_original_aspect_ratio=increase'
        ',crop=$targetWidth:$targetHeight[ck_bg]');

    // Composite: background under keyed foreground, then convert to yuv420p
    final overlayX = '(W-w)*${position.dx}';
    final overlayY = '(H-h)*${position.dy}';
    parts.add('[ck_bg][ck_keyed]overlay=$overlayX:$overlayY:shortest=1'
        ',fps=$targetFps,format=yuv420p[ck_out]');

    final filterComplex = parts.join(';');

    // ── Build audio handling ────────────────────────────────────────────────
    final int audioInputIdx = 2; // nullAudio is always input index 2
    String audioMap;
    String audioFilter = '';
    if (isFgImage || clip.isMuted || !hasAudio) {
      audioMap = '-map $audioInputIdx:a';
    } else {
      audioMap = '-map 0:a';
      final aFilters = <String>[];
      if (clip.volume != 1.0) aFilters.add('volume=${clip.volume}');
      if (speed != 1.0) {
        double ts = speed;
        while (ts > 2.0) { aFilters.add('atempo=2.0'); ts /= 2.0; }
        while (ts < 0.5) { aFilters.add('atempo=0.5'); ts *= 2.0; }
        aFilters.add('atempo=$ts');
      }
      if (aFilters.isNotEmpty) audioFilter = '-af "${aFilters.join(',')}"';
    }

    // ── Single-pass command ─────────────────────────────────────────────────
    // Both inputs + composite + encode in one FFmpeg invocation.
    // libx264 is mandatory here: hardware encoders reject YUVA frames from
    // chromakey, and alpha must not be stored in an intermediate file.
    final cmd = '-y $fgInput $bgInput $nullAudio '
        '-filter_complex "$filterComplex" '
        '-map "[ck_out]" $audioMap $audioFilter '
        '-c:v $_softwareEncoder -preset ultrafast -tune fastdecode -threads 0 -crf 23 -pix_fmt yuv420p '
        '-c:a aac -ar 44100 -ac 2 -shortest '
        '${forceKeyFrameAt != null ? '-force_key_frames ${_secs(forceKeyFrameAt)} ' : ''}'
        '"$outputPath"';

    final result = await _executeFFmpeg(cmd, onClipProgress,
        outputPath: outputPath, duration: outputDurationSeconds);

    // If single-pass fails fall back to standard export (no chroma key)
    if (result == null) {
      return _processClipComprehensiveNoChromaKey(
          clip, workDir, index, targetWidth, targetHeight, targetFps,
          _softwareEncoder, onClipProgress, sourceStartSeconds, durationSeconds,
          outputPath, preset: 'ultrafast', forceKeyFrameAt: forceKeyFrameAt);
    }
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
      ColorFilter? colorFilter,
      String preset = 'ultrafast',
      double? forceKeyFrameAt}) async {
    var inputPath = (clip.isReversed && clip.reversedFilePath != null && File(clip.reversedFilePath!).existsSync())
        ? clip.reversedFilePath
        : (clip.videoFile?.path ?? clip.imageFile?.path);
    if (inputPath == null) return null;

    // Still images: render the frame once with Flutter at the output size
    // (same contain-fit and EXIF orientation as the preview), then repeat that
    // single frame instead of decoding and rescaling the photo on every frame.
    bool imageFrameReady = false;
    if (clip.mediaType == MediaType.image) {
      final framePath = path.join(workDir.path, 'image_clip_$index.png');
      final rendered = await _prerenderImageClipFrame(
          inputPath, targetWidth, targetHeight, framePath);
      if (rendered != null) {
        inputPath = rendered;
        imageFrameReady = true;
      }
    }

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

      // Explicitly format to rgb24 BEFORE applying color multipliers and offsets.
      filters.add('${inputFilter}format=rgb24[rgb_in]');
      inputFilter = '[rgb_in]';

      // Apply color channel mixing (RGB multipliers)
      filters.add('${inputFilter}colorchannelmixer=rr=$rr:rg=$rg:rb=$rb:gr=$gr:gg=$gg:gb=$gb:br=$br:bg=$bg:bb=$bb[ccm_out]');
      inputFilter = '[ccm_out]';

      // Apply color offsets via SIMD-accelerated lookup table (lutrgb) instead of slow per-pixel geq
      if (roVal.abs() > 0.001 || goVal.abs() > 0.001 || boVal.abs() > 0.001) {
        final ro = roVal.toStringAsFixed(4);
        final go = goVal.toStringAsFixed(4);
        final bo = boVal.toStringAsFixed(4);
        filters.add("${inputFilter}lutrgb=r='clip(val+$ro,0,255)':g='clip(val+$go,0,255)':b='clip(val+$bo,0,255)'[lut_out]");
        inputFilter = '[lut_out]';
      }
    }
    // === END BAKED COLOR FILTERS ===

    String command;
    final double speed = clip.playbackSpeed;
    final outputDurationSeconds = durationSeconds / speed;

    // Format final processing back to yuv420p for standard mp4 encoding
    if (imageFrameReady) {
      final frames = math.max(1, (outputDurationSeconds * targetFps).round());
      filters.add('${inputFilter}format=yuv420p,'
          'loop=loop=${frames - 1}:size=1:start=0,'
          'setpts=N/($targetFps*TB),fps=$targetFps[final_out]');
    } else {
      filters.add('${inputFilter}fps=$targetFps,format=yuv420p[final_out]');
    }
    final keyFrameArg = forceKeyFrameAt != null
        ? '-force_key_frames ${_secs(forceKeyFrameAt)} '
        : '';
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
          '-y -ss $sourceStartSeconds -t $totalDurationSeconds -i "$inputPath" $nullAudio -filter_complex "${filters.join(',')}" -map "[final_out]" $audioMap $audioFilter -c:v $encoder -preset $preset -tune fastdecode -threads 0 -crf 23 -c:a aac -ar 44100 -ac 2 -shortest $keyFrameArg"$outputPath"';
    } else if (imageFrameReady) {
      command =
          '-y -i "$inputPath" $nullAudio -filter_complex "${filters.join(',')}" -map "[final_out]" -map 1:a -c:v $encoder -preset $preset -tune fastdecode -threads 0 -crf 23 -c:a aac -ar 44100 -ac 2 -t ${_secs(outputDurationSeconds)} $keyFrameArg"$outputPath"';
    } else {
      command =
          '-y -loop 1 -t $outputDurationSeconds -i "$inputPath" $nullAudio -filter_complex "${filters.join(',')}" -map "[final_out]" -map 1:a -c:v $encoder -preset $preset -tune fastdecode -threads 0 -crf 23 -c:a aac -ar 44100 -ac 2 -shortest $keyFrameArg"$outputPath"';
    }

    return await _executeFFmpeg(command, onClipProgress,
        outputPath: outputPath, duration: outputDurationSeconds);
  }

  static Future<bool> _hasAudioStream(String path) async {
    final cached = _audioStreamCache[path];
    if (cached != null) return cached;
    final result = await _probeHasAudioStream(path);
    _audioStreamCache[path] = result;
    return result;
  }

  static Future<bool> _probeHasAudioStream(String path) async {
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
    String preset = 'ultrafast',
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
              '-c:v $encoder -preset $preset -tune fastdecode -threads 0 -crf 23 -c:a aac -ar 44100 -ac 2 "$mergedPath"';
        }

        String? result;
        try {
          if (command.startsWith('-y -f concat')) {
            // Hard cut short-circuit logic from above
            result = await _executeFFmpeg(command, onProgress, outputPath: mergedPath, duration: mergedDur);
          } else {
            result = await _executeFFmpeg(command, onProgress, outputPath: mergedPath, duration: mergedDur);
          }
        } catch (e) {
          result = null;
        }

        if (result == null) {
          // Fallback: just concatenate without transition
          final concatFile = File(path.join(workDir.path, 'fallback_$i.txt'));
          await concatFile.writeAsString("file '$current'\nfile '$next'");
          final fallbackPath = path.join(workDir.path, 'fallback_merged_$i.mp4');
          final fbCmd = '-y -f concat -safe 0 -i "${concatFile.path}" -c:v $encoder -preset $preset -tune fastdecode -threads 0 -crf 23 -c:a aac -ar 44100 -ac 2 "$fallbackPath"';
          
          String? fbResult;
          try {
            fbResult = await _executeFFmpeg(fbCmd, null, outputPath: fallbackPath);
          } catch (e) {
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
       required int targetHeight,
       String preset = 'ultrafast'}) async {
    final outputPath = path.join(workDir.path, 'filtered_video_${DateTime.now().millisecondsSinceEpoch}.mp4');

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
      return inputPath;
    }

    final filterString = filters.join(',');

    final command = '-y -i "$inputPath" -vf "$filterString" -c:v $encoder -preset $preset -tune fastdecode -threads 0 -b:v 3M -c:a copy "$outputPath"';

    final result = await _executeFFmpeg(command, onProgress,
        outputPath: outputPath, duration: duration);

    if (result == null) {
    }
    return result ?? inputPath;
  }

  /// Applies video effects, text overlays, and stickers in a **single FFmpeg
  /// pass** to eliminate redundant decode→encode cycles.
  ///
  /// Filter graph:
  ///   [0:v] → setpts → effect_filters → overlay_text₁ → ... → sticker_overlayₙ → [out]
  ///
  /// If only effects are present (no overlays), uses a simple `-vf` pipeline
  /// identical to `_applyVideoFiltersAndEffects`.
  ///
  /// All rendering logic (PNG generation, position calculations, opacity,
  /// timing) is identical to the standalone methods for correctness.
  static Future<String?> _applyEffectsAndOverlaysInOnePass(
      String inputPath,
      VideoProject project,
      Directory workDir,
      String encoder,
      Function(double) onProgress,
      {required double duration,
       required int targetWidth,
       required int targetHeight,
       required double targetFps,
       String preset = 'ultrafast'}) async {
    final hasEffects = project.videoEffects.isNotEmpty;
    final hasText = project.textOverlays.isNotEmpty;
    final hasStickers = project.stickers.isNotEmpty;

    if (!hasEffects && !hasText && !hasStickers) return inputPath;

    // ── 1. Build video effect filter strings ──────────────────────────────
    // (same logic as _applyVideoFiltersAndEffects)
    final effectFilters = <String>[];
    if (hasEffects) {
      for (final effect in project.videoEffects) {
        final start = effect.startTime.inMilliseconds / 1000.0;
        final end =
            (effect.startTime + effect.duration).inMilliseconds / 1000.0;
        if (start >= duration) continue;
        final intensity = effect.intensity.clamp(0.01, 1.0);

        switch (effect.type) {
          case VideoEffectType.blur:
            final radius = (intensity * 15).toStringAsFixed(1);
            effectFilters.add(
                "boxblur=luma_radius=$radius:enable='between(t,$start,$end)'");
            break;
          case VideoEffectType.shake:
            effectFilters.add(
                "colorchannelmixer=rr=1.0:rg=0.1:rb=0.0:gr=0.0:gg=1.0:gb=0.1:br=0.1:bg=0.0:bb=1.0:enable='between(t,$start,$end)*lt(mod(t*15,1.0),0.5)'");
            break;
          case VideoEffectType.flash:
            effectFilters.add(
                "colorchannelmixer=rr=1.5:gg=1.5:bb=1.5:enable='between(t,$start,$end)*lt(mod(t-floor(t-$start),0.3),0.15)'");
            break;
          case VideoEffectType.glitch:
            effectFilters.add(
                "noise=alls=15:allf=t+u:enable='between(t,$start,$end)'");
            break;
          case VideoEffectType.grayscale:
            effectFilters.add(
                "colorchannelmixer=rr=0.2126:rg=0.7152:rb=0.0722:gr=0.2126:gg=0.7152:gb=0.0722:br=0.2126:bg=0.7152:bb=0.0722:enable='between(t,$start,$end)'");
            break;
          case VideoEffectType.sepia:
            effectFilters.add(
                "colorchannelmixer=rr=0.393:rg=0.769:rb=0.189:gr=0.349:gg=0.686:gb=0.168:br=0.272:bg=0.534:bb=0.131:enable='between(t,$start,$end)'");
            break;
          default:
            break;
        }
      }
    }

    // ── 2. Pre-render text overlay PNGs ───────────────────────────────────
    // (same logic as _addTextOverlays)
    final baseAspect = targetWidth / targetHeight;
    var renderedText = <_RenderedOverlay>[];
    if (hasText) {
      final renderFutures = <Future<_RenderedOverlay?>>[];
      for (int i = 0; i < project.textOverlays.length; i++) {
        final overlay = project.textOverlays[i];
        final clipAspect = await _getOverlayAspectRatio(
            project, overlay.startTime, targetWidth, targetHeight);
        final previewCanvasWidth =
            (1920.0 * clipAspect).round().clamp(1, 4096).toDouble();
        const previewCanvasHeight = 1920.0;

        renderFutures.add(
          _renderTextOverlayImage(
            overlay: overlay,
            fontSize: overlay.fontSize.clamp(1.0, 512.0).toDouble(),
            workDir: workDir,
            index: i,
            canvasWidth: previewCanvasWidth,
            canvasHeight: previewCanvasHeight,
          ).then((file) {
            if (file == null) return null;
            return _RenderedOverlay(
              index: i,
              file: file,
              overlay: overlay,
              clipAspect: clipAspect,
            );
          }),
        );
      }
      renderedText = (await Future.wait(renderFutures))
          .whereType<_RenderedOverlay>()
          .toList();
    }

    // ── 3. Pre-render sticker PNGs ───────────────────────────────────────
    // (same logic as _addStickers)
    var renderedStickers = <_RenderedSticker>[];
    if (hasStickers) {
      for (int i = 0; i < project.stickers.length; i++) {
        final sticker = project.stickers[i];
        final clipAspect = await _getOverlayAspectRatio(
            project, sticker.startTime, targetWidth, targetHeight);

        double clipWidthInsideTarget = clipAspect > baseAspect
            ? targetWidth.toDouble()
            : targetHeight * clipAspect;
        double clipHeightInsideTarget = clipAspect > baseAspect
            ? targetWidth / clipAspect
            : targetHeight.toDouble();

        double padX = (targetWidth - clipWidthInsideTarget) / 2;
        double padY = (targetHeight - clipHeightInsideTarget) / 2;

        final previewCanvasWidth =
            (1920.0 * clipAspect).round().clamp(1, 4096);
        const previewCanvasHeight = 1920.0;
        final tempStickerFile = await _renderStickerOverlayImage(
          sticker: sticker,
          workDir: workDir,
          index: i,
          canvasWidth: previewCanvasWidth.toDouble(),
          canvasHeight: previewCanvasHeight,
        );
        if (tempStickerFile == null) continue;

        renderedStickers.add(_RenderedSticker(
          file: tempStickerFile,
          sticker: sticker,
          scaledWidth: clipWidthInsideTarget.round(),
          scaledHeight: clipHeightInsideTarget.round(),
          x: padX.round(),
          y: padY.round(),
        ));
      }
    }

    // ── 4. Short-circuit if nothing to do after rendering ────────────────
    final hasEffectFilters = effectFilters.isNotEmpty;
    final hasOverlays = renderedText.isNotEmpty || renderedStickers.isNotEmpty;

    if (!hasEffectFilters && !hasOverlays) return inputPath;

    // ── 4a. Effects-only path — simple -vf, identical to original ────────
    if (hasEffectFilters && !hasOverlays) {
      final filterString = effectFilters.join(',');
      final effectsOutputPath = path.join(workDir.path, 'effects_only.mp4');
      final command = '-y -i "$inputPath" -vf "$filterString" '
          '-c:v $encoder -preset $preset -tune fastdecode -threads 0 '
          '-crf 23 -c:a copy "$effectsOutputPath"';
      return await _executeFFmpeg(command, onProgress,
              outputPath: effectsOutputPath, duration: duration) ??
          inputPath;
    }

    // ── 4b. Merged path — ONE filter_complex for everything ─────────────
    final inputArgs = StringBuffer('-y -i "$inputPath"');

    // Input indices: 0 = base video, 1..N = text PNGs, N+1..M = sticker PNGs
    int nextInputIdx = 1;
    final textInputStartIdx = nextInputIdx;
    for (final r in renderedText) {
      inputArgs.write(' -loop 1 -t $duration -i "${r.file.path}"');
      nextInputIdx++;
    }
    final stickerInputStartIdx = nextInputIdx;
    for (final r in renderedStickers) {
      inputArgs.write(' -loop 1 -t $duration -i "${r.file.path}"');
      nextInputIdx++;
    }

    final totalOverlays = renderedText.length + renderedStickers.length;
    final fc = StringBuffer();
    String prevOut;

    // Start with [0:v], apply effects first (if any), then hand off to overlays
    if (hasEffectFilters) {
      fc.write('[0:v]setpts=PTS-STARTPTS,${effectFilters.join(",")}[fx_out];');
    } else {
      fc.write('[0:v]setpts=PTS-STARTPTS[fx_out];');
    }
    prevOut = 'fx_out';

    // Chain text overlays — SAME filter params as _addTextOverlays
    int overlayCounter = 0;
    for (int j = 0; j < renderedText.length; j++) {
      final r = renderedText[j];
      final inputIdx = textInputStartIdx + j;
      overlayCounter++;

      final double clipW = r.clipAspect > baseAspect
          ? targetWidth.toDouble()
          : targetHeight * r.clipAspect;
      final double clipH = r.clipAspect > baseAspect
          ? targetWidth / r.clipAspect
          : targetHeight.toDouble();

      final padX = (targetWidth - clipW) / 2;
      final padY = (targetHeight - clipH) / 2;

      final w = ((clipW).round() ~/ 2) * 2;
      final h = ((clipH).round() ~/ 2) * 2;
      final x = padX.round();
      final y = padY.round();
      final opacity = r.overlay.opacity.clamp(0.0, 1.0);
      final opacityFilter = opacity < 1.0
          ? ',format=rgba,colorchannelmixer=aa=$opacity'
          : ',format=rgba';

      final start = r.overlay.startTime.inMilliseconds / 1000.0;
      final end = r.overlay.endTime.inMilliseconds / 1000.0;
      final outLabel =
          (overlayCounter == totalOverlays) ? 'out' : 'v$overlayCounter';

      fc.write(
          '[$inputIdx:v]fps=$targetFps,setpts=PTS-STARTPTS,scale=$w:$h$opacityFilter[ov$inputIdx];');
      fc.write(
          '[$prevOut][ov$inputIdx]overlay=$x:$y:enable=\'between(t,$start,$end)\':eof_action=pass[$outLabel];');
      prevOut = outLabel;
    }

    // Chain stickers — SAME filter params as _addStickers
    for (int j = 0; j < renderedStickers.length; j++) {
      final r = renderedStickers[j];
      final inputIdx = stickerInputStartIdx + j;
      overlayCounter++;

      final start = r.sticker.startTime.inMilliseconds / 1000.0;
      final end = r.sticker.endTime.inMilliseconds / 1000.0;
      final opacity = r.sticker.opacity.clamp(0.0, 1.0);
      final opacityFilter =
          opacity < 1.0 ? ',colorchannelmixer=aa=$opacity' : '';
      final outLabel =
          (overlayCounter == totalOverlays) ? 'out' : 'v$overlayCounter';

      fc.write(
          '[$inputIdx:v]fps=$targetFps,setpts=PTS-STARTPTS,format=rgba,scale=${r.scaledWidth}:${r.scaledHeight}$opacityFilter[stk$inputIdx];');
      fc.write(
          '[$prevOut][stk$inputIdx]overlay=${r.x}:${r.y}:enable=\'between(t,$start,$end)\':eof_action=pass[$outLabel];');
      prevOut = outLabel;
    }

    // Remove trailing semicolon
    String fcStr = fc.toString();
    if (fcStr.endsWith(';')) fcStr = fcStr.substring(0, fcStr.length - 1);

    final tempOutput =
        path.join(workDir.path, 'combined_effects_overlays.mp4');
    final command = '$inputArgs -filter_complex "$fcStr" '
        '-map "[out]" -map 0:a? '
        '-c:v $encoder -preset $preset -tune fastdecode -threads 0 -crf 23 '
        '-r $targetFps -pix_fmt yuv420p -c:a copy -shortest "$tempOutput"';

    final result = await _executeFFmpeg(command, onProgress,
        outputPath: tempOutput, duration: duration);

    if (result != null) return result;

    // ── Fallback: original multi-pass approach if merged command fails ───
    String current = inputPath;

    if (hasEffectFilters) {
      final filtered = await _applyVideoFiltersAndEffects(
          current, project, workDir, encoder, (p) => onProgress(p * 0.33),
          duration: duration,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          preset: preset);
      if (filtered != null) current = filtered;
    }

    if (project.textOverlays.isNotEmpty) {
      final withText = await _addTextOverlays(
          current, project, workDir, (p) => onProgress(0.33 + p * 0.33),
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          duration: duration,
          encoder: encoder,
          targetFps: targetFps,
          preset: preset);
      if (withText != null) current = withText;
    }

    if (project.stickers.isNotEmpty) {
      final withStickers = await _addStickers(
          current, project, workDir, (p) => onProgress(0.66 + p * 0.34),
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          duration: duration,
          encoder: encoder,
          targetFps: targetFps,
          preset: preset);
      if (withStickers != null) current = withStickers;
    }

    return current;
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
      required double targetFps,
      String preset = 'ultrafast'}) async {
    
    final stickers = project.stickers;
    if (stickers.isEmpty) return inputPath;
    
    final baseAspect = targetWidth / targetHeight;

    final renderedStickers = <_RenderedSticker>[];
    for (int i = 0; i < stickers.length; i++) {
      final sticker = stickers[i];
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

      renderedStickers.add(_RenderedSticker(
        file: tempStickerFile,
        sticker: sticker,
        scaledWidth: clipWidthInsideTarget.round(),
        scaledHeight: clipHeightInsideTarget.round(),
        x: padX.round(),
        y: padY.round(),
      ));
    }

    if (renderedStickers.isEmpty) return inputPath;

    // Build a single filter_complex string covering ALL stickers in ONE pass
    final inputArgs = StringBuffer('-y -i "$inputPath"');
    final fc = StringBuffer();
    String prevOut = 'in0';
    fc.write('[0:v]setpts=PTS-STARTPTS[$prevOut];');

    for (int j = 0; j < renderedStickers.length; j++) {
      final r = renderedStickers[j];
      final inputIdx = j + 1;
      inputArgs.write(' -loop 1 -t $duration -i "${r.file.path}"');

      final start = r.sticker.startTime.inMilliseconds / 1000.0;
      final end = r.sticker.endTime.inMilliseconds / 1000.0;
      final opacity = r.sticker.opacity.clamp(0.0, 1.0);
      final opacityFilter = opacity < 1.0 ? ",colorchannelmixer=aa=$opacity" : "";
      final outLabel = j == renderedStickers.length - 1 ? 'out' : 'out$j';

      fc.write('[$inputIdx:v]fps=$targetFps,setpts=PTS-STARTPTS,format=rgba,scale=${r.scaledWidth}:${r.scaledHeight}$opacityFilter[stk$inputIdx];');
      fc.write('[$prevOut][stk$inputIdx]overlay=${r.x}:${r.y}:enable=\'between(t,$start,$end)\':eof_action=pass[$outLabel];');
      prevOut = outLabel;
    }

    String fcStr = fc.toString();
    if (fcStr.endsWith(';')) fcStr = fcStr.substring(0, fcStr.length - 1);

    final tempOutput = path.join(workDir.path, 'with_stickers_batch.mp4');
    final command =
        '$inputArgs -filter_complex "$fcStr" '
        '-map "[out]" -map 0:a? '
        '-c:v $encoder -preset $preset -tune fastdecode -threads 0 -b:v 3M -r $targetFps -pix_fmt yuv420p -c:a copy -shortest "$tempOutput"';

    final result = await _executeFFmpeg(command, onProgress, outputPath: tempOutput, duration: duration);
    return result ?? inputPath;
  }

  static Future<String?> _addMediaOverlays(String inputPath,
      List<VideoClip> overlays, Directory workDir, Function(double) onProgress,
      {required int targetWidth,
      required int targetHeight,
      required double duration,
      required String encoder,
      String preset = 'ultrafast'}) async {
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
      final width = math.max(2, ((overlay.overlaySize.width * targetWidth).round() ~/ 2) * 2);
      final height = math.max(2, ((overlay.overlaySize.height * targetHeight).round() ~/ 2) * 2);
      final x = (overlay.overlayPosition.dx * targetWidth).round();
      final y = (overlay.overlayPosition.dy * targetHeight).round();
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
            '-map "[out]" -map 1:a? -c:v $encoder -preset $preset -tune fastdecode -threads 0 -b:v 3M -c:a copy -shortest "$tempOutput"';
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

        final overlayHasAudio = !overlay.isMuted &&
            overlay.volume > 0 &&
            await _hasAudioStream(overlayFilePath);
        final baseHasAudio = await _hasAudioStream(currentInput);

        if (overlayHasAudio) {
          final overlayVol = overlay.volume.clamp(0.0, 2.0);
          final delayMs = overlay.startTime.inMilliseconds;
          if (baseHasAudio) {
            command = '-y -i "$trimmedOverlay" -i "$currentInput" '
                '-filter_complex "[0:v]setpts=PTS-STARTPTS+$start/TB,scale=$width:$height:force_original_aspect_ratio=decrease$opacityFilter[opacity];'
                '[1:v][opacity]overlay=$x:$y:enable=\'between(t,$start,$end)\'[out];'
                '[0:a]volume=$overlayVol,adelay=$delayMs|$delayMs[a_delayed];'
                '[1:a][a_delayed]amix=inputs=2:duration=first:dropout_transition=0[aout]" '
                '-map "[out]" -map "[aout]" -c:v $encoder -preset $preset -tune fastdecode -threads 0 -b:v 3M -c:a aac "$tempOutput"';
          } else {
            command = '-y -i "$trimmedOverlay" -i "$currentInput" '
                '-filter_complex "[0:v]setpts=PTS-STARTPTS+$start/TB,scale=$width:$height:force_original_aspect_ratio=decrease$opacityFilter[opacity];'
                '[1:v][opacity]overlay=$x:$y:enable=\'between(t,$start,$end)\'[out];'
                '[0:a]volume=$overlayVol,adelay=$delayMs|$delayMs[aout]" '
                '-map "[out]" -map "[aout]" -c:v $encoder -preset $preset -tune fastdecode -threads 0 -b:v 3M -c:a aac "$tempOutput"';
          }
        } else {
          command = '-y -i "$trimmedOverlay" -i "$currentInput" '
              '-filter_complex "[0:v]setpts=PTS-STARTPTS+$start/TB,scale=$width:$height:force_original_aspect_ratio=decrease$opacityFilter[opacity];'
              '[1:v][opacity]overlay=$x:$y:enable=\'between(t,$start,$end)\'[out]" '
              '-map "[out]" -map 1:a? -c:v $encoder -preset $preset -tune fastdecode -threads 0 -b:v 3M -c:a copy "$tempOutput"';
        }
      }


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

  /// Adds ALL text overlays in a **single FFmpeg pass** for maximum speed.
  ///
  /// Each overlay PNG is loaded as a separate input.  A filter chain is built
  /// once: `[0:v]` is the video, `[N:v]` are the overlay images.
  static Future<String?> _addTextOverlays(
      String inputPath,
      VideoProject project,
      Directory workDir,
      Function(double) onProgress,
      {required int targetWidth,
      required int targetHeight,
      required double duration,
      required String encoder,
      required double targetFps,
      String preset = 'ultrafast'}) async {
    final overlays = project.textOverlays;
    if (overlays.isEmpty) return inputPath;

    final baseAspect = targetWidth / targetHeight;

    // Render all overlay PNGs first (can be done concurrently)
    final renderFutures = <Future<_RenderedOverlay?>>[];
    for (int i = 0; i < overlays.length; i++) {
      final overlay = overlays[i];
      final clipAspect =
          await _getOverlayAspectRatio(project, overlay.startTime, targetWidth, targetHeight);
      final previewCanvasWidth =
          (1920.0 * clipAspect).round().clamp(1, 4096).toDouble();
      const previewCanvasHeight = 1920.0;

      renderFutures.add(
        _renderTextOverlayImage(
          overlay: overlay,
          fontSize: overlay.fontSize.clamp(1.0, 512.0).toDouble(),
          workDir: workDir,
          index: i,
          canvasWidth: previewCanvasWidth,
          canvasHeight: previewCanvasHeight,
        ).then((file) {
          if (file == null) return null;
          return _RenderedOverlay(
            index: i,
            file: file,
            overlay: overlay,
            clipAspect: clipAspect,
          );
        }),
      );
    }

    final rendered = (await Future.wait(renderFutures))
        .whereType<_RenderedOverlay>()
        .toList();

    if (rendered.isEmpty) return inputPath;

    // Build a single filter_complex string covering all overlays in one pass.
    // Input 0 = base video; inputs 1..N = overlay PNGs.
    final inputArgs = StringBuffer('-y -i "$inputPath"');
    final fc = StringBuffer();

    // Sequential chain: [prevOut] + [N:v] -> [outN]
    String prevOut = 'in0';
    fc.write('[0:v]setpts=PTS-STARTPTS[$prevOut];');

    for (int j = 0; j < rendered.length; j++) {
      final r = rendered[j];
      final inputIdx = j + 1;
      inputArgs.write(' -loop 1 -t $duration -i "${r.file.path}"');

      final double clipW = r.clipAspect > baseAspect
          ? targetWidth.toDouble()
          : targetHeight * r.clipAspect;
      final double clipH = r.clipAspect > baseAspect
          ? targetWidth / r.clipAspect
          : targetHeight.toDouble();
      
      final padX = (targetWidth - clipW) / 2;
      final padY = (targetHeight - clipH) / 2;

      final w = ((clipW).round() ~/ 2) * 2;
      final h = ((clipH).round() ~/ 2) * 2;
      final x = padX.round();
      final y = padY.round();
      final opacity = r.overlay.opacity.clamp(0.0, 1.0);
      final opacityFilter = opacity < 1.0
          ? ',format=rgba,colorchannelmixer=aa=$opacity'
          : ',format=rgba';

      final start = r.overlay.startTime.inMilliseconds / 1000.0;
      final end = r.overlay.endTime.inMilliseconds / 1000.0;
      final outLabel = j == rendered.length - 1 ? 'out' : 'out$j';

      fc.write('[$inputIdx:v]fps=$targetFps,setpts=PTS-STARTPTS,scale=$w:$h$opacityFilter[ov$inputIdx];');
      fc.write('[$prevOut][ov$inputIdx]overlay=$x:$y:enable=\'between(t,$start,$end)\':eof_action=pass[$outLabel];');
      prevOut = outLabel;
    }

    // Remove trailing semicolon
    String fcStr = fc.toString();
    if (fcStr.endsWith(';')) fcStr = fcStr.substring(0, fcStr.length - 1);

    final tempOutput = path.join(workDir.path, 'with_text_overlays_batch.mp4');
    final command =
        '$inputArgs -filter_complex "$fcStr" '
        '-map "[out]" -map 0:a? '
        '-c:v $encoder -preset $preset -tune fastdecode -threads 0 -b:v 3M -r $targetFps -pix_fmt yuv420p -c:a copy -shortest "$tempOutput"';

    final result = await _executeFFmpeg(command, onProgress,
        outputPath: tempOutput, duration: duration);

    return result ?? inputPath;
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
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Fast, preview-accurate pipeline helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Length of the whole timeline in seconds — identical to the preview's
  /// `VideoEditorProvider.totalDuration` (video clips, audio and text).
  static double _timelineTotalSeconds(VideoProject project) {
    var maxMs = 0;
    for (final c in project.videoClips) {
      if (c.endTime.inMilliseconds > maxMs) maxMs = c.endTime.inMilliseconds;
    }
    for (final a in project.audioOverlays) {
      if (a.endTime.inMilliseconds > maxMs) maxMs = a.endTime.inMilliseconds;
    }
    for (final t in project.textOverlays) {
      if (t.endTime.inMilliseconds > maxMs) maxMs = t.endTime.inMilliseconds;
    }
    return maxMs / 1000.0;
  }

  static String _secs(double v) => v.toStringAsFixed(6);

  /// Area (inside the output frame) that the preview box maps to at [time].
  /// The preview draws text, stickers and media overlays relative to a box
  /// with the current clip's aspect ratio; the exporter fits that clip into
  /// the output frame, so overlays must be placed inside the same area.
  static Future<Rect> _clipAreaAt(VideoProject project, Duration time,
      int targetWidth, int targetHeight) async {
    final clipAspect = await _getClipAspectRatio(project, time);
    final baseAspect = targetWidth / targetHeight;
    final clipW = clipAspect > baseAspect
        ? targetWidth.toDouble()
        : targetHeight * clipAspect;
    final clipH = clipAspect > baseAspect
        ? targetWidth / clipAspect
        : targetHeight.toDouble();
    return Rect.fromLTWH((targetWidth - clipW) / 2, (targetHeight - clipH) / 2,
        clipW, clipH);
  }

  /// Draws [paint] on a [designWidth] x [designHeight] canvas scaled to
  /// [outWidth] x [outHeight], trims fully transparent borders and writes a
  /// small PNG. Returns null when nothing visible was drawn.
  ///
  /// Pre-rendering at the final pixel size (instead of a full-frame PNG that
  /// FFmpeg decodes and rescales on every frame) is the main export speed-up.
  static Future<_LayerPng?> _rasterizeLayer({
    required void Function(Canvas canvas) paint,
    required double designWidth,
    required double designHeight,
    required int outWidth,
    required int outHeight,
    required double offsetX,
    required double offsetY,
    required String filePath,
    double opacity = 1.0,
  }) async {
    if (outWidth <= 0 || outHeight <= 0) return null;
    if (designWidth <= 0 || designHeight <= 0) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(outWidth / designWidth, outHeight / designHeight);
    final op = opacity.clamp(0.0, 1.0).toDouble();
    if (op < 1.0) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, op));
    }
    paint(canvas);
    if (op < 1.0) canvas.restore();
    final picture = recorder.endRecording();
    final full = await picture.toImage(outWidth, outHeight);
    picture.dispose();
    try {
      final raw = await full.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) return null;
      final bytes =
          raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
      int minX = outWidth, minY = outHeight, maxX = -1, maxY = -1;
      for (int y = 0; y < outHeight; y++) {
        final row = y * outWidth * 4 + 3;
        int rowMin = -1, rowMax = -1;
        for (int x = 0; x < outWidth; x++) {
          if (bytes[row + x * 4] != 0) {
            rowMin = x;
            break;
          }
        }
        if (rowMin < 0) continue;
        for (int x = outWidth - 1; x >= rowMin; x--) {
          if (bytes[row + x * 4] != 0) {
            rowMax = x;
            break;
          }
        }
        if (rowMin < minX) minX = rowMin;
        if (rowMax > maxX) maxX = rowMax;
        if (y < minY) minY = y;
        maxY = y;
      }
      if (maxX < 0) return null;
      final cw = maxX - minX + 1;
      final ch = maxY - minY + 1;
      final rec2 = ui.PictureRecorder();
      Canvas(rec2).drawImageRect(
        full,
        Rect.fromLTWH(
            minX.toDouble(), minY.toDouble(), cw.toDouble(), ch.toDouble()),
        Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
        Paint()..filterQuality = FilterQuality.none,
      );
      final pic2 = rec2.endRecording();
      final cropped = await pic2.toImage(cw, ch);
      pic2.dispose();
      final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
      cropped.dispose();
      if (png == null) return null;
      final file = File(filePath);
      await file.writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
      return _LayerPng(
          file, (offsetX + minX).round(), (offsetY + minY).round());
    } finally {
      full.dispose();
    }
  }

  /// Decodes an image file with Flutter (EXIF orientation applied exactly as
  /// in the preview's `Image.file`), limiting the decoded size to [maxSide].
  static Future<ui.Image?> _decodeImageFile(String filePath, int maxSide) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (int w, int h) {
          final longest = math.max(w, h);
          final s = (maxSide > 0 && longest > maxSide) ? maxSide / longest : 1.0;
          return ui.TargetImageSize(
            width: math.max(1, (w * s).round()),
            height: math.max(1, (h * s).round()),
          );
        },
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static Rect _containRect(double srcW, double srcH, Rect box) {
    if (srcW <= 0 || srcH <= 0) return box;
    final s = math.min(box.width / srcW, box.height / srcH);
    final w = srcW * s;
    final h = srcH * s;
    return Rect.fromLTWH(
        box.left + (box.width - w) / 2, box.top + (box.height - h) / 2, w, h);
  }

  /// Renders a still-image clip onto a black output-size frame (contain fit,
  /// like the preview) and writes it as PNG. Returns null on failure.
  static Future<String?> _prerenderImageClipFrame(String imagePath,
      int targetWidth, int targetHeight, String outPath) async {
    final image = await _decodeImageFile(
        imagePath, math.max(targetWidth, targetHeight));
    if (image == null) return null;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final frame = Rect.fromLTWH(
          0, 0, targetWidth.toDouble(), targetHeight.toDouble());
      canvas.drawRect(frame, Paint()..color = const Color(0xFF000000));
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        _containRect(image.width.toDouble(), image.height.toDouble(), frame),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(targetWidth, targetHeight);
      picture.dispose();
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      if (png == null) return null;
      await File(outPath).writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
      return outPath;
    } catch (_) {
      return null;
    } finally {
      image.dispose();
    }
  }

  /// Text layer rendered exactly like the preview's text widget.
  static Future<_LayerPng?> _renderTextLayer(
    TextOverlay overlay,
    Rect clipArea,
    double designWidth,
    String filePath,
  ) async {
    TextStyle style;
    try {
      style = GoogleFonts.getFont(
        overlay.fontFamily,
        fontSize: overlay.fontSize.clamp(1.0, 512.0).toDouble(),
        color: overlay.color,
        fontWeight: overlay.fontWeight,
        fontStyle: overlay.flutterFontStyle,
        shadows: const [
          Shadow(offset: Offset(1, 1), color: Colors.black54, blurRadius: 2),
        ],
      );
    } catch (_) {
      style = GoogleFonts.roboto(
        fontSize: overlay.fontSize.clamp(1.0, 512.0).toDouble(),
        color: overlay.color,
        fontWeight: overlay.fontWeight,
        fontStyle: overlay.flutterFontStyle,
        shadows: const [
          Shadow(offset: Offset(1, 1), color: Colors.black54, blurRadius: 2),
        ],
      );
    }
    try {
      // Make sure the font is actually loaded before rasterizing.
      await GoogleFonts.pendingFonts([style]);
    } catch (_) {}

    const designHeight = 1920.0;
    // The preview draws the text inside a container with a 3px border and
    // 4px padding, positioned at (dx, dy) of the preview box, without wrapping.
    const previewInset = 7.0;
    final painter = TextPainter(
      text: TextSpan(text: overlay.text, style: style),
      textAlign: overlay.flutterTextAlign,
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = Offset(
      overlay.position.dx * designWidth + previewInset,
      overlay.position.dy * designHeight + previewInset,
    );
    return _rasterizeLayer(
      paint: (canvas) => painter.paint(canvas, origin),
      designWidth: designWidth,
      designHeight: designHeight,
      outWidth: clipArea.width.round(),
      outHeight: clipArea.height.round(),
      offsetX: clipArea.left,
      offsetY: clipArea.top,
      filePath: filePath,
      opacity: overlay.opacity,
    );
  }

  /// Sticker layer rendered exactly like the preview's sticker widget
  /// (600 * scale box centred on the position, rotated, image contain-fit).
  static Future<_LayerPng?> _renderStickerLayer(
    StickerModel sticker,
    Rect clipArea,
    double designWidth,
    String filePath,
  ) async {
    ui.Image? image;
    try {
      final byteData = await rootBundle.load(sticker.assetPath);
      final codec = await ui.instantiateImageCodec(byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
      image = (await codec.getNextFrame()).image;
      codec.dispose();
    } catch (_) {
      return null;
    }
    final img = image;
    try {
      const designHeight = 1920.0;
      const previewBaseStickerSize = 600.0;
      final size = previewBaseStickerSize * sticker.scale;
      final center = Offset(sticker.position.dx * designWidth,
          sticker.position.dy * designHeight);
      return await _rasterizeLayer(
        paint: (canvas) {
          canvas.save();
          canvas.translate(center.dx, center.dy);
          canvas.rotate(sticker.rotation);
          final box = Rect.fromCenter(
              center: Offset.zero, width: size, height: size);
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            _containRect(img.width.toDouble(), img.height.toDouble(), box),
            Paint()..filterQuality = FilterQuality.high,
          );
          canvas.restore();
        },
        designWidth: designWidth,
        designHeight: designHeight,
        outWidth: clipArea.width.round(),
        outHeight: clipArea.height.round(),
        offsetX: clipArea.left,
        offsetY: clipArea.top,
        filePath: filePath,
        opacity: sticker.opacity,
      );
    } finally {
      img.dispose();
    }
  }

  /// Image media overlay pre-rendered at its final on-screen size.
  static Future<_LayerPng?> _renderImageOverlayLayer(
      String imagePath, Rect box, double opacity, String filePath) async {
    final w = box.width.round();
    final h = box.height.round();
    if (w < 1 || h < 1) return null;
    final image = await _decodeImageFile(imagePath, math.max(w, h));
    if (image == null) return null;
    try {
      return await _rasterizeLayer(
        paint: (canvas) {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            _containRect(image.width.toDouble(), image.height.toDouble(),
                Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())),
            Paint()..filterQuality = FilterQuality.high,
          );
        },
        designWidth: w.toDouble(),
        designHeight: h.toDouble(),
        outWidth: w,
        outHeight: h,
        offsetX: box.left,
        offsetY: box.top,
        filePath: filePath,
        opacity: opacity,
      );
    } finally {
      image.dispose();
    }
  }

  static List<String> _effectFilterStrings(
      VideoProject project, double duration) {
    final out = <String>[];
    for (final effect in project.videoEffects) {
      final start = effect.startTime.inMilliseconds / 1000.0;
      final end = (effect.startTime + effect.duration).inMilliseconds / 1000.0;
      if (start >= duration) continue;
      final intensity = effect.intensity.clamp(0.01, 1.0);
      switch (effect.type) {
        case VideoEffectType.blur:
          final radius = (intensity * 15).toStringAsFixed(1);
          out.add("boxblur=luma_radius=$radius:enable='between(t,$start,$end)'");
          break;
        case VideoEffectType.shake:
          out.add(
              "colorchannelmixer=rr=1.0:rg=0.1:rb=0.0:gr=0.0:gg=1.0:gb=0.1:br=0.1:bg=0.0:bb=1.0:enable='between(t,$start,$end)*lt(mod(t*15,1.0),0.5)'");
          break;
        case VideoEffectType.flash:
          out.add(
              "colorchannelmixer=rr=1.5:gg=1.5:bb=1.5:enable='between(t,$start,$end)*lt(mod(t-floor(t-$start),0.3),0.15)'");
          break;
        case VideoEffectType.glitch:
          out.add("noise=alls=15:allf=t+u:enable='between(t,$start,$end)'");
          break;
        case VideoEffectType.grayscale:
          out.add(
              "colorchannelmixer=rr=0.2126:rg=0.7152:rb=0.0722:gr=0.2126:gg=0.7152:gb=0.0722:br=0.2126:bg=0.7152:bb=0.0722:enable='between(t,$start,$end)'");
          break;
        case VideoEffectType.sepia:
          out.add(
              "colorchannelmixer=rr=0.393:rg=0.769:rb=0.189:gr=0.349:gg=0.686:gb=0.168:br=0.272:bg=0.534:bb=0.131:enable='between(t,$start,$end)'");
          break;
        default:
          break;
      }
    }
    return out;
  }

  /// Composites media overlays, text and stickers onto [basePath] in the same
  /// stacking order as the preview (media overlays, then text, then
  /// stickers), in as few encoding passes as possible.
  ///
  /// Returns [basePath] when there is nothing to draw, or null on failure so
  /// the caller can fall back to the previous multi-pass implementation.
  static Future<String?> _composeLayers({
    required VideoProject project,
    required String basePath,
    required Directory workDir,
    required int targetWidth,
    required int targetHeight,
    required double targetFps,
    required double duration,
    required String encoder,
    required String preset,
    required void Function(double) onProgress,
  }) async {
    final effects = _effectFilterStrings(project, duration);
    final layers = <_ComposeLayer>[];

    // 1. Media overlays (bottom of the overlay stack in the preview)
    for (int i = 0; i < project.overlayClips.length; i++) {
      final o = project.overlayClips[i];
      final filePath = o.videoFile?.path ?? o.imageFile?.path;
      if (filePath == null) continue;
      final start = o.startTime.inMilliseconds / 1000.0;
      final end = o.endTime.inMilliseconds / 1000.0;
      if (end <= start) continue;
      final area =
          await _clipAreaAt(project, o.startTime, targetWidth, targetHeight);
      final box = Rect.fromLTWH(
        area.left + o.overlayPosition.dx * area.width,
        area.top + o.overlayPosition.dy * area.height,
        math.max(2.0, o.overlaySize.width * area.width),
        math.max(2.0, o.overlaySize.height * area.height),
      );
      final opacity = o.overlayOpacity.clamp(0.0, 1.0).toDouble();
      if (o.mediaType == MediaType.image) {
        final png = await _renderImageOverlayLayer(filePath, box, opacity,
            path.join(workDir.path, 'layer_media_$i.png'));
        if (png != null) {
          layers.add(_ComposeLayer.png(png, start, end));
        } else {
          layers.add(_ComposeLayer.rawImage(filePath, box, opacity, start, end));
        }
      } else {
        final hasAudio = !o.isMuted &&
            o.volume > 0 &&
            await _hasAudioStream(filePath);
        layers.add(_ComposeLayer.video(
          filePath,
          box,
          opacity,
          start,
          end,
          trimStart: o.trimStart.inMilliseconds / 1000.0,
          trimDuration: o.trimmedDuration.inMilliseconds / 1000.0,
          withAudio: hasAudio,
          volume: o.volume.clamp(0.0, 2.0).toDouble(),
        ));
      }
    }

    // 2. Text overlays
    for (int i = 0; i < project.textOverlays.length; i++) {
      final t = project.textOverlays[i];
      final start = t.startTime.inMilliseconds / 1000.0;
      final end = t.endTime.inMilliseconds / 1000.0;
      if (end <= start) continue;
      final clipAspect = await _getClipAspectRatio(project, t.startTime);
      final area =
          await _clipAreaAt(project, t.startTime, targetWidth, targetHeight);
      final designWidth =
          (1920.0 * clipAspect).round().clamp(1, 4096).toDouble();
      final png = await _renderTextLayer(
          t, area, designWidth, path.join(workDir.path, 'layer_text_$i.png'));
      if (png != null) layers.add(_ComposeLayer.png(png, start, end));
    }

    // 3. Stickers (top of the stack in the preview)
    for (int i = 0; i < project.stickers.length; i++) {
      final s = project.stickers[i];
      final start = s.startTime.inMilliseconds / 1000.0;
      final end = s.endTime.inMilliseconds / 1000.0;
      if (end <= start) continue;
      final clipAspect = await _getClipAspectRatio(project, s.startTime);
      final area =
          await _clipAreaAt(project, s.startTime, targetWidth, targetHeight);
      final designWidth =
          (1920.0 * clipAspect).round().clamp(1, 4096).toDouble();
      final png = await _renderStickerLayer(s, area, designWidth,
          path.join(workDir.path, 'layer_sticker_$i.png'));
      if (png != null) layers.add(_ComposeLayer.png(png, start, end));
    }

    if (effects.isEmpty && layers.isEmpty) return basePath;

    // Split into passes: at most 3 simultaneously decoded videos per pass
    // (keeps memory low on phones) and a bounded number of inputs.
    const maxVideosPerPass = 3;
    const maxInputsPerPass = 24;
    final passes = <List<_ComposeLayer>>[];
    var currentPass = <_ComposeLayer>[];
    var videosInPass = 0;
    for (final l in layers) {
      final isVideo = l.kind == _ComposeLayerKind.video;
      if (currentPass.isNotEmpty &&
          ((isVideo && videosInPass >= maxVideosPerPass) ||
              currentPass.length >= maxInputsPerPass)) {
        passes.add(currentPass);
        currentPass = <_ComposeLayer>[];
        videosInPass = 0;
      }
      currentPass.add(l);
      if (isVideo) videosInPass++;
    }
    if (currentPass.isNotEmpty || passes.isEmpty) passes.add(currentPass);

    String current = basePath;
    for (int p = 0; p < passes.length; p++) {
      final pass = passes[p];
      final inputs = StringBuffer('-y -i "$current"');
      final fc = StringBuffer();
      final baseFx = (p == 0 && effects.isNotEmpty) ? ',${effects.join(',')}' : '';
      fc.write('[0:v]setpts=PTS-STARTPTS$baseFx[b0];');
      var prev = 'b0';
      final audioLabels = <String>[];
      for (int j = 0; j < pass.length; j++) {
        final l = pass[j];
        final idx = j + 1;
        final layerDur = math.max(1.0 / targetFps, l.end - l.start);
        final bw = l.box == null ? 0 : math.max(2, (l.box!.width.round() ~/ 2) * 2);
        final bh = l.box == null ? 0 : math.max(2, (l.box!.height.round() ~/ 2) * 2);
        final alpha = l.opacity < 1.0
            ? ',colorchannelmixer=aa=${l.opacity.toStringAsFixed(4)}'
            : '';
        int x;
        int y;
        switch (l.kind) {
          case _ComposeLayerKind.png:
            inputs.write(
                ' -loop 1 -framerate $targetFps -t ${_secs(layerDur)} -i "${l.png!.file.path}"');
            fc.write(
                '[$idx:v]format=rgba,setpts=PTS-STARTPTS+${_secs(l.start)}/TB[l$idx];');
            x = l.png!.x;
            y = l.png!.y;
            break;
          case _ComposeLayerKind.rawImage:
            inputs.write(
                ' -loop 1 -framerate $targetFps -t ${_secs(layerDur)} -i "${l.path}"');
            fc.write('[$idx:v]scale=$bw:$bh:force_original_aspect_ratio=decrease,'
                'format=rgba$alpha,pad=$bw:$bh:(ow-iw)/2:(oh-ih)/2:color=black@0,'
                'setpts=PTS-STARTPTS+${_secs(l.start)}/TB[l$idx];');
            x = l.box!.left.round();
            y = l.box!.top.round();
            break;
          case _ComposeLayerKind.video:
            inputs.write(
                ' -ss ${_secs(l.trimStart)} -t ${_secs(l.trimDuration)} -i "${l.path}"');
            fc.write('[$idx:v]setpts=PTS-STARTPTS+${_secs(l.start)}/TB,'
                'scale=$bw:$bh:force_original_aspect_ratio=decrease,'
                'format=rgba$alpha,pad=$bw:$bh:(ow-iw)/2:(oh-ih)/2:color=black@0[l$idx];');
            x = l.box!.left.round();
            y = l.box!.top.round();
            if (l.withAudio) {
              final delayMs = (l.start * 1000).round();
              fc.write('[$idx:a]asetpts=PTS-STARTPTS,volume=${l.volume},'
                  'adelay=$delayMs|$delayMs[a$idx];');
              audioLabels.add('[a$idx]');
            }
            break;
        }
        final outLabel = 'v$idx';
        fc.write('[$prev][l$idx]overlay=$x:$y:'
            "enable='between(t,${_secs(l.start)},${_secs(l.end)})':"
            'eof_action=pass[$outLabel];');
        prev = outLabel;
      }
      String audioArgs;
      if (audioLabels.isNotEmpty) {
        fc.write('[0:a]${audioLabels.join()}amix=inputs=${audioLabels.length + 1}:'
            'duration=first:dropout_transition=0:normalize=0[aout];');
        audioArgs = '-map "[aout]" -c:a aac -ar 44100 -ac 2';
      } else {
        audioArgs = '-map 0:a? -c:a copy';
      }
      var fcStr = fc.toString();
      if (fcStr.endsWith(';')) fcStr = fcStr.substring(0, fcStr.length - 1);

      final out = path.join(workDir.path, 'composed_$p.mp4');
      final command = '$inputs -filter_complex "$fcStr" -map "[$prev]" $audioArgs '
          '-c:v $encoder -preset $preset -tune fastdecode -threads 0 -crf 23 '
          '-r $targetFps -pix_fmt yuv420p -t ${_secs(duration)} "$out"';
      final result = await _executeFFmpeg(command, (v) {
        onProgress((p + v) / passes.length);
      }, outputPath: out, duration: duration);
      if (result == null) return null;
      if (current != basePath) {
        try {
          await File(current).delete();
        } catch (_) {}
      }
      current = result;
    }
    return current;
  }

  /// Encodes [seconds] of black video with silent audio in the same format
  /// as processed clips so it can be stream-copied into the timeline.
  static Future<String?> _encodeBlackSegment(double seconds, int w, int h,
      double fps, String preset, String outPath) {
    final cmd = '-y -f lavfi -i color=c=black:s=${w}x$h:r=$fps '
        '-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 '
        '-t ${_secs(seconds)} -vf "setsar=1,format=yuv420p" '
        '-c:v $_softwareEncoder -preset $preset -tune fastdecode -threads 0 -crf 23 '
        '-c:a aac -ar 44100 -ac 2 "$outPath"';
    return _executeFFmpeg(cmd, null, outputPath: outPath);
  }

  /// Builds the base timeline exactly as the preview plays it:
  /// clips at their timeline positions, black where the timeline has gaps
  /// (including before the first clip and after the last one, up to the end
  /// of audio/text), and transitions that blend the outgoing clip's last
  /// frame into the incoming clip. Only the short transition windows and gaps
  /// are encoded; everything else is stream-copied, so the cost no longer
  /// grows with the square of the number of clips.
  static Future<String?> _stitchTimeline({
    required VideoProject project,
    required List<int> order,
    required List<String> processed,
    required Map<int, _TransitionPlan> incoming,
    required Directory workDir,
    required int targetWidth,
    required int targetHeight,
    required double targetFps,
    required double timelineTotal,
    required String encoder,
    required String preset,
    required void Function(double) onProgress,
  }) async {
    final frame = 1.0 / targetFps;
    final entries = <String>[];
    var cursor = 0.0;
    var generated = 0;
    final steps = math.max(1, order.length + 1);

    for (int k = 0; k < order.length; k++) {
      final clipIndex = order[k];
      final clip = project.videoClips[clipIndex];
      final start = clip.startTime.inMilliseconds / 1000.0;
      final len = (clip.endTime - clip.startTime).inMilliseconds / 1000.0;

      final gap = start - cursor;
      if (gap >= frame) {
        final gapPath = path.join(workDir.path, 'gap_${generated++}.mp4');
        final g = await _encodeBlackSegment(
            gap, targetWidth, targetHeight, targetFps, preset, gapPath);
        if (g == null) return null;
        entries.add("file '$g'");
        cursor += gap;
      }

      final plan = incoming[clipIndex];
      if (plan != null) {
        final lastFrame = path.join(workDir.path, 'last_$clipIndex.png');
        final lf = await _executeFFmpeg(
            '-y -sseof -1 -i "${processed[plan.fromIndex]}" -an -update 1 "$lastFrame"',
            null,
            outputPath: lastFrame);
        if (lf == null) return null;
        final tPath = path.join(workDir.path, 'transition_$clipIndex.mp4');
        final sd = _secs(plan.seconds);
        final xfadeName = _mapToFfmpegXfade(plan.type);
        final cmd = '-y -loop 1 -framerate $targetFps -t $sd -i "$lastFrame" '
            '-t $sd -i "${processed[clipIndex]}" '
            '-filter_complex "'
            '[0:v]scale=$targetWidth:$targetHeight,setsar=1,format=yuv420p,settb=AVTB,setpts=PTS-STARTPTS,fps=$targetFps[ta];'
            '[1:v]setsar=1,format=yuv420p,settb=AVTB,setpts=PTS-STARTPTS,fps=$targetFps[tb];'
            '[ta][tb]xfade=transition=$xfadeName:duration=$sd:offset=0,format=yuv420p[tv];'
            '[1:a]asetpts=PTS-STARTPTS[tau]" '
            '-map "[tv]" -map "[tau]" -c:v $encoder -preset $preset -tune fastdecode '
            '-threads 0 -crf 23 -c:a aac -ar 44100 -ac 2 -t $sd "$tPath"';
        final t = await _executeFFmpeg(cmd, null, outputPath: tPath);
        if (t == null) return null;
        entries.add("file '$t'");
        entries.add("file '${processed[clipIndex]}'");
        entries.add('inpoint $sd');
      } else {
        entries.add("file '${processed[clipIndex]}'");
      }
      cursor += len;
      onProgress((k + 1) / steps);
    }

    final tail = timelineTotal - cursor;
    if (tail >= frame) {
      final tailPath = path.join(workDir.path, 'gap_${generated++}.mp4');
      final g = await _encodeBlackSegment(
          tail, targetWidth, targetHeight, targetFps, preset, tailPath);
      if (g == null) return null;
      entries.add("file '$g'");
    }

    final fileEntries = entries.where((e) => e.startsWith('file ')).length;
    if (fileEntries == 1 && !entries.any((e) => e.startsWith('inpoint'))) {
      // Single segment: already in final form, no need to copy it.
      onProgress(1.0);
      return entries.first.substring(6, entries.first.length - 1);
    }

    final listFile = File(path.join(workDir.path, 'timeline_segments.txt'));
    await listFile.writeAsString(entries.join('\n'));
    final outputPath = path.join(workDir.path, 'timeline_base.mp4');
    return _executeFFmpeg(
        '-y -f concat -safe 0 -i "${listFile.path}" -c copy "$outputPath"',
        onProgress,
        outputPath: outputPath,
        duration: timelineTotal);
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
      if (videoMasterVolume == 1.0) {
        // Perfect case: just stream-copy everything — no re-encode at all
        final command = '-y -i "$inputPath" -c copy "$outputPath"';
        return await _executeFFmpeg(command, onProgress, outputPath: outputPath, duration: duration);
      }
      // Only adjust audio volume — copy video stream
      final command =
          '-y -i "$inputPath" -c:v copy -af "volume=$videoMasterVolume" -c:a aac "$outputPath"';
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
      // Same level as the preview: overlay volume x audio master volume.
      final overlayVolume =
          (overlay.volume * audioMasterVolume).clamp(0.0, 1.0);
      String filter = '[$audioInputIdx:a]volume=$overlayVolume';
      if (delayMs > 0) {
        filter += ',adelay=$delayMs|$delayMs';
      }
      filter += '[a$audioInputIdx];';
      fc.write(filter);
      mixInputs.add('[a$audioInputIdx]');
    }

    final inputsConcat = mixInputs.join('');
    // normalize=0: keep each track at its own level (as heard in the preview)
    // instead of dividing every track by the number of inputs.
    fc.write('${inputsConcat}amix=inputs=${mixInputs.length}:duration=first:dropout_transition=0:normalize=0[aout]');

    final command = '-y ${inputs.join(' ')} -filter_complex "$fc" -map 0:v -map "[aout]" -c:v copy -c:a aac "$outputPath"';
    return await _executeFFmpeg(command, onProgress, outputPath: outputPath, duration: duration);
  }

  /// Execute FFmpeg command asynchronously to provide real-time progress
  static Future<String?> _executeFFmpeg(
      String command, Function(double)? onProgress,
      {double? duration, String? outputPath}) async {
    if (_cancelled) return null;

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
            final String traceTail = logs.length > 300 ? logs.substring(logs.length - 300) : logs;
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
      return null;
    }
  }

  static Future<bool> cancelExport() async {
    _cancelled = true;
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
