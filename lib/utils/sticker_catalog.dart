import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;

/// One sticker the panel can offer: a bundled asset or one of the user's
/// own images.
class StickerEntry {
  final String path;
  final String label;
  final String category;

  const StickerEntry(this.path, this.label, this.category);

  bool get isAsset => path.startsWith('assets/');
}

/// Bundled stickers (read from the asset manifest, so adding a file to
/// `assets/stickers/` is enough), grouped into categories, plus the user's
/// own stickers and recently used ones.
class StickerCatalog {
  StickerCatalog._();

  static const String recent = 'Recent';
  static const String mine = 'My stickers';
  static const String shapes = 'Shapes';
  static const List<String> categories = [
    recent,
    mine,
    shapes,
    'Logos',
    'Study',
    'Words',
    'Calendar',
    'Animals',
    'Space',
  ];

  /// Byte-identical copies that were removed from the bundle. Projects that
  /// still reference them are drawn with the remaining file.
  static const Map<String, String> _aliases = {
    'assets/stickers/yeah (1).png': 'assets/stickers/yeah.png',
    'assets/stickers/Screenshot_2026-04-01_100153-removebg-preview (1).png':
        'assets/stickers/Screenshot_2026-04-01_100153-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100214-removebg-preview (1).png':
        'assets/stickers/Screenshot_2026-04-01_100214-removebg-preview.png',
  };

  /// The path to load for a stored sticker path.
  static String resolve(String path) => _aliases[path] ?? path;

  // Logo stickers are screenshots; name them by what they show.
  static const Map<String, String> _logoLabels = {
    '100038': 'Sri Sai Ram Engineering College',
    '100047': 'Sairam Engineering College (stacked)',
    '100058': 'Sai Ram Engineering College banner',
    '100108': 'Sairam Institutions',
    '100118': 'Sairam Institutions (dark)',
    '100124': 'Founder Chairman seal',
    '100141': 'Sairam RAISE',
    '100146': 'Sairam EOMS',
    '100153': 'Sairam SDG Action Program',
    '100159': 'Sairam Techno Culture',
    '100208': 'Sairam Techno Incubator',
    '100214': 'Sairam Innovation Eco-system',
    '100221': 'Sairam STEP',
    '100231': 'MyGov',
    '100237': 'Sairam Robotics Club',
    '100248': 'Higher Education Cell',
    '100254': 'Sairam Code Club',
    '100304': 'Youth Red Cross',
    '100327': 'IEEE',
    '100335': 'IEEE Sairam',
    '100350': 'IEEE Computer Society',
    '100400': 'IEEE Computational Intelligence Society',
    '100412': 'IEEE Students',
    '100417': 'IEEE Eta Kappa Nu',
  };

  static const Set<String> _calendar = {
    'january', 'february', 'march', 'april', 'may', 'june', 'july', //
    'august', 'september', 'october', 'november', 'december',
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday',
    'sunday',
  };
  static const Set<String> _animals = {
    'buffalo', 'cheetah', 'cow', 'crocodile', 'flamingo', 'hedgehog', //
    'horse', 'pig', 'sheep',
  };
  static const Set<String> _space = {'comet', 'rocket', 'star'};
  static const Set<String> _study = {
    'book', 'books', 'education', 'graduate', 'mortarboard', //
    'online-class', 'online-education', 'reading', 'study', 'studying',
    'pencil-case', 'drawing-tablet', 'painting-palette', 'creativity',
  };

  /// Category and display label for a bundled sticker path.
  static StickerEntry describe(String assetPath) {
    final file = p.basenameWithoutExtension(assetPath);
    final stamp = RegExp(r'_(\d{6})-removebg').firstMatch(file)?.group(1);
    if (stamp != null) {
      return StickerEntry(
          assetPath, _logoLabels[stamp] ?? 'Logo $stamp', 'Logos');
    }
    // "rocket (2)" -> "rocket"
    final base = file.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
    final label = base
        .split('-')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    final category = _calendar.contains(base)
        ? 'Calendar'
        : _animals.contains(base)
            ? 'Animals'
            : _space.contains(base)
                ? 'Space'
                : _study.contains(base)
                    ? 'Study'
                    : 'Words';
    return StickerEntry(assetPath, label, category);
  }

  static List<StickerEntry>? _bundled;

  /// Every bundled sticker, without duplicates, in a stable order.
  static Future<List<StickerEntry>> bundled() async {
    if (_bundled != null) return _bundled!;
    var paths = <String>[];
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      paths = manifest
          .listAssets()
          .where((a) => a.startsWith('assets/stickers/'))
          .where((a) => !_aliases.containsKey(a))
          .toList()
        ..sort();
    } catch (_) {}
    _bundled = paths.map(describe).toList();
    return _bundled!;
  }

  // ── Recents and the user's own stickers (persisted) ───────────────────

  static const String _boxName = 'editor_prefs';
  static const int _maxRecents = 16;

  static Future<Box> _box() async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);

  static Future<List<String>> recents() async {
    try {
      final box = await _box();
      return List<String>.from(box.get('stickerRecents', defaultValue: []));
    } catch (_) {
      return const [];
    }
  }

  static Future<void> markUsed(String path) async {
    try {
      final box = await _box();
      final list = List<String>.from(box.get('stickerRecents', defaultValue: []))
        ..remove(path)
        ..insert(0, path);
      await box.put('stickerRecents', list.take(_maxRecents).toList());
    } catch (_) {}
  }

  static Future<List<String>> custom() async {
    try {
      final box = await _box();
      return List<String>.from(box.get('stickerCustom', defaultValue: []));
    } catch (_) {
      return const [];
    }
  }

  static Future<void> addCustom(String path) async {
    try {
      final box = await _box();
      final list = List<String>.from(box.get('stickerCustom', defaultValue: []))
        ..remove(path)
        ..insert(0, path);
      await box.put('stickerCustom', list);
    } catch (_) {}
  }

  static Future<void> removeCustom(String path) async {
    try {
      final box = await _box();
      final list = List<String>.from(box.get('stickerCustom', defaultValue: []))
        ..remove(path);
      await box.put('stickerCustom', list);
      final recent =
          List<String>.from(box.get('stickerRecents', defaultValue: []))
            ..remove(path);
      await box.put('stickerRecents', recent);
    } catch (_) {}
  }
}
