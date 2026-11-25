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
              final chapter = await showModalBottomSheet<int>(
                context: context,
                builder: (sheet) => SafeArea(
                  child: ListView.builder(
                    itemBuilder: (context, chapter) {
                      final start = chapter * chapterSize + 1;
                      return ListTile(
                        enabled: model.canPlayLevel(start),
                        leading: Icon(
                          model.canPlayLevel(start)
                              ? Icons.terrain
                              : Icons.lock_outline,
                        ),
                        title: Text(chapterName(chapter)),
                        subtitle: Text('Levels $start–${chapterEnd(chapter)}'),
                        onTap: () => Navigator.pop(sheet, chapter),
                      );
                    },
                  ),
                ),
              );
              if (mounted && chapter != null)
                _go(pageForLevel(chapter * chapterSize + 1));
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: const AdBanner(),
      body: SafeArea(
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
                            'Levels $first–${first + levelsPerPage - 1}',
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
                                biomeAssetPath(biomeForTheme(model.theme)),
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
                        chapterName(chapterFor(first)),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      LinearProgressIndicator(
                        value:
                            Iterable<int>.generate(
                                  chapterEnd(chapterFor(first)) -
                                      chapterFor(first) * chapterSize,
                                  (index) =>
                                      chapterFor(first) * chapterSize +
                                      index +
                                      1,
                                )
                                .where(
                                  (level) =>
                                      model.result(PuzzleId.level(level)) !=
                                      null,
                                )
                                .length /
                            chapterSize,
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
                                if (mounted && model.highestUnlocked > level) {
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
        : (enabled ? palette.ink : palette.mutedInk.withValues(alpha: .7));
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${id.level}',
                      maxLines: 1,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      ),
                    ),
                    if (solved)
                      Text(
                        status,
                        maxLines: 1,
                        style: TextStyle(
                          color: foreground.withValues(alpha: .75),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                if (solved)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GameArt(ArtKind.check, palette: palette, size: 16),
                  ),
                if (current)
                  Positioned(
                    bottom: 6,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: foreground,
                    ),
                  ),
                if (!enabled)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GameArt(ArtKind.lock, palette: palette, size: 16),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
