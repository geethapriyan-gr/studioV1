import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:studio_v_v2/screens/home/home_storage.dart';

/// Separate documents and cache folders, as on a phone.
class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.docs, this.cache);
  final String docs;
  final String cache;
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
  @override
  Future<String?> getApplicationSupportPath() async => docs;
  @override
  Future<String?> getTemporaryPath() async => cache;
}

void main() {
  late Directory docs;
  late Directory cache;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('sv_docs');
    cache = await Directory.systemTemp.createTemp('sv_cache');
    PathProviderPlatform.instance = _FakePathProvider(docs.path, cache.path);
  });

  tearDown(() async {
    await docs.delete(recursive: true);
    await cache.delete(recursive: true);
  });

  test('new exports go to permanent storage, not the cache', () async {
    final path = await HomeStorage.newExportPath();
    expect(path.startsWith(docs.path), isTrue);
    expect(path.startsWith(cache.path), isFalse);
    expect(path, contains('edited_video_'));
  });

  test('exports left in the cache are moved and survive a cache wipe',
      () async {
    final old = File('${cache.path}${Platform.pathSeparator}edited_video_1000.mp4')
      ..writeAsBytesSync(List.filled(10, 1));
    final when = DateTime(2026, 10, 1, 12);
    old.setLastModifiedSync(when);

    final moved = await HomeStorage.migrateExports();
    expect(moved.keys.single, old.path);
    expect(old.existsSync(), isFalse);

    // The system empties the cache folder: the export is still listed.
    await for (final e in cache.list()) {
      await e.delete(recursive: true);
    }
    final list = await HomeStorage.exports();
    expect(list.single.path, moved.values.single);
    expect(list.single.created, when); // date kept for ordering

    // Counted as exports, not as project media; clearing cache keeps it.
    final usage = await HomeStorage.usage();
    expect(usage.exports, 10);
    expect(usage.projectMedia, 0);
    await HomeStorage.clearCache();
    expect((await HomeStorage.exports()).length, 1);
  });
}
