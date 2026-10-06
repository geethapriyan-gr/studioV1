import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show AppColors;
import '../providers/video_editor_provider.dart';
import '../utils/sticker_catalog.dart';
import 'length_prompt.dart';
import 'sticker_layer.dart' show stickerImageProvider;

/// Sticker picker: categories, search, recently used, and the user's own
/// images (PNG/WebP/JPG, or animated GIF). A tapped sticker is placed at
/// the playhead.
class StickerPanel extends StatefulWidget {
  const StickerPanel({super.key});

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  List<StickerEntry> _bundled = const [];
  List<String> _recents = const [];
  List<String> _custom = const [];
  String _category = StickerCatalog.categories[2];
  String _query = '';
  bool _loading = true;
  final _search = TextEditingController();

  static const Duration _stickerLength = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bundled = await StickerCatalog.bundled();
    final recents = await StickerCatalog.recents();
    final custom = (await StickerCatalog.custom())
        .where((p) => File(p).existsSync())
        .toList();
    if (!mounted) return;
    setState(() {
      _bundled = bundled;
      _recents = recents;
      _custom = custom;
      // Open on Recent when there is something in it.
      if (_loading && recents.isNotEmpty) _category = StickerCatalog.recent;
      _loading = false;
    });
  }

  StickerEntry _entryFor(String path) {
    for (final e in _bundled) {
      if (e.path == path) return e;
    }
    return StickerEntry(path, 'My sticker', StickerCatalog.mine);
  }

  List<StickerEntry> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      return [
        for (final e in _bundled)
          if (e.label.toLowerCase().contains(q) ||
              e.category.toLowerCase().contains(q))
            e,
      ];
    }
    switch (_category) {
      case StickerCatalog.recent:
        return _recents
            .where((p) => p.startsWith('assets/') || File(p).existsSync())
            .map(_entryFor)
            .toList();
      case StickerCatalog.mine:
        return _custom.map(_entryFor).toList();
      default:
        return _bundled.where((e) => e.category == _category).toList();
    }
  }

  Future<void> _add(VideoEditorProvider provider, String path) async {
    final start = provider.currentPosition;
    final before = provider.totalDuration;
    final id = await provider.addSticker(
      assetPath: path,
      startTime: start,
      endTime: start + _stickerLength,
    );
    await StickerCatalog.markUsed(path);
    if (id != null) provider.selectSticker(id);
    if (!mounted) return;
    await LengthPrompt.afterAdd(
        context, provider, before, TimelineItemKind.sticker, id);
    // Back to the timeline so the new sticker and its tools show.
    provider.toggleTimeline();
  }

  Future<void> _importOwn(VideoEditorProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'webp', 'gif', 'jpg', 'jpeg'],
      );
      final picked = result?.files.single.path;
      if (picked == null) return;
      final saved = await provider.importCustomSticker(File(picked));
      await _load();
      if (!mounted) return;
      setState(() => _category = StickerCatalog.mine);
      await _add(provider, saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not use that image: $e')),
      );
    }
  }

  Future<void> _removeOwn(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Remove from My stickers?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
            'Stickers already placed in projects stay where they are.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await StickerCatalog.removeCustom(path);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final items = _visible;
    final isMine = _category == StickerCatalog.mine && _query.isEmpty;
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          _buildHeader(provider),
          _buildCategories(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (items.isEmpty && !isMine)
                    ? _empty()
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 96,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: items.length + (isMine ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (isMine && index == 0) {
                            return _addOwnTile(provider);
                          }
                          final e = items[isMine ? index - 1 : index];
                          return _stickerTile(provider, e, removable: isMine);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final text = _query.isNotEmpty
        ? 'No stickers match "$_query".'
        : _category == StickerCatalog.recent
            ? 'Stickers you use show up here.'
            : 'Nothing here yet.';
    return Center(
      child: Text(text, style: TextStyle(color: AppColors.textTertiary)),
    );
  }

  Widget _buildHeader(VideoEditorProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.surfaceLight,
                prefixIcon: Icon(Icons.search_rounded,
                    color: AppColors.textTertiary, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                hintText: 'Search stickers',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Add my own',
            onPressed: () => _importOwn(provider),
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: provider.toggleTimeline,
            icon: Icon(Icons.close_rounded, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: StickerCatalog.categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final c = StickerCatalog.categories[i];
          final selected = _query.isEmpty && c == _category;
          return ChoiceChip(
            label: Text(c),
            selected: selected,
            onSelected: (_) {
              _search.clear();
              setState(() {
                _query = '';
                _category = c;
              });
            },
          );
        },
      ),
    );
  }

  Widget _addOwnTile(VideoEditorProvider provider) {
    return InkWell(
      onTap: () => _importOwn(provider),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary),
            const SizedBox(height: 4),
            Text('Add image',
                style: TextStyle(color: AppColors.primary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _stickerTile(VideoEditorProvider provider, StickerEntry e,
      {bool removable = false}) {
    return Tooltip(
      message: e.label,
      child: GestureDetector(
        onTap: () => _add(provider, e.path),
        onLongPress: removable ? () => _removeOwn(e.path) : null,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Image(
            image: ResizeImage(stickerImageProvider(e.path),
                width: 160, allowUpscaling: false),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined,
                color: AppColors.textTertiary),
          ),
        ),
      ),
    );
  }
}
