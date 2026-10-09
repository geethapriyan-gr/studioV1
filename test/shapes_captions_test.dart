import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:studio_v_v2/providers/video_editor_provider.dart';
import 'package:studio_v_v2/services/caption_service.dart';
import 'package:studio_v_v2/services/hive_service.dart';
import 'package:studio_v_v2/utils/caption_style.dart';
import 'package:studio_v_v2/utils/shape_spec.dart';

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
var _counter = 0;

Duration s(num secs) => Duration(milliseconds: (secs * 1000).round());

VideoClip image(String id, num start, num end) => VideoClip(
      id: id,
      mediaType: MediaType.image,
      imageFile: File('${tmp.path}/a.png'),
      startTime: s(start),
      endTime: s(end),
    );

Future<VideoEditorProvider> load(VideoProject Function(String id) build) async {
  final project = build('k${_counter++}');
  await HiveService.saveProject(project);
  final provider = VideoEditorProvider();
  await provider.loadProject(project.id);
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('studio_v_kf');
    File('${tmp.path}/a.png').writeAsBytesSync([0]);
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await HiveService.init();
  });

  group('shapes', () {
    test('a shape survives being stored as a sticker path', () {
      const spec = ShapeSpec(
          type: 'arrow',
          color: Color(0xFF0A84FF),
          stroke: 40,
          filled: true,
          aspect: 3);
      final path = spec.toPath();
      expect(ShapeSpec.isShape(path), isTrue);
      final back = ShapeSpec.parse(path)!;
      expect(back, spec);
      expect(back.color.toARGB32(), 0xFF0A84FF);
      expect(ShapeSpec.parse('assets/stickers/star.png'), isNull);
      final sticker = StickerModel(
          id: 's', assetPath: path, startTime: Duration.zero, endTime: s(2));
      expect(sticker.isShape, isTrue);
      expect(sticker.isAsset, isFalse);
    });

    test('shapes render at their aspect ratio', () async {
      for (final (_, spec) in ShapeSpec.presets) {
        final image = await spec.render(longSide: 300);
        expect(image.width / image.height,
            closeTo(spec.aspect >= 1 ? spec.aspect : spec.aspect, 0.05));
        image.dispose();
      }
    });

    test('shape files are never touched by media cleanup', () {
      final project = VideoProject(id: 'x', name: 'x', stickers: [
        StickerModel(
            id: 's',
            assetPath: const ShapeSpec(type: 'rect').toPath(),
            startTime: Duration.zero,
            endTime: s(1)),
      ]);
      expect(
          VideoEditorProvider.unusedMediaAfterDelete(project, [], tmp.path),
          isEmpty);
    });
  });

  group('captions', () {
    test('long phrases are split into short timed captions', () {
      final out = CaptionService.splitForReading([
        CaptionCue(Duration.zero, s(6),
            ' one two three four five six seven eight nine ten eleven twelve '),
        CaptionCue(s(6), s(7), '[Music]'),
        CaptionCue(s(7), s(8), ' Thank you. '),
      ]);
      expect(out.map((c) => c.text), [
        'one two three four five six',
        'seven eight nine ten eleven twelve',
        'Thank you.',
      ]);
      expect(out[0].start, Duration.zero);
      expect(out[1].end, s(6));
      expect(out[0].end, out[1].start);
    });

    test('speech times map onto the clip on the timeline', () {
      final clip = image('c', 10, 14);
      final cues = CaptionService.mapToTimeline([
        CaptionCue(s(1), s(2), 'a'),
        CaptionCue(s(3.5), s(5), 'b'), // runs past the clip end
        CaptionCue(s(6), s(7), 'c'), // after the clip
      ], clip);
      expect(cues.length, 2);
      expect(cues[0].start, s(11));
      expect(cues[1].end, s(14));
    });

    test('captions are added, restyled and removed in one step each',
        () async {
      final p = await load((id) => VideoProject(
          id: id,
          name: 't',
          videoClips: [image('c', 0, 6)],
          textOverlays: [
            TextOverlay(
                id: 'mine',
                text: 'Title',
                position: Offset.zero,
                startTime: Duration.zero,
                endTime: s(2)),
          ]));
      p.setCaptions([
        CaptionCue(Duration.zero, s(2), 'Hello there'),
        CaptionCue(s(2), s(4), 'General Kenobi'),
      ], CaptionStyle.all.first);
      expect(p.captions.length, 2);
      final c = p.captions.first;
      expect(c.outlineColor, isNotNull);
      // Centred near the bottom.
      expect(c.position.dy, greaterThan(0.7));
      expect(c.position.dx, inInclusiveRange(0.0, 0.5));

      p.restyleCaptions(CaptionStyle.all[1]); // box
      expect(p.captions.every((t) => t.boxColor != null), isTrue);
      p.removeCaptions();
      expect(p.captions, isEmpty);
      expect(p.currentProject!.textOverlays.single.id, 'mine');
      await p.undo();
      expect(p.captions.length, 2);
    });
  });
}
