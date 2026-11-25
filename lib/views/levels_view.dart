import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import '../model/journey.dart';
import '../ui/art/game_assets.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'campaign_journey_view.dart';
import 'components/ad_banner.dart';
import 'main_menu_view.dart';
import 'puzzle_view.dart';

class LevelsView extends StatefulWidget {
  const LevelsView({this.quickNavigation = false, super.key});
  final bool quickNavigation;

  @override
  State<LevelsView> createState() => _LevelsViewState();
}

class _LevelsViewState extends State<LevelsView> {
  late int _page;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _page = pageForLevel(context.read<AppModel>().highestUnlocked);
    _controller = PageController(initialPage: _page);
  }

  void _go(int page) {
    if (page < 0 || !_controller.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context) || (page - _page).abs() > 3) {
      _controller.jumpToPage(page);
    } else {
      _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.quickNavigation) return const CampaignJourneyView();
    context.select(
      (AppModel model) => (
        model.theme,
        model.highestUnlocked,
        model.levelsSolved,
        model.complete,
        model.activeId == null,
      ),
    );
    final model = context.read<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final first = firstLevelOnPage(_page);
    final last = first + levelsPerPage - 1;
    final firstChapter = chapterFor(first);
    final lastChapter = chapterFor(last);
    final primaryChapter = chapterFor(first + (levelsPerPage ~/ 2));
    final chapterTitle = firstChapter == lastChapter
        ? chapterName(primaryChapter)
        : 'Chapters ${firstChapter + 1}–${lastChapter + 1} · ${chapterName(primaryChapter)}';
    final clears = model.chapterClears(primaryChapter);
    final chapterBiome =
        BiomeKind.values[primaryChapter % BiomeKind.values.length];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Levels'),
        actions: [
          IconButton(
            tooltip: 'Current level',
            onPressed: () => _go(pageForLevel(model.highestUnlocked)),
            icon: const Icon(Icons.my_location_rounded),
          ),
          IconButton(
            tooltip: 'Chapters',
            icon: const Icon(Icons.map_outlined),
            onPressed: () async {
              final maxChapters = chapterFor(model.highestUnlocked) + 2;
              final chapter = await showModalBottomSheet<int>(
                context: context,
                builder: (sheet) => SafeArea(
                  child: ListView.builder(
                    itemCount: maxChapters,
                    itemBuilder: (context, chapter) {
                      final start = chapter * chapterSize + 1;
                      final unlocked = model.canPlayLevel(start);
                      return ListTile(
                        enabled: unlocked,
                        leading: unlocked
                            ? const Icon(Icons.terrain)
                            : GameArt(ArtKind.lock, palette: palette, size: 22),
                        title: Text(chapterName(chapter)),
                        subtitle: Text('Levels $start–${chapterEnd(chapter)}'),
                        onTap: () => Navigator.pop(sheet, chapter),
                      );
                    },
                  ),
                ),
              );
              if (mounted && chapter != null) {
                _go(pageForLevel(chapter * chapterSize + 1));
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: const AdBanner(),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: _page == 0 ? null : () => _go(_page - 1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              'Levels $first–$last',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: () => _go(_page + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            height: 64,
                            width: double.infinity,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  biomeAssetPath(chapterBiome),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          palette.cardTop,
                                          palette.cardBottom,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        palette.surface.withValues(
                                          alpha: palette.dark ? .20 : .14,
                                        ),
                                        palette.surface.withValues(
                                          alpha: palette.dark ? .52 : .42,
                                        ),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: palette.cardEdge.withValues(
                                        alpha: .7,
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: GameBar(value: clears / chapterSize),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '$clears / $chapterSize puzzles',
                              style: TextStyle(
                                color: palette.mutedInk,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      allowImplicitScrolling: true,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, page) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                        child: LayoutBuilder(
                          builder: (context, constraints) => GridView.builder(
                            itemCount: levelsPerPage,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  mainAxisExtent:
                                      ((constraints.maxHeight - 30) / 4).clamp(
                                        85,
                                        double.infinity,
                                      ),
                                ),
                            itemBuilder: (context, index) {
                              final level = firstLevelOnPage(page) + index;
                              final id = PuzzleId.level(level);
                              final result = model.result(id);
                              return _LevelTile(
                                id: id,
                                result: result,
                                palette: palette,
                                current: level == model.highestUnlocked,
                                enabled: model.canPlayLevel(level),
                                onTap: () async {
                                  await openPuzzle(
                                    context,
                                    id,
                                    replay:
                                        result != null && !model.hasAttempt(id),
                                  );
                                  if (mounted &&
                                      model.highestUnlocked > level) {
                                    _go(pageForLevel(model.highestUnlocked));
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
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

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.id,
    required this.result,
    required this.palette,
    required this.current,
    required this.enabled,
    required this.onTap,
  });

  final PuzzleId id;
  final RunResult? result;
  final BoardPalette palette;
  final bool current;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final solved = result != null;
    final background = current
        ? palette.route
        : solved
        ? palette.card
        : (enabled ? palette.card : palette.quiet);
    final foreground = current
        ? palette.onRoute
        : (enabled ? palette.ink : palette.mutedInk);
    final status = solved
        ? formatTime(Duration(milliseconds: result!.milliseconds))
        : (current
              ? 'Current'
              : enabled
              ? 'Available'
              : 'Locked');
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Level ${id.level}, $status',
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: current ? palette.accent : palette.cardEdge,
            width: current ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                children: [
                  SizedBox(
                    height: 16,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: solved
                          ? GameArt(ArtKind.check, palette: palette, size: 15)
                          : (!enabled
                                ? GameArt(
                                    ArtKind.lock,
                                    palette: palette,
                                    size: 15,
                                  )
                                : null),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${id.level}',
                          maxLines: 1,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: id.level >= 10000 ? 18 : 22,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 16,
                    child: Center(
                      child: solved
                          ? Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: current
                                    ? foreground.withValues(alpha: .88)
                                    : palette.mutedInk,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                height: 1.1,
                              ),
                            )
                          : (current
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        size: 15,
                                        color: foreground,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        'PLAY',
                                        style: TextStyle(
                                          color: foreground,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 10,
                                          letterSpacing: 0.6,
                                          height: 1.0,
                                        ),
                                      ),
                                    ],
                                  )
                                : null),
                    ),
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
