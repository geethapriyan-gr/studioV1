import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:studio_v_v2/providers/video_editor_provider.dart';

void main() {
  group('VideoEditorProvider timeline mapping', () {
    final clip = VideoClip(
      id: 'clip-1',
      mediaType: MediaType.video,
      videoFile: File('unused.mp4'),
      startTime: const Duration(seconds: 10),
      endTime: const Duration(seconds: 20),
      sourceStart: const Duration(seconds: 3),
      sourceEnd: const Duration(seconds: 13),
      trimStart: const Duration(seconds: 3),
      trimEnd: const Duration(seconds: 13),
    );

    test('maps timeline position into the clip source range', () {
      final sourcePosition =
          VideoEditorProvider.calculateSourcePositionForTimeline(
        clip,
        const Duration(seconds: 14, milliseconds: 500),
      );

      expect(sourcePosition, const Duration(seconds: 7, milliseconds: 500));
    });

    test('clamps timeline positions before the clip to sourceStart', () {
      final sourcePosition =
          VideoEditorProvider.calculateSourcePositionForTimeline(
        clip,
        const Duration(seconds: 8),
      );

      expect(sourcePosition, const Duration(seconds: 3));
    });

    test('never seeks exactly to native video duration', () {
      final clamped = VideoEditorProvider.clampSourcePositionForVideo(
        const Duration(seconds: 10),
        const Duration(seconds: 10),
      );

      expect(clamped, const Duration(seconds: 9, milliseconds: 999));
    });
  });
}
