import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:studio_v_v2/models/transition.dart';
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

  group('VideoEditorProvider transition preview timing', () {
    final clip1 = VideoClip(
      id: 'clip-1',
      mediaType: MediaType.video,
      videoFile: File('clip1.mp4'),
      startTime: Duration.zero,
      endTime: const Duration(seconds: 10),
      sourceStart: Duration.zero,
      sourceEnd: const Duration(seconds: 10),
      trimStart: Duration.zero,
      trimEnd: const Duration(seconds: 10),
    );

    final clip2 = VideoClip(
      id: 'clip-2',
      mediaType: MediaType.image,
      imageFile: File('clip2.png'),
      startTime: const Duration(seconds: 10),
      endTime: const Duration(seconds: 13),
      sourceStart: Duration.zero,
      sourceEnd: const Duration(seconds: 3),
      trimStart: Duration.zero,
      trimEnd: const Duration(seconds: 3),
    );

    final transition = Transition(
      id: 'transition-1',
      clipId1: clip1.id,
      clipId2: clip2.id,
      type: TransitionType.crossfade,
      duration: const Duration(milliseconds: 500),
      startTime: clip1.endTime - const Duration(milliseconds: 500),
    );

    test('uses clip2 start as the visual transition window', () {
      expect(
        VideoEditorProvider.transitionPreviewVisualStart(transition, clip2),
        clip2.startTime,
      );
      expect(
        VideoEditorProvider.transitionPreviewVisualEnd(transition, clip2),
        clip2.startTime + transition.duration,
      );
    });

    test('starts prewarming before clip2 starts', () {
      expect(
        VideoEditorProvider.transitionPreviewPrewarmStart(
          transition,
          clip1,
          clip2,
        ),
        const Duration(seconds: 9, milliseconds: 200),
      );
      expect(
        VideoEditorProvider.isTransitionPreviewPrewarmAt(
          const Duration(seconds: 9, milliseconds: 199),
          transition,
          clip1,
          clip2,
        ),
        isFalse,
      );
      expect(
        VideoEditorProvider.isTransitionPreviewPrewarmAt(
          const Duration(seconds: 9, milliseconds: 200),
          transition,
          clip1,
          clip2,
        ),
        isTrue,
      );
    });

    test('clamps prewarm start to the outgoing clip range', () {
      final shortClip1 = clip1.copyWith(
        startTime: const Duration(seconds: 9, milliseconds: 800),
        endTime: const Duration(seconds: 10),
      );

      expect(
        VideoEditorProvider.transitionPreviewPrewarmStart(
          transition,
          shortClip1,
          clip2,
        ),
        shortClip1.startTime,
      );
    });

    test('does not use transition.startTime as the visual animation start', () {
      expect(transition.startTime, isNot(clip2.startTime));
      expect(
        VideoEditorProvider.isTransitionPreviewActiveAt(
          transition.startTime,
          transition,
          clip2,
        ),
        isFalse,
      );
      expect(
        VideoEditorProvider.transitionPreviewProgress(
          transition.startTime,
          transition,
          clip2,
        ),
        0.0,
      );
    });

    test('is not active before the exported boundary', () {
      expect(
        VideoEditorProvider.isTransitionPreviewActiveAt(
          const Duration(seconds: 9, milliseconds: 999),
          transition,
          clip2,
        ),
        isFalse,
      );
    });

    test('is active from clip2 start through the transition duration', () {
      expect(
        VideoEditorProvider.isTransitionPreviewActiveAt(
          clip2.startTime,
          transition,
          clip2,
        ),
        isTrue,
      );
      expect(
        VideoEditorProvider.isTransitionPreviewActiveAt(
          clip2.startTime + const Duration(milliseconds: 499),
          transition,
          clip2,
        ),
        isTrue,
      );
    });

    test('is inactive after the transition duration', () {
      expect(
        VideoEditorProvider.isTransitionPreviewActiveAt(
          clip2.startTime + transition.duration,
          transition,
          clip2,
        ),
        isFalse,
      );
    });

    test('calculates progress from visual start to visual end', () {
      expect(
        VideoEditorProvider.transitionPreviewProgress(
          clip2.startTime,
          transition,
          clip2,
        ),
        0.0,
      );
      expect(
        VideoEditorProvider.transitionPreviewProgress(
          clip2.startTime + const Duration(milliseconds: 250),
          transition,
          clip2,
        ),
        0.5,
      );
      expect(
        VideoEditorProvider.transitionPreviewProgress(
          clip2.startTime + transition.duration,
          transition,
          clip2,
        ),
        1.0,
      );
    });
  });

  group('VideoEditorProvider playback recovery timing', () {
    test('does not hold the timeline when active video is in sync', () {
      final hold = VideoEditorProvider.shouldHoldTimelineForVideoSync(
        isPlayingRequested: true,
        controllerInitialized: true,
        controllerPlaying: true,
        controllerBuffering: false,
        controllerPosition: const Duration(seconds: 4),
        expectedPosition: const Duration(seconds: 4, milliseconds: 100),
      );

      expect(hold, isFalse);
    });

    test('holds the timeline when video is paused after requested playback',
        () {
      final hold = VideoEditorProvider.shouldHoldTimelineForVideoSync(
        isPlayingRequested: true,
        controllerInitialized: true,
        controllerPlaying: false,
        controllerBuffering: false,
        controllerPosition: const Duration(seconds: 4),
        expectedPosition: const Duration(seconds: 4),
      );

      expect(hold, isTrue);
    });

    test('holds the timeline when buffering video drifts behind', () {
      final hold = VideoEditorProvider.shouldHoldTimelineForVideoSync(
        isPlayingRequested: true,
        controllerInitialized: true,
        controllerPlaying: true,
        controllerBuffering: true,
        controllerPosition: const Duration(seconds: 4),
        expectedPosition: const Duration(seconds: 5),
      );

      expect(hold, isTrue);
    });

    test('does not hold when playback is not requested', () {
      final hold = VideoEditorProvider.shouldHoldTimelineForVideoSync(
        isPlayingRequested: false,
        controllerInitialized: false,
        controllerPlaying: false,
        controllerBuffering: false,
        controllerPosition: Duration.zero,
        expectedPosition: const Duration(seconds: 1),
      );

      expect(hold, isFalse);
    });
  });
}
