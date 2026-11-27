import 'notification_preferences.dart';

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
    this.soundEnabled = true,
    double soundVolume = 0.75,
    this.suggestSharing = true,
    NotificationPreferences? notifications,
  }) : soundVolume = soundVolume.clamp(0.0, 1.0).toDouble(),
       notifications = notifications ?? NotificationPreferences();

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    final rawVolume = json['soundVolume'];
    final parsedVolume = rawVolume is num ? rawVolume.toDouble() : 0.75;
    final rawNotif = json['notifications'];
    return UserPreferences(
      theme: PathwiseTheme.values.firstWhere(
        (theme) => theme.name == json['theme'],
        orElse: () => PathwiseTheme.field,
      ),
      haptics: json['haptics'] != false,
      soundEnabled: json['soundEnabled'] != false,
      soundVolume: parsedVolume.isFinite
          ? parsedVolume.clamp(0.0, 1.0).toDouble()
          : 0.75,
      suggestSharing: json['suggestSharing'] != false,
      notifications: rawNotif is Map<String, dynamic>
          ? NotificationPreferences.fromJson(rawNotif)
          : NotificationPreferences(),
    );
  }

  PathwiseTheme theme;
  bool haptics;
  bool soundEnabled;
  double soundVolume;
  bool suggestSharing;
  NotificationPreferences notifications;

  Map<String, Object> toJson() => {
    'theme': theme.name,
    'haptics': haptics,
    'soundEnabled': soundEnabled,
    'soundVolume': soundVolume,
    'suggestSharing': suggestSharing,
    'notifications': notifications.toJson(),
  };
}
