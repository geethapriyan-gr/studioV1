import 'package:flutter/material.dart';

import '../../models/transition.dart';
import '../../models/video_project.dart';

/// Output shapes offered when creating a project.
class AspectOption {
  final String id;
  final String label;
  final String hint;
  final Size resolution;
  final IconData icon;

  const AspectOption(
      this.id, this.label, this.hint, this.resolution, this.icon);

  static const List<AspectOption> all = [
    AspectOption('9:16', '9:16', 'Reels · Shorts · TikTok', Size(1080, 1920),
        Icons.stay_current_portrait_rounded),
    AspectOption('16:9', '16:9', 'YouTube · Landscape', Size(1920, 1080),
        Icons.stay_current_landscape_rounded),
    AspectOption('1:1', '1:1', 'Instagram post', Size(1080, 1080),
        Icons.crop_square_rounded),
    AspectOption('4:5', '4:5', 'Instagram feed', Size(1080, 1350),
        Icons.crop_portrait_rounded),
    AspectOption('original', 'Original', 'Match the first clip', Size.zero,
        Icons.aspect_ratio_rounded),
  ];

  static AspectOption byId(String id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);
}

/// A ready-made project recipe: an output shape, a transition between every
/// clip, an optional title and background music, and sample media from the
/// bundled library that the user can swap for their own.
class HomeTemplate {
  final String id;
  final String name;
  final String description;
  final String title;
  final String aspectId;
  final TransitionType transition;
  final Duration transitionDuration;
  final bool music;
  final List<String> sampleAssets;
  final List<Color> colors;
  final IconData icon;
  final bool imagesOnly;

  const HomeTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.title,
    required this.aspectId,
    required this.transition,
    this.transitionDuration = const Duration(milliseconds: 600),
    this.music = true,
    this.sampleAssets = const [],
    required this.colors,
    required this.icon,
    this.imagesOnly = false,
  });

  String get transitionName => Transition(
        id: '',
        clipId1: '',
        clipId2: '',
        startTime: Duration.zero,
        type: transition,
      ).getDisplayName();

  static const List<HomeTemplate> all = [
    HomeTemplate(
      id: 'class_recap',
      name: 'Class Recap',
      description: 'Sum up a lesson with smooth crossfades and a title card.',
      title: 'Class Recap',
      aspectId: '16:9',
      transition: TransitionType.crossfade,
      sampleAssets: [
        'assets/video-library/Studying.mp4',
        'assets/image-library/Modern SDG 4 Quality.png',
        'assets/video-library/Playing.mp4',
      ],
      colors: [Color(0xFF6D28D9), Color(0xFF2563EB)],
      icon: Icons.school_rounded,
    ),
    HomeTemplate(
      id: 'event_highlights',
      name: 'Event Highlights',
      description: 'Fast, punchy vertical highlights with zoom cuts.',
      title: 'Event Highlights',
      aspectId: '9:16',
      transition: TransitionType.zoom,
      transitionDuration: Duration(milliseconds: 450),
      sampleAssets: [
        'assets/video-library/Playing.mp4',
        'assets/video-library/Healthy-Food.mp4',
        'assets/video-library/Drinking .mp4',
      ],
      colors: [Color(0xFFDB2777), Color(0xFFF97316)],
      icon: Icons.celebration_rounded,
    ),
    HomeTemplate(
      id: 'sdg_awareness',
      name: 'SDG Awareness',
      description: 'Share the Sustainable Development Goals, one goal a slide.',
      title: 'Sustainable Development Goals',
      aspectId: '1:1',
      transition: TransitionType.circle,
      sampleAssets: [
        'assets/image-library/Full SDG poster with.png',
        'assets/image-library/Modern SDG 3 Good He.png',
        'assets/image-library/Modern SDG 4 Quality.png',
        'assets/image-library/Modern SDG 6 Afforda.png',
        'assets/image-library/Modern SDG 13 Climat.png',
        'assets/image-library/Modern SDG 14 Life B.png',
      ],
      colors: [Color(0xFF059669), Color(0xFF0891B2)],
      icon: Icons.public_rounded,
      imagesOnly: true,
    ),
    HomeTemplate(
      id: 'travel_vlog',
      name: 'Travel Vlog',
      description: 'Swipe through your trip with horizontal slide cuts.',
      title: 'My Trip',
      aspectId: '9:16',
      transition: TransitionType.horizontal,
      sampleAssets: [
        'assets/video-library/Healthy-Food.mp4',
        'assets/video-library/Playing.mp4',
      ],
      colors: [Color(0xFF0EA5E9), Color(0xFF22C55E)],
      icon: Icons.flight_takeoff_rounded,
    ),
    HomeTemplate(
      id: 'photo_memories',
      name: 'Photo Memories',
      description: 'A gentle photo slideshow with music and fades to white.',
      title: 'Memories',
      aspectId: '16:9',
      transition: TransitionType.white,
      transitionDuration: Duration(milliseconds: 800),
      sampleAssets: [
        'assets/image-library/0bb9b1683c1110041607bf2909f66957.jpg',
        'assets/image-library/232b7b8ede330a2c09cd0594b59c2044.jpg',
        'assets/image-library/55a69e7b6586595d356252d623157b44.jpg',
        'assets/image-library/811e5a915055c8a4165e3e60f8a494aa.jpg',
      ],
      colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
      icon: Icons.photo_library_rounded,
      imagesOnly: true,
    ),
    HomeTemplate(
      id: 'quick_promo',
      name: 'Quick Promo',
      description: 'Glitchy pixelate cuts for an energetic promo.',
      title: 'Coming Soon',
      aspectId: '9:16',
      transition: TransitionType.pixelate,
      transitionDuration: Duration(milliseconds: 400),
      sampleAssets: [
        'assets/video-library/Cleaning.mp4',
        'assets/video-library/Studying.mp4',
        'assets/video-library/Playing.mp4',
      ],
      colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
      icon: Icons.bolt_rounded,
    ),
  ];
}

/// Dismissible feature-discovery tips shown on the home tab.
class HomeTip {
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final Color color;

  const HomeTip(this.id, this.title, this.body, this.icon, this.color);

  static const List<HomeTip> all = [
    HomeTip(
        'pixelate',
        'Try the pixelate transition',
        'Open Transitions between two clips and pick Pixelate for a retro glitch cut.',
        Icons.grid_on_rounded,
        Color(0xFF8B5CF6)),
    HomeTip(
        'chroma',
        'Green screen in one tap',
        'Chroma Key removes a green background and puts any image behind you.',
        Icons.auto_fix_high_rounded,
        Color(0xFF22C55E)),
    HomeTip(
        'templates',
        'Start from a template',
        'Templates add transitions, a title and music to your clips automatically.',
        Icons.dashboard_customize_rounded,
        Color(0xFFF97316)),
    HomeTip(
        'longpress',
        'Hold a project for more',
        'Long-press any project to preview it, duplicate, rename, share or move it.',
        Icons.touch_app_rounded,
        Color(0xFF06B6D4)),
  ];
}

// ── Formatting helpers ─────────────────────────────────────────────────────

const _genericNames = {'untitled v', 'new project', 'untitled', ''};

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

String clockTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// Suggested name for a brand-new project, e.g. "Sep 30 · 1:42 PM".
String autoProjectName([DateTime? at]) {
  final d = at ?? DateTime.now();
  return '${shortDate(d)} · ${clockTime(d)}';
}

/// Card title: generic names ("Untitled V") are replaced by "Sep 30 · 3 clips"
/// so projects can be told apart without renaming them.
String displayName(VideoProject p) {
  if (!_genericNames.contains(p.name.trim().toLowerCase())) return p.name;
  final n = p.videoClips.length;
  return '${shortDate(p.createdAt)} · $n clip${n == 1 ? '' : 's'}';
}

String relativeTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return shortDate(d);
}

/// Real project length (the stored `totalDuration` can lag behind edits).
Duration projectLength(VideoProject p) => p.calculateTotalDuration();

String formatLength(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String aspectBadge(Size r) {
  if (r.width <= 0 || r.height <= 0) return '—';
  final ratio = r.width / r.height;
  const known = {
    '9:16': 9 / 16,
    '16:9': 16 / 9,
    '1:1': 1.0,
    '4:5': 4 / 5,
    '4:3': 4 / 3,
    '3:4': 3 / 4,
  };
  for (final e in known.entries) {
    if ((ratio - e.value).abs() < 0.02) return e.key;
  }
  return ratio > 1 ? 'Wide' : 'Tall';
}

String resolutionBadge(Size r) {
  final shortSide = r.width < r.height ? r.width : r.height;
  if (shortSide >= 2160) return '4K';
  if (shortSide >= 1440) return '1440p';
  if (shortSide >= 1080) return '1080p';
  if (shortSide >= 720) return '720p';
  if (shortSide > 0) return '${shortSide.round()}p';
  return '';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[i]}';
}

/// Home screen background themes. 'mountain' is the photo backdrop and
/// 'amoled' plain black; the rest are gradients with a soft accent glow.
class HomeThemeOption {
  final String id;
  final String name;
  final String description;
  final List<Color> colors;
  final Color glow;

  const HomeThemeOption(
      this.id, this.name, this.description, this.colors, this.glow);

  bool get isPhoto => id == 'mountain';

  static const List<HomeThemeOption> all = [
    HomeThemeOption('mountain', 'Mountain', 'Photo background (default)',
        [Color(0xFF3B2A4A), Color(0xFF8A5A6B)], Color(0xFFE0A07A)),
    HomeThemeOption(
        'aurora',
        'Aurora',
        'Purple and teal',
        [Color(0xFF1E0B3A), Color(0xFF0B1E3A), Color(0xFF062A2A)],
        Color(0xFF2DD4BF)),
    HomeThemeOption('amoled', 'AMOLED Black', 'Pure black, saves battery',
        [Color(0xFF000000), Color(0xFF000000)], Color(0xFF8B5CF6)),
    HomeThemeOption(
        'sunset',
        'Sunset',
        'Warm plum to amber',
        [Color(0xFF2A0F2E), Color(0xFF6B1F3A), Color(0xFFB8452F)],
        Color(0xFFFBBF24)),
    HomeThemeOption(
        'ocean',
        'Ocean',
        'Deep sea blues',
        [Color(0xFF021B2E), Color(0xFF043B5C), Color(0xFF0B6E7A)],
        Color(0xFF38BDF8)),
    HomeThemeOption(
        'forest',
        'Forest',
        'Pine and moss greens',
        [Color(0xFF06140C), Color(0xFF0F2E1B), Color(0xFF1F4A2C)],
        Color(0xFF4ADE80)),
    HomeThemeOption(
        'midnight',
        'Midnight',
        'Indigo night sky',
        [Color(0xFF0B1026), Color(0xFF1A1F4D), Color(0xFF2A1E5C)],
        Color(0xFF818CF8)),
    HomeThemeOption(
        'rose',
        'Rose',
        'Berry and blush',
        [Color(0xFF1C0A14), Color(0xFF4A1530), Color(0xFF7A2848)],
        Color(0xFFF472B6)),
    HomeThemeOption(
        'ember',
        'Ember',
        'Charcoal with a fire glow',
        [Color(0xFF120C08), Color(0xFF2C1A10), Color(0xFF5A2A10)],
        Color(0xFFF97316)),
    HomeThemeOption(
        'graphite',
        'Graphite',
        'Neutral greys',
        [Color(0xFF151517), Color(0xFF26262B), Color(0xFF3A3A40)],
        Color(0xFFA1A1AA)),
  ];

  static HomeThemeOption byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}
