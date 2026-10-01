import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/video_project.dart';
import '../../providers/video_editor_provider.dart';
import '../../services/video_thumbnail_service.dart';
import 'home_actions.dart';
import 'home_models.dart';
import 'home_prefs.dart';
import 'home_storage.dart';
import 'home_widgets.dart';
import 'new_project_sheet.dart';
import 'project_card.dart';
import 'settings_tab.dart';

/// Home tab: quick create, continue editing, tips and the project library.
class HomeTab extends StatefulWidget {
  final VideoEditorProvider provider;
  final HomePrefs prefs;
  final List<VideoProject> projects;
  final Future<void> Function(String projectId) onExportProject;
  final void Function(int tab) onSwitchTab;
  final Future<void> Function() onRefresh;
  final int refreshToken;

  const HomeTab({
    super.key,
    required this.provider,
    required this.prefs,
    required this.projects,
    required this.onExportProject,
    required this.onSwitchTab,
    required this.onRefresh,
    required this.refreshToken,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _searchController = TextEditingController();
  String _query = '';
  String _filter = 'all'; // all | drafts | exported | folder:<name>
  bool _animateEntries = true;
  StorageUsage? _usage;
  final _tipsController = PageController(viewportFraction: 0.92);

  HomePrefs get prefs => widget.prefs;
  VideoEditorProvider get provider => widget.provider;

  @override
  void initState() {
    super.initState();
    _loadUsage();
    // Stagger only the first appearance, not every rebuild.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _animateEntries = false);
    });
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadUsage();
  }

  Future<void> _loadUsage() async {
    final u = await HomeStorage.usage();
    if (mounted) setState(() => _usage = u);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tipsController.dispose();
    super.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────────────

  List<VideoProject> get _visibleProjects {
    var list = widget.projects.where((p) {
      if (_filter == 'drafts' && prefs.isExported(p.id)) return false;
      if (_filter == 'exported' && !prefs.isExported(p.id)) return false;
      if (_filter.startsWith('folder:') &&
          prefs.folderOf(p.id) != _filter.substring(7)) {
        return false;
      }
      if (_query.isNotEmpty &&
          !displayName(p).toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    switch (prefs.sortMode) {
      case 'oldest':
        list.sort((a, b) => a.lastModified.compareTo(b.lastModified));
        break;
      case 'name':
        list.sort((a, b) => displayName(a)
            .toLowerCase()
            .compareTo(displayName(b).toLowerCase()));
        break;
      case 'longest':
        list.sort((a, b) => projectLength(b).compareTo(projectLength(a)));
        break;
      default:
        list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    }
    return list;
  }

  VideoProject? get _continueProject {
    if (widget.projects.isEmpty) return null;
    final id = prefs.lastOpenedId;
    for (final p in widget.projects) {
      if (p.id == id) return p;
    }
    return widget.projects
        .reduce((a, b) => a.lastModified.isAfter(b.lastModified) ? a : b);
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _open(VideoProject p) async {
    homeHaptic(prefs);
    await HomeActions.openProject(provider, prefs, p.id);
  }

  Future<void> _newProject() =>
      startNewProject(context, provider: provider, prefs: prefs);

  Future<void> _record() async {
    final clip = await HomeActions.recordVideo(context);
    if (clip == null || !mounted) return;
    await startNewProject(context,
        provider: provider, prefs: prefs, media: [clip]);
  }

  Future<void> _import() async {
    final media = await HomeActions.pickFromGallery();
    if (media.isEmpty || !mounted) return;
    await startNewProject(context,
        provider: provider, prefs: prefs, media: media);
  }

  Future<void> _slideshow() async {
    final photos = await HomeActions.pickFromGallery(imagesOnly: true);
    if (photos.isEmpty || !mounted) return;
    await startNewProject(context,
        provider: provider,
        prefs: prefs,
        template: kSlideshowRecipe,
        media: photos);
  }

  Future<void> _menu(VideoProject p) async {
    final action = await showProjectMenu(context, project: p, prefs: prefs);
    if (action == null || !mounted) return;
    switch (action) {
      case ProjectMenuAction.open:
        await _open(p);
        break;
      case ProjectMenuAction.duplicate:
        final copy = await HomeActions.duplicate(p);
        final folder = prefs.folderOf(p.id);
        if (folder != null) await prefs.setFolder(copy.id, folder);
        await widget.onRefresh();
        _snack('Duplicated as "${copy.name}"');
        break;
      case ProjectMenuAction.rename:
        final name = await promptText(context,
            title: 'Rename project', initial: displayName(p), action: 'Rename');
        if (name == null || name.trim().isEmpty) return;
        await HomeActions.rename(p, name);
        await widget.onRefresh();
        break;
      case ProjectMenuAction.export:
        await widget.onExportProject(p.id);
        break;
      case ProjectMenuAction.share:
        await _share(p);
        break;
      case ProjectMenuAction.move:
        await _moveToFolder(p);
        break;
      case ProjectMenuAction.delete:
        await _delete(p);
        break;
    }
  }

  Future<void> _share(VideoProject p) async {
    final existing =
        prefs.exportsOf(p.id).where((path) => File(path).existsSync()).toList();
    if (existing.isEmpty) {
      final export = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Export first?'),
          content: const Text(
              'This project has not been exported yet. Export it now, then share the video from the Exports tab.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Export')),
          ],
        ),
      );
      if (export == true) await widget.onExportProject(p.id);
      return;
    }
    await SharePlus.instance.share(ShareParams(
      files: [XFile(existing.last)],
      text: displayName(p),
    ));
  }

  Future<void> _moveToFolder(VideoProject p) async {
    final current = prefs.folderOf(p.id);
    final choice = await showHomeSheet<String>(
      context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text('Move to folder',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          for (final f in prefs.folders)
            ListTile(
              leading: Icon(
                  f == current ? Icons.folder_rounded : Icons.folder_outlined,
                  color: kHomeAccent),
              title: Text(f, style: const TextStyle(color: Colors.white)),
              trailing: f == current
                  ? const Icon(Icons.check_rounded, color: kHomeAccent)
                  : null,
              onTap: () => Navigator.pop(ctx, f),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined,
                color: Colors.white70),
            title: const Text('New folder…',
                style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, '\u0000new'),
          ),
          if (current != null)
            ListTile(
              leading:
                  const Icon(Icons.folder_off_outlined, color: Colors.white70),
              title: const Text('Remove from folder',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, '\u0000none'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == '\u0000none') {
      await prefs.setFolder(p.id, null);
    } else if (choice == '\u0000new') {
      final name = await promptText(context,
          title: 'New folder', hint: 'e.g. College events', action: 'Create');
      if (name == null || name.trim().isEmpty) return;
      await prefs.addFolder(name.trim());
      await prefs.setFolder(p.id, name.trim());
    } else {
      await prefs.setFolder(p.id, choice);
    }
    homeHaptic(prefs);
  }

  Future<void> _delete(VideoProject p) async {
    homeHaptic(prefs, heavy: true);
    final folder = prefs.folderOf(p.id);
    await provider.deleteProject(p.id);
    await widget.onRefresh();
    if (!mounted) return;
    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final closed = messenger
        .showSnackBar(SnackBar(
          content: Text('Deleted "${displayName(p)}"'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () async {
              undone = true;
              await HomeActions.restore(provider, p);
              if (folder != null) await prefs.setFolder(p.id, folder);
              await widget.onRefresh();
            },
          ),
        ))
        .closed;
    await closed;
    if (!undone) await prefs.forgetProject(p.id);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pullToRefresh() async {
    // Regenerate covers and durations from the saved projects.
    for (final p in widget.projects) {
      for (final c in p.videoClips) {
        final path = c.videoFile?.path;
        if (path != null) VideoThumbnailService().clearCacheForVideo(path);
      }
    }
    await widget.onRefresh();
    await _loadUsage();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final projects = _visibleProjects;
    final hasAny = widget.projects.isNotEmpty;
    final tips =
        HomeTip.all.where((t) => !prefs.dismissedTips.contains(t.id)).toList();
    final grid = prefs.gridView;
    final width = MediaQuery.of(context).size.width;
    final columns = width > 900 ? 4 : (width > 600 ? 3 : 2);

    return RefreshIndicator(
      color: kHomeAccent,
      backgroundColor: const Color(0xFF1A1A1E),
      onRefresh: _pullToRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _HomeHeaderDelegate(
              topPadding: MediaQuery.of(context).padding.top,
              onSettings: () => widget.onSwitchTab(4),
            ),
          ),
          SliverToBoxAdapter(child: _buildQuickActions()),
          if (hasAny && _continueProject != null)
            SliverToBoxAdapter(child: _buildContinueCard(_continueProject!)),
          if (tips.isNotEmpty) SliverToBoxAdapter(child: _buildTips(tips)),
          if (!hasAny)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(),
            )
          else ...[
            SliverToBoxAdapter(child: _buildLibraryHeader()),
            if (projects.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    _query.isNotEmpty
                        ? 'No projects match "$_query".'
                        : 'Nothing here yet.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
              )
            else if (grid)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => StaggeredEntry(
                      key: ValueKey('g-${projects[i].id}'),
                      index: i,
                      animate: _animateEntries,
                      child: _card(projects[i], true),
                    ),
                    childCount: projects.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverList.separated(
                  itemCount: projects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => StaggeredEntry(
                    key: ValueKey('l-${projects[i].id}'),
                    index: i,
                    animate: _animateEntries,
                    child: _card(projects[i], false),
                  ),
                ),
              ),
            SliverToBoxAdapter(child: _buildStorageStrip()),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _card(VideoProject p, bool grid) {
    return ProjectCard(
      project: p,
      prefs: prefs,
      grid: grid,
      refreshToken: widget.refreshToken,
      onOpen: () => _open(p),
      onMenu: () => _menu(p),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _QuickAction('New Project', Icons.add_rounded,
          const [Color(0xFF8B5CF6), Color(0xFFCBAAFF)], _newProject),
      _QuickAction(
          'Templates',
          Icons.dashboard_customize_rounded,
          const [Color(0xFFF97316), Color(0xFFF59E0B)],
          () => widget.onSwitchTab(1)),
      _QuickAction('Record', Icons.videocam_rounded,
          const [Color(0xFFEF4444), Color(0xFFDB2777)], _record),
      _QuickAction('Import', Icons.photo_library_rounded,
          const [Color(0xFF06B6D4), Color(0xFF3B82F6)], _import),
      _QuickAction('Slideshow', Icons.slideshow_rounded,
          const [Color(0xFF22C55E), Color(0xFF059669)], _slideshow),
    ];
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final a = actions[i];
          return StaggeredEntry(
            index: i,
            animate: _animateEntries,
            child: _QuickActionTile(
              action: a,
              onTap: () {
                homeHaptic(prefs);
                a.onTap();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildContinueCard(VideoProject p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GestureDetector(
        onTap: () => _open(p),
        onLongPress: () => _menu(p),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          // Grows with the text (large system fonts) instead of a fixed height.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 170),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ProjectCover(
                      project: p, refreshToken: widget.refreshToken),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.black.withValues(alpha: 0.25),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const HomeBadge('CONTINUE EDITING',
                          icon: Icons.history_rounded,
                          color: Color(0xFF7C3AED)),
                      const SizedBox(height: 30),
                      Text(
                        displayName(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatLength(projectLength(p))} · '
                        '${p.videoClips.length} clips · '
                        '${relativeTime(p.lastModified)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12.5),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 38,
                        child: ElevatedButton.icon(
                          onPressed: () => _open(p),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Resume'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kHomeAccent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ),
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

  Widget _buildTips(List<HomeTip> tips) {
    return SizedBox(
      height: 132,
      child: PageView.builder(
        controller: _tipsController,
        padEnds: false,
        itemCount: tips.length,
        itemBuilder: (context, i) {
          final t = tips[i];
          return Padding(
            padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 6, 12, 6, 0),
            child: GlassPanel(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: t.color.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(t.icon, color: t.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            t.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.white60),
                    onPressed: () {
                      homeHaptic(prefs);
                      prefs.dismissTip(t.id);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLibraryHeader() {
    final showSearch = widget.projects.length > 6;
    final filters = <(String, String)>[
      ('all', 'All'),
      ('drafts', 'Drafts'),
      ('exported', 'Exported'),
      for (final f in prefs.folders) ('folder:$f', f),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Your Projects',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Sort',
                  initialValue: prefs.sortMode,
                  icon: const Icon(Icons.sort_rounded, color: Colors.white),
                  onSelected: prefs.setSortMode,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'recent', child: Text('Most recent')),
                    PopupMenuItem(value: 'oldest', child: Text('Oldest')),
                    PopupMenuItem(value: 'name', child: Text('Name')),
                    PopupMenuItem(value: 'longest', child: Text('Longest')),
                  ],
                ),
                IconButton(
                  tooltip: prefs.gridView ? 'List view' : 'Grid view',
                  icon: Icon(
                    prefs.gridView
                        ? Icons.view_agenda_outlined
                        : Icons.grid_view_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    homeHaptic(prefs);
                    prefs.setGridView(!prefs.gridView);
                  },
                ),
              ],
            ),
          ),
          if (showSearch) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.trim()),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search projects',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                fillColor: Colors.black.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = filters[i];
                final selected = _filter == f.$1;
                return ChoiceChip(
                  label: Text(f.$2),
                  avatar: f.$1.startsWith('folder:')
                      ? Icon(Icons.folder_rounded,
                          size: 16,
                          color: selected ? Colors.black : kHomeAccent)
                      : null,
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = f.$1),
                  selectedColor: kHomeAccent,
                  backgroundColor: Colors.black.withValues(alpha: 0.35),
                  labelStyle: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                      color: selected
                          ? kHomeAccent
                          : Colors.white.withValues(alpha: 0.15)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageStrip() {
    final u = _usage;
    if (u == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: GestureDetector(
        onTap: () async {
          await showStorageSheet(context, prefs: prefs);
          await _loadUsage();
        },
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.sd_storage_outlined, color: kHomeAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Projects use ${formatBytes(u.total)}'
                  '${u.cache > 0 ? ' · ${formatBytes(u.cache)} can be cleared' : ''}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              const Text('Manage',
                  style: TextStyle(
                      color: kHomeAccent, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: GlassPanel(
          borderRadius: BorderRadius.circular(28),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _EmptyIllustration(),
              const SizedBox(height: 18),
              const Text(
                'Create your first video',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Import clips and photos, record something new, or let a template do the editing for you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 13.5,
                    height: 1.45),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _newProject,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create your first video'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kHomeAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => widget.onSwitchTab(1),
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  label: const Text('Start from a template'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side:
                        BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  const _QuickAction(this.label, this.icon, this.colors, this.onTap);
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;
  final VoidCallback onTap;
  const _QuickActionTile({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: action.colors,
                ),
                boxShadow: [
                  BoxShadow(
                    color: action.colors.first.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(action.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 7),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo + title that shrink as the page scrolls.
class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;
  final VoidCallback onSettings;

  _HomeHeaderDelegate({required this.topPadding, required this.onSettings});

  static const double _expanded = 96;
  static const double _collapsed = 60;

  @override
  double get maxExtent => topPadding + _expanded;

  @override
  double get minExtent => topPadding + _collapsed;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (_expanded - _collapsed)).clamp(0.0, 1.0);
    final logo = 54 - 20 * t;
    final title = 32 - 10 * t;
    // Must fill the full header extent: a shorter child makes the sliver's
    // geometry invalid and the whole tab fails to lay out (blank screen).
    return Container(
      constraints: const BoxConstraints.expand(),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.fromLTRB(20, topPadding + 8, 12, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55 * t),
            Colors.black.withValues(alpha: 0.35 * t),
          ],
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/studiov_logo.png',
                width: logo, height: logo, fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Studio V',
              style: TextStyle(
                fontSize: title,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HomeHeaderDelegate old) =>
      old.topPadding != topPadding;
}

class _EmptyIllustration extends StatelessWidget {
  const _EmptyIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final (angle, dx, colors) in const [
            (-0.18, -34.0, [Color(0xFF06B6D4), Color(0xFF3B82F6)]),
            (0.18, 34.0, [Color(0xFFF97316), Color(0xFFDB2777)]),
          ])
            Transform.translate(
              offset: Offset(dx, 6),
              child: Transform.rotate(
                angle: angle,
                child: Container(
                  width: 66,
                  height: 86,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: colors),
                  ),
                ),
              ),
            ),
          Container(
            width: 74,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7C3AED), Color(0xFFCBAAFF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 42),
          ),
        ],
      ),
    );
  }
}
