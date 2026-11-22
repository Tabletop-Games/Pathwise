import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import 'components/ad_banner.dart';
import 'main_menu_view.dart';
import 'puzzle_view.dart';

class LevelsView extends StatefulWidget {
  const LevelsView({super.key});

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
          TextButton(
            onPressed: () => _go(pageForLevel(model.highestUnlocked)),
            child: const Text('Current level'),
          ),
          const SizedBox(width: 8),
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
    final background = current
        ? palette.route
        : (enabled ? palette.surface : palette.tile);
    final foreground = current
        ? palette.onRoute
        : (enabled ? palette.ink : palette.muted);
    final status = result == null
        ? (current
              ? 'Current'
              : enabled
              ? 'Available'
              : 'Locked')
        : formatTime(Duration(milliseconds: result!.milliseconds));
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Level ${id.level}, $status',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  result != null
                      ? Icons.check_circle_outline
                      : current
                      ? Icons.play_arrow_rounded
                      : enabled
                      ? Icons.grid_view_rounded
                      : Icons.lock_outline_rounded,
                  size: 18,
                  color: foreground,
                ),
                Text(
                  '${id.level}',
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 23,
                  ),
                ),
                Text(
                  status,
                  maxLines: 1,
                  style: TextStyle(color: foreground, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
