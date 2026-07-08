import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // ── Brand ──────────────────────────────────────────────────────────────────
  // "Sovereign Security" palette: near-black CTAs, cerulean accents,
  // white/slate neutrals. No pure #000000 (framework rule).
  static const primary      = Color(0xFF0F172A); // gray-900 — buttons, CTAs
  static const primaryLight = Color(0xFF109DD7); // cerulean — accents, links, scan overlays
  static const primaryDark  = Color(0xFF0A6A94); // deep cerulean — text on tint surfaces
  static const primaryTint  = Color(0xFFE3F4FC); // cerulean tint — chips, indicators
  static const accent       = primaryLight;

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const success      = Color(0xFF16A34A);
  static const successLight = Color(0xFFDCFCE7);
  static const warning      = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFEF3C7);
  static const error        = Color(0xFFDC2626);
  static const errorLight   = Color(0xFFFEE2E2);

  // ── Neutrals ───────────────────────────────────────────────────────────────
  static const background    = Color(0xFFF5F7FA);
  static const surface       = Color(0xFFFFFFFF);
  static const surfaceAlt    = Color(0xFFF8FAFC);
  static const textPrimary   = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const textHint      = Color(0xFF94A3B8);
  static const divider       = Color(0xFFE2E8F0);

  // Legacy alias used across screens
  static const secondary = primaryTint;
}

class AppColorsDark {
  static const background    = Color(0xFF0F172A);
  static const surface       = Color(0xFF1E293B);
  static const surfaceAlt    = Color(0xFF253350);
  static const textPrimary   = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textHint      = Color(0xFF64748B);
  static const divider       = Color(0xFF334155);
}

class AppTheme {
  // ── Light theme ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    const scheme = ColorScheme.light(
      primary:              AppColors.primary,
      onPrimary:            Colors.white,
      primaryContainer:     AppColors.primaryTint,
      onPrimaryContainer:   AppColors.primaryDark,
      secondary:            AppColors.primaryLight,
      onSecondary:          Colors.white,
      secondaryContainer:   AppColors.primaryTint,
      onSecondaryContainer: AppColors.primary,
      surface:              AppColors.surface,
      onSurface:            AppColors.textPrimary,
      onSurfaceVariant:     AppColors.textSecondary,
      error:                AppColors.error,
      onError:              Colors.white,
      outline:              AppColors.divider,
      outlineVariant:       Color(0xFFF1F5F9),
      surfaceContainerLow:  AppColors.background,
      surfaceContainer:     AppColors.surfaceAlt,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryTint,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary, size: 24);
          }
          return const IconThemeData(color: AppColors.textSecondary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary);
          }
          return const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary);
        }),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black12,
        elevation: 8,
      ),
      textTheme: const TextTheme(
        displaySmall:  TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        headlineSmall:  TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        titleMedium:    TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        titleSmall:     TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        bodyLarge:      TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.5),
        bodyMedium:     TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5),
        labelMedium:    TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 56),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border:       OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        errorBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 2)),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        hintStyle:  const TextStyle(color: AppColors.textHint, fontSize: 14),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
        elevation: 4,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        contentTextStyle: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
    );
  }

  // ── Dark theme ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      primary:              AppColors.primaryLight,
      onPrimary:            Colors.white,
      primaryContainer:     Color(0xFF0E3A50),
      onPrimaryContainer:   AppColors.primaryLight,
      secondary:            AppColors.primaryLight,
      onSecondary:          Colors.white,
      secondaryContainer:   Color(0xFF0E3A50),
      onSecondaryContainer: AppColors.primaryLight,
      surface:              AppColorsDark.surface,
      onSurface:            AppColorsDark.textPrimary,
      onSurfaceVariant:     AppColorsDark.textSecondary,
      error:                AppColors.error,
      onError:              Colors.white,
      outline:              AppColorsDark.divider,
      outlineVariant:       AppColorsDark.surfaceAlt,
      surfaceContainerLow:  AppColorsDark.background,
      surfaceContainer:     AppColorsDark.surfaceAlt,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColorsDark.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColorsDark.surface,
        foregroundColor: AppColorsDark.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: AppColorsDark.textPrimary, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        iconTheme: IconThemeData(color: AppColorsDark.textPrimary, size: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColorsDark.surface,
        indicatorColor: const Color(0xFF0E3A50),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primaryLight, size: 24);
          }
          return IconThemeData(color: AppColorsDark.textSecondary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryLight);
          }
          return TextStyle(
            fontSize: 11, fontWeight: FontWeight.w500, color: AppColorsDark.textSecondary);
        }),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
      ),
      textTheme: const TextTheme(
        displaySmall:   TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w800, color: AppColorsDark.textPrimary, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: AppColorsDark.textPrimary),
        headlineSmall:  TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700, color: AppColorsDark.textPrimary),
        titleMedium:    TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: AppColorsDark.textPrimary),
        titleSmall:     TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppColorsDark.textPrimary),
        bodyLarge:      TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w400, color: AppColorsDark.textPrimary, height: 1.5),
        bodyMedium:     TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, color: AppColorsDark.textSecondary, height: 1.5),
        labelMedium:    TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: AppColorsDark.textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorsDark.textPrimary,
          foregroundColor: AppColors.primary,
          disabledBackgroundColor: AppColorsDark.textPrimary.withValues(alpha: 0.40),
          disabledForegroundColor: AppColors.primary.withValues(alpha: 0.60),
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          minimumSize: const Size(double.infinity, 56),
          side: const BorderSide(color: AppColors.primaryLight, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColorsDark.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border:       OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColorsDark.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColorsDark.divider, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryLight, width: 2)),
        errorBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 2)),
        labelStyle: const TextStyle(color: AppColorsDark.textSecondary, fontSize: 14),
        hintStyle:  const TextStyle(color: AppColorsDark.textHint, fontSize: 14),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
      cardTheme: CardThemeData(
        color: AppColorsDark.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColorsDark.divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColorsDark.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
        elevation: 4,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColorsDark.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColorsDark.textPrimary),
        contentTextStyle: TextStyle(fontSize: 14, color: AppColorsDark.textSecondary, height: 1.5),
      ),
      dividerTheme: const DividerThemeData(color: AppColorsDark.divider, thickness: 1, space: 1),
    );
  }

  // Backward-compat alias
  static ThemeData get theme => lightTheme;
}

// ── Context-aware color resolver ─────────────────────────────────────────────
//
// Usage: final c = Ct(context);  then  c.background, c.surface, etc.
// Reads the current brightness so all screens adapt to dark mode automatically.

class Ct {
  final BuildContext _ctx;
  const Ct(this._ctx);

  bool get _dark => Theme.of(_ctx).brightness == Brightness.dark;

  Color get background    => _dark ? AppColorsDark.background    : AppColors.background;
  Color get surface       => _dark ? AppColorsDark.surface       : AppColors.surface;
  Color get surfaceAlt    => _dark ? AppColorsDark.surfaceAlt    : AppColors.surfaceAlt;
  Color get textPrimary   => _dark ? AppColorsDark.textPrimary   : AppColors.textPrimary;
  Color get textSecondary => _dark ? AppColorsDark.textSecondary : AppColors.textSecondary;
  Color get textHint      => _dark ? AppColorsDark.textHint      : AppColors.textHint;
  Color get divider       => _dark ? AppColorsDark.divider       : AppColors.divider;
}

// ── Shared shadow tokens ───────────────────────────────────────────────────────

class AppShadows {
  static List<BoxShadow> get card => [
        BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
      ];

  static List<BoxShadow> get button => [
        BoxShadow(color: AppColors.primary.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 6)),
      ];

  static List<BoxShadow> get elevated => [
        BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 8)),
      ];
}
