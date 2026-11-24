import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../model/app_themes.dart';
import 'game_art.dart';

/// Spacing, radii and timings used across the whole app.
abstract final class GameTokens {
  static const double gap = 8;
  static const double gapSmall = 4;
  static const double gapLarge = 16;
  static const double margin = 16;
  static const double cardRadius = 20;
  static const double pillRadius = 999;
  static const double minTouch = 48;
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration reveal = Duration(milliseconds: 320);
}

/// Resolves the equipped [BoardPalette] from the ambient theme. Every screen
/// uses the same lookup, so no widget needs to know about providers.
extension PaletteLookup on BuildContext {
  BoardPalette get palette {
    final scheme = Theme.of(this).colorScheme;
    for (final candidate in BoardPalette.palettes.values) {
      if (candidate.route == scheme.primary &&
          candidate.surface == scheme.surface) {
        return candidate;
      }
    }
    return BoardPalette.palettes.values.first;
  }
}

/// Semantic surface colours derived from the palette.
extension GameColors on BoardPalette {
  /// Flat card surface. Slightly separated from the canvas on every theme.
  Color get card => Color.lerp(surface, canvas, dark ? .0 : .0)!;
  Color get cardEdge => Color.lerp(surface, ink, dark ? .16 : .09)!;
  Color get quiet => Color.lerp(tile, surface, .45)!;
  Color get track => Color.lerp(canvas, ink, dark ? .16 : .08)!;
  Color get mutedInk => Color.lerp(muted, ink, .2)!;

  /// Foreground that is readable on [background].
  Color onColor(Color background) => background.computeLuminance() > .42
      ? const Color(0xff161616)
      : const Color(0xfffafafa);
}

/// Flat card with a hairline edge in place of Material elevation.
class GameCard extends StatelessWidget {
  const GameCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
    this.color,
    this.selected = false,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = Material(
      color: color ?? p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GameTokens.cardRadius),
        side: BorderSide(
          color: selected ? p.route : p.cardEdge,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
    if (semanticLabel == null) return body;
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: ExcludeSemantics(child: body),
    );
  }
}

/// A small coin glyph for prices and balances.
class CoinMark extends StatelessWidget {
  const CoinMark({this.size = 18, super.key});
  final double size;

  @override
  Widget build(BuildContext context) =>
      GameArt(ArtKind.coin, palette: context.palette, size: size);
}

/// Price shown as coin icon and number. The currency is never spelled out.
class PricePill extends StatelessWidget {
  const PricePill({
    required this.price,
    this.onTap,
    this.affordable = true,
    this.semanticLabel,
    super.key,
  });

  final int price;
  final VoidCallback? onTap;
  final bool affordable;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fill = affordable ? p.route : p.quiet;
    final ink = affordable ? p.onRoute : p.mutedInk;
    return _PillFrame(
      onTap: onTap,
      semanticLabel: semanticLabel ?? '$price coins',
      fill: fill,
      border: affordable ? null : p.cardEdge,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoinMark(size: 16),
          const SizedBox(width: 5),
          Text(
            '$price',
            style: TextStyle(
              color: ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

enum ActionTone { primary, quiet, selected }

/// A compact action. Primary is the one obvious action; quiet is secondary;
/// selected marks the state that is already active.
class ActionPill extends StatelessWidget {
  const ActionPill({
    required this.label,
    this.onTap,
    this.tone = ActionTone.quiet,
    this.icon,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final ActionTone tone;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (fill, ink, border) = switch (tone) {
      ActionTone.primary => (p.route, p.onRoute, null),
      ActionTone.quiet => (p.quiet, p.ink, p.cardEdge),
      ActionTone.selected => (Colors.transparent, p.mutedInk, null),
    };
    final disabled = onTap == null && tone != ActionTone.selected;
    return _PillFrame(
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      fill: disabled ? p.quiet : fill,
      border: border,
      selected: tone == ActionTone.selected,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: disabled ? p.mutedInk : ink),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: disabled ? p.mutedInk : ink,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillFrame extends StatelessWidget {
  const _PillFrame({
    required this.child,
    required this.fill,
    required this.semanticLabel,
    this.onTap,
    this.border,
    this.selected = false,
  });

  final Widget child;
  final Color fill;
  final Color? border;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 36,
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(GameTokens.pillRadius),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: GameTokens.minTouch,
            minWidth: GameTokens.minTouch,
          ),
          child: Center(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}

/// Full-width pill selector. The track is a quiet surface and the selected
/// segment is the theme's route colour.
class GameSegmented<T> extends StatelessWidget {
  const GameSegmented({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<({T value, String label})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.track,
        borderRadius: BorderRadius.circular(GameTokens.pillRadius),
      ),
      child: Row(
        children: [
          for (final segment in segments)
            Expanded(
              child: Semantics(
                button: true,
                selected: segment.value == selected,
                label: segment.label,
                excludeSemantics: true,
                onTap: () => onChanged(segment.value),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(segment.value),
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : GameTokens.quick,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: segment.value == selected
                          ? p.route
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        GameTokens.pillRadius,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          segment.label,
                          maxLines: 1,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: segment.value == selected
                                ? p.onRoute
                                : p.mutedInk,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Progress as discrete stages. The last stage can carry a reward icon.
class ProgressPips extends StatelessWidget {
  const ProgressPips({
    required this.done,
    required this.total,
    this.finalReward = false,
    this.semanticLabel,
    super.key,
  });

  final int done, total;
  final bool finalReward;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: semanticLabel ?? '$done of $total',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            if (finalReward && i == total - 1)
              GameArt(ArtKind.gift, palette: p, size: 26)
            else
              AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : GameTokens.reveal,
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < done ? p.route : Colors.transparent,
                  border: Border.all(
                    color: i < done ? p.route : p.cardEdge,
                    width: 2,
                  ),
                ),
                child: i < done
                    ? Icon(Icons.check_rounded, size: 12, color: p.onRoute)
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}

/// A thin determinate bar in the theme colours.
class GameBar extends StatelessWidget {
  const GameBar({required this.value, this.height = 8, super.key});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(GameTokens.pillRadius),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        color: p.route,
        backgroundColor: p.track,
      ),
    );
  }
}

/// A reward amount with coin art, e.g. `+60`.
class RewardAmount extends StatelessWidget {
  const RewardAmount(
    this.amount, {
    this.size = 34,
    this.plus = true,
    super.key,
  });
  final int amount;
  final double size;
  final bool plus;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: '$amount coins',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GameArt(ArtKind.coin, palette: p, size: size),
          const SizedBox(width: 8),
          Text(
            '${plus ? '+' : ''}$amount',
            style: TextStyle(
              color: p.ink,
              fontSize: size * .95,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Balance chip used in headers. Tapping opens the Coins category.
class BalanceChip extends StatelessWidget {
  const BalanceChip({required this.coins, this.onTap, super.key});
  final int coins;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: onTap != null,
      label: '$coins coins',
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: GameTokens.minTouch,
            minWidth: GameTokens.minTouch,
          ),
          child: Center(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: p.quiet,
                borderRadius: BorderRadius.circular(GameTokens.pillRadius),
                border: Border.all(color: p.cardEdge),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CoinMark(size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '$coins',
                    style: TextStyle(
                      color: p.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      height: 1,
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

/// System bars follow the equipped canvas.
SystemUiOverlayStyle overlayFor(BoardPalette p) => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: p.dark ? Brightness.light : Brightness.dark,
  systemNavigationBarColor: p.canvas,
  systemNavigationBarIconBrightness: p.dark
      ? Brightness.light
      : Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);

/// A themed dialog frame: optional art, title, body and actions.
class GameDialog extends StatelessWidget {
  const GameDialog({
    required this.actions,
    this.art,
    this.title,
    this.body,
    this.child,
    super.key,
  });

  final Widget? art;
  final String? title;
  final String? body;
  final Widget? child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      backgroundColor: p.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: p.cardEdge),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (art != null) Center(child: art),
              if (title != null) ...[
                const SizedBox(height: 10),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    title!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              if (body != null) ...[
                const SizedBox(height: 6),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.mutedInk, fontSize: 15),
                ),
              ],
              if (child != null) ...[const SizedBox(height: 12), child!],
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showGameDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: builder,
);

/// Small icon-and-label chip for benefits and stats.
class InfoChip extends StatelessWidget {
  const InfoChip({required this.icon, required this.label, super.key});
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.quiet,
        borderRadius: BorderRadius.circular(GameTokens.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
