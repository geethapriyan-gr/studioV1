import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../effects/effect_engine.dart';
import '../main.dart' show AppColors;
import '../models/video_effect.dart';
import '../models/video_project.dart';
import '../providers/video_editor_provider.dart';

/// Bottom sheets for the clip toolbar: speed, volume, rotate and effects.
/// Sliders commit on release so a drag is one undo step (and one re-render
/// of affected transitions), not dozens.
class ClipToolSheets {
  ClipToolSheets._();

  static VideoClip? _clip(VideoEditorProvider p, String id) {
    for (final c in p.currentProject?.videoClips ?? const <VideoClip>[]) {
      if (c.id == id) return c;
    }
    return null;
  }

  static Future<void> _show(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget Function(BuildContext, VideoEditorProvider, VideoClip)
        builder,
    required String clipId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Consumer<VideoEditorProvider>(
          builder: (ctx, provider, _) {
            final clip = _clip(provider, clipId);
            if (clip == null) return const SizedBox(height: 120);
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(icon, color: AppColors.primary, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        title,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  builder(ctx, provider, clip),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Speed ───────────────────────────────────────────────────────────────

  static const _speedPresets = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];

  static Future<void> speed(BuildContext context, String clipId) => _show(
        context,
        title: 'Speed',
        icon: Icons.speed_rounded,
        clipId: clipId,
        builder: (ctx, p, clip) => _SpeedBody(provider: p, clip: clip),
      );

  // ── Volume ──────────────────────────────────────────────────────────────

  static Future<void> volume(BuildContext context, String clipId) => _show(
        context,
        title: 'Clip volume',
        icon: Icons.volume_up_rounded,
        clipId: clipId,
        builder: (ctx, p, clip) => _VolumeBody(provider: p, clip: clip),
      );

  // ── Rotate ──────────────────────────────────────────────────────────────

  static Future<void> rotate(BuildContext context, String clipId) => _show(
        context,
        title: 'Rotate & flip',
        icon: Icons.rotate_90_degrees_ccw_rounded,
        clipId: clipId,
        builder: (ctx, p, clip) => _RotateBody(provider: p, clip: clip),
      );

  // ── Effects ─────────────────────────────────────────────────────────────

  static Future<void> effects(BuildContext context, String clipId) => _show(
        context,
        title: 'Effects',
        icon: Icons.auto_awesome_rounded,
        clipId: clipId,
        builder: (ctx, p, clip) => _EffectsBody(provider: p, clip: clip),
      );
}

String _fmtSecs(Duration d) =>
    '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

class _ValueBadge extends StatelessWidget {
  final String text;
  const _ValueBadge(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SpeedBody extends StatefulWidget {
  final VideoEditorProvider provider;
  final VideoClip clip;
  const _SpeedBody({required this.provider, required this.clip});

  @override
  State<_SpeedBody> createState() => _SpeedBodyState();
}

class _SpeedBodyState extends State<_SpeedBody> {
  double? _dragValue;

  Future<void> _apply(double v) async {
    HapticFeedback.selectionClick();
    setState(() => _dragValue = null);
    if ((v - widget.clip.playbackSpeed).abs() < 0.001) return;
    await widget.provider.setVideoClipPlaybackSpeed(widget.clip.id, v);
  }

  @override
  Widget build(BuildContext context) {
    final current = _dragValue ?? widget.clip.playbackSpeed;
    final source = widget.clip.trimEnd - widget.clip.trimStart;
    final newLength =
        VideoEditorProvider.timelineLengthForSource(source, current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ValueBadge('${current.toStringAsFixed(2)}×'),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Clip length ${_fmtSecs(widget.clip.endTime - widget.clip.startTime)}'
                ' → ${_fmtSecs(newLength)}',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Slider(
          value: current.clamp(0.25, 4.0),
          min: 0.25,
          max: 4.0,
          divisions: 75,
          onChanged: (v) => setState(() => _dragValue = v),
          onChangeEnd: _apply,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in ClipToolSheets._speedPresets)
              ChoiceChip(
                label: Text('${s}x'),
                selected: (s - current).abs() < 0.001,
                onSelected: (_) => _apply(s),
                showCheckmark: false,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                labelStyle: TextStyle(
                  color: (s - current).abs() < 0.001
                      ? Colors.white
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                side: BorderSide(color: AppColors.border),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Audio pitch is kept; later clips move to stay in sequence.',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
      ],
    );
  }
}

class _VolumeBody extends StatefulWidget {
  final VideoEditorProvider provider;
  final VideoClip clip;
  const _VolumeBody({required this.provider, required this.clip});

  @override
  State<_VolumeBody> createState() => _VolumeBodyState();
}

class _VolumeBodyState extends State<_VolumeBody> {
  double? _dragValue;

  Future<void> _apply(double v) async {
    HapticFeedback.selectionClick();
    setState(() => _dragValue = null);
    if (widget.clip.isMuted && v > 0) {
      await widget.provider.toggleVideoClipMute(widget.clip.id);
    }
    await widget.provider.updateVideoClipVolume(widget.clip.id, v);
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    if (clip.mediaType != MediaType.video) {
      return Text('Photos have no sound.',
          style: TextStyle(color: AppColors.textSecondary));
    }
    final current = _dragValue ?? clip.volume;
    final muted = clip.isMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ValueBadge(muted ? 'Muted' : '${(current * 100).round()}%'),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () {
                HapticFeedback.selectionClick();
                widget.provider.toggleVideoClipMute(clip.id);
              },
              icon: Icon(muted
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded),
              label: Text(muted ? 'Unmute' : 'Mute'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.volume_mute_rounded, color: AppColors.textTertiary),
            Expanded(
              child: Slider(
                value: current.clamp(0.0, 1.0),
                divisions: 20,
                onChanged:
                    muted ? null : (v) => setState(() => _dragValue = v),
                onChangeEnd: muted ? null : _apply,
              ),
            ),
            Icon(Icons.volume_up_rounded, color: AppColors.textTertiary),
          ],
        ),
        Row(
          children: [
            for (final v in const [0.0, 0.25, 0.5, 0.75, 1.0])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  onPressed: muted ? null : () => _apply(v),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.border),
                    minimumSize: const Size(52, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text('${(v * 100).round()}%'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RotateBody extends StatefulWidget {
  final VideoEditorProvider provider;
  final VideoClip clip;
  const _RotateBody({required this.provider, required this.clip});

  @override
  State<_RotateBody> createState() => _RotateBodyState();
}

class _RotateBodyState extends State<_RotateBody> {
  double? _fine;

  double get _rotation => widget.clip.rotation;

  /// Snapped quarter turn of the current rotation.
  double get _quarter => (_rotation / 90).round() * 90.0;

  Future<void> _set(double deg) async {
    HapticFeedback.selectionClick();
    var d = deg % 360;
    if (d < 0) d += 360;
    await widget.provider.rotateVideoClip(widget.clip.id, d);
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    // Fine tilt relative to the nearest quarter turn, in -45..45.
    var tilt = _rotation - _quarter;
    if (tilt > 180) tilt -= 360;
    final shownTilt = _fine ?? tilt.clamp(-45.0, 45.0);
    Widget action(IconData icon, String label, VoidCallback onTap,
        {bool active = false}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: active ? AppColors.primary : AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(icon,
                      color:
                          active ? AppColors.primary : AppColors.textPrimary),
                  const SizedBox(height: 6),
                  Text(label,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            action(Icons.rotate_left_rounded, 'Left 90°',
                () => _set(_rotation - 90)),
            action(Icons.rotate_right_rounded, 'Right 90°',
                () => _set(_rotation + 90)),
            action(Icons.flip_rounded, 'Mirror', () {
              HapticFeedback.selectionClick();
              widget.provider.toggleVideoClipMirror(clip.id);
            }, active: clip.isMirrored),
            action(Icons.restart_alt_rounded, 'Reset', () async {
              await _set(0);
              if (clip.isMirrored) {
                await widget.provider.toggleVideoClipMirror(clip.id);
              }
            }),
          ],
        ),
        const SizedBox(height: 16),
        Text('Straighten  ${shownTilt.toStringAsFixed(0)}°',
            style: TextStyle(color: AppColors.textSecondary)),
        Slider(
          value: shownTilt.toDouble(),
          min: -45,
          max: 45,
          divisions: 90,
          onChanged: (v) => setState(() => _fine = v),
          onChangeEnd: (v) async {
            setState(() => _fine = null);
            await _set(_quarter + v);
          },
        ),
      ],
    );
  }
}

class _EffectsBody extends StatelessWidget {
  final VideoEditorProvider provider;
  final VideoClip clip;
  const _EffectsBody({required this.provider, required this.clip});

  static const _uuid = Uuid();

  VideoEffect? _effectOf(VideoEffectType type) {
    for (final e in provider.currentProject?.videoEffects ??
        const <VideoEffect>[]) {
      if (e.clipId == clip.id && e.type == type) return e;
    }
    return null;
  }

  Future<void> _toggle(VideoEffectType type) async {
    HapticFeedback.selectionClick();
    final existing = _effectOf(type);
    if (existing != null) {
      await provider.removeVideoEffect(existing.id);
    } else {
      await provider.addVideoEffect(VideoEffect(
        id: _uuid.v4(),
        clipId: clip.id,
        type: type,
        intensity: 0.6,
        startTime: clip.startTime,
        duration: clip.endTime - clip.startTime,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = [
      for (final t in EffectEngine.pickerOrder)
        if (_effectOf(t) != null) _effectOf(t)!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tap to add or remove. Effects cover the whole clip and play live in the preview.',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.82,
          children: [
            for (final t in EffectEngine.pickerOrder)
              _EffectTile(
                type: t,
                selected: _effectOf(t) != null,
                onTap: () => _toggle(t),
              ),
          ],
        ),
        if (active.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final e in active)
            _IntensityRow(provider: provider, effect: e),
        ],
      ],
    );
  }
}

class _EffectTile extends StatelessWidget {
  final VideoEffectType type;
  final bool selected;
  final VoidCallback onTap;

  const _EffectTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  static List<Color> _colors(VideoEffectType t) => switch (t) {
        VideoEffectType.shake => const [Color(0xFFF97316), Color(0xFFEF4444)],
        VideoEffectType.glitch => const [Color(0xFF06B6D4), Color(0xFFDB2777)],
        VideoEffectType.flash => const [Color(0xFFFDE68A), Color(0xFFF59E0B)],
        VideoEffectType.blur => const [Color(0xFF93C5FD), Color(0xFF6366F1)],
        VideoEffectType.neon => const [Color(0xFFA855F7), Color(0xFF22D3EE)],
        VideoEffectType.vintage => const [Color(0xFFB45309), Color(0xFF78350F)],
        VideoEffectType.sepia => const [Color(0xFFD6B98C), Color(0xFF8B6B3D)],
        VideoEffectType.grayscale => const [Color(0xFFD4D4D8), Color(0xFF3F3F46)],
      };

  @override
  Widget build(BuildContext context) {
    final probe = VideoEffect(
      id: '',
      clipId: '',
      type: type,
      startTime: Duration.zero,
      duration: Duration.zero,
    );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _colors(type),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(probe.getIcon(), color: Colors.white, size: 26),
                    if (selected)
                      const Positioned(
                        right: 4,
                        top: 4,
                        child: Icon(Icons.check_circle_rounded,
                            color: Colors.white, size: 16),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              probe.getDisplayName(),
              maxLines: 1,
              style: TextStyle(
                color:
                    selected ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntensityRow extends StatefulWidget {
  final VideoEditorProvider provider;
  final VideoEffect effect;
  const _IntensityRow({required this.provider, required this.effect});

  @override
  State<_IntensityRow> createState() => _IntensityRowState();
}

class _IntensityRowState extends State<_IntensityRow> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final e = widget.effect;
    final v = _drag ?? e.intensity;
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            e.getDisplayName(),
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Slider(
            value: v.clamp(0.05, 1.0),
            min: 0.05,
            max: 1.0,
            onChanged: (x) => setState(() => _drag = x),
            onChangeEnd: (x) async {
              setState(() => _drag = null);
              await widget.provider
                  .updateVideoEffect(e.id, e.copyWith(intensity: x));
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${(v * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      ],
    );
  }
}
