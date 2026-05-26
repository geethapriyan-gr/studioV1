/// Standalone demo widget that showcases all video transitions.
///
/// Drop this widget into any screen to interactively preview every
/// transition using a slider that controls the normalised progress `t`.
///
/// Usage:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => const TransitionDemoScreen(),
/// ));
/// ```
library;

import 'package:flutter/material.dart';
import '../models/transition.dart';
import 'transition_factory.dart';

// ──────────────────────────────────────────────
//  Full-screen demo page
// ──────────────────────────────────────────────

class TransitionDemoScreen extends StatelessWidget {
  const TransitionDemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Transition Preview'),
        elevation: 0,
      ),
      body: const SafeArea(child: TransitionDemoWidget()),
    );
  }
}

// ──────────────────────────────────────────────
//  Demo widget (embeddable anywhere)
// ──────────────────────────────────────────────

class TransitionDemoWidget extends StatefulWidget {
  /// Optional fixed child widgets.  When `null` the demo uses coloured
  /// placeholder containers labelled **Clip A** / **Clip B**.
  final Widget? childA;
  final Widget? childB;

  const TransitionDemoWidget({
    super.key,
    this.childA,
    this.childB,
  });

  @override
  State<TransitionDemoWidget> createState() => _TransitionDemoWidgetState();
}

class _TransitionDemoWidgetState extends State<TransitionDemoWidget>
    with SingleTickerProviderStateMixin {
  // ── state ──
  TransitionType _selectedType = TransitionType.crossfade;
  TransitionCurvePreset _selectedCurve = TransitionCurvePreset.easeInOut;
  double _progress = 0.0;
  int _durationMs = 500;
  bool _isAnimating = false;

  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durationMs),
    );
    _rebuildAnimation();
  }

  void _rebuildAnimation() {
    _animation = CurvedAnimation(
      parent: _animController,
      curve: _selectedCurve.curve,
    )..addListener(() {
        if (mounted) {
          setState(() => _progress = _animation.value);
        }
      });

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        if (mounted) setState(() => _isAnimating = false);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _playAnimation() {
    _animController.duration = Duration(milliseconds: _durationMs);
    _animController.reset();
    setState(() => _isAnimating = true);
    _animController.forward();
  }

  void _resetAnimation() {
    _animController.reset();
    setState(() {
      _progress = 0.0;
      _isAnimating = false;
    });
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    // Placeholder clips
    final clipA = widget.childA ?? _buildPlaceholder('Clip A', const Color(0xFF1565C0));
    final clipB = widget.childB ?? _buildPlaceholder('Clip B', const Color(0xFFC62828));

    final effect = TransitionFactory.getTransition(_selectedType);

    return Column(
      children: [
        // ── Preview area ──
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Colors.black,
                child: RepaintBoundary(
                  child: effect.build(_progress, clipA, clipB),
                ),
              ),
            ),
          ),
        ),

        // ── Controls ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.4),
                blurRadius: 12,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress slider
              Row(
                children: [
                  const Text('t', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Expanded(
                    child: Slider(
                      value: _progress,
                      onChanged: _isAnimating
                          ? null
                          : (v) => setState(() => _progress = v),
                      activeColor: const Color(0xFF7C4DFF),
                      inactiveColor: Colors.white24,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      _progress.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              // Duration + Curve row
              Row(
                children: [
                  // Duration
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${_durationMs}ms',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _durationMs.toDouble(),
                      min: 100,
                      max: 2000,
                      divisions: 19,
                      label: '${_durationMs}ms',
                      onChanged: (v) {
                        setState(() => _durationMs = v.round());
                        _animController.duration =
                            Duration(milliseconds: _durationMs);
                      },
                      activeColor: const Color(0xFF00BFA5),
                      inactiveColor: Colors.white12,
                    ),
                  ),
                  // Curve selector
                  DropdownButton<TransitionCurvePreset>(
                    value: _selectedCurve,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    underline: const SizedBox.shrink(),
                    items: TransitionCurvePreset.values
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.displayName),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedCurve = v;
                        _rebuildAnimation();
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Play / Reset buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _actionButton(
                    icon: Icons.play_arrow_rounded,
                    label: 'Play',
                    onTap: _isAnimating ? null : _playAnimation,
                  ),
                  const SizedBox(width: 12),
                  _actionButton(
                    icon: Icons.replay_rounded,
                    label: 'Reset',
                    onTap: _resetAnimation,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Transition type grid
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: TransitionType.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final type = TransitionType.values[i];
                    final isSelected = type == _selectedType;
                    final effect = TransitionFactory.getTransition(type);
                    return GestureDetector(
                      onTap: () => setState(() => _selectedType = type),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 64,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0x407C4DFF)
                              : const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF7C4DFF)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(effect.icon,
                                size: 22,
                                color: isSelected
                                    ? const Color(0xFF7C4DFF)
                                    : Colors.white60),
                            const SizedBox(height: 4),
                            Text(
                              effect.displayName.split(' ').first,
                              style: TextStyle(
                                fontSize: 9,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white54,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── helpers ──

  Widget _buildPlaceholder(String label, Color color) {
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          shadows: [
            Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x337C4DFF),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF7C4DFF), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: const Color(0xFFB388FF)),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFFB388FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
