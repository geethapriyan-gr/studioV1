import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_v_v2/utils/track_allocation.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:flutter/material.dart';

void main() {
  group('Track Allocation Tests', () {
    test('Empty list returns 1 track and empty map', () {
      final result = computeTrackAllocation<TextOverlay>(
        items: [],
        getId: (t) => t.id,
        getStartTime: (t) => t.startTime,
        getEndTime: (t) => t.endTime,
      );

      expect(result.trackCount, equals(1));
      expect(result.itemToTrackMap.isEmpty, isTrue);
    });

    test('Non-overlapping text items stay on 1 track', () {
      final t1 = TextOverlay(
        id: '1',
        text: 'Text 1',
        position: Offset.zero,
        startTime: const Duration(seconds: 0),
        endTime: const Duration(seconds: 5),
      );
      final t2 = TextOverlay(
        id: '2',
        text: 'Text 2',
        position: Offset.zero,
        startTime: const Duration(seconds: 5),
        endTime: const Duration(seconds: 10),
      );

      final result = computeTrackAllocation<TextOverlay>(
        items: [t1, t2],
        getId: (t) => t.id,
        getStartTime: (t) => t.startTime,
        getEndTime: (t) => t.endTime,
      );

      expect(result.trackCount, equals(1));
      expect(result.itemToTrackMap['1'], equals(0));
      expect(result.itemToTrackMap['2'], equals(0));
    });

    test('Overlapping text items are dynamically allocated to new tracks', () {
      final t1 = TextOverlay(
        id: '1',
        text: 'Text 1',
        position: Offset.zero,
        startTime: const Duration(seconds: 0),
        endTime: const Duration(seconds: 5),
      );
      final t2 = TextOverlay(
        id: '2',
        text: 'Text 2',
        position: Offset.zero,
        startTime: const Duration(seconds: 2),
        endTime: const Duration(seconds: 7),
      );

      final result = computeTrackAllocation<TextOverlay>(
        items: [t1, t2],
        getId: (t) => t.id,
        getStartTime: (t) => t.startTime,
        getEndTime: (t) => t.endTime,
      );

      expect(result.trackCount, equals(2));
      expect(result.itemToTrackMap['1'], equals(0));
      expect(result.itemToTrackMap['2'], equals(1));
    });

    test('Moving or deleting overlapping item dynamically deletes extra track', () {
      final t1 = TextOverlay(
        id: '1',
        text: 'Text 1',
        position: Offset.zero,
        startTime: const Duration(seconds: 0),
        endTime: const Duration(seconds: 5),
      );
      final t2Moved = TextOverlay(
        id: '2',
        text: 'Text 2',
        position: Offset.zero,
        startTime: const Duration(seconds: 6),
        endTime: const Duration(seconds: 10),
      );

      final result = computeTrackAllocation<TextOverlay>(
        items: [t1, t2Moved],
        getId: (t) => t.id,
        getStartTime: (t) => t.startTime,
        getEndTime: (t) => t.endTime,
      );

      expect(result.trackCount, equals(1));
      expect(result.itemToTrackMap['1'], equals(0));
      expect(result.itemToTrackMap['2'], equals(0));
    });

    test('Stickers track allocation works identically', () {
      final s1 = StickerModel(
        id: 's1',
        assetPath: 'assets/stickers/happy.png',
        startTime: const Duration(seconds: 1),
        endTime: const Duration(seconds: 4),
      );
      final s2 = StickerModel(
        id: 's2',
        assetPath: 'assets/stickers/sad.png',
        startTime: const Duration(seconds: 3),
        endTime: const Duration(seconds: 6),
      );

      final result = computeTrackAllocation<StickerModel>(
        items: [s1, s2],
        getId: (s) => s.id,
        getStartTime: (s) => s.startTime,
        getEndTime: (s) => s.endTime,
      );

      expect(result.trackCount, equals(2));
      expect(result.itemToTrackMap['s1'], equals(0));
      expect(result.itemToTrackMap['s2'], equals(1));
    });

    test('Audio overlays track allocation works identically', () {
      final a1 = AudioOverlay(
        id: 'a1',
        audioFile: File('test.mp3'),
        startTime: const Duration(seconds: 0),
        endTime: const Duration(seconds: 5),
      );
      final a2 = AudioOverlay(
        id: 'a2',
        audioFile: File('test2.mp3'),
        startTime: const Duration(seconds: 2),
        endTime: const Duration(seconds: 7),
      );

      final result = computeTrackAllocation<AudioOverlay>(
        items: [a1, a2],
        getId: (a) => a.id,
        getStartTime: (a) => a.startTime,
        getEndTime: (a) => a.endTime,
      );

      expect(result.trackCount, equals(2));
      expect(result.itemToTrackMap['a1'], equals(0));
      expect(result.itemToTrackMap['a2'], equals(1));
    });

    test('Video overlay clips track allocation works identically', () {
      final v1 = VideoClip(
        id: 'v1',
        mediaType: MediaType.video,
        startTime: const Duration(seconds: 0),
        endTime: const Duration(seconds: 4),
      );
      final v2 = VideoClip(
        id: 'v2',
        mediaType: MediaType.video,
        startTime: const Duration(seconds: 2),
        endTime: const Duration(seconds: 6),
      );

      final result = computeTrackAllocation<VideoClip>(
        items: [v1, v2],
        getId: (v) => v.id,
        getStartTime: (v) => v.startTime,
        getEndTime: (v) => v.endTime,
      );

      expect(result.trackCount, equals(2));
      expect(result.itemToTrackMap['v1'], equals(0));
      expect(result.itemToTrackMap['v2'], equals(1));
    });
  });
}
