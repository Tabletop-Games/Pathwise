import 'package:material_ui/material_ui.dart';

import 'user_preferences.dart';

final class BoardPalette {
  const BoardPalette({
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.tile,
    required this.covered,
    required this.route,
    required this.onRoute,
    required this.accent,
    required this.onAccent,
    this.dark = false,
  });

  final Color canvas, surface, ink, muted, tile, covered;
  final Color route, onRoute, accent, onAccent;
  final bool dark;

  static const palettes = {
    PathwiseTheme.field: BoardPalette(
      canvas: Color(0xfff1efe2),
      surface: Color(0xfffffdf2),
      ink: Color(0xff172b23),
      muted: Color(0xff505e51),
      tile: Color(0xffe4e7d7),
      covered: Color(0xffc5dbbc),
      route: Color(0xff265c48),
      onRoute: Color(0xffffffff),
      accent: Color(0xfff3ca67),
      onAccent: Color(0xff342b17),
    ),
    PathwiseTheme.blackwater: BoardPalette(
      canvas: Color(0xff131f27),
      surface: Color(0xff1c2b34),
      ink: Color(0xfff1f6f3),
      muted: Color(0xffb5c9cb),
      tile: Color(0xff2b404c),
      covered: Color(0xff345759),
      route: Color(0xff98dabe),
      onRoute: Color(0xff152923),
      accent: Color(0xffe7be76),
      onAccent: Color(0xff372b1b),
      dark: true,
    ),
    PathwiseTheme.terracotta: BoardPalette(
      canvas: Color(0xfff8eadd),
      surface: Color(0xfffff5ea),
      ink: Color(0xff45291f),
      muted: Color(0xff735748),
      tile: Color(0xffefdaca),
      covered: Color(0xffebc1a8),
      route: Color(0xff9a442c),
      onRoute: Color(0xfffff6ed),
      accent: Color(0xfff6c872),
      onAccent: Color(0xff402a18),
    ),
  };

  ThemeData get theme {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: route,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: route,
          onPrimary: onRoute,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          secondaryContainer: accent,
          onSecondaryContainer: onAccent,
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Bricolage',
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
    );
  }
}
