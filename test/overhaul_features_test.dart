import 'dart:io';

import 'package:flutter/material.dart' hide ColorFilter;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:studio_v_v2/models/chroma_key_settings.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:studio_v_v2/providers/video_editor_provider.dart';
import 'package:studio_v_v2/services/export_service.dart';
import 'package:studio_v_v2/services/hive_service.dart';
import 'package:studio_v_v2/utils/snap_guides.dart';
import 'package:studio_v_v2/utils/sticker_catalog.dart';
import 'package:studio_v_v2/utils/text_overlay_painter.dart';
import 'package:studio_v_v2/widgets/item_toolbars.dart';

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

/// Editor with [build]'s project loaded without media players.
VideoEditorProvider loadBare(VideoProject Function(String id) build) =>
    VideoEditorProvider()..debugSetProject(build('p${_counter++}'));

Future<VideoEditorProvider> load(VideoProject Function(String id) build) async {
  final project = build('p${_counter++}');
  await HiveService.saveProject(project);
  final provider = VideoEditorProvider();
  await provider.loadProject(project.id);
  return provider;
}

// ── Adapters that write projects the way older builds did ────────────────

class _OldAudioAdapter extends TypeAdapter<AudioOverlay> {
  @override
  final int typeId = 2;
  @override
  AudioOverlay read(BinaryReader reader) => throw UnimplementedError();
  @override
  void write(BinaryWriter writer, AudioOverlay obj) {
    // Before trackIndex (field 8) existed.
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.audioFile)
      ..writeByte(2)
      ..write(obj.startTime)
      ..writeByte(3)
      ..write(obj.endTime)
      ..writeByte(4)
      ..write(obj.audioStartOffset)
      ..writeByte(5)
      ..write(obj.volume)
      ..writeByte(6)
      ..write(obj.fadeIn)
      ..writeByte(7)
      ..write(obj.fadeOut);
  }
}

class _OldStickerAdapter extends TypeAdapter<StickerModel> {
  @override
  final int typeId = 4;
  @override
  StickerModel read(BinaryReader reader) => throw UnimplementedError();
  @override
  void write(BinaryWriter writer, StickerModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.assetPath)
      ..writeByte(2)
      ..write(obj.position)
      ..writeByte(3)
      ..write(obj.scale)
      ..writeByte(4)
      ..write(obj.rotation)
      ..writeByte(5)
      ..write(obj.startTime)
      ..writeByte(6)
      ..write(obj.endTime);
  }
}

class _OldProjectAdapter extends TypeAdapter<VideoProject> {
  @override
  final int typeId = 6;
  @override
  VideoProject read(BinaryReader reader) => throw UnimplementedError();
  @override
  void write(BinaryWriter writer, VideoProject obj) {
    // Before chroma backgrounds, transitions, effects and overlays.
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.videoClips)
      ..writeByte(3)
      ..write(obj.textOverlays)
      ..writeByte(4)
      ..write(obj.audioOverlays)
      ..writeByte(5)
      ..write(obj.stickers)
      ..writeByte(7)
      ..write(obj.totalDuration)
      ..writeByte(8)
      ..write(obj.outputResolution)
      ..writeByte(9)
      ..write(obj.outputFrameRate)
      ..writeByte(10)
      ..write(obj.createdAt);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('studio_v_overhaul');
    File('${tmp.path}/a.png').writeAsBytesSync([0]);
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await HiveService.init();
  });

  group('saved projects', () {
    test('projects written by older builds still load', () async {
      final old = VideoProject(
        id: 'legacy',
        name: 'Legacy',
        videoClips: [image('c', 0, 4)],
        audioOverlays: [
          AudioOverlay(
            id: 'a',
            audioFile: File('${tmp.path}/song.mp3'),
            startTime: Duration.zero,
            endTime: s(3),
          ),
        ],
        stickers: [
          StickerModel(
              id: 'st',
              assetPath: 'assets/stickers/star.png',
              startTime: Duration.zero,
              endTime: s(2)),
        ],
      );
      final box = await Hive.openBox<VideoProject>('legacy_box');
      Hive.registerAdapter(_OldAudioAdapter(), override: true);
      Hive.registerAdapter(_OldStickerAdapter(), override: true);
      Hive.registerAdapter(_OldProjectAdapter(), override: true);
      await box.put(old.id, old);
      await box.close();

      Hive.registerAdapter(AudioOverlayAdapter(), override: true);
      Hive.registerAdapter(StickerModelAdapter(), override: true);
      Hive.registerAdapter(VideoProjectAdapter(), override: true);
      final reopened = await Hive.openBox<VideoProject>('legacy_box');
      final p = reopened.get('legacy')!;
      expect(p.name, 'Legacy');
      expect(p.audioOverlays.single.trackIndex, 0);
      expect(p.stickers.single.opacity, 1.0);
      expect(p.stickers.single.flipX, isFalse);
      expect(p.stickers.single.animIn, 'none');
      expect(p.overlayClips, isEmpty);
      expect(p.transitions, isEmpty);
      expect(p.colorFilter.contrast, 1.0);
      await reopened.close();
    });

    test('new overlay and sticker fields survive a save/load round trip',
        () async {
      final project = VideoProject(
        id: 'roundtrip',
        name: 'rt',
        overlayClips: [
          image('o', 0, 3).copyWith(
            maskShape: 'heart',
            borderWidth: 9,
            borderColor: Colors.white,
            shadow: true,
            animIn: 'pop',
            animOut: 'fade',
            keyframeData: OverlayKeyframe.encode([
              OverlayKeyframe(Duration.zero, const Offset(0.1, 0.2),
                  const Size(0.3, 0.3)),
              OverlayKeyframe(
                  s(2), const Offset(0.5, 0.6), const Size(0.4, 0.4)),
            ]),
          ),
        ],
        stickers: [
          StickerModel(
            id: 'st',
            assetPath: 'assets/stickers/star.png',
            startTime: Duration.zero,
            endTime: s(2),
            flipX: true,
            animIn: 'slide',
          ),
        ],
      );
      await HiveService.saveProject(project);
      final o = HiveService.getProject('roundtrip')!.overlayClips.single;
      expect(o.maskShape, 'heart');
      expect(o.borderWidth, 9);
      expect(o.borderColor?.toARGB32(), Colors.white.toARGB32());
      expect(o.shadow, isTrue);
      expect(o.animIn, 'pop');
      expect(o.keyframes.length, 2);
      expect(o.keyframes.last.position.dx, closeTo(0.5, 1e-9));
      final st = HiveService.getProject('roundtrip')!.stickers.single;
      expect(st.flipX, isTrue);
      expect(st.animIn, 'slide');
    });
  });

  group('undo', () {
    test('rapid edits with one key are one undo step', () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            videoClips: [image('c', 0, 5)],
            textOverlays: [
              TextOverlay(
                  id: 't',
                  text: '',
                  position: Offset.zero,
                  startTime: Duration.zero,
                  endTime: s(2)),
            ],
          ));
      for (final text in ['H', 'He', 'Hel', 'Hell', 'Hello']) {
        await p.updateTextOverlay('t', text: text, undoKey: 'text-edit:t');
      }
      expect(p.currentProject!.textOverlays.single.text, 'Hello');
      await p.undo();
      expect(p.currentProject!.textOverlays.single.text, '');
      expect(p.canUndo, isFalse);
    });

    test('a gesture is one undo step; separate gestures are separate',
        () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            videoClips: [image('c', 0, 5)],
            stickers: [
              StickerModel(
                  id: 'st',
                  assetPath: 'assets/stickers/star.png',
                  startTime: Duration.zero,
                  endTime: s(2)),
            ],
          ));
      p.beginUndoGesture('sticker-trim:st');
      for (int i = 1; i <= 10; i++) {
        await p.updateSticker('st', endTime: s(2) + Duration(milliseconds: i * 100));
      }
      p.endUndoGesture();
      p.beginUndoGesture('sticker-trim:st');
      await p.updateSticker('st', endTime: s(4));
      p.endUndoGesture();

      await p.undo();
      expect(p.currentProject!.stickers.single.endTime, s(3));
      await p.undo();
      expect(p.currentProject!.stickers.single.endTime, s(2));
      expect(p.canUndo, isFalse);
    });

    test('moving, resizing and deleting an overlay can be undone', () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            videoClips: [image('c', 0, 5)],
            overlayClips: [image('o', 0, 3)],
          ));
      p.updateOverlayClipBox('o',
          position: const Offset(0.4, 0.4), size: const Size(0.2, 0.2));
      p.sealUndo();
      p.removeOverlayClip('o');
      expect(p.currentProject!.overlayClips, isEmpty);
      await p.undo();
      expect(p.currentProject!.overlayClips.single.overlayPosition,
          const Offset(0.4, 0.4));
      await p.undo();
      expect(p.currentProject!.overlayClips.single.overlayPosition,
          const Offset(0.1, 0.1));
    });
  });

  group('audio', () {
    test('changing volume keeps the same file (no re-import)', () async {
      final song = File('${tmp.path}/song.mp3')..writeAsBytesSync([1, 2, 3]);
      final p = loadBare((id) => VideoProject(
            id: id,
            name: 't',
            videoClips: [image('c', 0, 5)],
            audioOverlays: [
              AudioOverlay(
                  id: 'a',
                  audioFile: song,
                  startTime: s(1.25),
                  endTime: s(3.75)),
            ],
          ));
      final filesBefore = tmp.listSync().length;
      for (final v in [0.2, 0.4, 0.6]) {
        await p.updateAudioOverlay('a',
            audioFile: song, volume: v, undoKey: 'audio-vol:a');
      }
      final a = p.currentProject!.audioOverlays.single;
      expect(a.audioFile.path, song.path);
      expect(a.volume, 0.6);
      // Timing untouched (used to snap to whole seconds).
      expect(a.startTime, s(1.25));
      expect(a.endTime, s(3.75));
      expect(tmp.listSync().length, filesBefore);
    });

    test('the start offset never goes negative', () async {
      final p = loadBare((id) => VideoProject(
            id: id,
            name: 't',
            audioOverlays: [
              AudioOverlay(
                  id: 'a',
                  audioFile: File('${tmp.path}/song.mp3'),
                  startTime: s(2),
                  endTime: s(4)),
            ],
          ));
      await p.updateAudioOverlay('a', audioStartOffset: s(-1));
      expect(p.currentProject!.audioOverlays.single.audioStartOffset,
          Duration.zero);
    });

    test('split keeps the track and duplicate goes right after', () async {
      final p = loadBare((id) => VideoProject(
            id: id,
            name: 't',
            audioOverlays: [
              AudioOverlay(
                  id: 'a',
                  audioFile: File('${tmp.path}/song.mp3'),
                  startTime: Duration.zero,
                  endTime: s(4),
                  trackIndex: 2),
            ],
          ));
      await p.seekTo(s(1));
      p.cutAudioOverlay('a');
      expect(p.currentProject!.audioOverlays.map((a) => a.trackIndex),
          [2, 2]);
      final second = p.currentProject!.audioOverlays.last;
      final copy = p.duplicateAudioOverlay(second.id)!;
      final c = p.currentProject!.audioOverlays.firstWhere((a) => a.id == copy);
      expect(c.startTime, second.endTime);
      expect(c.endTime - c.startTime, second.endTime - second.startTime);
    });
  });

  group('video length', () {
    test('every item counts toward the length, for preview and export',
        () async {
      final project = VideoProject(
        id: 'len',
        name: 'len',
        videoClips: [image('c', 0, 4)],
        stickers: [
          StickerModel(
              id: 'st',
              assetPath: 'assets/stickers/star.png',
              startTime: s(3),
              endTime: s(7)),
        ],
        overlayClips: [image('o', 5, 9)],
      );
      expect(project.contentEnd, s(9));
      expect(ExportService.timelineTotalSeconds(project), 9.0);
    });

    test('moving never makes the video longer', () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            videoClips: [image('c', 0, 10)],
          ));
      expect(p.clampMoveStart(s(9), s(3)), s(7));
      expect(p.clampMoveStart(s(-2), s(3)), Duration.zero);
      expect(p.clampMoveStart(s(4), s(12)), Duration.zero);
    });

    test('trim to fit shortens the added item to the old end', () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            videoClips: [image('c', 0, 5)],
          ));
      await p.seekTo(s(3));
      final id = await p.addSticker(
          assetPath: 'assets/stickers/star.png',
          startTime: s(3),
          endTime: s(8));
      expect(p.totalDuration, s(8));
      p.trimItemToEnd(TimelineItemKind.sticker, id!, s(5));
      expect(p.totalDuration, s(5));
      // The add and the trim are one undo step.
      await p.undo();
      expect(p.currentProject!.stickers, isEmpty);
    });
  });

  group('item tools', () {
    test('text and stickers split at the playhead with their animations',
        () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            videoClips: [image('c', 0, 6)],
            textOverlays: [
              TextOverlay(
                  id: 't',
                  text: 'Hi',
                  position: Offset.zero,
                  startTime: Duration.zero,
                  endTime: s(4),
                  animIn: 'fade',
                  animOut: 'pop'),
            ],
            stickers: [
              StickerModel(
                  id: 'st',
                  assetPath: 'assets/stickers/star.png',
                  startTime: s(1),
                  endTime: s(5),
                  animIn: 'slide',
                  animOut: 'fade'),
            ],
          ));
      await p.seekTo(s(2));
      expect(p.cutTextOverlay('t'), isTrue);
      expect(p.cutSticker('st'), isTrue);
      final t = p.currentProject!.textOverlays;
      expect([t[0].endTime, t[1].startTime], [s(2), s(2)]);
      expect([t[0].animIn, t[0].animOut, t[1].animIn, t[1].animOut],
          ['fade', 'none', 'none', 'pop']);
      final st = p.currentProject!.stickers;
      expect([st[0].animOut, st[1].animIn], ['none', 'none']);
      // Outside the item: nothing happens.
      await p.seekTo(s(5.5));
      expect(p.cutTextOverlay(t[0].id), isFalse);
    });

    test('overlay layer order and duplicate', () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            videoClips: [image('c', 0, 6)],
            overlayClips: [image('a', 0, 3), image('b', 0, 3), image('c2', 0, 3)],
          ));
      p.moveOverlayLayer('a', LayerMove.front);
      expect(p.currentProject!.overlayClips.map((c) => c.id), ['b', 'c2', 'a']);
      p.moveOverlayLayer('a', LayerMove.backward);
      expect(p.currentProject!.overlayClips.map((c) => c.id), ['b', 'a', 'c2']);
      final copy = p.duplicateOverlayClip('b')!;
      expect(p.selectedOverlayClipId, copy);
      expect(p.overlayLayerOf(copy), (3, 4));
    });

    test('overlay speed sets the timeline length', () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            overlayClips: [
              VideoClip(
                id: 'v',
                mediaType: MediaType.video,
                videoFile: File('${tmp.path}/v.mp4'),
                startTime: s(1),
                endTime: s(5),
                sourceStart: Duration.zero,
                sourceEnd: s(4),
              ),
            ],
          ));
      p.setOverlayClipSpeed('v', 2.0);
      final c = p.currentProject!.overlayClips.single;
      expect(c.playbackSpeed, 2.0);
      expect(c.endTime, s(3));
    });

    test('crop keeps the box width and reshapes its height', () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            overlayClips: [
              image('o', 0, 3).copyWith(overlaySize: const Size(0.4, 0.2)),
            ],
          ));
      // Cropping to the left half halves the picture's width/height ratio.
      p.setOverlayCrop('o', const Rect.fromLTWH(0, 0, 0.5, 1));
      final c = p.currentProject!.overlayClips.single;
      expect(c.overlaySize.width, closeTo(0.4, 1e-9));
      expect(c.overlaySize.height, closeTo(0.4, 1e-9));
      p.setOverlayCrop('o', null);
      expect(p.currentProject!.overlayClips.single.overlaySize.height,
          closeTo(0.2, 1e-9));
    });

    test('green screen on an overlay turns on and off', () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            overlayClips: [image('o', 0, 3)],
          ));
      p.setOverlayChromaKey('o', const ChromaKeySettings(enabled: true));
      expect(p.currentProject!.overlayClips.single.chromaKeySettings?.enabled,
          isTrue);
      p.setOverlayChromaKey('o', null);
      expect(
          p.currentProject!.overlayClips.single.chromaKeySettings, isNull);
    });
  });

  group('overlay motion', () {
    test('keyframes interpolate linearly and clamp outside', () {
      final clip = image('o', 0, 4).copyWith(
        keyframeData: OverlayKeyframe.encode([
          OverlayKeyframe(s(3), const Offset(0.6, 0.6), const Size(0.2, 0.2)),
          OverlayKeyframe(s(1), const Offset(0.2, 0.2), const Size(0.4, 0.4)),
        ]),
      );
      final (p0, s0) = OverlayKeyframe.boxAt(clip, Duration.zero);
      expect(p0, const Offset(0.2, 0.2));
      expect(s0, const Size(0.4, 0.4));
      final (p2, s2) = OverlayKeyframe.boxAt(clip, s(2));
      expect(p2.dx, closeTo(0.4, 1e-9));
      expect(s2.width, closeTo(0.3, 1e-9));
      final (p4, _) = OverlayKeyframe.boxAt(clip, s(4));
      expect(p4, const Offset(0.6, 0.6));
    });

    test('dragging an animated overlay edits the keyframe at the playhead',
        () async {
      final p = await load((id) => VideoProject(
            id: id,
            name: 't',
            videoClips: [image('c', 0, 6)],
            overlayClips: [image('o', 0, 4)],
          ));
      await p.seekTo(s(1));
      p.addOverlayKeyframeAtPlayhead('o');
      // The first keyframe also pins the start.
      expect(p.currentProject!.overlayClips.single.keyframes.length, 2);
      await p.seekTo(s(3));
      p.updateOverlayClipBox('o', position: const Offset(0.5, 0.5));
      final c = p.currentProject!.overlayClips.single;
      expect(c.keyframes.length, 3);
      expect(c.overlayPosition, const Offset(0.1, 0.1)); // static box kept
      expect(OverlayKeyframe.boxAt(c, s(3)).$1, const Offset(0.5, 0.5));
      expect(p.overlayHasKeyframeAtPlayhead('o'), isTrue);
      p.clearOverlayKeyframes('o');
      final cleared = p.currentProject!.overlayClips.single;
      expect(cleared.keyframes, isEmpty);
      expect(cleared.overlayPosition, const Offset(0.5, 0.5));
    });

    test('splitting an overlay splits its motion continuously', () {
      final clip = image('o', 0, 4).copyWith(
        keyframeData: OverlayKeyframe.encode([
          OverlayKeyframe(Duration.zero, const Offset(0, 0), const Size(0.2, 0.2)),
          OverlayKeyframe(s(4), const Offset(0.8, 0), const Size(0.2, 0.2)),
        ]),
      );
      final (a, b) = VideoEditorProvider.splitKeyframes(clip, s(1));
      expect(a.last.time, s(1));
      expect(a.last.position.dx, closeTo(0.2, 1e-9));
      expect(b.first.time, Duration.zero);
      expect(b.first.position.dx, closeTo(0.2, 1e-9));
      expect(b.last.time, s(3));
    });
  });

  group('media files', () {
    test('only app copies no other project uses are deleted', () {
      final app = tmp.path;
      final mine = '$app${Platform.pathSeparator}mine.mp4';
      final shared = '$app${Platform.pathSeparator}shared.mp3';
      final gallery = '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'gallery.mp4';
      final deleted = VideoProject(
        id: 'd',
        name: 'd',
        videoClips: [
          VideoClip(
              id: 'v',
              mediaType: MediaType.video,
              videoFile: File(mine),
              startTime: Duration.zero,
              endTime: s(1)),
        ],
        overlayClips: [
          VideoClip(
              id: 'g',
              mediaType: MediaType.video,
              videoFile: File(gallery),
              startTime: Duration.zero,
              endTime: s(1)),
        ],
        audioOverlays: [
          AudioOverlay(
              id: 'a',
              audioFile: File(shared),
              startTime: Duration.zero,
              endTime: s(1)),
        ],
        stickers: [
          StickerModel(
              id: 'st',
              assetPath: 'assets/stickers/star.png',
              startTime: Duration.zero,
              endTime: s(1)),
        ],
      );
      final other = VideoProject(id: 'o', name: 'o', audioOverlays: [
        AudioOverlay(
            id: 'a2',
            audioFile: File(shared),
            startTime: Duration.zero,
            endTime: s(1)),
      ]);
      expect(
          VideoEditorProvider.unusedMediaAfterDelete(deleted, [other], app),
          {mine});
    });

    test('missing overlay and sticker files are found again by name', () {
      final healed = File('${tmp.path}/moved.png')..writeAsBytesSync([0]);
      final project = VideoProject(
        id: 'h',
        name: 'h',
        overlayClips: [
          VideoClip(
              id: 'o',
              mediaType: MediaType.image,
              imageFile: File('/old/sandbox/moved.png'),
              startTime: Duration.zero,
              endTime: s(1)),
        ],
        stickers: [
          StickerModel(
              id: 'st',
              assetPath: '/old/sandbox/moved.png',
              startTime: Duration.zero,
              endTime: s(1)),
          StickerModel(
              id: 'asset',
              assetPath: 'assets/stickers/star.png',
              startTime: Duration.zero,
              endTime: s(1)),
        ],
      );
      final fixed = VideoEditorProvider.healProjectPaths(project, tmp.path);
      expect(p.normalize(fixed.overlayClips.single.imageFile!.path),
          p.normalize(healed.path));
      expect(p.normalize(fixed.stickers.first.assetPath),
          p.normalize(healed.path));
      expect(fixed.stickers.last.assetPath, 'assets/stickers/star.png');
    });
  });

  group('helpers', () {
    test('new overlays keep the media shape inside the preview box', () {
      // 16:9 video on a 9:16 portrait clip: on screen w/h must be 16:9.
      final size = VideoEditorProvider.initialOverlaySize(
          mediaAspect: 16 / 9, canvasAspect: 9 / 16);
      final onScreen = (size.width * 9) / (size.height * 16);
      expect(onScreen, closeTo(16 / 9, 1e-9));
      expect(size.width, closeTo(0.45, 1e-9));
    });

    test('snapping pulls a box to the centre lines', () {
      final p = SnapGuides.snapBox(const Offset(0.39, 0.1), const Size(0.2, 0.2));
      expect(p.dx, closeTo(0.4, 1e-9)); // centred horizontally
      expect(p.dy, closeTo(0.1, 1e-9)); // nothing nearby vertically
      expect(SnapGuides.active.value, {SnapLine.centerV});
      SnapGuides.clear();
      expect(SnapGuides.active.value, isEmpty);
    });

    test('sticker catalog names logos and maps removed duplicates', () {
      expect(
          StickerCatalog.describe(
                  'assets/stickers/Screenshot_2026-04-01_100327-removebg-preview.png')
              .label,
          'IEEE');
      expect(StickerCatalog.describe('assets/stickers/rocket (2).png').category,
          'Space');
      expect(StickerCatalog.describe('assets/stickers/june.png').category,
          'Calendar');
      expect(StickerCatalog.resolve('assets/stickers/yeah (1).png'),
          'assets/stickers/yeah.png');
    });

    test('shared animation timing for stickers and overlays', () {
      final mid = TextAnimations.atTimes('pop', 'fade', 4, 2);
      expect(mid.isIdle, isTrue);
      final start = TextAnimations.atTimes('fade', 'none', 4, 0.25);
      expect(start.opacity, closeTo(0.5, 1e-9));
    });
  });

  group('export expressions', () {
    test('piecewise path matches the keyframe interpolation', () {
      final expr = ExportService.piecewiseExpr(
          [(0.0, 10.0), (2.0, 30.0)], 't');
      expect(expr, startsWith('if(lt(t,0.000000),10.000,'));
      expect(expr, contains('if(lt(t,2.000000),10.000+(20.000)*((t)-0.000000)/2.000000,30.000)'));
      expect(ExportService.piecewiseExpr([(0.0, 5.0)], 't'), '5.000');
    });

    test('colour key matches the preview shader parameters', () {
      expect(
          ExportService.colorKeyFilter(const ChromaKeySettings(
              keyColor: Color(0xFF00FF00), similarity: 0.3, blend: 0.1)),
          'colorkey=0x00ff00:0.3000:0.1000');
    });

    test('motion graph rotates, animates and centres the tile', () {
      final g = ExportService.motionGraphForTest(
        tileW: 200,
        tileH: 100,
        start: 1,
        end: 5,
        path: [(0.0, 500.0, 400.0, 1.0)],
        rotationDeg: 90,
        opacity: 0.5,
        animIn: 'pop',
      );
      expect(g.filters, contains('rotate=a=1.570796:ow=100:oh=200:c=none'));
      expect(g.filters, contains('fade=t=in'));
      expect(g.filters, contains("scale=w='max(2,100.000*(1.000)*"));
      expect(g.filters, contains('pad='));
      expect(g.filters, contains('colorchannelmixer=aa=0.5000'));
      expect(g.filters, contains('setpts=PTS-STARTPTS+1.000000/TB'));
      // Pop pads to 108% + 2 px: 100 -> 110, 200 -> 218.
      expect(g.x, "'500.000-55.000'");
      expect(g.y, "'400.000-109.000'");
    });

    test('static overlay without animation needs no scaling', () {
      final g = ExportService.motionGraphForTest(
        tileW: 200,
        tileH: 100,
        start: 0,
        end: 3,
        path: [(0.0, 100.0, 100.0, 1.0)],
      );
      expect(g.filters, isNot(contains('scale=')));
      expect(g.filters, isNot(contains('rotate=')));
      expect(g.x, "'100.000-100.000'");
    });
  });

  group('toolbars', () {
    Future<void> pump(WidgetTester tester, Widget bar) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(bottomNavigationBar: bar)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('media overlay toolbar', (tester) async {
      await pump(
        tester,
        OverlayItemToolbar(
          provider: VideoEditorProvider(),
          clip: VideoClip(
            id: 'o',
            mediaType: MediaType.video,
            videoFile: File('o.mp4'),
            startTime: Duration.zero,
            endTime: const Duration(seconds: 3),
            playbackSpeed: 2,
          ),
        ),
      );
      expect(find.text('Overlay'), findsOneWidget);
      expect(find.text('Split'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('2.0x'), findsOneWidget);
    });

    testWidgets('text, sticker and audio toolbars', (tester) async {
      final provider = VideoEditorProvider();
      await pump(
        tester,
        TextItemToolbar(
          provider: provider,
          overlay: TextOverlay(
              id: 't',
              text: 'Hello',
              position: Offset.zero,
              startTime: Duration.zero,
              endTime: const Duration(seconds: 2)),
        ),
      );
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Animate'), findsOneWidget);

      await pump(
        tester,
        StickerItemToolbar(
          provider: provider,
          sticker: StickerModel(
              id: 's',
              assetPath: 'assets/stickers/star.png',
              startTime: Duration.zero,
              endTime: const Duration(seconds: 2)),
        ),
      );
      expect(find.text('Flip'), findsOneWidget);

      await pump(
        tester,
        AudioItemToolbar(
          provider: provider,
          overlay: AudioOverlay(
              id: 'a',
              audioFile: File('a.mp3'),
              startTime: Duration.zero,
              endTime: const Duration(seconds: 2)),
        ),
      );
      expect(find.text('Fade in'), findsOneWidget);
    });
  });
}
