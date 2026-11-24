import 'dart:io';
import 'dart:math';

import '../lib/model/economy.dart';
import '../lib/model/fortune.dart';
import '../lib/model/game_state.dart';
import '../lib/model/product_catalog.dart';
import '../lib/model/progression.dart';
import '../lib/model/user_preferences.dart';

typedef Profile = ({
  String name,
  int minutes,
  double attendance,
  double secondsPerBoard,
  double crateRate,
  int videos,
  bool strategic,
  bool pay,
  bool premium,
});

const profiles = <Profile>[
  (
    name: 'Casual',
    minutes: 18,
    attendance: .80,
    secondsPerBoard: 245,
    crateRate: .50,
    videos: 0,
    strategic: false,
    pay: false,
    premium: false,
  ),
  (
    name: 'Regular',
    minutes: 37,
    attendance: .90,
    secondsPerBoard: 230,
    crateRate: .70,
    videos: 2,
    strategic: false,
    pay: false,
    premium: false,
  ),
  (
    name: 'Dedicated',
    minutes: 75,
    attendance: .96,
    secondsPerBoard: 210,
    crateRate: .83,
    videos: 4,
    strategic: true,
    pay: false,
    premium: false,
  ),
  (
    name: 'Optimized',
    minutes: 90,
    attendance: .99,
    secondsPerBoard: 175,
    crateRate: .95,
    videos: 7,
    strategic: true,
    pay: false,
    premium: false,
  ),
  (
    name: 'Coin packs',
    minutes: 37,
    attendance: .90,
    secondsPerBoard: 230,
    crateRate: .70,
    videos: 2,
    strategic: true,
    pay: true,
    premium: false,
  ),
  (
    name: 'Premium',
    minutes: 37,
    attendance: .90,
    secondsPerBoard: 230,
    crateRate: .70,
    videos: 2,
    strategic: true,
    pay: false,
    premium: true,
  ),
];

const horizons = [30, 90, 180, 365, 730, 1095, 1825];
final researchRanks = Research.values.fold(0, (sum, item) => sum + item.limit);
final coinThemes =
    PathwiseTheme.values.where((item) => economy.themePrice(item) > 0).toList()
      ..sort((a, b) => economy.themePrice(a).compareTo(economy.themePrice(b)));
final startingOwned = PathwiseTheme.values.length - coinThemes.length;
final catalog = FortuneCatalog(
  File('assets/data/fortune-prizes.json').readAsStringSync(),
);

typedef Snapshot = ({
  int balance,
  int earned,
  int spent,
  int ranks,
  int themes,
  int minutes,
  Map<String, int> sources,
});

class Player {
  Player(this.profile, this.random, {this.ads = true, this.boosts = true})
    : coins = economy.starterCoins,
      earned = economy.starterCoins {
    if (profile.premium) {
      credit('premium', economy.premiumBonus);
      owned.addAll(coinThemes);
    }
  }

  final Profile profile;
  final Random random;
  final bool ads, boosts;
  final progression = Progression({});
  final owned = <PathwiseTheme>{};
  final sources = <String, int>{};
  final achievements = <Achievement>{};
  int coins, earned;
  int spent = 0, activeMinutes = 0, level = 0;
  int firstRank = 0, firstTheme = 0, build = 0, finished = 0;
  int streak = 0, sessions = 0, clean = 0, bestAttack = 0;
  int get ranks =>
      Research.values.fold(0, (sum, item) => sum + progression.rank(item));
  void credit(String source, int amount) {
    coins += amount;
    earned += amount;
    sources.update(source, (value) => value + amount, ifAbsent: () => amount);
  }

  bool debit(int amount) {
    if (amount > coins) return false;
    spent += amount;
    coins -= amount;
    return true;
  }

  void award(Achievement item, bool qualified) {
    if (qualified && achievements.add(item)) {
      credit('achievements', item.coins + progression.effect(Research.mastery));
    }
  }

  void day(int number) {
    if (random.nextDouble() > profile.attendance) {
      streak = 0;
      return;
    }
    sessions++;
    activeMinutes += profile.minutes;
    final videos = ads ? profile.videos : 0;
    final wheelVideos = (videos ~/ 2).clamp(0, economy.wheelAdsPerDay);
    final coinVideos = (videos - wheelVideos).clamp(
      0,
      economy.rewardedAdsPerDay,
    );
    for (var spin = 0; spin <= wheelVideos; spin++) {
      final prize = catalog.pick(random.nextInt(100));
      credit(spin == 0 ? 'free wheel' : 'wheel videos', prize.coins);
    }
    credit(
      'coin videos',
      coinVideos * economy.rewardedAdCoins +
          (coinVideos >= economy.coinAdMilestone
              ? economy.coinAdMilestoneBonus
              : 0),
    );
    if (EconomyRules.milestones[streak + 1] case final milestone?) {
      credit('streak milestones', milestone.coins);
    }
    final payDay = (number - 1) % 30 == 0;
    if (profile.pay && payDay) {
      final sku = number % 90 == 1
          ? 'pathwise_coins_3000'
          : 'pathwise_coins_1250';
      credit('coin packs', storeProducts[sku]!.coins);
    }
    progression.active.clear();
    final sessionSeconds =
        profile.minutes * 60 - (wheelVideos + coinVideos) * 35;
    final stepSeconds =
        (profile.secondsPerBoard * (.8 + .4 * random.nextDouble())).round();
    final clears = max(1, sessionSeconds ~/ stepSeconds);
    final focus = random.nextDouble();
    final start = number * fortuneWindowMs;
    final attackMode = number % 11 == 0 && profile.minutes >= 30;
    if (attackMode) {
      final solves = min(8, max(1, 600 ~/ stepSeconds));
      credit('time attack', economy.attackReward(solves));
      bestAttack = max(bestAttack, solves);
    }
    if (boosts && profile.strategic && clears >= 4 && coins >= 80) {
      final ownedBoost = progression.inventory[Boost.doubleTen.name] ?? 0;
      final chosen = ownedBoost > 0
          ? Boost.doubleTen
          : clears >= 13
          ? Boost.doubleSixty
          : Boost.doubleTen;
      if (ownedBoost > 0 || debit(progression.discount(chosen.price))) {
        if (ownedBoost == 0) progression.inventory[chosen.name] = 1;
        progression.activate(chosen, start);
      }
    }
    for (var second = 10; second <= sessionSeconds; second += 10) {
      if (attackMode && second <= 600) continue;
      progression.accrueCrateTime(10000);
      final crate = progression.considerCrate((
        boot: 1,
        milliseconds: start + second * 1000,
      ), () => random.nextInt(100));
      if (crate == null ||
          !ads ||
          profile.videos == 0 ||
          random.nextDouble() > profile.crateRate) {
        continue;
      }
      credit('crates', crate.coins);
      if (crate.coins == crateTopPrize) progression.legendary++;
    }
    final daily = focus < .92 && (profile.minutes >= 30 || number.isEven);
    streak = daily ? streak + 1 : 0;
    final spendHints = random.nextDouble() < (profile.strategic ? .23 : .46);
    if (spendHints && debit(economy.hintPrice)) {
      // One tank refill at most per modeled session.
    }
    for (var index = 0; index < clears; index++) {
      final time = (index + 1) * stepSeconds * 1000;
      if (time > sessionSeconds * 1000 || (attackMode && time <= 10 * 60000))
        continue;
      final unaided = random.nextDouble() < (profile.strategic ? .86 : .65);
      if (unaided) clean++;
      final bonus = unaided ? progression.effect(Research.golden) : 0;
      if (index == 0 && daily && !attackMode) {
        credit(
          'daily challenge',
          (economy.clearReward(PlayMode.daily) +
                  progression.effect(Research.fortune) +
                  bonus) *
              progression.multiplier(start + time),
        );
        if (streak % economy.streakInterval == 0) {
          credit(
            'streak',
            economy.streakBonus + progression.effect(Research.specialist),
          );
        }
      } else {
        level++;
        credit(
          'levels',
          (economy.clearReward(PlayMode.levels) +
                  progression.effect(Research.magnet) +
                  bonus +
                  (level % 5 == 0
                      ? progression.effect(Research.momentum)
                      : 0)) *
              progression.multiplier(start + time),
        );
      }
    }
    award(Achievement.trailhead, level >= 1);
    award(Achievement.trailblazer, level >= 12);
    award(Achievement.pathfinder, level >= 50);
    award(Achievement.twentyFive, level >= 25);
    award(Achievement.hundred, level >= 100);
    award(Achievement.fiveHundred, level >= 500);
    award(Achievement.thousand, level >= 1000);
    award(Achievement.dailyHabit, streak >= 3);
    award(Achievement.weeklyRitual, streak >= 7);
    award(Achievement.unaided, clean >= 10);
    award(Achievement.timeTrial, bestAttack >= 3);
    award(Achievement.legendaryCrate, progression.legendary > 0);
    award(Achievement.collector, startingOwned + owned.length >= 6);
    _shop(number);
  }

  void _shop(int number) {
    for (var attempt = 0; attempt < 12; attempt++) {
      final available =
          Research.values
              .where(
                (item) =>
                    progression.unlocked(item) &&
                    progression.rank(item) < item.limit,
              )
              .toList()
            ..sort(
              (a, b) => a
                  .price(progression.rank(a))
                  .compareTo(b.price(progression.rank(b))),
            );
      final research = available.firstOrNull;
      final theme = coinThemes
          .where((item) => !owned.contains(item))
          .firstOrNull;
      if (theme != null &&
          ranks > 0 &&
          (research == null ||
              (owned.isEmpty || ranks >= 8) &&
                  economy.themePrice(theme) <=
                      research.price(progression.rank(research)))) {
        if (!debit(economy.themePrice(theme))) break;
        owned.add(theme);
        if (firstTheme == 0) firstTheme = number;
        continue;
      }
      if (research == null ||
          !debit(research.price(progression.rank(research))))
        break;
      progression.ranks[research.name] = progression.rank(research) + 1;
      if (firstRank == 0) firstRank = number;
      if (ranks >= 30 && build == 0) build = number;
      award(Achievement.researcher, ranks >= 10);
    }
    if (finished == 0 &&
        ranks == researchRanks &&
        owned.length == coinThemes.length)
      finished = number;
  }

  Snapshot snapshot() => (
    balance: coins,
    earned: earned,
    spent: spent,
    ranks: ranks,
    themes: owned.length,
    minutes: activeMinutes,
    sources: Map.of(sources),
  );
}

num median(Iterable<num> values) {
  final ordered = values.toList()..sort();
  return ordered[ordered.length ~/ 2];
}

void simulate(
  Profile profile, {
  bool ads = true,
  bool boosts = true,
  bool detail = true,
}) {
  final rows = {for (final day in horizons) day: <Snapshot>[]};
  final players = [
    for (var seed = 0; seed < 24; seed++)
      Player(profile, Random(1173 + seed * 419), ads: ads, boosts: boosts),
  ];
  for (final player in players) {
    for (var day = 1; day <= 10950; day++) {
      player.day(day);
      rows[day]?.add(player.snapshot());
      if ((!detail || day >= horizons.last) && player.finished > 0) break;
    }
  }
  print('\n${profile.name} · ads $ads · timed boosts $boosts');
  print(
    'Median days to first rank/theme/30 ranks/full coin catalog + research: '
    '${median(players.map((p) => p.firstRank))}/'
    '${profile.premium ? 'included' : median(players.map((p) => p.firstTheme))}/'
    '${median(players.map((p) => p.build))}/'
    '${median(players.map((p) => p.finished == 0 ? 10951 : p.finished))}',
  );
  if (!detail) return;
  print(
    'day | balance | earned | spent | coins/hour | research% | coin themes%',
  );
  for (final day in horizons) {
    final samples = rows[day]!;
    print(
      [
        day,
        median(samples.map((s) => s.balance)),
        median(samples.map((s) => s.earned)),
        median(samples.map((s) => s.spent)),
        median(samples.map((s) => (s.earned * 60 / max(1, s.minutes)).round())),
        median(samples.map((s) => (100 * s.ranks / researchRanks).round())),
        median(
          samples.map((s) => (100 * s.themes / coinThemes.length).round()),
        ),
      ].join(' | '),
    );
  }
  final year = rows[365]!;
  final keys = year.expand((sample) => sample.sources.keys).toSet().toList()
    ..sort();
  print(
    'Year-one median amounts by source: '
    '${keys.map((key) => '$key=${median(year.map((s) => s.sources[key] ?? 0))}').join(', ')}',
  );
}

void main() {
  final researchCost = Research.values
      .expand((item) => List.generate(item.limit, item.price))
      .reduce((a, b) => a + b);
  final themeCost = coinThemes.fold(
    0,
    (sum, item) => sum + economy.themePrice(item),
  );
  final wheelEv = catalog.prizes.fold(
    0.0,
    (sum, p) => sum + p.coins * p.weight / 100,
  );
  print(
    'Research $researchRanks ranks cost $researchCost · coin themes cost $themeCost · '
    'wheel liquid EV ${wheelEv.toStringAsFixed(2)} per spin',
  );
  for (final profile in profiles) {
    simulate(profile);
  }
  simulate(profiles[2], ads: false, detail: false);
  simulate(profiles[2], boosts: false, detail: false);
}
