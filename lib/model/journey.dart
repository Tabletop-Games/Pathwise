const chapterSize = 25;
const discoveryInterval = 10;
const chapterRewardCoins = 25;
const chapterRewardHints = 1;
const discoveryFallbackCoins = 20;
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

const discoveryCatalogue = [
  'tip/arrow',
  'theme/forestMint',
  'tip/crystal',
  'theme/warmWalnut',
  'tip/star',
  'theme/glacier',
  'tip/cat',
  'theme/midnightSlate',
  'tip/dog',
  'tip/rabbit',
  'tip/fox',
  'tip/panda',
  'tip/frog',
  'tip/penguin',
  'tip/turtle',
  'tip/bee',
  'tip/ghost',
  'tip/robot',
  'tip/ufo',
  'tip/flame',
  'tip/dragon',
  'tip/phoenix',
  'tip/rocket',
];

class Discovery {
  const Discovery(this.number, this.item);
  final int number;
  final String item;
  static const fallback = 'coins';

  bool get isTip => item.startsWith('tip/');
  String get cosmeticId => item.split('/').last;
}
