import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:studio_v_v2/effects/effect_engine.dart';
import 'package:studio_v_v2/models/video_effect.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:studio_v_v2/services/hive_service.dart';
import 'package:studio_v_v2/utils/audio_fades.dart';
import 'package:studio_v_v2/utils/text_overlay_painter.dart';

VideoClip _clip(String id, int startS, int endS) => VideoClip(
      id: id,
      mediaType: MediaType.image,
      imageFile: File('x.png'),
      startTime: Duration(seconds: startS),
      endTime: Duration(seconds: endS),
    );

VideoEffect _fx(String clipId, VideoEffectType type) => VideoEffect(
      id: '$clipId-${type.name}',
      clipId: clipId,
      type: type,
      intensity: 0.6,
      startTime: Duration.zero,
      duration: Duration.zero,
    );

void main() {
  group('EffectEngine', () {
    final project = VideoProject(
      id: 'p',
      name: 'p',
      videoClips: [_clip('a', 0, 4), _clip('b', 4, 9)],
      videoEffects: [
        _fx('b', VideoEffectType.shake),
        _fx('b', VideoEffectType.grayscale),
        _fx('gone', VideoEffectType.blur), // clip deleted -> inactive
      ],
    );

    test('effects follow their clip and skip deleted clips', () {
      expect(EffectEngine.activeAt(project, const Duration(seconds: 2)),
          isEmpty);
      final active =
          EffectEngine.activeAt(project, const Duration(seconds: 5));
      expect(active.map((a) => a.$1.type), [
        VideoEffectType.shake,
        VideoEffectType.grayscale,
      ]);
      // Time inside the window is relative to the clip start.
      expect(active.first.$2, closeTo(1.0, 1e-6));
    });

    test('ffmpeg graph runs from e0 to b0 and uses the clip window', () {
      final graph = EffectEngine.ffmpegGraph(project,
          width: 1080, height: 1920, duration: 9)!;
      expect(graph.startsWith('[e0]'), isTrue);
      expect(graph.endsWith('[b0];'), isTrue);
      expect(graph, contains("between(t,4.00000,9.00000)"));
      expect(graph, contains('trim=start=4.00000:end=9.00000'));
      expect(graph, isNot(contains('gblur'))); // orphan effect ignored
    });

    test('no effects -> no graph', () {
      final empty = VideoProject(id: 'e', name: 'e');
      expect(
          EffectEngine.ffmpegGraph(empty,
              width: 100, height: 100, duration: 1),
          isNull);
    });
  });

  group('TextAnimations', () {
    TextOverlay text(String animIn, String animOut) => TextOverlay(
          id: 't',
          text: 'Hi',
          position: Offset.zero,
          startTime: Duration.zero,
          endTime: const Duration(seconds: 3),
          animIn: animIn,
          animOut: animOut,
        );

    test('fade in starts invisible and ends fully visible', () {
      final o = text('fade', 'none');
      expect(TextAnimations.at(o, 0).opacity, 0);
      expect(TextAnimations.at(o, 0.25).opacity, closeTo(0.5, 1e-6));
      expect(TextAnimations.at(o, 1.0).isIdle, isTrue);
    });

    test('pop overshoots and settles at 1', () {
      expect(TextAnimations.popScale(0), closeTo(0.6, 1e-9));
      expect(TextAnimations.popScale(0.7), closeTo(1.08, 1e-9));
      expect(TextAnimations.popScale(1), closeTo(1.0, 1e-9));
    });

    test('typewriter out hides from the end', () {
      final o = text('none', 'typewriter');
      expect(TextAnimations.at(o, 1.5).reveal, 1);
      expect(TextAnimations.at(o, 2.75).reveal, closeTo(0.5, 1e-6));
    });
  });

  group('AudioFades', () {
    AudioOverlay audio({bool fadeIn = false, bool fadeOut = false}) =>
        AudioOverlay(
          id: 'a',
          audioFile: File('a.mp3'),
          startTime: const Duration(seconds: 10),
          endTime: const Duration(seconds: 20),
          fadeIn: fadeIn,
          fadeOut: fadeOut,
        );

    test('linear 1.5 s fades at both ends', () {
      final a = audio(fadeIn: true, fadeOut: true);
      expect(AudioFades.gain(a, const Duration(seconds: 10)), 0);
      expect(AudioFades.gain(a, const Duration(milliseconds: 10750)),
          closeTo(0.5, 1e-6));
      expect(AudioFades.gain(a, const Duration(seconds: 15)), 1);
      expect(AudioFades.gain(a, const Duration(milliseconds: 19250)),
          closeTo(0.5, 1e-6));
    });

    test('no fades -> unity gain', () {
      expect(AudioFades.gain(audio(), const Duration(seconds: 10)), 1);
    });
  });

  group('TextOverlay storage', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('text_overlay_hive');
      Hive.init(dir.path);
      // The adapters HiveService registers for text overlays.
      void reg<T>(TypeAdapter<T> a) {
        if (!Hive.isAdapterRegistered(a.typeId)) Hive.registerAdapter<T>(a);
      }

      reg(OffsetAdapter());
      reg(ColorAdapter());
      reg(FontWeightAdapter());
      reg(DurationAdapter());
      reg(FontStyleEnumAdapter());
      reg(TextAlignEnumAdapter());
      reg(TextOverlayAdapter());
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('new style fields survive a save/load round trip', () async {
      final box = await Hive.openBox<TextOverlay>('t1');
      await box.put(
        'x',
        TextOverlay(
          id: 'x',
          text: 'Hello',
          position: const Offset(0.1, 0.2),
          startTime: Duration.zero,
          endTime: const Duration(seconds: 2),
          animIn: 'pop',
          animOut: 'slide',
          boxColor: const Color(0x99000000),
          outlineColor: Colors.white,
          outlineWidth: 4,
          shadow: false,
        ),
      );
      await box.close();
      final reopened = await Hive.openBox<TextOverlay>('t1');
      final o = reopened.get('x')!;
      expect(o.animIn, 'pop');
      expect(o.animOut, 'slide');
      expect(o.boxColor?.toARGB32(), 0x99000000);
      expect(o.outlineColor?.toARGB32(), Colors.white.toARGB32());
      expect(o.outlineWidth, 4);
      expect(o.shadow, isFalse);
    });

    test('defaults: no animation, no box/outline, shadow on', () {
      final o = TextOverlay(
        id: 'y',
        text: 'Old',
        position: Offset.zero,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 1),
      );
      expect(o.animIn, 'none');
      expect(o.boxColor, isNull);
      expect(o.outlineWidth, 0);
      expect(o.shadow, isTrue);
    });
  });
}
