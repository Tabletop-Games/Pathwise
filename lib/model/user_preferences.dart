enum PathwiseTheme {
  field('Field'),
  blackwater('Blackwater'),
  terracotta('Terracotta'),
  forestMint('Forest Mint'),
  midnightSlate('Midnight Slate'),
  royalVelvet('Royal Velvet'),
  warmWalnut('Warm Walnut'),
  glacier('Winter Glacier'),
  oceanicBreeze('Oceanic Breeze'),
  chalk('Chalk'),
  amoledCarbon('AMOLED Carbon'),
  canyon('Painted Canyon'),
  neon('Night Signal'),
  tidal('Tidal Glass'),
  parchment('Parchment'),
  violet('Lavender Hour'),
  koi('Koi Pond'),
  crt('Retro Terminal'),
  gilded('Gilded Ink'),
  signal('High Contrast'),
  basinGold('Basin Gold'),
  copperSky('Copper Sky'),
  highPass('High Pass');

  const PathwiseTheme(this.label);
  final String label;
}

class UserPreferences {
  UserPreferences({
    this.theme = PathwiseTheme.field,
    this.haptics = true,
    this.suggestSharing = true,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        theme: PathwiseTheme.values.firstWhere(
          (theme) => theme.name == json['theme'],
          orElse: () => PathwiseTheme.field,
        ),
        haptics: json['haptics'] != false,
        suggestSharing: json['suggestSharing'] != false,
      );

  PathwiseTheme theme;
  bool haptics;
  bool suggestSharing;

  Map<String, Object> toJson() => {
    'theme': theme.name,
    'haptics': haptics,
    'suggestSharing': suggestSharing,
  };
}
