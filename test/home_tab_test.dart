import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:studio_v_v2/models/video_project.dart';
import 'package:studio_v_v2/providers/video_editor_provider.dart';
import 'package:studio_v_v2/screens/home/home_prefs.dart';
import 'package:studio_v_v2/screens/home/home_tab.dart';
import 'package:studio_v_v2/screens/home/library_tab.dart';
import 'package:studio_v_v2/screens/home/settings_tab.dart';
import 'package:studio_v_v2/screens/home/templates_tab.dart';

void main() {
  late Directory hiveDir;
  late HomePrefs prefs;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('home_tab_test');
    Hive.init(hiveDir.path);
    prefs = await HomePrefs.load();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  VideoProject project(String id, String name, int clips) => VideoProject(
        id: id,
        name: name,
        outputResolution: const Size(1080, 1920),
        videoClips: [
          for (var i = 0; i < clips; i++)
            VideoClip(
              id: '$id-c$i',
              mediaType: MediaType.image,
              imageFile: File('missing_$i.png'),
              startTime: Duration(seconds: 3 * i),
              endTime: Duration(seconds: 3 * i + 3),
            ),
        ],
      );

  Future<void> pumpHome(
      WidgetTester tester, List<VideoProject> projects) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeTab(
          provider: VideoEditorProvider(),
          prefs: prefs,
          projects: projects,
          onExportProject: (_) async {},
          onSwitchTab: (_) {},
          onRefresh: () async {},
          refreshToken: 0,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1500));
  }

  testWidgets('shows header, quick actions and projects', (tester) async {
    await pumpHome(tester, [
      project('a', 'Untitled V', 3),
      project('b', 'Trip', 2),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('Studio V'), findsOneWidget);
    expect(find.text('New Project'), findsOneWidget);
    expect(find.text('Your Projects'), findsOneWidget);
    expect(find.text('Trip'), findsWidgets);
  });

  testWidgets('list view with large system font lays out cleanly',
      (tester) async {
    await tester.runAsync(() => prefs.setGridView(false));
    addTearDown(() => tester.runAsync(() => prefs.setGridView(true)));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpHome(tester, [
      for (var i = 0; i < 8; i++) project('p$i', 'Project $i', i % 4 + 1),
    ]);
    expect(find.text('Search projects'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('templates tab lays out cleanly', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TemplatesTab(provider: VideoEditorProvider(), prefs: prefs),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });

  testWidgets('library tile opens an enlarged preview with a close button',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibraryTab(provider: VideoEditorProvider(), prefs: prefs),
      ),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 500));

    final firstPhoto = find.byType(Image).first;
    await tester.tap(firstPhoto);
    await tester.pump(const Duration(milliseconds: 400));

    // Preview only: a close button, no selection controls.
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('Select'), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.textContaining('Create project'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final which in ['home', 'editor']) {
    testWidgets('$which theme picker shows swatches and closes',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 850);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => which == 'home'
                    ? showHomeThemePicker(context, prefs)
                    : showEditorThemePicker(context, prefs),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(which == 'home' ? 'Home theme' : 'Editor theme'),
          findsOneWidget);
      expect(find.text(which == 'home' ? 'Sunset' : 'Midnight Blue'),
          findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsNothing);
    });
  }

  testWidgets('shows the empty state without projects', (tester) async {
    await pumpHome(tester, const []);

    expect(tester.takeException(), isNull);
    expect(find.text('Create your first video'), findsWidgets);
  });
}
