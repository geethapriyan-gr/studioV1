import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:studio_v_v2/providers/video_editor_provider.dart';
import 'package:studio_v_v2/widgets/clip_toolbar.dart';

void main() {
  testWidgets('clip toolbar lays out at phone width with large text',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final clip = VideoClip(
      id: 'c1',
      mediaType: MediaType.video,
      videoFile: File('clip.mp4'),
      startTime: Duration.zero,
      endTime: const Duration(seconds: 4),
      playbackSpeed: 1.5,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar:
            ClipToolbar(provider: VideoEditorProvider(), clip: clip),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Effects'), findsOneWidget);
    expect(find.text('1.5x'), findsOneWidget); // speed badge
  });
}
