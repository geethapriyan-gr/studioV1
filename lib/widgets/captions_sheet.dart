import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart' show AppColors;
import '../providers/video_editor_provider.dart';
import '../services/caption_service.dart';
import '../utils/caption_style.dart';

/// Auto-captions: listens to the clips' speech on the device and adds the
/// words as timed text items.
class CaptionsSheet extends StatefulWidget {
  const CaptionsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const SafeArea(top: false, child: CaptionsSheet()),
    );
  }

  @override
  State<CaptionsSheet> createState() => _CaptionsSheetState();
}

class _CaptionsSheetState extends State<CaptionsSheet> {
  static const _languages = [
    ('auto', 'Detect'),
    ('en', 'English'),
    ('ta', 'Tamil'),
    ('hi', 'Hindi'),
    ('te', 'Telugu'),
    ('ml', 'Malayalam'),
    ('kn', 'Kannada'),
  ];

  String _language = 'auto';
  bool _translate = false;
  CaptionQuality _quality = CaptionQuality.better;
  CaptionStyle _style = CaptionStyle.all.first;
  final Map<CaptionQuality, bool> _downloaded = {};

  CaptionService? _service;
  CaptionProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final q in CaptionQuality.values) {
      CaptionService.isModelReady(q).then((ok) {
        if (mounted) setState(() => _downloaded[q] = ok);
      });
    }
  }

  bool get _running => _service != null;

  Future<void> _generate(VideoEditorProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;
    if (provider.isPlaying) await provider.togglePlayback();
    final service = CaptionService();
    setState(() {
      _service = service;
      _error = null;
      _progress = const CaptionProgress('Starting');
    });
    try {
      final cues = await service.generate(
        project,
        language: _language,
        translate: _translate,
        quality: _quality,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (cues.isEmpty) {
        setState(() {
          _service = null;
          _error = 'No speech found in the clips (muted clips and '
              'reversed clips are skipped).';
        });
        return;
      }
      provider.setCaptions(cues, _style);
      HapticFeedback.mediumImpact();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Added ${cues.length} captions'),
        action: SnackBarAction(label: 'UNDO', onPressed: provider.undo),
      ));
    } on CaptionCancelled {
      if (mounted) setState(() => _service = null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _service = null;
        _error = 'Could not make captions: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(builder: (context, provider, _) {
      final existing = provider.captions.length;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
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
          Row(children: [
            Icon(Icons.closed_caption_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('Auto captions',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            if (!_running)
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded,
                    color: AppColors.textSecondary),
              ),
          ]),
          Text(
            'Listens to the speech in your clips and adds it as text — '
            'on this phone, nothing is uploaded.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (_running) _progressView() else ..._options(provider, existing),
        ],
      );
    });
  }

  Widget _progressView() {
    final p = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(p?.message ?? '',
            style: TextStyle(color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: p?.fraction, minHeight: 6),
        const SizedBox(height: 8),
        Text('Usually takes about as long as the video itself.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => _service?.cancel(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  List<Widget> _options(VideoEditorProvider provider, int existing) {
    return [
      if (existing > 0) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Expanded(
              child: Text('$existing captions in this project. '
                  'Tap a style below to restyle them.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                provider.removeCaptions();
                HapticFeedback.mediumImpact();
              },
              child: Text('Remove all',
                  style: TextStyle(color: AppColors.error)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      _label('Spoken language'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (code, name) in _languages)
            ChoiceChip(
              label: Text(name),
              selected: _language == code,
              onSelected: (_) => setState(() => _language = code),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Translate to English',
            style: TextStyle(color: AppColors.textPrimary)),
        value: _translate,
        onChanged: (v) => setState(() => _translate = v),
      ),
      _label('Quality'),
      Row(children: [
        for (final q in CaptionQuality.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _quality = q),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _quality == q
                        ? AppColors.primary.withValues(alpha: 0.16)
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            _quality == q ? AppColors.primary : AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.label,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(q.hint,
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                          _downloaded[q] == true
                              ? 'Ready'
                              : 'One-time download · ${q.sizeLabel}',
                          style: TextStyle(
                              color: _downloaded[q] == true
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                              fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      _label('Style'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in CaptionStyle.all)
            ChoiceChip(
              label: Text(s.label),
              selected: _style.id == s.id,
              onSelected: (_) {
                setState(() => _style = s);
                if (existing > 0) provider.restyleCaptions(s);
              },
            ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: TextStyle(color: AppColors.error)),
        ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: () => _generate(provider),
        icon: const Icon(Icons.auto_awesome_rounded),
        label: Text(existing > 0 ? 'Make captions again' : 'Make captions'),
      ),
    ];
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      );
}
