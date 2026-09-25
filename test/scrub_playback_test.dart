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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('studio_v_scrub');
    File('${tmp.path}/a.png').writeAsBytesSync([0]);
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await HiveService.init();
  });

  Future<VideoEditorProvider> load() async {
    final project = VideoProject(id: 'scrub', name: 'scrub', videoClips: [
      VideoClip(
        id: 'a',
        mediaType: MediaType.image,
        imageFile: File('${tmp.path}/a.png'),
        startTime: Duration.zero,
        endTime: const Duration(seconds: 20),
      ),
    ]);
    await HiveService.saveProject(project);
    final p = VideoEditorProvider();
    await p.loadProject(project.id);
    return p;
  }

  test('dragging the timeline while playing pauses once and resumes from the '
      'new position', () async {
    final p = await load();
    await p.togglePlayback();
    expect(p.isPlaying, isTrue);

    await p.beginScrub();
    // Still reported as playing (no UI flicker), but the clock is stopped.
    expect(p.isPlaying, isTrue);
    for (var ms = 2000; ms <= 8000; ms += 250) {
      await p.seekTo(Duration(milliseconds: ms));
    }
    final whileScrubbing = p.currentPosition;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(p.currentPosition, whileScrubbing,
        reason: 'playhead must not run while the user is dragging');

    await p.endScrub();
    expect(p.isPlaying, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(p.currentPosition > const Duration(milliseconds: 8000), isTrue,
        reason: 'playback resumes from where the timeline was left');

    await p.togglePlayback(); // pause
    expect(p.isPlaying, isFalse);
  });

  test('pressing pause during a scrub keeps playback stopped', () async {
    final p = await load();
    await p.togglePlayback();
    await p.beginScrub();
    await p.seekTo(const Duration(seconds: 5));
    await p.togglePlayback(); // user taps pause mid-drag
    await p.endScrub();
    expect(p.isPlaying, isFalse);
  });

  test('scrubbing while paused does not start playback', () async {
    final p = await load();
    await p.beginScrub();
    await p.seekTo(const Duration(seconds: 5));
    await p.endScrub();
    expect(p.isPlaying, isFalse);
    expect(p.currentPosition, const Duration(seconds: 5));
  });
}
