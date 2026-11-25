import 'economy.dart';
import 'progression.dart';
import 'user_preferences.dart';

const chapterSize = 25;
const discoveryInterval = 10;
const chapterRewardCoins = 25;
const chapterRewardHints = 1;
const discoveryFallbackCoins = 25;
const accessibleMultiplier = 3;
const multiplierRegions = <(double, int)>[
  (.24, 2),
  (.45, 3),
  (.55, 4),
  (.76, 3),
  (1, 2),
];

int multiplierAt(double position) {
  final clamped = position.clamp(0.0, 1.0);
  return multiplierRegions.firstWhere((region) => clamped <= region.$1).$2;
}

int chapterFor(int level) => (level - 1) ~/ chapterSize;

const _landscapes = [
  'First Light',
  'Quiet Grove',
  'Still Waters',
  'Fern Hollow',
  'Cloud Terrace',
  'Copper Dunes',
  'Evening Ridge',
  'Northern Sky',
];
const _seasons = ['Arrival', 'Drift', 'Echo', 'Return', 'Horizon'];

String chapterName(int chapter) {
  final landscape = _landscapes[chapter % _landscapes.length];
  final season = _seasons[chapter ~/ _landscapes.length % _seasons.length];
  if (chapter < _landscapes.length) return landscape;
  final volume = chapter ~/ (_landscapes.length * _seasons.length);
  return volume == 0
      ? '$landscape · $season'
      : '$landscape · $season ${volume + 1}';
}

int chapterEnd(int chapter) => (chapter + 1) * chapterSize;

enum MysteryCategory { coins, boost, tip, theme }

/// Base category weights for Economy 2.0 mystery rewards.
const mysteryCategoryWeights = <MysteryCategory, int>{
  MysteryCategory.coins: 40,
  MysteryCategory.boost: 30,
  MysteryCategory.tip: 20,
  MysteryCategory.theme: 10,
};

/// Weighted coin reward sizes (EV = 38.25 coins).
const mysteryCoinWeights = <({int coins, int weight})>[
  (coins: 25, weight: 50),
  (coins: 40, weight: 30),
  (coins: 60, weight: 15),
  (coins: 100, weight: 5),
];

/// Weighted boost reward tiers.
const mysteryBoostWeights = <({Boost boost, int weight})>[
  (boost: Boost.doubleTen, weight: 45),
  (boost: Boost.doubleSixty, weight: 25),
  (boost: Boost.tripleFifteen, weight: 20),
  (boost: Boost.quadrupleTen, weight: 10),
];

int mysteryTipWeight(PathTip tip) => switch (tip.price) {
  <= 0 => 0,
  <= 120 => 10,
  <= 250 => 5,
  <= 500 => 2,
  _ => 1,
};

int mysteryThemeWeight(PathwiseTheme theme) {
  final price = economy.themePrice(theme);
  if (price <= 0) return 0;
  if (price <= 220) return 10;
  if (price <= 1000) return 5;
  if (price <= 4500) return 2;
  return 1;
}

int _deterministicMix(int seed, int salt) {
  var x = (seed ^ (salt * 0x9E3779B1)) & 0x7FFFFFFF;
  x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0x7FFFFFFF;
  x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0x7FFFFFFF;
  return (x ^ (x >> 16)) & 0x7FFFFFFF;
}

T _pickWeighted<T>(List<({T item, int weight})> options, int seed, int salt) {
  final total = options.fold<int>(0, (sum, entry) => sum + entry.weight);
  var roll = _deterministicMix(seed, salt) % total;
  for (final entry in options) {
    if (roll < entry.weight) return entry.item;
    roll -= entry.weight;
  }
  return options.last.item;
}

/// Deterministically selects the mystery reward for [cycle] given current
/// cosmetic ownership and entitlements. Never uses wall-clock or unseeded RNG.
Discovery selectMysteryReward({
  required int cycle,
  required Set<PathTip> ownedTips,
  required Set<PathwiseTheme> ownedThemes,
  required bool hasThemePass,
  int salt = 0,
}) {
  final eligibleTips = [
    for (final tip in PathTip.values)
      if (tip.price > 0 && !ownedTips.contains(tip))
        (item: tip, weight: mysteryTipWeight(tip)),
  ];
  final eligibleThemes = hasThemePass
      ? <({PathwiseTheme item, int weight})>[]
      : [
          for (final theme in PathwiseTheme.values)
            if (economy.themePrice(theme) > 0 && !ownedThemes.contains(theme))
              (item: theme, weight: mysteryThemeWeight(theme)),
        ];

  final categories = <({MysteryCategory item, int weight})>[
    (
      item: MysteryCategory.coins,
      weight: mysteryCategoryWeights[MysteryCategory.coins]!,
    ),
    (
      item: MysteryCategory.boost,
      weight: mysteryCategoryWeights[MysteryCategory.boost]!,
    ),
    if (eligibleTips.isNotEmpty)
      (
        item: MysteryCategory.tip,
        weight: mysteryCategoryWeights[MysteryCategory.tip]!,
      ),
    if (eligibleThemes.isNotEmpty)
      (
        item: MysteryCategory.theme,
        weight: mysteryCategoryWeights[MysteryCategory.theme]!,
      ),
  ];

  final category = _pickWeighted(categories, cycle, 1 + salt);
  final item = switch (category) {
    MysteryCategory.coins =>
      'coins/${_pickWeighted([for (final entry in mysteryCoinWeights) (item: entry.coins, weight: entry.weight)], cycle, 2 + salt)}',
    MysteryCategory.boost =>
      'boost/${_pickWeighted([for (final entry in mysteryBoostWeights) (item: entry.boost.name, weight: entry.weight)], cycle, 3 + salt)}',
    MysteryCategory.tip =>
      'tip/${_pickWeighted(eligibleTips, cycle, 4 + salt).name}',
    MysteryCategory.theme =>
      'theme/${_pickWeighted(eligibleThemes, cycle, 5 + salt).name}',
  };
  return Discovery(cycle, item);
}

class Discovery {
  const Discovery(this.number, this.item);
  final int number;
  final String item;
  static const fallback = 'coins';

  bool get isCoins => item == fallback || item.startsWith('coins/');
  bool get isBoost => item.startsWith('boost/');
  bool get isTip => item.startsWith('tip/');
  bool get isTheme => item.startsWith('theme/');
  String get cosmeticId => item.split('/').last;

  int get coinAmount {
    if (item == fallback) return discoveryFallbackCoins;
    if (!item.startsWith('coins/')) return 0;
    return int.tryParse(item.split('/').last) ?? discoveryFallbackCoins;
  }

  Boost? get boost {
    if (!isBoost) return null;
    final id = item.split('/').last;
    for (final value in Boost.values) {
      if (value.name == id) return value;
    }
    return null;
  }

  PathTip? get tip {
    if (!isTip) return null;
    return PathTip.fromId(cosmeticId);
  }

  PathwiseTheme? get theme {
    if (!isTheme) return null;
    final id = cosmeticId;
    for (final value in PathwiseTheme.values) {
      if (value.name == id) return value;
    }
    return null;
  }

  String get displayName {
    if (isCoins) return '$coinAmount coins';
    if (boost case final b?) return '${b.multiplier}× ${b.title}';
    if (tip case final t?) return t.label;
    if (theme case final th?) return th.name;
    return item;
  }

  String get categoryLabel {
    if (isCoins) return 'Coin pouch';
    if (isBoost) return 'Coin boost';
    if (isTip) return 'Path tip';
    if (isTheme) return 'Theme';
    return 'Mystery reward';
  }
}
