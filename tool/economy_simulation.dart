import 'dart:io';
import 'dart:math';

import '../lib/logic/star_rating.dart';
import '../lib/model/economy.dart';
import '../lib/model/fortune.dart';
import '../lib/model/game_state.dart';
import '../lib/model/journey.dart';
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
  bool offline,
  bool maxResearchStart,
  bool allCosmeticsStart,
  bool mixedDifficulty,
});

const profiles = <Profile>[
  (
    name: 'Casual',
    minutes: 15,
    attendance: .75,
    secondsPerBoard: 60,
    crateRate: .40,
    videos: 0,
    strategic: false,
    pay: false,
    premium: false,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'Regular',
    minutes: 30,
    attendance: .90,
    secondsPerBoard: 30,
    crateRate: .65,
    videos: 2,
    strategic: false,
    pay: false,
    premium: false,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'Dedicated',
    minutes: 60,
    attendance: .96,
    secondsPerBoard: 15,
    crateRate: .80,
    videos: 4,
    strategic: true,
    pay: false,
    premium: false,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'Optimized',
    minutes: 75,
    attendance: .99,
    secondsPerBoard: 10,
    crateRate: .95,
    videos: 7,
    strategic: true,
    pay: false,
    premium: false,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: false,
  ),
  (
    name: 'No-Ads',
    minutes: 35,
    attendance: .90,
    secondsPerBoard: 25,
    crateRate: 0,
    videos: 0,
    strategic: true,
    pay: false,
    premium: false,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'Occasional-Ads',
    minutes: 35,
    attendance: .90,
    secondsPerBoard: 25,
    crateRate: .50,
    videos: 1,
    strategic: true,
    pay: false,
    premium: false,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'Frequent-Ads',
    minutes: 45,
    attendance: .92,
    secondsPerBoard: 20,
    crateRate: .90,
    videos: 6,
    strategic: true,
    pay: false,
    premium: false,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'Coin-Packs',
    minutes: 30,
    attendance: .90,
    secondsPerBoard: 30,
    crateRate: .65,
    videos: 2,
    strategic: true,
    pay: true,
    premium: false,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'Premium',
    minutes: 30,
    attendance: .90,
    secondsPerBoard: 30,
    crateRate: .65,
    videos: 2,
    strategic: true,
    pay: false,
    premium: true,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'Offline',
    minutes: 30,
    attendance: .90,
    secondsPerBoard: 25,
    crateRate: 0,
    videos: 0,
    strategic: true,
    pay: false,
    premium: false,
    offline: true,
    maxResearchStart: false,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'Max-Research',
    minutes: 45,
    attendance: .95,
    secondsPerBoard: 20,
    crateRate: .75,
    videos: 3,
    strategic: true,
    pay: false,
    premium: false,
    offline: false,
    maxResearchStart: true,
    allCosmeticsStart: false,
    mixedDifficulty: true,
  ),
  (
    name: 'All-Cosmetics',
    minutes: 45,
    attendance: .95,
    secondsPerBoard: 20,
    crateRate: .75,
    videos: 3,
    strategic: true,
    pay: false,
    premium: false,
    offline: false,
    maxResearchStart: false,
    allCosmeticsStart: true,
    mixedDifficulty: true,
  ),
];

const horizons = [1, 7, 30, 90, 180, 365, 730, 1095];
const solveSpeeds = [5, 10, 15, 30, 60, 120, 240];
const navOverheadSeconds = 4;
const adDurationSeconds = 30;

final researchRanks = Research.values.fold(0, (sum, item) => sum + item.limit);
final coinThemes =
    PathwiseTheme.values.where((item) => economy.themePrice(item) > 0).toList()
      ..sort((a, b) => economy.themePrice(a).compareTo(economy.themePrice(b)));
final paidTips = PathTip.values.where((item) => item.price > 0).toList()
  ..sort((a, b) => a.price.compareTo(b.price));
final startingOwnedThemes = PathwiseTheme.values.length - coinThemes.length;
final catalog = FortuneCatalog(
  File('assets/data/fortune-prizes.json').readAsStringSync(),
);

typedef Snapshot = ({
  int balance,
  int earned,
  int spent,
  int ranks,
  int themes,
  int tips,
  int levels,
  int minutes,
  Map<String, int> sources,
});

class SimPlayer {
  SimPlayer(this.profile, this.random)
    : coins = economy.starterCoins,
      earned = economy.starterCoins,
      hints = economy.starterHints {
    if (profile.premium) {
      credit('premium', economy.premiumBonus);
      ownedThemes.addAll(coinThemes);
    }
    if (profile.maxResearchStart) {
      for (final r in Research.values) {
        progression.ranks[r.name] = r.limit;
      }
    }
    if (profile.allCosmeticsStart) {
      ownedThemes.addAll(coinThemes);
      ownedTips.addAll(paidTips);
    }
  }

  final Profile profile;
  final Random random;
  final progression = Progression({});
  final ownedThemes = <PathwiseTheme>{
    for (final t in PathwiseTheme.values)
      if (economy.themePrice(t) == 0) t,
  };
  final ownedTips = <PathTip>{PathTip.classic};
  final sources = <String, int>{};
  final achievements = <Achievement>{};
  int coins, earned, hints;
  int spent = 0, activeMinutes = 0, level = 0, journeyClears = 0;
  int firstRank = 0, firstTheme = 0, build = 0, finished = 0;
  int streak = 0, freezes = 0, sessions = 0, clean = 0, bestAttack = 0;
  int get ranks =>
      Research.values.fold(0, (sum, item) => sum + progression.rank(item));

  void credit(String source, int amount) {
    if (amount <= 0) return;
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
      if (freezes > 0) {
        freezes--;
      } else {
        streak = 0;
      }
      return;
    }
    sessions++;
    activeMinutes += profile.minutes;
    final online = !profile.offline;
    final videos = online ? profile.videos : 0;
    final wheelVideos = (videos ~/ 2).clamp(0, _wheelVideosPerDay);
    final coinVideos = (videos - wheelVideos).clamp(
      0,
      economy.rewardedAdsPerDay,
    );

    // Fortune wheel (free spin works offline; ad spins require online)
    for (var spin = 0; spin <= wheelVideos; spin++) {
      final prize = catalog.pick(random.nextInt(100));
      credit(spin == 0 ? 'free_wheel' : 'wheel_videos', prize.coins);
    }

    if (coinVideos > 0) {
      credit(
        'coin_videos',
        coinVideos * economy.rewardedAdCoins +
            (coinVideos >= economy.coinAdMilestone
                ? economy.coinAdMilestoneBonus
                : 0),
      );
    }

    // Boost ads: up to 3x doubleTen, 1x tripleFifteen if >=4 coin ads
    if (online && videos >= 3) {
      progression.inventory.update(
        Boost.doubleTen.name,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
    }
    if (online && coinVideos >= economy.coinAdMilestone) {
      progression.inventory.update(
        Boost.tripleFifteen.name,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
    }

    if (EconomyRules.milestones[streak + 1] case final milestone?) {
      credit('streak_milestones', milestone.coins);
      hints += milestone.hints;
    }

    final payDay = (number - 1) % 30 == 0;
    if (online && profile.pay && payDay) {
      final sku = number % 90 == 1
          ? 'pathwise_coins_3000'
          : 'pathwise_coins_1250';
      credit('coin_packs', storeProducts[sku]!.coins);
    }

    progression.active.clear();
    final adOverhead = (wheelVideos + coinVideos) * adDurationSeconds;
    final sessionSeconds = max(60, profile.minutes * 60 - adOverhead);
    final start = number * fortuneWindowMs;

    // 3-minute Time Attack every ~11 days for engaged players
    final attackMode = number % 11 == 0 && profile.minutes >= 30;
    var elapsed = 0;
    if (attackMode) {
      final avgStep = profile.secondsPerBoard + navOverheadSeconds;
      final solves = max(1, (180 / avgStep).floor());
      credit('time_attack', economy.attackReward(solves));
      bestAttack = max(bestAttack, solves);
      elapsed += 180;
    }

    // Strategic boost usage
    if (profile.strategic && coins >= 120) {
      Boost? chosen;
      if ((progression.inventory[Boost.tripleFifteen.name] ?? 0) > 0) {
        chosen = Boost.tripleFifteen;
      } else if ((progression.inventory[Boost.doubleTen.name] ?? 0) > 0) {
        chosen = Boost.doubleTen;
      } else if (profile.secondsPerBoard <= 20 &&
          debit(progression.discount(Boost.quadrupleTen.price))) {
        chosen = Boost.quadrupleTen;
        progression.inventory[chosen.name] =
            (progression.inventory[chosen.name] ?? 0) + 1;
      } else if (profile.minutes >= 45 &&
          debit(progression.discount(Boost.doubleSixty.price))) {
        chosen = Boost.doubleSixty;
        progression.inventory[chosen.name] =
            (progression.inventory[chosen.name] ?? 0) + 1;
      }
      if (chosen != null &&
          progression.canActivate(chosen, start + elapsed * 1000)) {
        progression.activate(chosen, start + elapsed * 1000);
      }
    }

    // Crates during active online campaign play
    if (online && videos > 0) {
      for (var second = elapsed + 10; second <= sessionSeconds; second += 10) {
        progression.accrueCrateTime(10000);
        final crate = progression.considerCrate((
          boot: 1,
          milliseconds: start + second * 1000,
        ), () => random.nextInt(100));
        if (crate != null && random.nextDouble() <= profile.crateRate) {
          credit('crates', crate.coins);
          if (crate.coins == crateTopPrize) progression.legendary++;
        }
      }
    }

    final daily =
        random.nextDouble() < .90 && (profile.minutes >= 25 || number.isEven);
    streak = daily ? streak + 1 : 0;

    // Simulate individual puzzle clears with realistic mixed difficulty
    var didDaily = false;
    while (elapsed < sessionSeconds) {
      final difficultyFactor = profile.mixedDifficulty
          ? (0.7 + 0.6 * random.nextDouble()) * (1.0 + min(0.35, level / 4000))
          : 1.0;
      final stepSec = max(
        5,
        (profile.secondsPerBoard * difficultyFactor).round() +
            navOverheadSeconds,
      );
      if (elapsed + stepSec > sessionSeconds) break;
      elapsed += stepSec;
      final nowMs = start + elapsed * 1000;

      var usedHint = false;
      if (random.nextDouble() < (profile.strategic ? 0.05 : 0.12)) {
        if (hints > 0) {
          hints--;
          usedHint = true;
        } else if (online && videos > 0 && random.nextDouble() < 0.5) {
          usedHint = true; // hint ad
        } else if (debit(economy.hintPrice)) {
          usedHint = true;
        }
      }
      if (!usedHint) clean++;
      final goldenBonus = usedHint ? 0 : progression.effect(Research.golden);

      if (!didDaily && daily) {
        didDaily = true;
        credit(
          'daily_challenge',
          economy.dailyClearCoins(
            multiplier: progression.multiplier(nowMs),
            fortuneBonus: progression.effect(Research.fortune),
            goldenBonus: goldenBonus,
          ),
        );
        if (streak > 0 && streak % economy.streakInterval == 0) {
          credit(
            'streak',
            economy.streakBonus + progression.effect(Research.specialist),
          );
        }
      } else {
        level++;
        journeyClears++;
        final puzzleSize = level <= 30
            ? 4
            : level <= 100
            ? 5
            : level <= 300
            ? 6
            : 7;
        final diffScale = switch (puzzleSize) {
          4 => 1.0 + (random.nextDouble() < 0.3 ? 0.25 : 0.0),
          5 => 1.5 + (random.nextDouble() < 0.5 ? 0.25 : 0.0),
          6 => 2.25 + (random.nextDouble() < 0.5 ? 0.50 : 0.0),
          _ => 3.0 + (random.nextDouble() < 0.5 ? 0.75 : 0.0),
        };
        final solveMs = max(3000, (stepSec - navOverheadSeconds) * 1000);
        final thresholds = StarThresholds(
          threeStarMs: (baselineThreeStarMs * diffScale).round(),
          twoStarMs: (baselineTwoStarMs * diffScale).round(),
          oneStarMs: (baselineOneStarMs * diffScale).round(),
          multiplier: diffScale,
        );
        final stars = thresholds.rate(solveMs);
        final activeMult = progression.multiplier(nowMs);
        final momentumBonus = level % 5 == 0
            ? progression.effect(Research.momentum)
            : 0;
        credit(
          'levels',
          economy.campaignClearCoins(
            multiplier: activeMult,
            magnetBonus: progression.effect(Research.magnet),
            goldenBonus: goldenBonus,
            momentumBonus: momentumBonus,
            stars: stars,
          ),
        );

        // Occasional replay improvement (+1 star on ~8% of sub-3-star clears)
        if (stars < 3 && profile.strategic && random.nextDouble() < 0.08) {
          credit('star_replays', activeMult);
        }

        // Post-completion ad multiplier (~20% take rate for video viewers)
        if (online && videos > 0 && random.nextDouble() < 0.20) {
          final mult = random.nextDouble() < 0.25 ? 4 : 3;
          credit(
            'completion_ads',
            economy.completionBonusCoins(
              mult,
              coins: economy.clearReward(PlayMode.levels) + stars,
            ),
          );
        }

        // Chapter treasure every 25 levels
        if (level % chapterSize == 0) {
          credit('chapter_treasures', chapterRewardCoins);
          hints += chapterRewardHints;
        }

        // Mystery reward every 10 eligible campaign clears
        if (journeyClears % discoveryInterval == 0) {
          final cycle = journeyClears ~/ discoveryInterval;
          final reward = selectMysteryReward(
            cycle: cycle,
            ownedTips: ownedTips,
            ownedThemes: ownedThemes,
            hasThemePass: profile.premium,
          );
          if (online && (videos > 0 || random.nextDouble() < 0.35)) {
            if (reward.isCoins) {
              credit('mystery_rewards', reward.coinAmount);
            } else if (reward.boost case final b?) {
              progression.inventory.update(
                b.name,
                (v) => v + 1,
                ifAbsent: () => 1,
              );
            } else if (reward.tip case final t?) {
              ownedTips.add(t);
            } else if (reward.theme case final th?) {
              ownedThemes.add(th);
            }
          }
        }
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
    award(Achievement.collector, ownedThemes.length >= 6);
    _shop(number);
  }

  void _shop(int number) {
    if (profile.strategic && streak >= 5 && freezes == 0 && coins >= 400) {
      if (debit(economy.freezePrice)) freezes++;
    }
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
          .where((item) => !ownedThemes.contains(item))
          .firstOrNull;
      final tip = paidTips
          .where((item) => !ownedTips.contains(item))
          .firstOrNull;

      if (tip != null &&
          ranks > 0 &&
          (research == null ||
              tip.price <= research.price(progression.rank(research)))) {
        if (!debit(tip.price)) break;
        ownedTips.add(tip);
        continue;
      }

      if (theme != null &&
          ranks > 0 &&
          (research == null ||
              economy.themePrice(theme) <=
                  research.price(progression.rank(research)))) {
        if (!debit(economy.themePrice(theme))) break;
        ownedThemes.add(theme);
        if (firstTheme == 0) firstTheme = number;
        continue;
      }
      if (research == null ||
          !debit(research.price(progression.rank(research)))) {
        break;
      }
      progression.ranks[research.name] = progression.rank(research) + 1;
      if (firstRank == 0) firstRank = number;
      if (ranks >= 30 && build == 0) build = number;
      award(Achievement.researcher, ranks >= 10);
    }
    if (finished == 0 &&
        ranks == researchRanks &&
        ownedThemes.length == PathwiseTheme.values.length &&
        ownedTips.length == PathTip.values.length) {
      finished = number;
    }
  }

  Snapshot snapshot() => (
    balance: coins,
    earned: earned,
    spent: spent,
    ranks: ranks,
    themes: ownedThemes.length - startingOwnedThemes,
    tips: ownedTips.length - 1,
    levels: level,
    minutes: activeMinutes,
    sources: Map.of(sources),
  );
}

num median(Iterable<num> values) {
  final ordered = values.toList()..sort();
  return ordered[ordered.length ~/ 2];
}

num percentile(Iterable<num> values, double p) {
  final ordered = values.toList()..sort();
  final idx = ((ordered.length - 1) * p).round().clamp(0, ordered.length - 1);
  return ordered[idx];
}

void writeBoostProfitabilityCsv(StringBuffer csv) {
  csv.writeln(
    'boost_id,name,multiplier,base_min,max_research_min,base_price,max_discount_price,solve_speed_s,puzzles_in_base,puzzles_in_max_res,breakeven_puzzles,net_profit_base,net_profit_max_res',
  );
  final maxRes = Progression({
    'ranks': {for (final r in Research.values) r.name: r.limit},
  });
  for (final b in Boost.values) {
    final maxMin = b.minutes * (100 + maxRes.durationBonus) / 100.0;
    final minPrice = maxRes.discount(b.price);
    final extraPerClear =
        economy.clearReward(PlayMode.levels) * (b.multiplier - 1);
    final breakevenBase = (b.price / extraPerClear).ceil();
    for (final s in solveSpeeds) {
      final stepSec = s + navOverheadSeconds;
      final puzzlesBase = (b.minutes * 60) ~/ stepSec;
      final puzzlesMax = (maxMin * 60).floor() ~/ stepSec;
      final netBase = puzzlesBase * extraPerClear - b.price;
      final netMax = puzzlesMax * extraPerClear - minPrice;
      csv.writeln(
        '${b.name},${b.title},${b.multiplier},${b.minutes},${maxMin.toStringAsFixed(2)},${b.price},$minPrice,$s,$puzzlesBase,$puzzlesMax,$breakevenBase,$netBase,$netMax',
      );
    }
  }
}

void writeResearchPaybackCsv(StringBuffer csv) {
  csv.writeln(
    'branch,title,rank,max_rank,advanced,price,effect_delta,total_effect,payback_puzzles_or_events',
  );
  for (final r in Research.values) {
    for (var rank = 0; rank < r.limit; rank++) {
      final price = r.price(rank);
      final delta = r.effectAt(rank + 1) - r.effectAt(rank);
      final total = r.effectAt(rank + 1);
      final payback = switch (r) {
        Research.magnet => (price / delta).ceil(),
        Research.golden => (price / (delta * 0.85)).ceil(),
        Research.fortune => (price / delta).ceil(),
        Research.momentum => (price * 5 / delta).ceil(),
        Research.specialist => (price * 7 / delta).ceil(),
        Research.mastery => (price / delta).ceil(),
        _ => (price / 5).ceil(),
      };
      csv.writeln(
        '${r.name},${r.title},${rank + 1},${r.limit},${r.advanced},$price,$delta,$total,$payback',
      );
    }
  }
}

void writeRatesCsv(StringBuffer csv) {
  csv.writeln('category,key,value,notes');
  csv.writeln('starter,coins,${economy.starterCoins},Welcome coins');
  csv.writeln('starter,hints,${economy.starterHints},Welcome hints');
  csv.writeln(
    'clear,campaign_base,${economy.clearReward(PlayMode.levels)},Base first-clear',
  );
  csv.writeln(
    'clear,daily_base,${economy.clearReward(PlayMode.daily)},Daily first-clear',
  );
  csv.writeln('consumable,hint_price,${economy.hintPrice},Coin cost per hint');
  csv.writeln(
    'consumable,freeze_price,${economy.freezePrice},Coin cost per streak freeze',
  );
  csv.writeln(
    'chapter,treasure_coins,$chapterRewardCoins,Per 25 campaign levels',
  );
  csv.writeln(
    'chapter,treasure_hints,$chapterRewardHints,Per 25 campaign levels',
  );
  for (final b in Boost.values) {
    csv.writeln(
      'boost,${b.name},${b.price},${b.title} (${b.multiplier}x ${b.minutes}m)',
    );
  }
  for (final t in PathTip.values) {
    csv.writeln('tip,${t.name},${t.price},${economy.tipRarity(t)}');
  }
  for (final th in PathwiseTheme.values) {
    csv.writeln('theme,${th.name},${economy.themePrice(th)},Theme');
  }
}

/// Simulation assumption: wheel video spins have no product cap, so the model
/// assumes a dedicated player watches at most this many a day.
const _wheelVideosPerDay = 6;

void main() {
  final reportDir = Directory('build/economy_reports');
  if (!reportDir.existsSync()) reportDir.createSync(recursive: true);

  final researchCost = Research.values
      .expand((item) => List.generate(item.limit, item.price))
      .reduce((a, b) => a + b);
  final themeCost = coinThemes.fold(
    0,
    (sum, item) => sum + economy.themePrice(item),
  );
  final tipCost = paidTips.fold(0, (sum, item) => sum + item.price);
  final wheelEv = catalog.prizes.fold(
    0.0,
    (sum, p) => sum + p.coins * p.weight / 100,
  );
  final crateEv =
      List.generate(100, crateCoins).reduce((a, b) => a + b) / 100.0;
  final mysteryCoinEv = mysteryCoinWeights.fold(
    0.0,
    (sum, e) => sum + e.coins * e.weight / 100.0,
  );

  print(
    'Economy 2.0 Summary:\n'
    '  Research ($researchRanks ranks): $researchCost coins\n'
    '  Coin Themes (${coinThemes.length}): $themeCost coins\n'
    '  Paid Tips (${paidTips.length}): $tipCost coins\n'
    '  Wheel EV: ${wheelEv.toStringAsFixed(2)} coins/spin | '
    'Crate EV: ${crateEv.toStringAsFixed(2)} coins/crate | '
    'Mystery Coin EV: ${mysteryCoinEv.toStringAsFixed(2)} coins',
  );

  final simCsv = StringBuffer()
    ..writeln(
      'profile,day,p10_earned,median_earned,p90_earned,median_balance,median_spent,coins_per_hour,research_pct,themes_pct,tips_pct,median_levels',
    );

  for (final profile in profiles) {
    final rows = {for (final day in horizons) day: <Snapshot>[]};
    final players = [
      for (var seed = 0; seed < 24; seed++)
        SimPlayer(profile, Random(1173 + seed * 419)),
    ];
    for (final player in players) {
      for (var day = 1; day <= horizons.last; day++) {
        player.day(day);
        rows[day]?.add(player.snapshot());
      }
    }
    print(
      '\n${profile.name} (${profile.minutes}m/day, ${profile.secondsPerBoard}s/puzzle)',
    );
    print(
      'day | median_earned | balance | coins/hr | res% | themes% | tips% | levels',
    );
    for (final day in horizons) {
      final s = rows[day]!;
      final medEarned = median(s.map((x) => x.earned));
      final medBal = median(s.map((x) => x.balance));
      final medSpent = median(s.map((x) => x.spent));
      final medCph = median(
        s.map((x) => (x.earned * 60 / max(1, x.minutes)).round()),
      );
      final medRes = median(
        s.map((x) => (100 * x.ranks / researchRanks).round()),
      );
      final medTh = median(
        s.map((x) => (100 * x.themes / coinThemes.length).round()),
      );
      final medTip = median(
        s.map((x) => (100 * x.tips / paidTips.length).round()),
      );
      final medLvl = median(s.map((x) => x.levels));
      print(
        '$day | $medEarned | $medBal | $medCph | $medRes | $medTh | $medTip | $medLvl',
      );
      simCsv.writeln(
        '${profile.name},$day,${percentile(s.map((x) => x.earned), 0.1)},$medEarned,${percentile(s.map((x) => x.earned), 0.9)},$medBal,$medSpent,$medCph,$medRes,$medTh,$medTip,$medLvl',
      );
    }
  }

  final boostCsv = StringBuffer();
  writeBoostProfitabilityCsv(boostCsv);
  final researchCsv = StringBuffer();
  writeResearchPaybackCsv(researchCsv);
  final ratesCsv = StringBuffer();
  writeRatesCsv(ratesCsv);

  File('build/economy_reports/economy_simulation.csv')
      .writeAsStringSync(simCsv.toString());
  File('build/economy_reports/boost_profitability.csv')
      .writeAsStringSync(boostCsv.toString());
  File('build/economy_reports/research_payback.csv')
      .writeAsStringSync(researchCsv.toString());
  File('build/economy_reports/economy_rates.csv').writeAsStringSync(ratesCsv.toString());
  print('\nWrote CSV reports to build/economy_reports/*.csv');
}
