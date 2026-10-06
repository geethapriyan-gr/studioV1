import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';
import '../main.dart' show AppColors;
import 'modern_slider.dart';
import '../utils/text_overlay_painter.dart';
import 'length_prompt.dart';

class TextOverlayEditor extends StatefulWidget {
  const TextOverlayEditor({super.key});

  @override
  State<TextOverlayEditor> createState() => _TextOverlayEditorState();
}

class _TextOverlayEditorState extends State<TextOverlayEditor> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  double _durationSeconds = 3.0;
  double _fontSize = 250.0;
  Color _textColor = Colors.white;
  String? _lastOverlayId;

  // Text styling properties
  String _selectedFontFamily = 'Roboto'; // Modern style
  bool _isBold = false;
  bool _isItalic = false;
  TextAlign _textAlign = TextAlign.center;
  // Look & motion (box, outline, shadow, in/out animation).
  Color? _boxColor;
  Color? _outlineColor;
  double _outlineWidth = 3;
  bool _shadow = true;
  String _animIn = TextAnimations.none;
  String _animOut = TextAnimations.none;
  Offset _position = const Offset(0.5, 0.5);

  // Fonts (bundled in assets/google_fonts, so they work offline).
  static const List<String> _fontNames = [
    'Roboto',
    'Poppins',
    'Montserrat',
    'Bebas Neue',
    'Anton',
    'Oswald',
    'Playfair Display',
    'Lobster',
    'Pacifico',
    'Dancing Script',
    'Caveat',
    'Permanent Marker',
    'Righteous',
    'Space Mono',
    'Lato',
    'Comic Neue',
    'Averia Libre',
    'Actor',
    'Odor Mean Chey',
    'Nabla',
  ];
  late final Map<String, TextStyle Function()> _fontFamilies = {
    for (final name in _fontNames) name: () => GoogleFonts.getFont(name),
  };

  static const List<Color> _boxColors = [
    Color(0x99000000),
    Color(0xE6FFFFFF),
    Color(0xCC7C3AED),
    Color(0xE6FACC15),
    Color(0xE6EF4444),
    Color(0xE622C55E),
  ];
  static const List<Color> _outlineColors = [
    Colors.black,
    Colors.white,
    Color(0xFFEC4899),
    Color(0xFF22D3EE),
    Color(0xFFFACC15),
  ];

  final List<Color> _colors = [
    Colors.white,
    Colors.black,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.brown,
    Colors.grey,
    Colors.blueGrey
  ];

  /// Helper method to get the current TextStyle based on selected font and properties
  TextStyle _getTextStyle({double? fontSize, Color? color}) {
    final baseStyle =
        _fontFamilies[_selectedFontFamily]?.call() ?? GoogleFonts.roboto();
    return baseStyle.copyWith(
      color: color ?? _textColor,
      fontSize: fontSize ?? 14,
      fontWeight: _isBold ? FontWeight.bold : FontWeight.w500,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    // Clear any preview when the widget is disposed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The builder will handle cleanup through the Consumer
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final selId = provider.selectedTextOverlayId;
        TextOverlay? currentOverlay;
        if (selId != null && provider.currentProject != null) {
          try {
            currentOverlay = provider.currentProject!.textOverlays
                .firstWhere((o) => o.id == selId);
          } catch (_) {}
        }

        if (selId != _lastOverlayId) {
          if (currentOverlay != null) {
            _textController.text = currentOverlay.text;
            _fontSize = currentOverlay.fontSize;
            _textColor = currentOverlay.color;
            _selectedFontFamily = currentOverlay.fontFamily;
            _isBold = currentOverlay.fontWeight == FontWeight.bold;
            _isItalic = currentOverlay.flutterFontStyle == FontStyle.italic;
            _textAlign = currentOverlay.flutterTextAlign;
            _durationSeconds =
                ((currentOverlay.endTime - currentOverlay.startTime)
                            .inMilliseconds /
                        1000.0)
                    .clamp(1.0, 20.0);
            _boxColor = currentOverlay.boxColor;
            _outlineColor = currentOverlay.outlineColor;
            if (currentOverlay.outlineWidth > 0) {
              _outlineWidth = currentOverlay.outlineWidth;
            }
            _shadow = currentOverlay.shadow;
            _animIn = currentOverlay.animIn;
            _animOut = currentOverlay.animOut;
            _position = currentOverlay.position;
            provider.clearTextPreview();
          } else {
            _textController.clear();
            _fontSize = 250.0;
            _textColor = Colors.white;
            _selectedFontFamily = 'Roboto';
            _isBold = false;
            _isItalic = false;
            _textAlign = TextAlign.center;
            _boxColor = null;
            _outlineColor = null;
            _outlineWidth = 3;
            _shadow = true;
            _animIn = TextAnimations.none;
            _animOut = TextAnimations.none;
            _position = const Offset(0.5, 0.5);
            _durationSeconds = 3.0;
            provider.clearTextPreview();
          }
          _lastOverlayId = selId;
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Text Input Row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          style: _getTextStyle(fontSize: 14),
                          cursorColor: AppColors.primary,
                          textAlign: _textAlign,
                          decoration: InputDecoration(
                            hintText: 'Type text here...',
                            hintStyle: TextStyle(
                                color: AppColors.textTertiary, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            if (selId != null) {
                              _updateSelectedOverlay(provider);
                            } else {
                              _commit(provider, selId);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (selId == null)
                      _buildActionButton(
                        icon: Icons.send_outlined,
                        color: AppColors.primary,
                        onTap: () => _addTextOverlay(provider),
                      )
                    else ...[
                      _buildActionButton(
                        icon: Icons.check,
                        color: AppColors.success,
                        onTap: () {
                          _updateSelectedOverlay(provider);
                          provider.selectTextOverlay(null);
                          FocusScope.of(context).unfocus();
                          provider.toggleTimeline();
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildActionButton(
                        icon: Icons.delete_outline,
                        color: AppColors.error,
                        onTap: () => _deleteSelectedOverlay(provider),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 14),
                _buildSectionLabel(Icons.auto_awesome_rounded, 'Quick styles'),
                _buildPresets(provider, selId),

                const SizedBox(height: 14),

                // Font Style Selection
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _fontFamilies.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final entry = _fontFamilies.entries.elementAt(index);
                      final styleLabel = entry.key;
                      final isSelected = _selectedFontFamily == styleLabel;

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedFontFamily = styleLabel);
                          if (selId != null) {
                            _updateSelectedOverlay(provider);
                          } else {
                            _commit(provider, selId);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.2)
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              styleLabel,
                              style: _fontFamilies[styleLabel]?.call().copyWith(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                      ) ??
                                  TextStyle(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                  ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 14),

                // Color Picker
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Icon(Icons.palette,
                              size: 16, color: AppColors.textTertiary),
                          SizedBox(width: 8),
                          Text(
                            'Color',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _colors.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final color = _colors[index];
                          final isSelected = _textColor.value == color.value;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _textColor = color);
                              if (selId != null) {
                                _updateSelectedOverlay(provider);
                              } else {
                                _commit(provider, selId);
                              }
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(
                                        color: AppColors.textPrimary, width: 2)
                                    : null,
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                            color: color.withOpacity(0.4),
                                            blurRadius: 8)
                                      ]
                                    : [],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Text Formatting Toolbar
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      // Bold Button
                      _buildFormatButton(
                        icon: Icons.format_bold,
                        label: 'B',
                        isSelected: _isBold,
                        onTap: () {
                          setState(() => _isBold = !_isBold);
                          if (selId != null) {
                            _updateSelectedOverlay(provider);
                          } else {
                            _commit(provider, selId);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      // Italic Button
                      _buildFormatButton(
                        icon: Icons.format_italic,
                        label: 'I',
                        isSelected: _isItalic,
                        onTap: () {
                          setState(() => _isItalic = !_isItalic);
                          if (selId != null) {
                            _updateSelectedOverlay(provider);
                          } else {
                            _commit(provider, selId);
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                _buildSectionLabel(Icons.animation_rounded, 'Animation'),
                _buildAnimationRow(
                    provider, selId, 'In', _animIn, (v) => _animIn = v),
                const SizedBox(height: 6),
                _buildAnimationRow(
                    provider, selId, 'Out', _animOut, (v) => _animOut = v),

                const SizedBox(height: 14),
                _buildSectionLabel(Icons.format_paint_rounded, 'Style'),
                _buildStyleControls(provider, selId),

                const SizedBox(height: 14),

                // Font Size Slider
                ModernSlider(
                  label: 'Font size',
                  value: _fontSize.clamp(10.0, TextOverlayPainter.maxFontSize),
                  min: 10,
                  // Larger sizes are not drawn, so the slider stops here.
                  max: TextOverlayPainter.maxFontSize,
                  divisions: 100,
                  onChanged: (v) {
                    setState(() => _fontSize = v);
                    if (selId != null) {
                      _updateSelectedOverlay(provider);
                    } else {
                      _commit(provider, selId);
                    }
                  },
                ),

                const SizedBox(height: 10),

                // Duration Slider
                ModernSlider(
                  label: 'Duration',
                  value: _durationSeconds,
                  min: 1,
                  max: 20,
                  divisions: 19,
                  unit: 's',
                  onChanged: (v) {
                    setState(() => _durationSeconds = v);
                    if (selId != null) {
                      _updateSelectedOverlay(provider, durationChanged: true);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormatButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.2)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Future<void> _addTextOverlay(VideoEditorProvider provider) async {
    if (_textController.text.trim().isEmpty) return;
    _focusNode.unfocus();
    final start = provider.currentPosition;
    final end =
        start + Duration(milliseconds: (_durationSeconds * 1000).round());
    final before = provider.totalDuration;
    final id = await provider.addTextOverlay(
      text: _textController.text,
      position: _position,
      startTime: start,
      endTime: end,
      fontSize: _fontSize,
      color: _textColor,
      fontFamily: _selectedFontFamily,
      fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
      textAlign: _textAlign,
      animIn: _animIn,
      animOut: _animOut,
      boxColor: _boxColor,
      outlineColor: _outlineColor,
      outlineWidth: _outlineColor == null ? 0 : _outlineWidth,
      shadow: _shadow,
    );
    _textController.clear();
    provider.clearTextPreview();
    if (mounted) {
      await LengthPrompt.afterAdd(
          context, provider, before, TimelineItemKind.text, id);
    }
    provider.toggleTimeline();
  }

  /// Applies the editor's settings to the selected text. Only the duration
  /// slider changes the text's length ([durationChanged]); other edits keep
  /// the length set on the timeline. Rapid edits (typing, slider drags) are
  /// one undo step.
  Future<void> _updateSelectedOverlay(VideoEditorProvider provider,
      {bool durationChanged = false}) async {
    final selId = provider.selectedTextOverlayId;
    if (selId == null) return;
    final exists =
        provider.currentProject?.textOverlays.any((o) => o.id == selId) ??
            false;
    if (!exists) return;
    final overlay =
        provider.currentProject!.textOverlays.firstWhere((o) => o.id == selId);
    final newEnd = durationChanged
        ? overlay.startTime +
            Duration(milliseconds: (_durationSeconds * 1000).round())
        : overlay.endTime;
    await provider.updateTextOverlay(
      selId,
      text: _textController.text,
      fontSize: _fontSize,
      color: _textColor,
      fontFamily: _selectedFontFamily,
      fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
      textAlign: _textAlign,
      endTime: newEnd,
      animIn: _animIn,
      animOut: _animOut,
      boxColor: _boxColor,
      clearBox: _boxColor == null,
      outlineColor: _outlineColor,
      clearOutline: _outlineColor == null,
      outlineWidth: _outlineColor == null ? 0 : _outlineWidth,
      shadow: _shadow,
      undoKey: 'text-edit:$selId',
    );
  }

  // ── Presets, animation and style ──────────────────────────────────────

  /// Applies a change: updates the selected overlay, or the live preview
  /// of the text being typed.
  void _commit(VideoEditorProvider provider, String? selId) {
    if (selId != null) {
      _updateSelectedOverlay(provider);
    } else {
      provider.setTextPreview(
        _textController.text,
        _fontSize,
        _textColor,
        fontFamily: _selectedFontFamily,
        fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
        textAlign: _textAlign,
        position: _position,
        boxColor: _boxColor,
        outlineColor: _outlineColor,
        outlineWidth: _outlineColor == null ? 0 : _outlineWidth,
        shadow: _shadow,
      );
    }
  }

  Widget _buildSectionLabel(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  static const List<_TextPreset> _presets = [
    _TextPreset(
      name: 'Title',
      sample: 'Your Title',
      font: 'Poppins',
      size: 210,
      bold: true,
      animIn: 'pop',
      animOut: 'fade',
      position: Offset(0.12, 0.42),
    ),
    _TextPreset(
      name: 'Lower third',
      sample: 'Name Surname',
      font: 'Montserrat',
      size: 95,
      bold: true,
      box: Color(0xCC7C3AED),
      shadow: false,
      animIn: 'slide',
      animOut: 'slide',
      position: Offset(0.05, 0.78),
      align: TextAlign.left,
    ),
    _TextPreset(
      name: 'Subtitle',
      sample: 'Subtitles go here',
      font: 'Roboto',
      size: 80,
      box: Color(0x99000000),
      shadow: false,
      animIn: 'fade',
      animOut: 'fade',
      position: Offset(0.1, 0.86),
    ),
    _TextPreset(
      name: 'Caption',
      sample: 'WOW!',
      font: 'Anton',
      size: 230,
      outline: Colors.black,
      outlineWidth: 4,
      animIn: 'pop',
      animOut: 'pop',
      position: Offset(0.2, 0.12),
    ),
    _TextPreset(
      name: 'Neon',
      sample: 'Neon Night',
      font: 'Righteous',
      size: 170,
      color: Color(0xFF67E8F9),
      outline: Color(0xFFEC4899),
      outlineWidth: 2,
      animIn: 'fade',
      animOut: 'fade',
      position: Offset(0.12, 0.45),
    ),
    _TextPreset(
      name: 'Typewriter',
      sample: 'Once upon a time…',
      font: 'Space Mono',
      size: 105,
      animIn: 'typewriter',
      animOut: 'fade',
      position: Offset(0.08, 0.5),
      align: TextAlign.left,
    ),
    _TextPreset(
      name: 'Handwritten',
      sample: 'with love',
      font: 'Dancing Script',
      size: 190,
      color: Color(0xFFFDE68A),
      animIn: 'slide',
      animOut: 'fade',
      position: Offset(0.18, 0.4),
    ),
  ];

  void _applyPreset(
      VideoEditorProvider provider, String? selId, _TextPreset p) {
    setState(() {
      _selectedFontFamily = p.font;
      _fontSize = p.size;
      _textColor = p.color;
      _isBold = p.bold;
      _isItalic = false;
      _textAlign = p.align;
      _boxColor = p.box;
      _outlineColor = p.outline;
      _outlineWidth = p.outline == null ? 3 : p.outlineWidth;
      _shadow = p.shadow;
      _animIn = p.animIn;
      _animOut = p.animOut;
      if (selId == null) {
        _position = p.position;
        if (_textController.text.trim().isEmpty) {
          _textController.text = p.sample;
        }
      }
    });
    _commit(provider, selId);
  }

  Widget _buildPresets(VideoEditorProvider provider, String? selId) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = _presets[i];
          TextStyle style;
          try {
            style = GoogleFonts.getFont(p.font,
                fontSize: 17,
                color: p.color,
                fontWeight: p.bold ? FontWeight.bold : FontWeight.normal);
          } catch (_) {
            style = TextStyle(fontSize: 17, color: p.color);
          }
          return GestureDetector(
            onTap: () => _applyPreset(provider, selId, p),
            child: Container(
              width: 104,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.surfaceLighter, AppColors.background],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: p.box == null
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                    decoration: p.box == null
                        ? null
                        : BoxDecoration(
                            color: p.box,
                            borderRadius: BorderRadius.circular(4)),
                    child: Text('Aa',
                        maxLines: 1,
                        style: style.copyWith(
                          shadows: p.outline != null
                              ? [
                                  for (final o in const [
                                    Offset(1, 1),
                                    Offset(-1, -1),
                                    Offset(1, -1),
                                    Offset(-1, 1),
                                  ])
                                    Shadow(offset: o, color: p.outline!),
                                ]
                              : null,
                        )),
                  ),
                  const SizedBox(height: 4),
                  Text(p.name,
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimationRow(VideoEditorProvider provider, String? selId,
      String label, String value, void Function(String) set) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(label,
              style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: TextAnimations.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final (id, name, icon) = TextAnimations.all[i];
                final selected = value == id;
                return GestureDetector(
                  onTap: () {
                    setState(() => set(id));
                    _commit(provider, selId);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                          color:
                              selected ? AppColors.primary : AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(icon,
                            size: 14,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(name,
                            style: TextStyle(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStyleControls(VideoEditorProvider provider, String? selId) {
    Widget toggle(String label, IconData icon, bool on, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: () {
            onTap();
            _commit(provider, selId);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 36,
            decoration: BoxDecoration(
              color: on
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: on ? AppColors.primary : AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 15,
                    color: on ? AppColors.primary : AppColors.textTertiary),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        color: on ? AppColors.primary : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    Widget swatches(
        List<Color> colors, Color? current, void Function(Color) pick) {
      return SizedBox(
        height: 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: colors.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final c = colors[i];
            final selected = current?.toARGB32() == c.toARGB32();
            return GestureDetector(
              onTap: () {
                setState(() => pick(c));
                _commit(provider, selId);
              },
              child: Container(
                width: 30,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.textPrimary : AppColors.border,
                    width: selected ? 2.5 : 1,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            toggle('Box', Icons.rectangle_rounded, _boxColor != null, () {
              setState(() =>
                  _boxColor = _boxColor == null ? _boxColors.first : null);
            }),
            const SizedBox(width: 8),
            toggle('Outline', Icons.border_style_rounded, _outlineColor != null,
                () {
              setState(() => _outlineColor =
                  _outlineColor == null ? _outlineColors.first : null);
            }),
            const SizedBox(width: 8),
            toggle('Shadow', Icons.blur_on_rounded, _shadow, () {
              setState(() => _shadow = !_shadow);
            }),
          ],
        ),
        if (_boxColor != null) ...[
          const SizedBox(height: 8),
          swatches(_boxColors, _boxColor, (c) => _boxColor = c),
        ],
        if (_outlineColor != null) ...[
          const SizedBox(height: 8),
          swatches(_outlineColors, _outlineColor, (c) => _outlineColor = c),
          ModernSlider(
            label: 'Outline width',
            value: _outlineWidth,
            min: 1,
            max: 8,
            divisions: 14,
            onChanged: (v) {
              setState(() => _outlineWidth = v);
              _commit(provider, selId);
            },
          ),
        ],
      ],
    );
  }

  Future<void> _deleteSelectedOverlay(VideoEditorProvider provider) async {
    if (provider.selectedTextOverlayId != null) {
      await provider.removeTextOverlay(provider.selectedTextOverlayId!);
      _textController.clear();
      _lastOverlayId = null;
      provider.clearTextPreview();
    }
  }
}

/// One-tap text look: font, size, colour, box/outline/shadow, animation and
/// placement.
class _TextPreset {
  final String name;
  final String sample;
  final String font;
  final double size;
  final Color color;
  final bool bold;
  final Color? box;
  final Color? outline;
  final double outlineWidth;
  final bool shadow;
  final String animIn;
  final String animOut;
  final Offset position;
  final TextAlign align;

  const _TextPreset({
    required this.name,
    required this.sample,
    required this.font,
    required this.size,
    this.color = Colors.white,
    this.bold = false,
    this.box,
    this.outline,
    this.outlineWidth = 3,
    this.shadow = true,
    this.animIn = 'none',
    this.animOut = 'none',
    required this.position,
    this.align = TextAlign.center,
  });
}
