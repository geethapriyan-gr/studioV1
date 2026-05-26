/// Enum for managing the current editor panel mode
/// This replaces multiple showX boolean flags
enum EditorPanelMode {
  /// No panel is currently shown
  none,

  /// Timeline view is shown
  timeline,

  /// Filter editor is shown
  filters,

  /// Text overlay editor is shown
  text,

  /// Audio overlay editor is shown
  audio,

  /// Crop/rotate editor is shown
  cropRotate,

  /// Trim editor is shown
  trim,

  /// Chroma key (green screen) editor is shown
  chromaKey,
}
