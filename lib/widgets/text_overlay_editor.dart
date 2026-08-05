import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';
import '../main.dart' show AppColors;
import 'modern_slider.dart';

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
  bool _hasOutline = false;
  bool _hasShadow = false;

  // Font family options from Google Fonts
  final Map<String, TextStyle Function()> _fontFamilies = {
    'Roboto': () => GoogleFonts.roboto(),
    'Averia Libre': () => GoogleFonts.averiaLibre(),
    'Lato': () => GoogleFonts.lato(),
    'Comic Neue': () => GoogleFonts.comicNeue(),
    'Actor': () => GoogleFonts.actor(),
    'Odor Mean Chey': () => GoogleFonts.odorMeanChey(),
    'Nabla': () => GoogleFonts.nabla(),
  };

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
                (currentOverlay.endTime - currentOverlay.startTime)
                    .inSeconds
                    .toDouble()
                    .clamp(1.0, 60.0);
            provider.clearTextPreview();
          } else {
            _textController.clear();
            _fontSize = 250.0;
            _textColor = Colors.white;
            _selectedFontFamily = 'Roboto';
            _isBold = false;
            _isItalic = false;
            _textAlign = TextAlign.center;
            _hasOutline = false;
            _hasShadow = false;
            _durationSeconds = 3.0;
            provider.clearTextPreview();
          }
          _lastOverlayId = selId;
        }

        return Container(
          decoration: const BoxDecoration(
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
                          decoration: const InputDecoration(
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
                              provider.setTextPreview(
                                val,
                                _fontSize,
                                _textColor,
                                fontFamily: _selectedFontFamily,
                                fontWeight: _isBold
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontStyle: _isItalic
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                textAlign: _textAlign,
                              );
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

                const SizedBox(height: 16),

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
                            provider.setTextPreview(
                              _textController.text,
                              _fontSize,
                              _textColor,
                              fontFamily: styleLabel,
                              fontWeight:
                                  _isBold ? FontWeight.bold : FontWeight.normal,
                              fontStyle: _isItalic
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              textAlign: _textAlign,
                            );
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
                    const Padding(
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
                                provider.setTextPreview(
                                  _textController.text,
                                  _fontSize,
                                  color,
                                  fontFamily: _selectedFontFamily,
                                  fontWeight: _isBold
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontStyle: _isItalic
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  textAlign: _textAlign,
                                );
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
                            provider.setTextPreview(
                              _textController.text,
                              _fontSize,
                              _textColor,
                              fontFamily: _selectedFontFamily,
                              fontWeight:
                                  _isBold ? FontWeight.bold : FontWeight.normal,
                              fontStyle: _isItalic
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              textAlign: _textAlign,
                            );
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
                            provider.setTextPreview(
                              _textController.text,
                              _fontSize,
                              _textColor,
                              fontFamily: _selectedFontFamily,
                              fontWeight:
                                  _isBold ? FontWeight.bold : FontWeight.normal,
                              fontStyle: _isItalic
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              textAlign: _textAlign,
                            );
                          }
                        },
                      ),

                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Font Size Slider
                ModernSlider(
                  label: 'Font size',
                  value: _fontSize,
                  min: 10,
                  max: 1000,
                  divisions: 100,
                  onChanged: (v) {
                    setState(() => _fontSize = v);
                    if (selId != null) {
                      _updateSelectedOverlay(provider);
                    } else {
                      provider.setTextPreview(
                        _textController.text,
                        v,
                        _textColor,
                        fontFamily: _selectedFontFamily,
                        fontWeight:
                            _isBold ? FontWeight.bold : FontWeight.normal,
                        fontStyle:
                            _isItalic ? FontStyle.italic : FontStyle.normal,
                        textAlign: _textAlign,
                      );
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
                    if (selId != null) _updateSelectedOverlay(provider);
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
    final end = start + Duration(seconds: _durationSeconds.toInt());
    await provider.addTextOverlay(
      text: _textController.text,
      position: const Offset(0.5, 0.5),
      startTime: start,
      endTime: end,
      fontSize: _fontSize,
      color: _textColor,
      fontFamily: _selectedFontFamily,
      fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
      textAlign: _textAlign,
    );
    _textController.clear();
    provider.clearTextPreview();
    provider.toggleTimeline();
  }

  Future<void> _updateSelectedOverlay(VideoEditorProvider provider) async {
    final selId = provider.selectedTextOverlayId;
    if (selId == null) return;
    final exists =
        provider.currentProject?.textOverlays.any((o) => o.id == selId) ??
            false;
    if (!exists) return;
    final overlay =
        provider.currentProject!.textOverlays.firstWhere((o) => o.id == selId);
    final newEnd =
        overlay.startTime + Duration(seconds: _durationSeconds.toInt());
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
