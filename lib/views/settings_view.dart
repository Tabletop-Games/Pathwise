import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../cloud/cloud_sync_service.dart';
import '../logic/ad_service.dart';
import '../logic/notification_service.dart';
import '../logic/social_sharing.dart';
import '../logic/update_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/user_preferences.dart';
import '../ui/art/control_art.dart';
import '../ui/art/game_assets.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import '../viewmodels/statistics_viewmodel.dart';
import 'cloud_save_section.dart';
import 'components/brand_mark.dart';
import 'level_one_demo.dart';
import 'play_games_view.dart';
import 'puzzle_view.dart';
import 'share_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
    final cloud = context.watch<CloudSyncService?>();
    final p = context.palette;

    Widget section(String title, List<Widget> tiles) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
            child: Text(
              title,
              style: TextStyle(
                color: p.mutedInk,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ),
          GameCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.cardEdge),
                  tiles[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final volumePercent = (model.soundVolume * 100).round();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 0,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
      ),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 530),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                children: [
                  section('Audio & feedback', [
                    SwitchListTile(
                      secondary: const PathIcon(ControlGlyph.sound),
                      title: const Text('Sound effects'),
                      value: model.soundEnabled,
                      onChanged: model.setSoundEnabled,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Sound volume',
                                  style: TextStyle(
                                    color: model.soundEnabled
                                        ? p.ink
                                        : p.mutedInk,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Text(
                                model.soundEnabled
                                    ? '$volumePercent%'
                                    : 'Muted',
                                style: TextStyle(
                                  color: p.mutedInk,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Semantics(
                            slider: true,
                            enabled: model.soundEnabled,
                            label: 'Sound effects volume',
                            value: model.soundEnabled
                                ? '$volumePercent percent'
                                : 'Muted',
                            child: Slider(
                              value: model.soundVolume,
                              onChanged: model.soundEnabled
                                  ? (value) => model.setSoundVolume(value)
                                  : null,
                              onChangeEnd: model.soundEnabled
                                  ? (value) => model.setSoundVolume(
                                      value,
                                      preview: true,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      secondary: const PathIcon(ControlGlyph.haptics),
                      title: const Text('Haptic feedback'),
                      value: model.haptics,
                      onChanged: model.setHaptics,
                    ),
                  ]),
                  if (defaultTargetPlatform == TargetPlatform.android)
                    _NotificationSettingsSection(model: model, palette: p),
                  section('Gameplay', [
                    ListTile(
                      leading: GameArt(ArtKind.levels, size: 28),
                      title: const Text('How to play'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openLevelOneDemo(context),
                    ),
                    SwitchListTile(
                      title: const Text('Suggest sharing achievements'),
                      value: model.suggestSharing,
                      onChanged: model.setSharingSuggestions,
                    ),
                  ]),
                  section('Account & data', [
                    if (cloud != null) const CloudSaveSection(compact: true),
                    ListTile(
                      leading: GameArt(ArtKind.trophy, size: 28),
                      title: const Text('Google Play Achievements'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PlayGamesView(),
                        ),
                      ),
                    ),
                  ]),
                  section('About & support', [
                    if (ads.canManagePrivacy)
                      ListTile(
                        title: const Text('Ad privacy'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          if (!ads.privacyRequired) {
                            await ads.prepare(
                              canPresent: () =>
                                  context.mounted &&
                                  ModalRoute.isCurrentOf(context) == true,
                            );
                          }
                          if (!context.mounted) return;
                          if (ads.privacyRequired) {
                            if (ModalRoute.isCurrentOf(context) == true) {
                              await ads.privacyOptions();
                              if (context.mounted && ads.message != null) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text(ads.message!)),
                                );
                              }
                            }
                          } else {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  ads.message ?? 'Ad privacy options are not required in your region.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    if (defaultTargetPlatform == TargetPlatform.android)
                      const _CheckForUpdates(),
                    AboutListTile(
                      applicationName: 'Pathwise',
                      applicationVersion: '1.0.0',
                      icon: const Icon(Icons.info_outline_rounded),
                      applicationIcon: BrandMark(
                        background: Theme.of(context).colorScheme.primary,
                        ink: Theme.of(context).colorScheme.onPrimary,
                      ),
                      aboutBoxChildren: const [
                        Text(
                          'A route puzzle by Tabletop Games. Draw one continuous '
                          'path through every tile, visiting checkpoints in order.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Play an endless campaign, a three-puzzle Daily Challenge, '
                          'or race the clock in Time Attack.',
                        ),
                      ],
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatisticsView extends StatelessWidget {
  const StatisticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final summary = StatisticsSummary.fromModel(model);
    final highContrast =
        palette == BoardPalette.palettes[PathwiseTheme.signal] ||
        palette == BoardPalette.palettes[PathwiseTheme.amoledCarbon];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 0,
        title: const Text(
          'Statistics',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
      ),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 530),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                children: [
                  _ChapterProgressHeader(
                    summary: summary,
                    palette: palette,
                    theme: model.theme,
                  ),
                  const SizedBox(height: 10),
                  _KeyStatsGrid(summary: summary, palette: palette),
                  const SizedBox(height: 10),
                  _CampaignPerformanceCard(
                    summary: summary,
                    palette: palette,
                    highContrast: highContrast,
                  ),
                  const SizedBox(height: 10),
                  _DailyPerformanceCard(summary: summary, palette: palette),
                  const SizedBox(height: 10),
                  _TimeAttackCard(summary: summary, palette: palette),
                  const SizedBox(height: 10),
                  _LifetimeActivityCard(
                    summary: summary,
                    palette: palette,
                    model: model,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pathwise Achievements',
                              style: TextStyle(
                                color: palette.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                            Text(
                              '${summary.unlockedAchievements} / ${summary.achievements.length} unlocked',
                              style: TextStyle(
                                color: palette.mutedInk,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ActionPill(
                        label: 'Play Games',
                        icon: Icons.emoji_events_outlined,
                        semanticLabel: 'Google Play Achievements',
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const PlayGamesView(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final item in summary.achievements)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AchievementCard(item: item, palette: palette),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterProgressHeader extends StatelessWidget {
  const _ChapterProgressHeader({
    required this.summary,
    required this.palette,
    required this.theme,
  });

  final StatisticsSummary summary;
  final BoardPalette palette;
  final PathwiseTheme theme;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GameCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GameTokens.cardRadius - 2),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: palette.dark ? 0.22 : 0.20,
                child: Image.asset(
                  biomeAssetPath(biomeForTheme(theme)),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GameArt(ArtKind.levels, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chapter ${summary.chapter + 1} · ${summary.chapterTitle}',
                              style: text.titleMedium?.copyWith(
                                color: palette.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Level ${summary.currentLevel} · ${summary.chapterCompleted}/${summary.chapterTotal} in chapter',
                              style: TextStyle(
                                color: palette.mutedInk,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: summary.chapterProgress,
                      minHeight: 7,
                      backgroundColor: palette.track,
                      valueColor: AlwaysStoppedAnimation(palette.route),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyStatsGrid extends StatelessWidget {
  const _KeyStatsGrid({required this.summary, required this.palette});

  final StatisticsSummary summary;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('${summary.totalSolved}', 'Puzzles solved'),
      ('${summary.hintFree}', 'Hint-free'),
      ('${summary.totalStars}', 'Stars earned'),
      ('${summary.dayStreak}', 'Current streak'),
      ('${summary.longestPlayStreak}', 'Longest streak'),
      (formatTime(summary.playTime), 'Play time'),
    ];
    return GameCard(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 340 ? 3 : 2;
          final cellWidth =
              (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (value, label) in metrics)
                SizedBox(
                  width: cellWidth,
                  child: Semantics(
                    label: '$label: $value',
                    excludeSemantics: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: palette.quiet,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              value,
                              style: TextStyle(
                                color: palette.ink,
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.mutedInk,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CampaignPerformanceCard extends StatelessWidget {
  const _CampaignPerformanceCard({
    required this.summary,
    required this.palette,
    required this.highContrast,
  });

  final StatisticsSummary summary;
  final BoardPalette palette;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final counts = [
      (3, summary.threeStar),
      (2, summary.twoStar),
      (1, summary.oneStar),
      (0, summary.zeroStar),
    ];
    return GameCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            art: ArtKind.levels,
            title: 'Campaign performance',
            trailing: '${summary.levelsSolved} completed',
            palette: palette,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CompactMetric(
                  label: 'Earned stars',
                  value: summary.possibleStars > 0
                      ? '${summary.totalStars} / ${summary.possibleStars}'
                      : '0',
                  palette: palette,
                ),
              ),
              if (summary.bestLevelTime case final best?)
                Expanded(
                  child: _CompactMetric(
                    label: 'Best level time',
                    value: formatTime(best),
                    palette: palette,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < counts.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: palette.quiet,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${counts[i].$1}',
                              style: TextStyle(
                                color: palette.mutedInk,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 2),
                            RatingStar(
                              earned: counts[i].$1 > 0,
                              size: 13,
                              highContrast: highContrast,
                              palette: palette,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${counts[i].$2}',
                          style: TextStyle(
                            color: palette.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyPerformanceCard extends StatelessWidget {
  const _DailyPerformanceCard({required this.summary, required this.palette});

  final StatisticsSummary summary;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    return GameCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            art: ArtKind.calendar,
            title: 'Daily challenge',
            trailing: '${summary.dailySolved} solved',
            palette: palette,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CompactMetric(
                  label: 'Daily streak',
                  value: '${summary.dailyStreak}',
                  palette: palette,
                ),
              ),
              Expanded(
                child: _CompactMetric(
                  label: 'Best daily streak',
                  value: '${summary.longestStreak}',
                  palette: palette,
                ),
              ),
              if (summary.bestDailyTime case final best?)
                Expanded(
                  child: _CompactMetric(
                    label: 'Best time',
                    value: formatTime(best),
                    palette: palette,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeAttackCard extends StatelessWidget {
  const _TimeAttackCard({required this.summary, required this.palette});

  final StatisticsSummary summary;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    return GameCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            art: ArtKind.timer,
            title: 'Time Attack',
            trailing: 'Best ${summary.attackBestScore} pts',
            palette: palette,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CompactMetric(
                  label: '1 min best',
                  value: '${summary.attackBest1m}',
                  palette: palette,
                ),
              ),
              Expanded(
                child: _CompactMetric(
                  label: '3 min best',
                  value: '${summary.attackBest3m}',
                  palette: palette,
                ),
              ),
              Expanded(
                child: _CompactMetric(
                  label: '5 min best',
                  value: '${summary.attackBest5m}',
                  palette: palette,
                ),
              ),
              Expanded(
                child: _CompactMetric(
                  label: 'Most clears',
                  value: '${summary.attackHighestClears}',
                  palette: palette,
                ),
              ),
            ],
          ),
          if (summary.recentAttackRuns.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: palette.cardEdge),
            const SizedBox(height: 6),
            for (final run in summary.recentAttackRuns)
              _Stat(
                '${run.minutes}m run · ${run.clears.length} solved',
                '${run.score} pts',
              ),
          ],
        ],
      ),
    );
  }
}

class _LifetimeActivityCard extends StatelessWidget {
  const _LifetimeActivityCard({
    required this.summary,
    required this.palette,
    required this.model,
  });

  final StatisticsSummary summary;
  final BoardPalette palette;
  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final milestone = SharePromptPolicy.lastLevelMilestone(
      model.highestUnlocked - 1,
    );
    return GameCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            art: ArtKind.brush,
            title: 'Collection & activity',
            palette: palette,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CompactMetric(
                  label: 'Themes owned',
                  value: '${summary.ownedThemes}/${summary.totalThemes}',
                  palette: palette,
                ),
              ),
              Expanded(
                child: _CompactMetric(
                  label: 'Path tips owned',
                  value: '${summary.ownedTips}/${summary.totalTips}',
                  palette: palette,
                ),
              ),
              Expanded(
                child: _CompactMetric(
                  label: 'Total play time',
                  value: formatTime(summary.playTime),
                  palette: palette,
                ),
              ),
            ],
          ),
          if (milestone != null &&
              model.result(PuzzleId.level(milestone)) != null) ...[
            const SizedBox(height: 10),
            ShareResultButton(
              result: ShareResult.level(
                level: milestone,
                total: model.levelsSolved,
              ),
              label: 'Share Level Milestone',
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.art,
    required this.title,
    required this.palette,
    this.trailing,
  });

  final ArtKind art;
  final String title;
  final BoardPalette palette;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      GameArt(art, size: 22),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: palette.ink,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: TextStyle(
            color: palette.mutedInk,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
    ],
  );
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: palette.ink,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.mutedInk,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.item, required this.palette});

  final AchievementProgressItem item;
  final BoardPalette palette;

  Achievement get achievement => item.achievement;
  bool get earned => item.earned;

  String get _asset => switch (achievement) {
    Achievement.trailhead ||
    Achievement.trailblazer ||
    Achievement.pathfinder => 'assets/art/ui/compass.webp',
    Achievement.dailyHabit ||
    Achievement.weeklyRitual => 'assets/art/ui/flame.webp',
    Achievement.unaided => 'assets/art/resources/hint.webp',
    Achievement.collector => 'assets/art/tips/crystal.webp',
    Achievement.timeTrial => 'assets/art/ui/timer.webp',
    Achievement.researcher => 'assets/art/ui/research.webp',
    Achievement.legendaryCrate => 'assets/art/resources/crate.webp',
    Achievement.twentyFive ||
    Achievement.hundred => 'assets/art/ui/achievement.webp',
    Achievement.fiveHundred ||
    Achievement.thousand => 'assets/art/ui/trophy.webp',
  };

  Widget _achievementIcon() {
    final img = Image.asset(
      _asset,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => GameArt(ArtKind.trophy, size: 42),
    );
    if (earned || item.inProgress) return img;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: img,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GameCard(
      padding: const EdgeInsets.all(12),
      selected: earned,
      child: Row(
        children: [
          SizedBox.square(dimension: 42, child: _achievementIcon()),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: TextStyle(
                    color: (earned || item.inProgress)
                        ? palette.ink
                        : palette.mutedInk,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  achievement.description,
                  style: TextStyle(color: palette.mutedInk, fontSize: 12),
                ),
                if (!earned && item.target > 1) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: item.fraction,
                            minHeight: 5,
                            backgroundColor: palette.track,
                            valueColor: AlwaysStoppedAnimation(
                              item.inProgress
                                  ? palette.route
                                  : palette.mutedInk,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.progressText,
                        style: TextStyle(
                          color: palette.mutedInk,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (earned)
            IconButton(
              tooltip: 'Share Achievement',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => const ShareDestinationService().open(
                ShareResult.achievement(
                  achievement.title,
                  achievement.description,
                ),
                ShareDestination.android,
              ),
            )
          else
            RewardAmount(achievement.coins, size: 18),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.title, this.value);

  final String title, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(title)),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}

class _CheckForUpdates extends StatefulWidget {
  const _CheckForUpdates();

  @override
  State<_CheckForUpdates> createState() => _CheckForUpdatesState();
}

class _CheckForUpdatesState extends State<_CheckForUpdates> {
  final _updates = UpdateService();
  bool _checking = false;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.system_update_outlined),
    title: const Text('Check for updates'),
    subtitle: _checking ? const Text('Checking Google Play…') : null,
    trailing: const Icon(Icons.chevron_right),
    onTap: _checking
        ? null
        : () async {
            setState(() => _checking = true);
            final messenger = ScaffoldMessenger.of(context);
            final outcome = await _updates.checkAndApply();
            if (!mounted) return;
            setState(() => _checking = false);
            final message = switch (outcome) {
              AppUpdateOutcome.upToDate => 'Pathwise is up to date.',
              AppUpdateOutcome.downloaded => 'Update installed.',
              AppUpdateOutcome.started => 'Update started.',
              AppUpdateOutcome.notCompleted => 'Update was cancelled.',
              AppUpdateOutcome.unavailable =>
                'Google Play updates are unavailable right now.',
              AppUpdateOutcome.unsupported =>
                'Updates are only supported on Android.',
            };
            messenger.showSnackBar(SnackBar(content: Text(message)));
          },
  );
}

class _NotificationSettingsSection extends StatelessWidget {
  const _NotificationSettingsSection({
    required this.model,
    required this.palette,
  });

  final AppModel model;
  final BoardPalette palette;

  String _formatMinutes(BuildContext context, int minutes) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return time.format(context);
  }

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<NotificationService?>();
    if (notifications == null) return const SizedBox.shrink();
    final prefs = model.notificationPreferences;
    final permitted = notifications.permissionGranted;
    final learnedMinutes = notifications.adaptiveMinutesFor(prefs);

    Future<void> toggleMaster(bool value) async {
      if (value && !permitted && !prefs.permissionAsked) {
        final granted = await notifications.requestPermission();
        model.updateNotificationPreferences((p) {
          p.permissionAsked = true;
          p.enabled = granted;
        });
        return;
      }
      model.updateNotificationPreferences((p) => p.enabled = value);
    }

    Future<void> pickPreferredTime() async {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: prefs.preferredMinutes ~/ 60,
          minute: prefs.preferredMinutes % 60,
        ),
      );
      if (picked != null) {
        model.updateNotificationPreferences(
          (p) => p.preferredMinutes = picked.hour * 60 + picked.minute,
        );
      }
    }

    Future<void> pickQuietHours() async {
      final start = await showTimePicker(
        context: context,
        helpText: 'Quiet hours start',
        initialTime: TimeOfDay(
          hour: prefs.quietStartMinutes ~/ 60,
          minute: prefs.quietStartMinutes % 60,
        ),
      );
      if (start == null || !context.mounted) return;
      final end = await showTimePicker(
        context: context,
        helpText: 'Quiet hours end',
        initialTime: TimeOfDay(
          hour: prefs.quietEndMinutes ~/ 60,
          minute: prefs.quietEndMinutes % 60,
        ),
      );
      if (end != null) {
        model.updateNotificationPreferences((p) {
          p.quietStartMinutes = start.hour * 60 + start.minute;
          p.quietEndMinutes = end.hour * 60 + end.minute;
        });
      }
    }

    final tiles = <Widget>[
      SwitchListTile(
        secondary: const Icon(Icons.notifications_none_rounded),
        title: const Text('Reminders'),
        subtitle: !permitted && prefs.permissionAsked
            ? const Text('Blocked in Android settings')
            : null,
        value: prefs.enabled && permitted,
        onChanged: toggleMaster,
      ),
      if (!permitted && prefs.permissionAsked)
        ListTile(
          title: const Text('Enable notifications in Android settings'),
          trailing: ActionPill(
            label: 'Open',
            onTap: notifications.openSystemSettings,
          ),
        ),
      if (prefs.enabled && permitted) ...[
        SwitchListTile(
          title: const Text('Daily challenge reminder'),
          value: prefs.dailyReminder,
          onChanged: (v) =>
              model.updateNotificationPreferences((p) => p.dailyReminder = v),
        ),
        SwitchListTile(
          title: const Text('Streak reminder'),
          value: prefs.streakReminder,
          onChanged: (v) =>
              model.updateNotificationPreferences((p) => p.streakReminder = v),
        ),
        SwitchListTile(
          title: const Text('Puzzle invitations'),
          value: prefs.inviteReminder,
          onChanged: (v) =>
              model.updateNotificationPreferences((p) => p.inviteReminder = v),
        ),
        SwitchListTile(
          title: const Text('Adaptive timing'),
          subtitle: Text(
            prefs.adaptiveTiming
                ? 'Learns your play times (${_formatMinutes(context, learnedMinutes)})'
                : 'Uses your preferred reminder time',
          ),
          value: prefs.adaptiveTiming,
          onChanged: (v) =>
              model.updateNotificationPreferences((p) => p.adaptiveTiming = v),
        ),
        ListTile(
          title: const Text('Preferred reminder time'),
          trailing: Text(
            _formatMinutes(context, prefs.preferredMinutes),
            style: TextStyle(
              color: palette.mutedInk,
              fontWeight: FontWeight.w700,
            ),
          ),
          onTap: pickPreferredTime,
        ),
        ListTile(
          title: const Text('Quiet hours'),
          trailing: Text(
            '${_formatMinutes(context, prefs.quietStartMinutes)} – ${_formatMinutes(context, prefs.quietEndMinutes)}',
            style: TextStyle(
              color: palette.mutedInk,
              fontWeight: FontWeight.w700,
            ),
          ),
          onTap: pickQuietHours,
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
            child: Text(
              'Notifications',
              style: TextStyle(
                color: palette.mutedInk,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ),
          GameCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: palette.cardEdge),
                  tiles[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
