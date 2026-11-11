import 'package:flutter/material.dart';

import 'sure_colors.dart';
import 'sure_tokens.dart';

class SureTheme {
  const SureTheme._();

  static ThemeData get light => _build(SureTokens.light, Brightness.light);

  static ThemeData get dark => _build(SureTokens.dark, Brightness.dark);

  /// Top corner radius of bottom sheets.
  static const double sheetRadius = 16;

  static ThemeData _build(SureTokenPalette tokens, Brightness brightness) {
    final colors = SureColors(tokens);
    final hairline = colors.hairline;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: tokens.link,
      onPrimary: tokens.textInverse,
      // The container roles were unset, so on screens not yet redesigned with
      // SureColors (e.g. Chats) Material defaulted them to a blue that read as
      // off-brand on FAB/badge/avatar surfaces. Pin them to a neutral Sure
      // surface with primary text on top. `primary`/`secondary` stay link/info so
      // existing link/accent callers are unchanged; the prominent neutral primary
      // action color is applied to FABs via floatingActionButtonTheme below.
      primaryContainer: tokens.surfaceInset,
      onPrimaryContainer: tokens.textPrimary,
      secondary: tokens.info,
      onSecondary: tokens.textInverse,
      secondaryContainer: tokens.surfaceInset,
      onSecondaryContainer: tokens.textPrimary,
      error: tokens.destructive,
      onError: tokens.textInverse,
      errorContainer: tokens.destructiveSubtle,
      onErrorContainer: tokens.textPrimary,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
      onSurfaceVariant: tokens.textSecondary,
      // Material 3 tints elevated surfaces with `surfaceTint` and picks menu,
      // dialog and sheet fills from the surfaceContainer ramp. Pin the ramp to
      // the flat Sure panel color and turn the tint off, so nothing picks up a
      // colored cast as it gains elevation.
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: tokens.container,
      surfaceContainerLow: tokens.container,
      surfaceContainer: tokens.container,
      surfaceContainerHigh: tokens.container,
      surfaceContainerHighest: tokens.containerInset,
      outline: tokens.borderSecondary,
      outlineVariant: hairline,
      shadow: tokens.shadow,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(SureTokens.radiusLg),
      borderSide: BorderSide(color: tokens.borderSecondary),
    );

    final base = ThemeData(
      fontFamily: SureTokens.fontSans,
      fontFamilyFallback: SureTokens.fontFallback,
      colorScheme: colorScheme,
      // Pages sit on `surface`; panels and cards on `container`.
      scaffoldBackgroundColor: tokens.surface,
      canvasColor: tokens.surface,
      dividerColor: hairline,
      useMaterial3: true,
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        // No M3 "scrolled under" color change: the bar stays the page color.
        scrolledUnderElevation: 0,
        backgroundColor: tokens.surface,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: tokens.container,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SureTokens.radiusLg),
          side: BorderSide(color: hairline),
        ),
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface,
        modalBackgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
        ),
        clipBehavior: Clip.antiAlias,
        // Sheets that ask for Material's drag handle get the iOS grabber look.
        dragHandleColor: tokens.textSubdued.withValues(alpha: 0.5),
        dragHandleSize: const Size(36, 5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.container,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.container,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SureTokens.radiusLg),
          side: BorderSide(color: hairline),
        ),
      ),
      // NavigationBar is replaced by SureTabBar in the shell; if one is used
      // anywhere else it gets no indicator pill and no tint either.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: tokens.borderPrimary),
        ),
        filled: true,
        fillColor: tokens.container,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: tokens.buttonPrimary,
          foregroundColor: tokens.textInverse,
          disabledBackgroundColor: tokens.containerInset,
          disabledForegroundColor: tokens.textSubdued,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SureTokens.radiusLg),
          ),
        ),
      ),
      // The FAB is Sure's primary action surface — use the neutral brand primary
      // (near-black in light, white in dark) so it reads as the prominent action
      // instead of the subtle primaryContainer the Material 3 default would use.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.buttonPrimary,
        foregroundColor: tokens.textInverse,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: tokens.textPrimary,
        displayColor: tokens.textPrimary,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        bodyColor: tokens.textPrimary,
        displayColor: tokens.textPrimary,
      ),
    );
  }
}
