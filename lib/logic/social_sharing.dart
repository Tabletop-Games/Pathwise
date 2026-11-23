import 'package:flutter/services.dart';

abstract final class ShareLinks {
  static const playStore =
      'https://play.google.com/store/apps/details?id=games.tabletop.pathwise';
}

enum ShareDestination {
  android('More Apps'),
  whatsapp('WhatsApp'),
  x('X'),
  linkedin('LinkedIn'),
  telegram('Telegram');

  const ShareDestination(this.label);
  final String label;
}

abstract final class SharePromptPolicy {
  static const _earlyLevels = [10, 25, 50, 100, 250, 500, 1000];

  static bool levelMilestone(int level) =>
      _earlyLevels.contains(level) || (level > 1000 && level % 500 == 0);

  static int? lastLevelMilestone(int level) => level >= 1000
      ? level ~/ 500 * 500
      : _earlyLevels.where((milestone) => milestone <= level).lastOrNull;
}

final class ShareResult {
  const ShareResult._(this.heading, this.details, this.invitation);

  factory ShareResult.daily(
    String day, {
    required Duration time,
    required int hints,
    required bool newBest,
  }) {
    final date = DateTime.parse(day);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return ShareResult._(
      'Pathwise Daily Challenge — ${date.day} ${months[date.month - 1]} ${date.year}',
      'Solved in ${_duration(time)}. Hints used: $hints.'
          '${newBest ? ' New personal best!' : ''}',
      'Think you can beat my time?',
    );
  }

  factory ShareResult.attack({
    required int score,
    required int puzzles,
    required bool newBest,
  }) => ShareResult._(
    newBest
        ? 'New Pathwise Time Attack personal best!'
        : 'Pathwise Time Attack',
    '$score points. $puzzles ${puzzles == 1 ? 'puzzle' : 'puzzles'} solved.',
    'Think you can beat that?',
  );

  factory ShareResult.level({required int level, required int total}) =>
      ShareResult._(
        'Level $level cleared in Pathwise!',
        '$total levels cleared.',
        'Can you catch up?',
      );

  factory ShareResult.achievement(String name, String description) =>
      ShareResult._(
        'Pathwise Achievement Unlocked',
        '$name — $description',
        'Think you can unlock it too?',
      );

  factory ShareResult.research(String name, int rank) => ShareResult._(
    'Pathwise Research Milestone',
    'I reached rank $rank in $name.',
    'What would you research first?',
  );

  factory ShareResult.cosmetic(String name) => ShareResult._(
    'Pathwise Theme Unlocked',
    'I added $name to my collection.',
    'Which theme would you choose?',
  );

  final String heading, details, invitation;

  static String _duration(Duration time) {
    final minutes = time.inMinutes;
    final seconds = time.inSeconds.remainder(60);
    return minutes == 0 ? '${seconds}s' : '${minutes}m ${seconds}s';
  }
}

abstract final class ShareContentBuilder {
  /// These templates contain no nested URLs, emoji or player-entered text.
  static const xPostLimit = 280;
  static const xShortenedLinkLength = 23;
  static const _xBodyLimit = xPostLimit - xShortenedLinkLength - 2;

  static String caption(ShareResult result, ShareDestination destination) {
    final ShareResult(:heading, :details, :invitation) = result;
    return switch (destination) {
      ShareDestination.x =>
        '$heading\n${_xDetails(details, heading, invitation)}\n$invitation',
      ShareDestination.linkedin =>
        '$heading\n\n$details\n\nTry this route-drawing puzzle on Google Play.',
      ShareDestination.whatsapp => '$heading\n\n$details\n\n$invitation',
      ShareDestination.telegram => '$heading\n$details\n\n$invitation',
      ShareDestination.android => '$heading\n\n$details\n$invitation',
    };
  }

  static String _xDetails(String text, String heading, String invitation) {
    // X counts a range of Unicode characters as two. Use a conservative
    // estimate outside ASCII so even long translated achievement names fit.
    var count = '\n\n$heading$invitation'.runes.fold(
      0,
      (sum, rune) => sum + (rune <= 127 ? 1 : 2),
    );
    final body = StringBuffer();
    for (final rune in text.runes) {
      count += rune <= 127 ? 1 : 2;
      if (count >= _xBodyLimit - 2) return '${body.toString().trimRight()}…';
      body.writeCharCode(rune);
    }
    return text;
  }

  static String message(ShareResult result, ShareDestination destination) =>
      '${caption(result, destination)}\n\n${ShareLinks.playStore}';

  static Uri? web(ShareResult result, ShareDestination destination) =>
      switch (destination) {
        ShareDestination.x => Uri.https('twitter.com', '/intent/tweet', {
          'text': caption(result, destination),
          'url': ShareLinks.playStore,
        }),
        ShareDestination.linkedin => Uri.https(
          'www.linkedin.com',
          '/sharing/share-offsite/',
          {'url': ShareLinks.playStore},
        ),
        ShareDestination.telegram => Uri.https('t.me', '/share/url', {
          'url': ShareLinks.playStore,
          'text': caption(result, destination),
        }),
        _ => null,
      };
}

class ShareDestinationService {
  const ShareDestinationService();

  static const _channel = MethodChannel('games.tabletop.pathwise/share');

  Future<bool> _open(String method, String content) async {
    try {
      return await _channel.invokeMethod<bool>(method, {'content': content}) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> copyMessage(ShareResult result, ShareDestination destination) =>
      Clipboard.setData(
        ClipboardData(text: ShareContentBuilder.message(result, destination)),
      );

  Future<void> copyLink() =>
      Clipboard.setData(const ClipboardData(text: ShareLinks.playStore));

  Future<bool> open(ShareResult result, ShareDestination destination) async {
    final message = ShareContentBuilder.message(result, destination);
    if (destination == ShareDestination.linkedin) {
      await copyMessage(result, destination);
    }
    final url = ShareContentBuilder.web(result, destination);
    if (url != null && await _open('web', url.toString())) return true;
    if (destination == ShareDestination.whatsapp &&
        await _open('whatsapp', message))
      return true;
    return _open('chooser', message);
  }
}
