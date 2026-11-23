import 'dart:io';

import '../lib/model/native_achievements.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/export_play_games_achievements.dart OUTPUT_DIRECTORY',
    );
    exitCode = 64;
    return;
  }
  final output = Directory(args.single)..createSync(recursive: true);
  final metadata = StringBuffer();
  final mappings = StringBuffer();
  final icons = <String>{};
  for (final (index, item) in nativeAchievements.indexed) {
    final icon = switch (item.metric) {
      AchievementMetric.solves => 'progression',
      AchievementMetric.hintFree || AchievementMetric.precision => 'skill',
      AchievementMetric.daily => 'daily',
      AchievementMetric.attackFinished ||
      AchievementMetric.attackScore => 'attack',
      AchievementMetric.trails ||
      AchievementMetric.perfectTrails => 'expedition',
      AchievementMetric.research => 'research',
      AchievementMetric.themes => 'themes',
      AchievementMetric.crates => 'crates',
    };
    // Google bulk import rejects commas in names and descriptions.
    metadata.writeln(
      [
        item.name.replaceAll(',', ''),
        item.description.replaceAll(',', ''),
        item.incremental ? 'True' : 'False',
        item.incremental ? item.target : '',
        item.hidden ? 'Hidden' : 'Revealed',
        20,
        index + 1,
      ].join(','),
    );
    mappings.writeln('${item.name.replaceAll(',', '')},$icon.png');
    icons.add(icon);
  }
  for (final icon in icons) {
    File('docs/media/play-games/$icon.png')
        .copySync('${output.path}/$icon.png');
  }
  File('${output.path}/AchievementsMetadata.csv')
      .writeAsStringSync(metadata.toString());
  File('${output.path}/AchievementsIconsMappings.csv')
      .writeAsStringSync(mappings.toString());
}
