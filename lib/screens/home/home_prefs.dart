import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Home-screen preferences and bookkeeping (view mode, folders, exports,
/// dismissed tips, settings). Kept in its own Hive box so project data and
/// the editor are never touched.
class HomePrefs extends ChangeNotifier {
  HomePrefs._(this._box);

  static const String _boxName = 'home_prefs';
  static HomePrefs? _instance;

  static Future<HomePrefs> load() async {
    if (_instance != null) return _instance!;
    final box = await Hive.openBox(_boxName);
    _instance = HomePrefs._(box);
    return _instance!;
  }

  final Box _box;

  T _get<T>(String key, T fallback) {
    final value = _box.get(key);
    return value is T ? value : fallback;
  }

  Future<void> _put(String key, Object? value) async {
    await _box.put(key, value);
    notifyListeners();
  }

  // ── Project list ───────────────────────────────────────────────────────
  bool get gridView => _get<bool>('gridView', true);
  Future<void> setGridView(bool v) => _put('gridView', v);

  /// 'recent' | 'oldest' | 'name' | 'longest'
  String get sortMode => _get<String>('sortMode', 'recent');
  Future<void> setSortMode(String v) => _put('sortMode', v);

  // ── Folders ────────────────────────────────────────────────────────────
  List<String> get folders =>
      List<String>.from(_get<List>('folders', const []));

  Future<void> addFolder(String name) async {
    final list = folders;
    if (!list.contains(name)) list.add(name);
    await _put('folders', list);
  }

  Future<void> removeFolder(String name) async {
    final list = folders..remove(name);
    final map = _projectFolders..removeWhere((_, f) => f == name);
    await _box.put('projectFolders', map);
    await _put('folders', list);
  }

  Map<String, String> get _projectFolders =>
      Map<String, String>.from(_get<Map>('projectFolders', const {}));

  String? folderOf(String projectId) => _projectFolders[projectId];

  Future<void> setFolder(String projectId, String? folder) async {
    final map = _projectFolders;
    if (folder == null) {
      map.remove(projectId);
    } else {
      map[projectId] = folder;
    }
    await _put('projectFolders', map);
  }

  // ── Exports ────────────────────────────────────────────────────────────
  Map<String, List<String>> get _exports {
    final raw = _get<Map>('exports', const {});
    return raw.map((k, v) => MapEntry(k as String, List<String>.from(v)));
  }

  List<String> exportsOf(String projectId) => _exports[projectId] ?? const [];
  bool isExported(String projectId) => exportsOf(projectId).isNotEmpty;

  /// projectId of an exported file, when known.
  String? projectOfExport(String path) {
    for (final e in _exports.entries) {
      if (e.value.contains(path)) return e.key;
    }
    return null;
  }

  Future<void> addExports(String projectId, List<String> paths) async {
    if (paths.isEmpty) return;
    final map = _exports;
    final list = map[projectId] ?? <String>[];
    for (final p in paths) {
      if (!list.contains(p)) list.add(p);
    }
    map[projectId] = list;
    await _put('exports', map);
  }

  Future<void> forgetExports(Iterable<String> paths) async {
    final set = paths.toSet();
    final map = _exports;
    for (final key in map.keys.toList()) {
      map[key] = map[key]!.where((p) => !set.contains(p)).toList();
      if (map[key]!.isEmpty) map.remove(key);
    }
    await _put('exports', map);
  }

  Future<void> forgetProject(String projectId) async {
    final exports = _exports..remove(projectId);
    final folders = _projectFolders..remove(projectId);
    await _box.put('exports', exports);
    await _box.put('projectFolders', folders);
    if (lastOpenedId == projectId) await _box.delete('lastOpenedId');
    notifyListeners();
  }

  // ── Continue editing / export attribution ─────────────────────────────
  String? get lastOpenedId => _box.get('lastOpenedId') as String?;
  int get lastOpenedAtMs => _get<int>('lastOpenedAtMs', 0);

  Future<void> markOpened(String projectId) async {
    await _box.put('lastOpenedId', projectId);
    await _put('lastOpenedAtMs', DateTime.now().millisecondsSinceEpoch);
  }

  // ── Tips ───────────────────────────────────────────────────────────────
  Set<String> get dismissedTips =>
      Set<String>.from(_get<List>('dismissedTips', const []));

  Future<void> dismissTip(String id) async {
    final set = dismissedTips..add(id);
    await _put('dismissedTips', set.toList());
  }

  Future<void> resetTips() => _put('dismissedTips', <String>[]);

  // ── Settings ───────────────────────────────────────────────────────────
  /// 'mountain' | 'amoled' | 'aurora'
  String get homeTheme => _get<String>('homeTheme', 'mountain');
  Future<void> setHomeTheme(String v) => _put('homeTheme', v);

  /// Aspect option id used to preselect new projects ('9:16', '16:9', ...).
  String get defaultAspect => _get<String>('defaultAspect', '9:16');
  Future<void> setDefaultAspect(String v) => _put('defaultAspect', v);

  String get language => _get<String>('language', 'English');
  Future<void> setLanguage(String v) => _put('language', v);

  bool get haptics => _get<bool>('haptics', true);
  Future<void> setHaptics(bool v) => _put('haptics', v);
}
