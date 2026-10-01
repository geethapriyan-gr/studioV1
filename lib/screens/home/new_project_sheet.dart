import 'package:flutter/material.dart';

import '../../models/transition.dart';
import '../../providers/video_editor_provider.dart';
import 'home_actions.dart';
import 'home_models.dart';
import 'home_prefs.dart';
import 'home_widgets.dart';

/// Recipe for "Photo Slideshow": the user's photos, crossfades and music.
const HomeTemplate kSlideshowRecipe = HomeTemplate(
  id: 'slideshow',
  name: 'Photo Slideshow',
  description: 'Your photos with crossfades and background music.',
  title: '',
  aspectId: '16:9',
  transition: TransitionType.crossfade,
  transitionDuration: Duration(milliseconds: 700),
  colors: [Color(0xFFF59E0B), Color(0xFFDB2777)],
  icon: Icons.slideshow_rounded,
  imagesOnly: true,
);

enum _MediaSource { samples, mine }

/// Name + aspect ratio (+ media source for templates) before creating.
///
/// [media] is media the user already picked (record, import, library,
/// slideshow photos). With none and no template, the gallery opens right
/// after the project is created, like the old "+" flow.
Future<void> startNewProject(
  BuildContext context, {
  required VideoEditorProvider provider,
  required HomePrefs prefs,
  HomeTemplate? template,
  List<HomeMedia> media = const [],
}) async {
  final nameController = TextEditingController(
    text: template != null && template.title.isNotEmpty && media.isEmpty
        ? template.name
        : autoProjectName(),
  );
  var aspect = AspectOption.byId(template?.aspectId ?? prefs.defaultAspect);
  var source = _MediaSource.samples;
  final hasSamples = template != null && template.sampleAssets.isNotEmpty;
  if (!hasSamples) source = _MediaSource.mine;

  final confirmed = await showHomeSheet<bool>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (template != null)
                    Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(colors: template.colors),
                      ),
                      child: Icon(template.icon, color: Colors.white, size: 22),
                    ),
                  Expanded(
                    child: Text(
                      template?.name ?? 'New Project',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (template != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${template.description}\n${template.transitionName} transitions'
                  '${template.title.isNotEmpty ? ' · title card' : ''}'
                  '${template.music ? ' · music' : ''}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      height: 1.4),
                ),
              ],
              if (media.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${media.length} item${media.length == 1 ? '' : 's'} ready to import',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13),
                ),
              ],
              const SizedBox(height: 22),
              const _Label('PROJECT NAME'),
              TextField(
                controller: nameController,
                maxLength: 50,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 18),
              const _Label('ASPECT RATIO'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in AspectOption.all)
                    _AspectChip(
                      option: a,
                      selected: a.id == aspect.id,
                      onTap: () => setSheet(() => aspect = a),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                aspect.hint,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
              if (hasSamples && media.isEmpty) ...[
                const SizedBox(height: 18),
                const _Label('MEDIA'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _SourceTile(
                        icon: Icons.auto_awesome_mosaic_rounded,
                        title: 'Sample media',
                        subtitle: 'Swap clips later',
                        selected: source == _MediaSource.samples,
                        onTap: () =>
                            setSheet(() => source = _MediaSource.samples),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SourceTile(
                        icon: Icons.photo_library_outlined,
                        title: 'My media',
                        subtitle: template.imagesOnly
                            ? 'Pick photos'
                            : 'Pick videos & photos',
                        selected: source == _MediaSource.mine,
                        onTap: () => setSheet(() => source = _MediaSource.mine),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(template != null ? 'Use template' : 'Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kHomeAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  final name = nameController.text;
  nameController.dispose();
  if (confirmed != true || !context.mounted) return;

  var items = media;
  if (template != null && items.isEmpty) {
    items = source == _MediaSource.samples
        ? await HomeActions.assetsToMedia(template.sampleAssets)
        : await HomeActions.pickFromGallery(imagesOnly: template.imagesOnly);
    if (items.isEmpty) return; // picker cancelled
  }
  if (!context.mounted) return;

  await HomeActions.createProject(
    context: context,
    provider: provider,
    prefs: prefs,
    name: name,
    aspect: aspect,
    media: items,
    template: template,
    pickAfterCreate: template == null && items.isEmpty,
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF9B6FD6),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}

class _AspectChip extends StatelessWidget {
  final AspectOption option;
  final bool selected;
  final VoidCallback onTap;

  const _AspectChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? kHomeAccent.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color:
                selected ? kHomeAccent : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(option.icon,
                size: 18, color: selected ? kHomeAccent : Colors.white70),
            const SizedBox(width: 6),
            Text(
              option.label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? kHomeAccent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected ? kHomeAccent : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? kHomeAccent : Colors.white70),
            const SizedBox(height: 8),
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}
