import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ColorFilter;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:studio_v_v2/models/chroma_key_settings.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:studio_v_v2/providers/video_editor_provider.dart';
import 'package:studio_v_v2/services/export_service.dart';
import 'package:studio_v_v2/services/hive_service.dart';
import 'package:studio_v_v2/utils/chroma_key.dart';
import 'package:studio_v_v2/widgets/clip_toolbar.dart';

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

TextOverlay text(String id, {List<double> keyframes = const []}) => TextOverlay(
      id: id,
      text: 'Hi',
      position: const Offset(0.1, 0.1),
      fontSize: 100,
      startTime: Duration.zero,
      endTime: s(4),
      keyframeData: keyframes,
    );

StickerModel sticker(String id) => StickerModel(
      id: id,
      assetPath: 'assets/stickers/star.png',
      position: const Offset(0.5, 0.5),
      startTime: Duration.zero,
      endTime: s(4),
    );

Future<VideoEditorProvider> load(VideoProject Function(String id) build) async {
  final project = build('m${_counter++}');
  await HiveService.saveProject(project);
  final provider = VideoEditorProvider();
  await provider.loadProject(project.id);
  return provider;
}

/// [w] x [h] straight-RGBA frame: [border] on the outer band, [center]
/// inside.
Uint8List frame(int w, int h, Color border, Color center) {
  final out = Uint8List(w * h * 4);
  final band = (w * 0.15).round();
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final edge = x < band || y < band || x >= w - band || y >= h - band;
      final c = edge ? border : center;
      final i = (y * w + x) * 4;
      out[i] = (c.r * 255).round();
      out[i + 1] = (c.g * 255).round();
      out[i + 2] = (c.b * 255).round();
      out[i + 3] = 255;
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('studio_v_motion');
    File('${tmp.path}/a.png').writeAsBytesSync([0]);
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await HiveService.init();
  });

  group('text and sticker motion', () {
    test('keyframes interpolate position and size', () {
      final data = ItemKeyframe.encode([
        ItemKeyframe(s(2), const Offset(0.5, 0.5), 200),
        ItemKeyframe(Duration.zero, const Offset(0.1, 0.1), 100),
      ]);
      final (p, size) =
          ItemKeyframe.at(data, s(1), const Offset(9, 9), 9);
      expect(p.dx, closeTo(0.3, 1e-9));
      expect(size, closeTo(150, 1e-9));
      // No keyframes: the item's own values.
      expect(ItemKeyframe.at(const [], s(1), const Offset(0.2, 0.2), 42),
          (const Offset(0.2, 0.2), 42.0));
    });

    test('text keyframes: add, drag edits the playhead keyframe, clear',
        () async {
      final p = await load((id) => VideoProject(
          id: id,
          name: 't',
          videoClips: [image('c', 0, 6)],
          textOverlays: [text('t')]));
      await p.seekTo(s(1));
      p.addKeyframeAtPlayhead(TimelineItemKind.text, 't');
      expect(p.keyframeCount(TimelineItemKind.text, 't'), 2); // pins 0 too
      await p.seekTo(s(3));
      p.updateTextTransform('t',
          position: const Offset(0.6, 0.6), fontSize: 200);
      final t = p.currentProject!.textOverlays.single;
      expect(t.position, const Offset(0.1, 0.1)); // static values kept
      expect(t.keyframes.length, 3);
      final (pos, font) =
          ItemKeyframe.at(t.keyframeData, s(3), t.position, t.fontSize);
      expect(pos, const Offset(0.6, 0.6));
      expect(font, 200);
      expect(p.hasKeyframeAtPlayhead(TimelineItemKind.text, 't'), isTrue);

      p.clearKeyframes(TimelineItemKind.text, 't');
      final cleared = p.currentProject!.textOverlays.single;
      expect(cleared.keyframes, isEmpty);
      // Stays where it was at the playhead.
      expect(cleared.position, const Offset(0.6, 0.6));
      expect(cleared.fontSize, 200);
    });

    test('sticker keyframes and split keep the motion continuous', () async {
      final p = await load((id) => VideoProject(
          id: id,
          name: 't',
          videoClips: [image('c', 0, 6)],
          stickers: [sticker('st')]));
      p.addKeyframeAtPlayhead(TimelineItemKind.sticker, 'st');
      await p.seekTo(s(4));
      p.updateStickerTransform('st',
          position: const Offset(0.9, 0.5), scale: 2.0);
      await p.seekTo(s(2));
      expect(p.cutSticker('st'), isTrue);
      final halves = p.currentProject!.stickers;
      final a = halves.first.keyframes;
      final b = halves.last.keyframes;
      expect(a.last.time, s(2));
      expect(a.last.position.dx, closeTo(0.7, 1e-9));
      expect(a.last.size, closeTo(1.5, 1e-9));
      expect(b.first.time, Duration.zero);
      expect(b.first.position.dx, closeTo(0.7, 1e-9));
      expect(b.last.time, s(2));
    });

    test('without motion, transforms just move the item', () async {
      final p = await load((id) => VideoProject(
          id: id,
          name: 't',
          videoClips: [image('c', 0, 6)],
          textOverlays: [text('t')],
          stickers: [sticker('st')]));
      p.updateTextTransform('t', position: const Offset(0.3, 0.3));
      p.updateStickerTransform('st', scale: 1.5, rotation: 0.5);
      expect(p.currentProject!.textOverlays.single.position,
          const Offset(0.3, 0.3));
      final st = p.currentProject!.stickers.single;
      expect(st.scale, 1.5);
      expect(st.rotation, 0.5);
      expect(st.keyframes, isEmpty);
    });

    test('typewriter text in the motion pipeline reveals left to right', () {
      final g = ExportService.motionGraphForTest(
        tileW: 200,
        tileH: 80,
        start: 0,
        end: 3,
        path: [(0.0, 100.0, 100.0, 1.0), (2.0, 300.0, 100.0, 1.0)],
        animIn: 'typewriter',
      );
      expect(g.filters, contains('geq='));
      expect(g.filters, contains('clip(T/0.500000,0,1)'));
      expect(g.x, contains('if(lt((t-0.000000),2.000000)'));
    });
  });

  group('green screen', () {
    test('auto-detect finds a green border, and blue, not grey', () {
      final green = ChromaKey.detect(
          frame(60, 40, const Color(0xFF10C030), const Color(0xFFCC8866)),
          60,
          40);
      expect(green, isNotNull);
      expect(green!.g, greaterThan(green.r));
      expect(ChromaKey.canDespill(green), isTrue);

      final blue = ChromaKey.detect(
          frame(60, 40, const Color(0xFF1030D0), const Color(0xFFCC8866)),
          60,
          40);
      expect(blue!.b, greaterThan(blue.g));

      expect(
          ChromaKey.detect(
              frame(60, 40, const Color(0xFF808080), const Color(0xFF202020)),
              60,
              40),
          isNull);
    });

    test('picking samples the colour under the tap', () {
      final px = frame(60, 40, const Color(0xFF00FF00), const Color(0xFFFF0000));
      expect(ChromaKey.sample(px, 60, 40, const Offset(0.5, 0.5)).toARGB32(),
          0xFFFF0000);
      expect(ChromaKey.sample(px, 60, 40, const Offset(0.02, 0.02)).toARGB32(),
          0xFF00FF00);
    });

    test('edge clean-up follows the screen colour', () {
      expect(
          ChromaKey.despillFilter(const ChromaKeySettings(
              keyColor: Color(0xFF00B140), spillReduction: 1)),
          startsWith('despill=type=green'));
      expect(
          ChromaKey.despillFilter(const ChromaKeySettings(
              keyColor: Color(0xFF0047BB), spillReduction: 1)),
          startsWith('despill=type=blue'));
      expect(
          ChromaKey.despillFilter(const ChromaKeySettings(
              keyColor: Color(0xFF00FF00), spillReduction: 0)),
          isNull);
      expect(
          ExportService.keyFilters(const ChromaKeySettings(
              keyColor: Color(0xFF00FF00),
              similarity: 0.3,
              blend: 0.1,
              spillReduction: 1)),
          'colorkey=0x00ff00:0.3000:0.1000,'
          'despill=type=green:mix=0.5:expand=0:red=0:green=-1:blue=0'
          ':brightness=0');
    });

    test('export graph keys, keeps colour filters transparent and centres '
        'the subject', () {
      final clip = VideoClip(
        id: 'v',
        mediaType: MediaType.video,
        videoFile: File('v.mp4'),
        startTime: Duration.zero,
        endTime: s(4),
      );
      final graph = ExportService.chromaKeyGraph(
        settings: const ChromaKeySettings(
          enabled: true,
          keyColor: Color(0xFF00FF00),
          position: Offset(0.25, 0.5),
          scale: 0.5,
          spillReduction: 0,
        ),
        clip: clip,
        targetWidth: 1920,
        targetHeight: 1080,
        targetFps: 30,
        colorFilter: const ColorFilter(brightness: 0.2),
        backgroundPath: '/bg.jpg',
      );
      expect(graph, contains('colorkey=0x00ff00'));
      expect(graph, isNot(contains('despill')));
      expect(graph, contains('scale=w=960:h=540:force_original_aspect_ratio=decrease'));
      // Colour filter keeps alpha (RGBA, not rgb24).
      expect(graph, contains('format=rgba,colorchannelmixer'));
      expect(graph, isNot(contains('rgb24')));
      expect(graph, contains("x='W*0.2500-w/2':y='H*0.5000-h/2'"));
      expect(graph, contains('force_original_aspect_ratio=increase'));

      final noBg = ExportService.chromaKeyGraph(
        settings: const ChromaKeySettings(enabled: true),
        clip: clip,
        targetWidth: 1920,
        targetHeight: 1080,
        targetFps: 30,
      );
      expect(noBg, contains('[1:v]setsar=1[ck_bg]'));
    });

    test('settings follow the selected clip and never carry over', () async {
      final p = await load((id) => VideoProject(
          id: id,
          name: 't',
          videoClips: [image('a', 0, 3), image('b', 3, 6)]));
      p.selectVideoClip('a');
      p.toggleChromaKeyEditor();
      expect(p.currentChromaKeySettings!.enabled, isFalse);
      p.updateChromaKeySettings(
          enabled: true, keyColor: const Color(0xFF0047BB), similarity: 0.5);
      p.selectVideoClip('b');
      expect(p.currentChromaKeySettings!.enabled, isFalse);
      p.updateChromaKeySettings(scale: 1.5);
      final clips = p.currentProject!.videoClips;
      expect(clips[0].chromaKeySettings!.similarity, 0.5);
      expect(clips[1].chromaKeySettings!.similarity,
          ChromaKey.defaults.similarity);
      expect(clips[1].chromaKeySettings!.scale, 1.5);
      expect(clips[1].chromaKeySettings!.keyColor.toARGB32(), 0xFF00FF00);
    });

    test('a slider drag is one undo step; clearing the background works',
        () async {
      final p = await load((id) => VideoProject(
          id: id, name: 't', videoClips: [image('a', 0, 3)]));
      p.selectVideoClip('a');
      p.updateChromaKeySettings(enabled: true);
      p.sealUndo();
      for (final v in [0.1, 0.2, 0.3, 0.4]) {
        p.updateChromaKeySettings(similarity: v, undoKey: 'chroma-strength');
      }
      p.sealUndo();
      await p.undo();
      expect(p.currentChromaKeySettings!.similarity,
          ChromaKey.defaults.similarity);

      p.updateChromaKeySettings(backgroundPath: '/x.jpg');
      p.clearChromaBackground();
      expect(p.currentChromaKeySettings!.backgroundPath, isNull);
      expect(p.currentChromaKeySettings!.enabled, isTrue);
    });
  });

  testWidgets('clip toolbar offers trim left and right', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: ClipToolbar(
          provider: VideoEditorProvider(),
          clip: VideoClip(
            id: 'c',
            mediaType: MediaType.video,
            videoFile: File('c.mp4'),
            startTime: Duration.zero,
            endTime: const Duration(seconds: 4),
          ),
        ),
      ),
    ));
    expect(find.text('Trim left'), findsOneWidget);
    expect(find.text('Trim right'), findsOneWidget);
  });
}
