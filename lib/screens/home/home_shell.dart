import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../providers/video_editor_provider.dart';
import 'exports_tab.dart';
import 'home_actions.dart';
import 'home_models.dart' show HomeThemeOption;
import 'home_prefs.dart';
import 'home_storage.dart';
import 'home_tab.dart';
import 'home_widgets.dart';
import 'library_tab.dart';
import 'new_project_sheet.dart';
import 'settings_tab.dart';
import 'templates_tab.dart';

/// The home screen shown when no project is open: Home, Templates, Library,
/// Exports and Settings behind a bottom navigation bar.
///
/// [onExportProject] opens a project and runs the editor's own export flow;
/// the editor, preview and export code are not changed by the home screen.
class HomeShell extends StatefulWidget {
  final VideoEditorProvider provider;
  final Future<void> Function(String projectId) onExportProject;

  const HomeShell({
    super.key,
    required this.provider,
    required this.onExportProject,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  HomePrefs? _prefs;
  int _tab = 0;
  int _refreshToken = 0;
  bool _fabOpen = false;
  // Tabs are built the first time they are opened, then kept alive.
  final Set<int> _visited = {0};

  VideoEditorProvider get provider => widget.provider;

  @override
  void initState() {
    super.initState();
    HomePrefs.load().then((prefs) async {
      if (!mounted) return;
      setState(() => _prefs = prefs);
      await _attributeNewExports(prefs);
    });
  }

  /// Exports made since the last project was opened belong to that project
  /// (only one project can be open between two visits to the home screen).
  Future<void> _attributeNewExports(HomePrefs prefs) async {
    final projectId = prefs.lastOpenedId;
    final since = prefs.lastOpenedAtMs;
    if (projectId == null || since == 0) return;
    final exports = await HomeStorage.exports();
    final fresh = exports
        .where((e) =>
            e.created.millisecondsSinceEpoch >= since &&
            prefs.projectOfExport(e.path) == null)
        .map((e) => e.path)
        .toList();
    await prefs.addExports(projectId, fresh);
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _refreshToken++);
  }

  Future<void> _export(String projectId) async {
    await _prefs?.markOpened(projectId);
    await widget.onExportProject(projectId);
  }

  void _switchTab(int tab) {
    if (tab == _tab) return;
    homeHaptic(_prefs);
    setState(() {
      _tab = tab;
      _visited.add(tab);
      _fabOpen = false;
    });
  }

  // ── Speed-dial actions ────────────────────────────────────────────────

  Future<void> _fab(Future<void> Function() action) async {
    setState(() => _fabOpen = false);
    homeHaptic(_prefs);
    await action();
  }

  Future<void> _fabNew() =>
      startNewProject(context, provider: provider, prefs: _prefs!);

  Future<void> _fabRecord() async {
    final clip = await HomeActions.recordVideo(context);
    if (clip == null || !mounted) return;
    await startNewProject(context,
        provider: provider, prefs: _prefs!, media: [clip]);
  }

  Future<void> _fabImport() async {
    final media = await HomeActions.pickFromGallery();
    if (media.isEmpty || !mounted) return;
    await startNewProject(context,
        provider: provider, prefs: _prefs!, media: media);
  }

  Future<void> _fabSlideshow() async {
    final photos = await HomeActions.pickFromGallery(imagesOnly: true);
    if (photos.isEmpty || !mounted) return;
    await startNewProject(context,
        provider: provider,
        prefs: _prefs!,
        template: kSlideshowRecipe,
        media: photos);
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    if (prefs == null) {
      return const Center(child: CircularProgressIndicator(color: kHomeAccent));
    }
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) {
        final projects = provider.getSavedProjects();
        return Stack(
          children: [
            Positioned.fill(child: _ThemeBackdrop(theme: prefs.homeTheme)),
            Positioned.fill(
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: _AnimatedTabStack(
                  index: _tab,
                  children: [
                    HomeTab(
                      provider: provider,
                      prefs: prefs,
                      projects: projects,
                      onExportProject: _export,
                      onSwitchTab: _switchTab,
                      onRefresh: _refresh,
                      refreshToken: _refreshToken,
                    ),
                    if (_visited.contains(1))
                      TemplatesTab(provider: provider, prefs: prefs)
                    else
                      const SizedBox.shrink(),
                    if (_visited.contains(2))
                      LibraryTab(provider: provider, prefs: prefs)
                    else
                      const SizedBox.shrink(),
                    if (!_visited.contains(3))
                      const SizedBox.shrink()
                    else
                      ExportsTab(
                        prefs: prefs,
                        projects: projects,
                        onExportProject: _export,
                        refreshToken: _refreshToken,
                      ),
                    if (_visited.contains(4))
                      SettingsTab(prefs: prefs, onStorageChanged: _refresh)
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
            if (_fabOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _fabOpen = false),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child:
                        Container(color: Colors.black.withValues(alpha: 0.45)),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildNavBar(),
            ),
            if (_tab == 0) _buildSpeedDial(),
          ],
        );
      },
    );
  }

  Widget _buildNavBar() {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (
        Icons.dashboard_customize_outlined,
        Icons.dashboard_customize_rounded,
        'Templates'
      ),
      (Icons.photo_library_outlined, Icons.photo_library_rounded, 'Library'),
      (Icons.movie_filter_outlined, Icons.movie_filter_rounded, 'Exports'),
      (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
    ];
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.only(bottom: bottom, top: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF111114).withValues(alpha: 0.78),
            border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => _switchTab(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: _tab == i
                                  ? kHomeAccent.withValues(alpha: 0.22)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _tab == i ? items[i].$2 : items[i].$1,
                              color: _tab == i ? kHomeAccent : Colors.white60,
                              size: 23,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            items[i].$3,
                            style: TextStyle(
                              color: _tab == i ? Colors.white : Colors.white54,
                              fontSize: 10.5,
                              fontWeight:
                                  _tab == i ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedDial() {
    final bottom = MediaQuery.of(context).padding.bottom + 78;
    final actions = [
      (
        'Template',
        Icons.dashboard_customize_rounded,
        () async => _switchTab(1)
      ),
      ('Slideshow', Icons.slideshow_rounded, _fabSlideshow),
      ('Import', Icons.photo_library_rounded, _fabImport),
      ('Record', Icons.videocam_rounded, _fabRecord),
      ('New project', Icons.movie_creation_rounded, _fabNew),
    ];
    return Positioned(
      right: 20,
      bottom: bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < actions.length; i++)
            _SpeedDialItem(
              visible: _fabOpen,
              delay: (actions.length - 1 - i) * 35,
              label: actions[i].$1,
              icon: actions[i].$2,
              onTap: () => _fab(actions[i].$3),
            ),
          const SizedBox(height: 4),
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kHomeAccent.withValues(alpha: 0.45),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SizedBox(
              width: 64,
              height: 64,
              child: ElevatedButton(
                onPressed: () {
                  homeHaptic(_prefs);
                  setState(() => _fabOpen = !_fabOpen);
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  backgroundColor: kHomeAccent,
                  foregroundColor: Colors.black,
                  elevation: 0,
                ),
                child: AnimatedRotation(
                  turns: _fabOpen ? 0.125 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(Icons.add_rounded, size: 34),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedDialItem extends StatelessWidget {
  final bool visible;
  final int delay;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SpeedDialItem({
    required this.visible,
    required this.delay,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Duration(milliseconds: 160 + delay),
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.4),
          duration: Duration(milliseconds: 200 + delay),
          curve: Curves.easeOutBack,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12, right: 6),
            child: GestureDetector(
              onTap: onTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(label,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    child: Icon(icon, color: const Color(0xFF7C3AED)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeBackdrop extends StatelessWidget {
  final String theme;
  const _ThemeBackdrop({required this.theme});

  @override
  Widget build(BuildContext context) {
    final option = HomeThemeOption.byId(theme);
    switch (theme) {
      case 'amoled':
        return const ColoredBox(color: Colors.black);
      case 'mountain':
        break;
      default:
        // Gradient theme with a soft accent glow near the top.
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: option.colors,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.7, -0.8),
                radius: 1.1,
                colors: [
                  option.glow.withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        );
    }
    {
      // The mountain photo is already drawn behind the screen; add a soft
      // gradient so text stays readable.
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.05),
              Colors.black.withValues(alpha: 0.30),
            ],
          ),
        ),
      );
    }
  }
}

/// Like an [IndexedStack] (every opened tab keeps its state and scroll
/// position) but switching tabs cross-fades with a slight slide in the
/// direction of travel instead of cutting abruptly.
class _AnimatedTabStack extends StatelessWidget {
  final int index;
  final List<Widget> children;

  const _AnimatedTabStack({required this.index, required this.children});

  static const _duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++) _buildPage(i, children[i]),
      ],
    );
  }

  Widget _buildPage(int i, Widget child) {
    final active = i == index;
    // Pages left of the current tab rest slightly to the left, pages to the
    // right slightly to the right, so the new tab slides in from its side.
    final dx = active ? 0.0 : (i < index ? -0.05 : 0.05);
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: AnimatedSlide(
          offset: Offset(dx, 0),
          duration: _duration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: _duration,
            curve: Curves.easeOut,
            // Hidden tabs stop their animations, like IndexedStack.
            child: TickerMode(enabled: active, child: child),
          ),
        ),
      ),
    );
  }
}
