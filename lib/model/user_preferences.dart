enum PathwiseTheme {
  field('Field'),
  blackwater('Blackwater'),
  terracotta('Terracotta'),
  forestMint('Forest Mint'),
  midnightSlate('Midnight Slate'),
  royalVelvet('Royal Velvet'),
  warmWalnut('Warm Walnut'),
  glacier('Winter Glacier'),
  oceanicBreeze('Oceanic Breeze');

  const PathwiseTheme(this.label);
  final String label;
}

class UserPreferences {
  UserPreferences({this.theme = PathwiseTheme.field, this.haptics = true});

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        theme: PathwiseTheme.values.firstWhere(
          (theme) => theme.name == json['theme'],
          orElse: () => PathwiseTheme.field,
        ),
        haptics: json['haptics'] != false,
      );

  PathwiseTheme theme;
  bool haptics;

  Map<String, Object> toJson() => {'theme': theme.name, 'haptics': haptics};
}
