import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'providers/video_editor_provider.dart';
import 'screens/video_editor_screen.dart';
import 'services/hive_service.dart';
import 'utils/responsive.dart';
import 'splash_screen.dart';
import 'screens/home/home_prefs.dart';
import 'theme/editor_themes.dart';

// Editor colour palette. The values are switched at runtime by
// [AppColors.apply] when the user picks another editor theme in Settings.
class AppColors {
  AppColors._();

  // Core Background Colors
  static Color background = EditorThemeData.premium.background;
  static Color surface = EditorThemeData.premium.surface;
  static Color surfaceLight = EditorThemeData.premium.surfaceLight;
  static Color surfaceLighter = EditorThemeData.premium.surfaceLighter;

  // Accent Colors
  static Color primary = EditorThemeData.premium.primary;
  static Color primaryLight = EditorThemeData.premium.primaryLight;
  static Color primaryDark = EditorThemeData.premium.primaryDark;
  static Color accent = EditorThemeData.premium.accent;

  // Text Colors
  static Color textPrimary = EditorThemeData.premium.textPrimary;
  static Color textSecondary = EditorThemeData.premium.textSecondary;
  static Color textTertiary = EditorThemeData.premium.textTertiary;

  // Border & Divider
  static Color border = EditorThemeData.premium.border;
  static Color borderLight = EditorThemeData.premium.borderLight;

  // Status Colors (shared by every theme)
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Track Colors for Timeline
  static Color videoTrack = EditorThemeData.premium.primary;
  static Color audioTrack = EditorThemeData.premium.audioTrack;
  static Color textTrack = EditorThemeData.premium.textTrack;

  /// The active editor theme; listen to rebuild when it changes.
  static final ValueNotifier<EditorThemeData> theme =
      ValueNotifier(EditorThemeData.premium);

  static void apply(EditorThemeData t) {
    background = t.background;
    surface = t.surface;
    surfaceLight = t.surfaceLight;
    surfaceLighter = t.surfaceLighter;
    primary = t.primary;
    primaryLight = t.primaryLight;
    primaryDark = t.primaryDark;
    accent = t.accent;
    textPrimary = t.textPrimary;
    textSecondary = t.textSecondary;
    textTertiary = t.textTertiary;
    border = t.border;
    borderLight = t.borderLight;
    videoTrack = t.primary;
    audioTrack = t.audioTrack;
    textTrack = t.textTrack;
    theme.value = t;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set premium status bar style
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Fonts in assets/google_fonts are bundled for offline text rendering.
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['google_fonts'],
      'The text fonts bundled in assets/google_fonts (Roboto, Lato, Poppins, '
      'Montserrat, Playfair Display, Oswald and others) are licensed by their '
      'authors under the SIL Open Font License 1.1 or the Apache License 2.0.',
    );
  });

  // Initialize Hive
  await HiveService.init();

  // Restore the chosen editor theme before the first frame.
  try {
    final prefs = await HomePrefs.load();
    AppColors.apply(EditorThemeData.byId(prefs.editorTheme));
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  } catch (_) {}

  unawaited(_playStartupSound());

  runApp(const VideoEditorApp());
}

/// Plays bundled startup audio once; failures are ignored (missing asset, etc.).
Future<void> _playStartupSound() async {
  final player = AudioPlayer();
  try {
    await player.setAsset('assets/audio/audio.mp3');
    await player.play();
    await player.processingStateStream.firstWhere(
      (state) => state == ProcessingState.completed,
    );
  } catch (_) {
    // Ignore: asset absent, or platform cannot play yet.
  } finally {
    await player.dispose();
  }
}

class VideoEditorApp extends StatefulWidget {
  const VideoEditorApp({super.key});

  @override
  State<VideoEditorApp> createState() => _VideoEditorAppState();
}

class _VideoEditorAppState extends State<VideoEditorApp> {
  @override
  void initState() {
    super.initState();
    AppColors.theme.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppColors.theme.removeListener(_onThemeChanged);
    super.dispose();
  }

  /// Applies a new editor theme everywhere without restarting the app:
  /// the MaterialApp theme is rebuilt, and because many widgets read
  /// [AppColors] directly, every element is marked for rebuild once.
  void _onThemeChanged() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => VideoEditorProvider(),
      child: MaterialApp(
        title: 'Studio V',
        debugShowCheckedModeBanner: false,
        theme: _buildPremiumDarkTheme(),
        initialRoute: '/',
        routes: {
          '/': (context) => SplashScreen(),
          '/home': (context) => ResponsiveBuilder(
                builder: (context) => const VideoEditorScreen(),
              ),
        },
      ),
    );
  }

  ThemeData _buildPremiumDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryDark,
        secondary: AppColors.accent,
        secondaryContainer: AppColors.primaryLight,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.textPrimary,
        onSecondary: AppColors.textPrimary,
        onSurface: AppColors.textPrimary,
        onError: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.background,

      // AppBar Theme - Minimal and clean
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: AppColors.textPrimary,
        ),
        iconTheme: IconThemeData(
          color: AppColors.textSecondary,
          size: 20,
        ),
      ),

      // Elevated Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 36),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
      ),

      // Text Button Theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 32),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),

      // Icon Theme
      iconTheme: IconThemeData(
        color: AppColors.textSecondary,
        size: 20,
      ),

      // Slider Theme - Refined and minimal
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.border,
        thumbColor: AppColors.textPrimary,
        overlayColor: AppColors.primary.withOpacity(0.15),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLighter,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 13,
        ),
        labelStyle: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
      ),

      // Divider Theme
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // Text Theme - Refined typography
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        displaySmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        headlineLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: AppColors.textTertiary,
        ),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: 0.3,
        ),
        labelMedium: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.textTertiary,
          letterSpacing: 0.3,
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border, width: 1),
        ),
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),

      // Bottom Sheet Theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),

      // Snackbar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceLighter,
        contentTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Tooltip Theme
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceLighter,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // Popup Menu Theme
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.border),
        ),
        textStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
        ),
      ),
    );
  }
}
