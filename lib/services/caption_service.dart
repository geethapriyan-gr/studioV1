import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_edge/whisper_edge.dart';

import '../models/video_project.dart';

/// One caption: text shown from [start] to [end] on the timeline.
@immutable
class CaptionCue {
  final Duration start;
  final Duration end;
  final String text;

  const CaptionCue(this.start, this.end, this.text);

  @override
  String toString() => 'CaptionCue($start-$end "$text")';
}

/// Speed/size trade-off of the on-device speech model (downloaded once).
enum CaptionQuality {
  fast(WhisperModel.tinyQ5_1, 'Fast', 'Quick, best for clear English'),
  better(WhisperModel.baseQ5_1, 'Better', 'Slower, better for accents and '
      'Indian languages');

  const CaptionQuality(this.model, this.label, this.hint);
  final WhisperModel model;
  final String label;
  final String hint;

  String get sizeLabel => '${model.approxSizeMb} MB';
}

/// What the caption generator is doing, for the progress UI.
@immutable
class CaptionProgress {
  final String message;

  /// 0..1, or null while the length is unknown.
  final double? fraction;

  const CaptionProgress(this.message, [this.fraction]);
}

/// Turns the speech in a project's clips into timed captions, fully on the
/// device (whisper.cpp). The speech model is downloaded on first use.
class CaptionService {
  WhisperTranscriber? _transcriber;
  bool _cancelled = false;

  static Future<Directory> modelDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'speech_models'));
  }

  static Future<bool> isModelReady(CaptionQuality q) async =>
      WhisperModelDownloader.isDownloaded(q.model, await modelDir());

  /// Stops the run in progress (the current clip finishes cancelling).
  void cancel() {
    _cancelled = true;
    _transcriber?.cancel();
  }

  /// Captions for the speech in [project]'s video clips. [language] is an
  /// ISO 639-1 code or 'auto'; [translate] turns the speech into English.
  Future<List<CaptionCue>> generate(
    VideoProject project, {
    String language = 'auto',
    bool translate = false,
    CaptionQuality quality = CaptionQuality.better,
    required void Function(CaptionProgress) onProgress,
  }) async {
    _cancelled = false;
    final dir = await modelDir();
    final modelPath = await WhisperModelDownloader().download(
      quality.model,
      dir,
      onProgress: (received, total) {
        final mb = (received / 1048576).toStringAsFixed(0);
        onProgress(CaptionProgress(
          total > 0
              ? 'Downloading speech model ($mb / ${quality.model.approxSizeMb} MB)'
              : 'Downloading speech model ($mb MB)',
          total > 0 ? received / total : null,
        ));
      },
    );
    _throwIfCancelled();

    onProgress(const CaptionProgress('Loading speech model'));
    final transcriber = await WhisperTranscriber.load(modelPath);
    _transcriber = transcriber;
    final temp = await getTemporaryDirectory();
    final clips = [
      for (final c in project.videoClips)
        if (c.mediaType == MediaType.video &&
            c.videoFile != null &&
            !c.isMuted &&
            !c.isReversed)
          c
    ]..sort((a, b) => a.startTime.compareTo(b.startTime));

    final cues = <CaptionCue>[];
    try {
      for (int i = 0; i < clips.length; i++) {
        _throwIfCancelled();
        final clip = clips[i];
        final label = clips.length > 1 ? ' (clip ${i + 1} of ${clips.length})' : '';
        onProgress(CaptionProgress('Preparing audio$label', i / clips.length));
        final wav = p.join(temp.path, 'caption_${clip.id}.wav');
        if (!await _extractSpeechAudio(clip, wav)) continue;
        _throwIfCancelled();
        // whisper only reports progress per 30 s of audio, so a short clip
        // sits at 0% until it is done. Tick every second with the time spent
        // so the user can see it is working.
        final watch = Stopwatch()..start();
        var percent = 0;
        void report() {
          final secs = watch.elapsed.inSeconds;
          final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
          onProgress(CaptionProgress(
            percent > 0
                ? 'Listening$label · $percent% · $time'
                : 'Listening$label · $time',
            percent > 0 ? (i + percent / 100) / clips.length : null,
          ));
        }

        report();
        final ticker =
            Timer.periodic(const Duration(seconds: 1), (_) => report());
        try {
          final result = await transcriber.transcribeWavFile(
            wav,
            language: language,
            translate: translate,
            onProgress: (p) {
              if (p == percent) return;
              percent = p;
              report();
            },
          );
          cues.addAll(mapToTimeline(
            [
              for (final s in result.segments)
                CaptionCue(s.start, s.end, s.text)
            ],
            clip,
          ));
        } on WhisperException {
          // A cancelled run reports failure too.
          _throwIfCancelled();
          rethrow;
        } finally {
          ticker.cancel();
          try {
            await File(wav).delete();
          } catch (_) {}
        }
      }
    } finally {
      transcriber.dispose();
      _transcriber = null;
    }
    _throwIfCancelled();
    return splitForReading(cues);
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const CaptionCancelled();
  }

  /// 16 kHz mono WAV of the part of [clip] that plays, at the clip's speed
  /// (so speech times are timeline times). False when it has no audio.
  static Future<bool> _extractSpeechAudio(VideoClip clip, String out) async {
    final speed = clip.playbackSpeed <= 0 ? 1.0 : clip.playbackSpeed;
    final tempo = <String>[];
    var s = speed;
    while (s > 2.0) {
      tempo.add('atempo=2.0');
      s /= 2.0;
    }
    while (s < 0.5) {
      tempo.add('atempo=0.5');
      s *= 2.0;
    }
    if ((s - 1).abs() > 0.001) tempo.add('atempo=${s.toStringAsFixed(4)}');
    final filters = [...tempo, 'aresample=16000'].join(',');
    final start = clip.trimStart.inMilliseconds / 1000.0;
    final dur = clip.trimmedDuration.inMilliseconds / 1000.0;
    final session = await FFmpegKit.execute(
        '-y -ss $start -t $dur -i "${clip.videoFile!.path}" -vn '
        '-af "$filters" -ac 1 -c:a pcm_s16le "$out"');
    final rc = await session.getReturnCode();
    final file = File(out);
    return ReturnCode.isSuccess(rc) &&
        file.existsSync() &&
        file.lengthSync() > 2048;
  }

  /// Moves cues from [clip]'s own time (0 = its start) onto the timeline,
  /// dropping what falls outside the clip.
  @visibleForTesting
  static List<CaptionCue> mapToTimeline(List<CaptionCue> cues, VideoClip clip) {
    final out = <CaptionCue>[];
    for (final c in cues) {
      final start = clip.startTime + c.start;
      var end = clip.startTime + c.end;
      if (start >= clip.endTime) continue;
      if (end > clip.endTime) end = clip.endTime;
      if (end <= start) continue;
      out.add(CaptionCue(start, end, c.text));
    }
    return out;
  }

  static final RegExp _annotation = RegExp(r'^[\[\(\*♪].*[\]\)\*♪]$');

  /// Readable captions: drops non-speech notes like "[Music]" or
  /// "(applause)" and splits long phrases into groups of at most
  /// [maxWords] words, timed in proportion to their length.
  @visibleForTesting
  static List<CaptionCue> splitForReading(List<CaptionCue> cues,
      {int maxWords = 6}) {
    final out = <CaptionCue>[];
    for (final c in cues) {
      final text = c.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty || _annotation.hasMatch(text)) continue;
      final words = text.split(' ');
      if (words.length <= maxWords) {
        out.add(CaptionCue(c.start, c.end, text));
        continue;
      }
      final groups = <String>[];
      for (int i = 0; i < words.length; i += maxWords) {
        groups.add(words
            .sublist(i, (i + maxWords).clamp(0, words.length))
            .join(' '));
      }
      final totalChars = groups.fold<int>(0, (n, g) => n + g.length);
      final span = (c.end - c.start).inMicroseconds;
      var t = c.start;
      for (int g = 0; g < groups.length; g++) {
        final end = g == groups.length - 1
            ? c.end
            : t + Duration(
                microseconds: (span * groups[g].length / totalChars).round());
        out.add(CaptionCue(t, end, groups[g]));
        t = end;
      }
    }
    // Never overlap: a caption ends where the next one starts.
    for (int i = 0; i < out.length - 1; i++) {
      if (out[i].end > out[i + 1].start && out[i + 1].start > out[i].start) {
        out[i] = CaptionCue(out[i].start, out[i + 1].start, out[i].text);
      }
    }
    return out;
  }
}

/// Thrown when [CaptionService.cancel] stops a run.
class CaptionCancelled implements Exception {
  const CaptionCancelled();
}
