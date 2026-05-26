import 'dart:async';
import 'dart:ui' as ui;

class TransitionShaderService {
  static final Map<String, ui.FragmentProgram> _compiledShaders = {};
  static final Completer<void> _initCompleter = Completer<void>();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) {
      return _initCompleter.future;
    }

    try {
      await _compileAllShaders();
      _initialized = true;
      _initCompleter.complete();
    } catch (e) {
      _initCompleter.completeError(e);
      rethrow;
    }
  }

  static Future<void> _compileAllShaders() async {
    await Future.wait([
      _compileShader('assets/shaders/crossfade.frag'),
      _compileShader('assets/shaders/zoom.frag'),
      _compileShader('assets/shaders/blur.frag'),
      _compileShader('assets/shaders/shake.frag'),
      _compileShader('assets/shaders/glitch.frag'),
      _compileShader('assets/shaders/flash.frag'),
      _compileShader('assets/shaders/chroma_key.frag'),
    ]);
  }

  static Future<void> _compileShader(String shaderPath) async {
    try {
      final program = await ui.FragmentProgram.fromAsset(shaderPath);
      _compiledShaders[shaderPath] = program;
    } catch (e) {
      print('Failed to compile shader $shaderPath: $e');
    }
  }

  static Future<ui.FragmentProgram?> getShader(String shaderPath) async {
    if (!_initialized) {
      await initialize();
    }

    if (_compiledShaders.containsKey(shaderPath)) {
      return _compiledShaders[shaderPath];
    }

    try {
      await _compileShader(shaderPath);
      return _compiledShaders[shaderPath];
    } catch (e) {
      print('Failed to get shader $shaderPath: $e');
      return null;
    }
  }

  static bool isShaderAvailable(String shaderPath) {
    return _compiledShaders.containsKey(shaderPath);
  }

  static void dispose() {
    _compiledShaders.clear();
    _initialized = false;
  }
}
