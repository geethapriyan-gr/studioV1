import 'package:flutter/material.dart';

import '../../providers/video_editor_provider.dart';
import 'home_actions.dart';
import 'home_models.dart';
import 'home_prefs.dart';
import 'home_widgets.dart';
import 'new_project_sheet.dart';

/// Ready-made project recipes. Picking one asks for a name/aspect and
/// whether to start with the bundled sample media or the user's own.
class TemplatesTab extends StatelessWidget {
  final VideoEditorProvider provider;
  final HomePrefs prefs;

  const TemplatesTab({super.key, required this.provider, required this.prefs});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    const templates = HomeTemplate.all;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, top + 18, 20, 4),
            child: const HomeTabTitle(
              'Templates',
              'Transitions, a title and music — just add your clips.',
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
          sliver: SliverList.separated(
            itemCount: templates.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              if (i == templates.length) {
                return StaggeredEntry(
                  index: i,
                  child: _TemplateCard(
                    template: kSlideshowRecipe,
                    subtitle: 'Pick photos — crossfades and music are added.',
                    onTap: () => _slideshow(context),
                  ),
                );
              }
              final t = templates[i];
              return StaggeredEntry(
                index: i,
                child: _TemplateCard(
                  template: t,
                  onTap: () {
                    homeHaptic(prefs);
                    startNewProject(context,
                        provider: provider, prefs: prefs, template: t);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _slideshow(BuildContext context) async {
    homeHaptic(prefs);
    final photos = await HomeActions.pickFromGallery(imagesOnly: true);
    if (photos.isEmpty || !context.mounted) return;
    await startNewProject(context,
        provider: provider,
        prefs: prefs,
        template: kSlideshowRecipe,
        media: photos);
  }
}

/// Large tab heading with a subtitle, shared by the home tabs.
class HomeTabTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const HomeTabTitle(this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            shadows: [
              Shadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final HomeTemplate template;
  final String? subtitle;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final samples =
        template.sampleAssets.where((a) => !isVideoPath(a)).take(3).toList();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              template.colors.first.withValues(alpha: 0.9),
              template.colors.last.withValues(alpha: 0.75),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: template.colors.first.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Fanned sample thumbnails on the right.
            Positioned(
              right: 14,
              top: 18,
              bottom: 18,
              width: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (var i = 0; i < samples.length; i++)
                    Transform.translate(
                      offset: Offset((i - (samples.length - 1) / 2) * 26, 0),
                      child: Transform.rotate(
                        angle: (i - (samples.length - 1) / 2) * 0.12,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            samples[i],
                            width: 64,
                            height: 88,
                            fit: BoxFit.cover,
                            cacheWidth: 200,
                          ),
                        ),
                      ),
                    ),
                  if (samples.isEmpty)
                    Icon(template.icon,
                        size: 64, color: Colors.white.withValues(alpha: 0.35)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 150, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(template.icon, color: Colors.white, size: 26),
                  const Spacer(),
                  Text(
                    template.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle ?? template.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      HomeBadge(template.aspectId),
                      HomeBadge(template.transitionName,
                          icon: Icons.auto_awesome_rounded),
                      if (template.music)
                        const HomeBadge('Music',
                            icon: Icons.music_note_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
