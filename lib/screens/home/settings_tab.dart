import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../main.dart' show AppColors;
import '../../theme/editor_themes.dart';
import 'home_models.dart';
import 'home_prefs.dart';
import 'home_storage.dart';
import 'home_widgets.dart';
import 'templates_tab.dart' show HomeTabTitle;

const String kAppVersion = '1.0.0 (1)';

/// Settings: project defaults, appearance, language, storage, about.
class SettingsTab extends StatefulWidget {
  final HomePrefs prefs;
  final VoidCallback onStorageChanged;

  const SettingsTab({
    super.key,
    required this.prefs,
    required this.onStorageChanged,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  StorageUsage? _usage;

  HomePrefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final u = await HomeStorage.usage();
    if (mounted) setState(() => _usage = u);
  }

  Future<void> _pickAspect() async {
    final choice = await showHomeSheet<String>(
      context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        children: [
          const _SheetTitle('Default aspect ratio'),
          for (final a in AspectOption.all)
            ListTile(
              leading: Icon(a.icon, color: kHomeAccent),
              title: Text(a.label, style: const TextStyle(color: Colors.white)),
              subtitle:
                  Text(a.hint, style: const TextStyle(color: Colors.white54)),
              trailing: a.id == prefs.defaultAspect
                  ? const Icon(Icons.check_rounded, color: kHomeAccent)
                  : null,
              onTap: () => Navigator.pop(ctx, a.id),
            ),
        ],
      ),
    );
    if (choice != null) await prefs.setDefaultAspect(choice);
  }

  Future<void> _pickTheme() async {
    const themes = [
      ('mountain', 'Mountain', 'Photo background (default)'),
      ('aurora', 'Aurora', 'Purple and teal gradient'),
      ('amoled', 'AMOLED Black', 'Pure black, saves battery'),
    ];
    final choice = await showHomeSheet<String>(
      context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        children: [
          const _SheetTitle('Home theme'),
          for (final t in themes)
            ListTile(
              leading: const Icon(Icons.palette_outlined, color: kHomeAccent),
              title: Text(t.$2, style: const TextStyle(color: Colors.white)),
              subtitle:
                  Text(t.$3, style: const TextStyle(color: Colors.white54)),
              trailing: t.$1 == prefs.homeTheme
                  ? const Icon(Icons.check_rounded, color: kHomeAccent)
                  : null,
              onTap: () => Navigator.pop(ctx, t.$1),
            ),
        ],
      ),
    );
    if (choice != null) await prefs.setHomeTheme(choice);
  }

  Future<void> _pickLanguage() async {
    const languages = ['English', 'हिन्दी', 'தமிழ்', 'తెలుగు', 'മലയാളം'];
    await showHomeSheet<void>(
      context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        children: [
          const _SheetTitle('Language'),
          for (final l in languages)
            ListTile(
              enabled: l == 'English',
              title: Text(l,
                  style: TextStyle(
                      color: l == 'English' ? Colors.white : Colors.white38)),
              subtitle: l == 'English'
                  ? null
                  : const Text('Coming soon',
                      style: TextStyle(color: Colors.white38)),
              trailing: l == prefs.language
                  ? const Icon(Icons.check_rounded, color: kHomeAccent)
                  : null,
              onTap: () => Navigator.pop(ctx),
            ),
        ],
      ),
    );
  }

  void _showHelp() {
    showHomeSheet<void>(
      context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          const _SheetTitle('Help & Feedback'),
          for (final (q, a) in const [
            (
              'How do I add a transition?',
              'Open a project, tap the small square between two clips on the timeline and pick a transition.'
            ),
            (
              'Why does a "Rendering transition" badge appear?',
              'Transitions are pre-rendered in the background so they play smoothly in the preview. It only takes a few seconds.'
            ),
            (
              'Where are my exported videos?',
              'In the Exports tab. Each export is also saved wherever you chose when exporting.'
            ),
            (
              'How do I free up space?',
              'Settings → Storage → Clear cache. Your projects are not affected.'
            ),
          ])
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              iconColor: kHomeAccent,
              collapsedIconColor: Colors.white54,
              title: Text(q,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(a,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.4)),
                ),
              ],
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              SharePlus.instance.share(ShareParams(
                subject: 'Studio V feedback',
                text: 'Studio V $kAppVersion feedback:\n\n',
              ));
            },
            icon: const Icon(Icons.feedback_outlined),
            label: const Text('Send feedback'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kHomeAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacy() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy'),
        content: const SingleChildScrollView(
          child: Text(
            'Studio V keeps your projects, imported media and exported videos on this device. '
            'Videos are not uploaded anywhere by the app.\n\n'
            'Camera, microphone and storage access are only used to record, import and save '
            'media you choose. Text fonts may be downloaded from Google Fonts.\n\n'
            'Sharing a video hands it to the app you pick in the share sheet.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final aspect = AspectOption.byId(prefs.defaultAspect);
    final themeName = switch (prefs.homeTheme) {
      'amoled' => 'AMOLED Black',
      'aurora' => 'Aurora',
      _ => 'Mountain',
    };
    final u = _usage;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, top + 18, 16, 120),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: HomeTabTitle('Settings', 'Make Studio V work your way.'),
        ),
        const SizedBox(height: 18),
        _Group('Projects', [
          _Tile(
            icon: Icons.aspect_ratio_rounded,
            title: 'Default aspect ratio',
            value: '${aspect.label} · ${aspect.hint}',
            onTap: _pickAspect,
          ),
          SwitchListTile(
            value: prefs.haptics,
            onChanged: prefs.setHaptics,
            activeThumbColor: kHomeAccent,
            secondary: const Icon(Icons.vibration_rounded, color: kHomeAccent),
            title: const Text('Haptic feedback',
                style: TextStyle(color: Colors.white)),
          ),
        ]),
        _Group('Appearance', [
          _Tile(
            icon: Icons.palette_outlined,
            title: 'Home theme',
            value: themeName,
            onTap: _pickTheme,
          ),
          _Tile(
            icon: Icons.dark_mode_outlined,
            title: 'Editor theme',
            value: EditorThemeData.byId(prefs.editorTheme).name,
            onTap: () => showEditorThemePicker(context, prefs),
          ),
          _Tile(
            icon: Icons.language_rounded,
            title: 'Language',
            value: prefs.language,
            onTap: _pickLanguage,
          ),
        ]),
        _Group('Storage', [
          _Tile(
            icon: Icons.sd_storage_outlined,
            title: u == null ? 'Calculating…' : 'Using ${formatBytes(u.total)}',
            value: u == null
                ? null
                : 'Projects ${formatBytes(u.projectMedia)} · Exports ${formatBytes(u.exports)} · Cache ${formatBytes(u.cache)}',
            onTap: () async {
              await showStorageSheet(context, prefs: prefs);
              await _loadUsage();
              widget.onStorageChanged();
            },
          ),
        ]),
        _Group('About', [
          const _Tile(
            icon: Icons.info_outline_rounded,
            title: 'Studio V',
            value: 'Version $kAppVersion · Sairam Institutions',
          ),
          _Tile(
            icon: Icons.help_outline_rounded,
            title: 'Help & Feedback',
            onTap: _showHelp,
          ),
          _Tile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy policy',
            onTap: _showPrivacy,
          ),
          _TipsTile(prefs: prefs),
          _Tile(
            icon: Icons.description_outlined,
            title: 'Open-source licenses',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Studio V',
              applicationVersion: kAppVersion,
            ),
          ),
        ]),
      ],
    );
  }
}

/// Storage breakdown with "Clear cache" and "Delete exports".
Future<void> showStorageSheet(
  BuildContext context, {
  required HomePrefs prefs,
}) {
  return showHomeSheet<void>(
    context,
    builder: (ctx) => _StorageSheet(prefs: prefs),
  );
}

class _StorageSheet extends StatefulWidget {
  final HomePrefs prefs;
  const _StorageSheet({required this.prefs});

  @override
  State<_StorageSheet> createState() => _StorageSheetState();
}

class _StorageSheetState extends State<_StorageSheet> {
  StorageUsage? _u;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = await HomeStorage.usage();
    if (mounted) setState(() => _u = u);
  }

  Future<void> _clearCache() async {
    setState(() => _busy = true);
    final freed = await HomeStorage.clearCache();
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Freed ${formatBytes(freed)}')));
  }

  Future<void> _deleteExports() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all exports?'),
        content: const Text(
            'Exported videos stored in Studio V are removed. Copies you saved to your gallery or shared stay where they are.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final exports = await HomeStorage.exports();
    final freed = await HomeStorage.deleteExports(exports);
    await widget.prefs.forgetExports(exports.map((e) => e.path));
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Freed ${formatBytes(freed)}')));
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    final rows = u == null
        ? const <(String, int, Color)>[]
        : [
            ('Project media', u.projectMedia, const Color(0xFF8B5CF6)),
            ('Exports', u.exports, const Color(0xFF22C55E)),
            ('Render cache', u.renderCache, const Color(0xFFF97316)),
            ('Other cache', u.otherCache, const Color(0xFF06B6D4)),
          ];
    final total = u?.total ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetTitle('Storage'),
          if (u == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child:
                  Center(child: CircularProgressIndicator(color: kHomeAccent)),
            )
          else ...[
            Text(formatBytes(total),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final r in rows)
                      if (r.$2 > 0)
                        Expanded(
                          flex: (r.$2 * 1000 ~/ (total == 0 ? 1 : total))
                              .clamp(1, 1000),
                          child: ColoredBox(color: r.$3),
                        ),
                    if (total == 0)
                      const Expanded(child: ColoredBox(color: Colors.white12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(color: r.$3, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(r.$1,
                            style: const TextStyle(color: Colors.white))),
                    Text(formatBytes(r.$2),
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _busy || u.cache == 0 ? null : _clearCache,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text('Clear cache (${formatBytes(u.cache)})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kHomeAccent,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _busy || u.exports == 0 ? null : _deleteExports,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text('Delete exports (${formatBytes(u.exports)})'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0x66EF4444)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Clearing the cache never touches your projects; transition previews are rebuilt automatically when needed.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Group(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: kHomeAccent,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ),
          GlassPanel(
            color: Colors.black.withValues(alpha: 0.35),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: kHomeAccent),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: value == null
          ? null
          : Text(value!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: onTap,
    );
  }
}

/// "Tips & tricks": expands in place to show every tip right here in
/// Settings, with an inline switch to bring dismissed tips back to Home.
class _TipsTile extends StatefulWidget {
  final HomePrefs prefs;
  const _TipsTile({required this.prefs});

  @override
  State<_TipsTile> createState() => _TipsTileState();
}

class _TipsTileState extends State<_TipsTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final prefs = widget.prefs;
    final dismissed = prefs.dismissedTips;
    final allOnHome = HomeTip.all.every((t) => !dismissed.contains(t.id));

    return Column(
      children: [
        ListTile(
          leading:
              const Icon(Icons.lightbulb_outline_rounded, color: kHomeAccent),
          title: const Text('Tips & tricks',
              style: TextStyle(color: Colors.white)),
          subtitle: Text(
            '${HomeTip.all.length} tips',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          trailing: AnimatedRotation(
            turns: _expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child:
                const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ),
          onTap: () {
            homeHaptic(prefs);
            setState(() => _expanded = !_expanded);
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Column(
                    children: [
                      for (final t in HomeTip.all)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: t.color.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(t.icon, color: t.color, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.title,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 3),
                                    Text(
                                      t.body,
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                          fontSize: 12.5,
                                          height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        value: allOnHome,
                        activeThumbColor: kHomeAccent,
                        title: const Text('Show tips on Home',
                            style: TextStyle(color: Colors.white)),
                        subtitle: Text(
                          allOnHome
                              ? 'All tips appear on the Home tab'
                              : '${dismissed.length} dismissed',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6)),
                        ),
                        onChanged: (on) async {
                          homeHaptic(prefs);
                          if (on) {
                            await prefs.resetTips();
                          } else {
                            for (final t in HomeTip.all) {
                              await prefs.dismissTip(t.id);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Editor theme picker: each option is a miniature of the editor (preview,
/// timeline and toolbar) drawn in that theme's colours. Picking one applies
/// it to the whole app immediately.
Future<void> showEditorThemePicker(BuildContext context, HomePrefs prefs) {
  return showHomeSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          const _SheetTitle('Editor theme'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
            children: [
              for (final t in EditorThemeData.all)
                _ThemeSwatch(
                  theme: t,
                  selected: t.id == prefs.editorTheme,
                  onTap: () async {
                    homeHaptic(prefs);
                    AppColors.apply(t);
                    await prefs.setEditorTheme(t.id);
                    setSheet(() {});
                  },
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ThemeSwatch extends StatelessWidget {
  final EditorThemeData theme;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    Widget bar(double w, Color c) => Container(
          width: w,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? t.primary : Colors.white.withValues(alpha: 0.1),
            width: selected ? 2.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ColoredBox(
            color: t.background,
            child: Column(
              children: [
                // Mini preview area
                Expanded(
                  flex: 5,
                  child: Center(
                    child: Container(
                      width: 46,
                      height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          colors: [t.primaryDark, t.primaryLight],
                        ),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
                // Mini timeline
                Expanded(
                  flex: 4,
                  child: Container(
                    width: double.infinity,
                    color: t.surface,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Row(children: [
                          bar(40, t.primary),
                          const SizedBox(width: 3),
                          bar(28, t.primary.withValues(alpha: 0.7)),
                        ]),
                        bar(52, t.audioTrack),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var i = 0; i < 4; i++)
                              Container(
                                width: 16,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: i == 0
                                      ? t.primary.withValues(alpha: 0.25)
                                      : t.surfaceLight,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                      color: i == 0 ? t.primary : t.border),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  color: t.surfaceLight,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_circle_rounded,
                            color: t.primary, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
