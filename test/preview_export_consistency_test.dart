import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:studio_v_v2/providers/video_editor_provider.dart';
import 'package:studio_v_v2/services/hive_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

late Directory tmp;
var _projectCounter = 0;

VideoClip img(String id, int startMs, int endMs,
        {int trimStartMs = 0, double speed = 1.0}) =>
    VideoClip(
      id: id,
      mediaType: MediaType.image,
      imageFile: File('${tmp.path}/a.png'),
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
      sourceStart: Duration(milliseconds: trimStartMs),
      sourceEnd: Duration(
          milliseconds: trimStartMs + ((endMs - startMs) * speed).round()),
      playbackSpeed: speed,
    );

Future<VideoEditorProvider> load(List<VideoClip> clips) async {
  final project =
      VideoProject(id: 'p${_projectCounter++}', name: 'test', videoClips: clips);
  await HiveService.saveProject(project);
  final provider = VideoEditorProvider();
  await provider.loadProject(project.id);
  return provider;
}

/// The exporter renders every clip as (trimEnd - trimStart) / speed seconds
/// starting at trimStart; the preview must agree with that for every clip.
void expectPreviewMatchesExport(VideoEditorProvider p) {
  for (final c in p.currentProject!.videoClips) {
    final exportLen = VideoEditorProvider.timelineLengthForSource(
        c.trimEnd - c.trimStart, c.playbackSpeed);
    expect((exportLen - c.duration).inMilliseconds.abs() <= 2, isTrue,
        reason: 'clip ${c.id}: export length $exportLen vs timeline '
            '${c.duration}');
    expect(
        VideoEditorProvider.calculateSourcePositionForTimeline(c, c.startTime),
        c.trimStart,
        reason: 'clip ${c.id}: preview must start where export starts');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('studio_v_test');
    File('${tmp.path}/a.png').writeAsBytesSync([0]);
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await HiveService.init();
  });

  test('preview source mapping uses trimStart and playback speed', () {
    final clip = VideoClip(
      id: 'c',
      mediaType: MediaType.video,
      videoFile: File('x.mp4'),
      startTime: const Duration(seconds: 10),
      endTime: const Duration(seconds: 12),
      sourceStart: const Duration(seconds: 1),
      sourceEnd: const Duration(seconds: 20),
      trimStart: const Duration(seconds: 5),
      trimEnd: const Duration(seconds: 9),
      playbackSpeed: 2.0,
    );
    expect(
        VideoEditorProvider.calculateSourcePositionForTimeline(
            clip, const Duration(seconds: 11)),
        const Duration(seconds: 7));
  });

  test('trim at cursor keeps preview and export identical', () async {
    final p = await load([img('a', 0, 10000), img('b', 10000, 13000)]);
    await p.seekTo(const Duration(seconds: 4));
    await p.applyLeftTrimAtCursor('a');
    final a = p.currentProject!.videoClips.first;
    expect(a.trimStart, const Duration(seconds: 4));
    expect(a.duration, const Duration(seconds: 6));
    expect(p.currentProject!.videoClips[1].startTime,
        const Duration(seconds: 6));
    expectPreviewMatchesExport(p);

    await p.seekTo(const Duration(seconds: 2));
    await p.applyRightTrimAtCursor('a');
    expect(p.currentProject!.videoClips.first.trimEnd,
        const Duration(seconds: 6));
    expectPreviewMatchesExport(p);
  });

  test('reorder keeps trimmed lengths', () async {
    final p = await load([img('a', 0, 10000), img('b', 10000, 13000)]);
    await p.seekTo(const Duration(seconds: 4));
    await p.applyLeftTrimAtCursor('a');
    p.reorderVideoClips(0, 1);
    final clips = p.currentProject!.videoClips;
    expect(clips.map((c) => c.id).toList(), ['b', 'a']);
    expect(clips[1].duration, const Duration(seconds: 6));
    expectPreviewMatchesExport(p);
  });

  test('cut keeps settings and splits the played window', () async {
    final base = img('a', 0, 6000).copyWith(
        volume: 0.3, isMuted: true, rotation: 90, isMirrored: true);
    final p = await load([base]);
    await p.seekTo(const Duration(seconds: 2));
    p.cutVideoClip('a');
    final parts = p.currentProject!.videoClips;
    expect(parts.length, 2);
    expect(parts[0].trimEnd, parts[1].trimStart);
    for (final c in parts) {
      expect(c.volume, 0.3);
      expect(c.isMuted, isTrue);
      expect(c.rotation, 90);
      expect(c.isMirrored, isTrue);
    }
    expectPreviewMatchesExport(p);
  });

  test('speed change updates clip length and shifts following clips',
      () async {
    final p = await load([img('a', 0, 10000), img('b', 10000, 13000)]);
    await p.setVideoClipPlaybackSpeed('a', 2.0);
    final clips = p.currentProject!.videoClips;
    expect(clips[0].duration, const Duration(seconds: 5));
    expect(clips[1].startTime, const Duration(seconds: 5));
    expectPreviewMatchesExport(p);
  });

  test('trim editor left/right trim and split stay consistent', () async {
    final p = await load([img('a', 0, 10000), img('b', 10000, 13000)]);
    await p.applyLeftTrim('a', const Duration(seconds: 2));
    expect(p.currentProject!.videoClips[0].trimStart,
        const Duration(seconds: 2));
    expect(p.currentProject!.videoClips[0].startTime, Duration.zero);
    expect(p.currentProject!.videoClips[1].startTime,
        const Duration(seconds: 8));
    expectPreviewMatchesExport(p);

    await p.applyRightTrim('a', const Duration(seconds: 7));
    expect(p.currentProject!.videoClips[0].trimEnd,
        const Duration(seconds: 9));
    expectPreviewMatchesExport(p);

    final p2 = await load([img('s', 0, 10000)]);
    await p2.applyTrimSplit(
        's', const Duration(seconds: 3), const Duration(seconds: 6));
    final parts = p2.currentProject!.videoClips;
    expect(parts.length, 2);
    expect(parts[0].trimEnd, const Duration(seconds: 3));
    expect(parts[1].trimStart, const Duration(seconds: 6));
    expect(parts[1].startTime, const Duration(seconds: 6));
    expectPreviewMatchesExport(p2);
  });

  test('legacy projects are normalized on load', () async {
    // Saved by the old cursor-trim code: preview used sourceStart (4s),
    // export used trimStart (0s).
    final legacy = VideoClip(
      id: 'l',
      mediaType: MediaType.image,
      imageFile: File('${tmp.path}/a.png'),
      startTime: Duration.zero,
      endTime: const Duration(seconds: 6),
      sourceStart: const Duration(seconds: 4),
      sourceEnd: const Duration(seconds: 10),
      trimStart: Duration.zero,
      trimEnd: const Duration(seconds: 10),
    );
    // Old speed handling: length not divided by speed.
    final legacySpeed = img('s', 6000, 10000).copyWith(playbackSpeed: 2.0);
    final after = img('z', 10000, 12000);
    final p = await load([legacy, legacySpeed, after]);
    final clips = p.currentProject!.videoClips;
    expect(clips[0].trimStart, const Duration(seconds: 4));
    expect(clips[1].duration, const Duration(seconds: 2));
    expect(clips[2].startTime, const Duration(seconds: 8));
    expectPreviewMatchesExport(p);
  });
}
