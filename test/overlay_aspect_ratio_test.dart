import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_v_v2/models/video_project.dart';

void main() {
  group('Overlay Aspect Ratio Calculation Tests', () {
    Size computeOverlaySize({
      required Size parentResolution,
      required double mediaWidth,
      required double mediaHeight,
      int rotationCorrection = 0,
      double maxDimensionFraction = 0.45,
    }) {
      double effectiveWidth = mediaWidth;
      double effectiveHeight = mediaHeight;

      if ((rotationCorrection % 180) != 0) {
        effectiveWidth = mediaHeight;
        effectiveHeight = mediaWidth;
      }

      final parentWidth = parentResolution.width;
      final parentHeight = parentResolution.height;
      final parentAspectRatio = (parentWidth > 0 && parentHeight > 0)
          ? (parentWidth / parentHeight)
          : (16.0 / 9.0);
      final mediaAspectRatio = (effectiveWidth > 0 && effectiveHeight > 0)
          ? (effectiveWidth / effectiveHeight)
          : 1.0;

      final normalizedRatio = mediaAspectRatio / parentAspectRatio;

      double overlayWidth;
      double overlayHeight;

      if (normalizedRatio >= 1.0) {
        overlayWidth = maxDimensionFraction;
        overlayHeight = overlayWidth / normalizedRatio;
        if (overlayHeight > maxDimensionFraction) {
          overlayHeight = maxDimensionFraction;
          overlayWidth = overlayHeight * normalizedRatio;
        }
      } else {
        overlayHeight = maxDimensionFraction;
        overlayWidth = overlayHeight * normalizedRatio;
        if (overlayWidth > maxDimensionFraction) {
          overlayWidth = maxDimensionFraction;
          overlayHeight = overlayWidth / normalizedRatio;
        }
      }

      overlayWidth = overlayWidth.clamp(0.05, 1.0);
      overlayHeight = overlayHeight.clamp(0.05, 1.0);

      return Size(overlayWidth, overlayHeight);
    }

    test('Portrait overlay (with 90deg rotation) on Portrait base video preserves 9:16 aspect ratio', () {
      // Base video: 1080x1920 (9:16)
      // Overlay video: 1920x1080 buffer rotated 90 degrees (effective 1080x1920)
      final parentRes = const Size(1080, 1920);
      final overlaySize = computeOverlaySize(
        parentResolution: parentRes,
        mediaWidth: 1920,
        mediaHeight: 1080,
        rotationCorrection: 90,
      );

      final renderedWidth = overlaySize.width * parentRes.width;
      final renderedHeight = overlaySize.height * parentRes.height;
      final renderedAspectRatio = renderedWidth / renderedHeight;

      final expectedAspectRatio = 1080.0 / 1920.0;
      expect(renderedAspectRatio, closeTo(expectedAspectRatio, 0.001));
    });

    test('Portrait overlay (with 90deg rotation) on Landscape base video preserves 9:16 aspect ratio', () {
      // Base video: 1920x1080 (16:9)
      // Overlay video: 1920x1080 buffer rotated 90 degrees (effective 1080x1920)
      final parentRes = const Size(1920, 1080);
      final overlaySize = computeOverlaySize(
        parentResolution: parentRes,
        mediaWidth: 1920,
        mediaHeight: 1080,
        rotationCorrection: 90,
      );

      final renderedWidth = overlaySize.width * parentRes.width;
      final renderedHeight = overlaySize.height * parentRes.height;
      final renderedAspectRatio = renderedWidth / renderedHeight;

      final expectedAspectRatio = 1080.0 / 1920.0;
      expect(renderedAspectRatio, closeTo(expectedAspectRatio, 0.001));
    });

    test('Landscape overlay on Portrait base video preserves 16:9 aspect ratio', () {
      // Base video: 1080x1920 (9:16)
      // Overlay video: 1920x1080 landscape
      final parentRes = const Size(1080, 1920);
      final overlaySize = computeOverlaySize(
        parentResolution: parentRes,
        mediaWidth: 1920,
        mediaHeight: 1080,
        rotationCorrection: 0,
      );

      final renderedWidth = overlaySize.width * parentRes.width;
      final renderedHeight = overlaySize.height * parentRes.height;
      final renderedAspectRatio = renderedWidth / renderedHeight;

      final expectedAspectRatio = 1920.0 / 1080.0;
      expect(renderedAspectRatio, closeTo(expectedAspectRatio, 0.001));
    });

    test('Landscape overlay on Landscape base video preserves 16:9 aspect ratio', () {
      // Base video: 1920x1080 (16:9)
      // Overlay video: 1920x1080 landscape
      final parentRes = const Size(1920, 1080);
      final overlaySize = computeOverlaySize(
        parentResolution: parentRes,
        mediaWidth: 1920,
        mediaHeight: 1080,
        rotationCorrection: 0,
      );

      final renderedWidth = overlaySize.width * parentRes.width;
      final renderedHeight = overlaySize.height * parentRes.height;
      final renderedAspectRatio = renderedWidth / renderedHeight;

      final expectedAspectRatio = 1920.0 / 1080.0;
      expect(renderedAspectRatio, closeTo(expectedAspectRatio, 0.001));
    });

    test('Portrait overlay on Square base video preserves 9:16 aspect ratio', () {
      // Base video: 1080x1080 (1:1)
      // Overlay video: 1080x1920 portrait
      final parentRes = const Size(1080, 1080);
      final overlaySize = computeOverlaySize(
        parentResolution: parentRes,
        mediaWidth: 1080,
        mediaHeight: 1920,
        rotationCorrection: 0,
      );

      final renderedWidth = overlaySize.width * parentRes.width;
      final renderedHeight = overlaySize.height * parentRes.height;
      final renderedAspectRatio = renderedWidth / renderedHeight;

      final expectedAspectRatio = 1080.0 / 1920.0;
      expect(renderedAspectRatio, closeTo(expectedAspectRatio, 0.001));
    });
  });

  group('Overlay Volume & Mute Model Tests', () {
    test('VideoClip default volume is 1.0 and isMuted is false', () {
      final clip = VideoClip(
        id: 'overlay-1',
        mediaType: MediaType.video,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 5),
      );

      expect(clip.volume, 1.0);
      expect(clip.isMuted, false);
    });

    test('VideoClip copyWith volume and isMuted updates properly', () {
      final clip = VideoClip(
        id: 'overlay-1',
        mediaType: MediaType.video,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 5),
        volume: 1.0,
      );

      final updatedVolume = clip.copyWith(volume: 1.5);
      expect(updatedVolume.volume, 1.5);
      expect(updatedVolume.isMuted, false);

      final muted = updatedVolume.copyWith(isMuted: true);
      expect(muted.isMuted, true);
      expect(muted.volume, 1.5);
    });
  });
}
