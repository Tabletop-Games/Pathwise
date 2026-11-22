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
    PathwiseTheme.forestMint: BoardPalette(
      canvas: Color(0xffeff6ef),
      surface: Color(0xfffafff8),
      ink: Color(0xff163127),
      muted: Color(0xff425c50),
      tile: Color(0xffdcecdf),
      covered: Color(0xffb9dbca),
      route: Color(0xff24664e),
      onRoute: Color(0xffffffff),
      accent: Color(0xffead47d),
      onAccent: Color(0xff302700),
    ),
    PathwiseTheme.midnightSlate: BoardPalette(
      canvas: Color(0xff121721),
      surface: Color(0xff222a37),
      ink: Color(0xfff2f6ff),
      muted: Color(0xffb6c5dc),
      tile: Color(0xff303b50),
      covered: Color(0xff415470),
      route: Color(0xffa5c5ff),
      onRoute: Color(0xff162840),
      accent: Color(0xfff1d287),
      onAccent: Color(0xff31260e),
      dark: true,
    ),
    PathwiseTheme.royalVelvet: BoardPalette(
      canvas: Color(0xff251525),
      surface: Color(0xff352036),
      ink: Color(0xfffff5fc),
      muted: Color(0xffe1bed8),
      tile: Color(0xff512e4d),
      covered: Color(0xff63395f),
      route: Color(0xfff3adcf),
      onRoute: Color(0xff361529),
      accent: Color(0xfff1ce82),
      onAccent: Color(0xff322611),
      dark: true,
    ),
    PathwiseTheme.warmWalnut: BoardPalette(
      canvas: Color(0xfff1e8db),
      surface: Color(0xfffffbf1),
      ink: Color(0xff3d291c),
      muted: Color(0xff65503f),
      tile: Color(0xffe6d5be),
      covered: Color(0xffd7bd98),
      route: Color(0xff76462c),
      onRoute: Color(0xfffffaf0),
      accent: Color(0xffeac174),
      onAccent: Color(0xff39250a),
    ),
    PathwiseTheme.glacier: BoardPalette(
      canvas: Color(0xffedf5fa),
      surface: Color(0xfff8fcff),
      ink: Color(0xff163442),
      muted: Color(0xff425d6e),
      tile: Color(0xffd6e9f3),
      covered: Color(0xffa9d1e8),
      route: Color(0xff1b5d82),
      onRoute: Color(0xffffffff),
      accent: Color(0xfff6ce72),
      onAccent: Color(0xff362b15),
    ),
    PathwiseTheme.oceanicBreeze: BoardPalette(
      canvas: Color(0xff10272c),
      surface: Color(0xff1a3538),
      ink: Color(0xffebfcf6),
      muted: Color(0xffa8d1c9),
      tile: Color(0xff24484a),
      covered: Color(0xff396461),
      route: Color(0xff8ee5cf),
      onRoute: Color(0xff142925),
      accent: Color(0xfff2cf88),
      onAccent: Color(0xff382c16),
      dark: true,
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
