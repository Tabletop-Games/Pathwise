import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/progression.dart';
import 'vector_path.dart';

const _marks = <Research, String>{
  Research.magnet: 'M 4 4 L 4 12 Q 4 20 11 20 Q 18 20 18 12 L 18 4 M 4 8 L 8 8 M 18 8 L 14 8 M 10 12 L 12 12',
  Research.golden: 'M 3 19 L 9 19 L 9 12 L 15 12 L 15 5 L 21 5 M 3 16 L 3 21 M 18 3 L 21 3 L 21 8',
  Research.fortune: 'M 4 6 L 20 6 L 20 20 L 4 20 Z M 4 10 L 20 10 M 8 4 L 8 8 M 16 4 L 16 8 M 12 12 L 15 15 L 12 18 L 9 15 Z',
  Research.mastery:
      'M 12 3 L 20 7 L 20 16 L 12 21 L 4 16 L 4 7 Z M 8 12 L 11 15 L 16 9',
  Research.hunter: 'M 3 9 L 12 5 L 21 9 L 21 17 L 12 21 L 3 17 Z M 3 9 L 12 13 L 21 9 M 12 13 L 12 21 M 10 9 L 14 9',
  Research.collector:
      'M 3 12 L 7 19 L 19 19 L 22 12 Z M 7 12 L 13 5 L 19 12 M 11 15 L 15 15',
  Research.efficiency: 'M 8 3 L 16 3 M 8 21 L 16 21 M 8 3 Q 7 8 12 12 Q 17 16 16 21 M 16 3 Q 17 8 12 12 Q 7 16 8 21 M 10 18 L 14 18',
  Research.savings: 'M 5 12 Q 5 7 11 7 L 15 7 L 18 4 L 18 8 L 21 10 L 21 14 L 18 14 L 17 19 L 14 19 L 14 16 L 9 16 L 9 19 L 6 19 L 6 16 Q 3 16 3 12 M 10 10 L 14 10',
  Research.momentum:
      'M 3 5 L 9 12 L 3 19 M 9 5 L 15 12 L 9 19 M 15 5 L 21 12 L 15 19',
  Research.specialist: 'M 3 7 L 21 7 L 21 19 L 3 19 Z M 8 4 L 8 9 M 16 4 L 16 9 M 6 15 L 10 12 L 14 15 L 18 12',
  Research.tuning: 'M 5 4 L 5 20 M 12 4 L 12 20 M 19 4 L 19 20 M 2 9 L 8 9 M 9 15 L 15 15 M 16 7 L 22 7',
  Research.procurement:
      'M 5 4 L 19 4 L 19 20 L 5 20 Z M 8 15 L 10 17 L 15 12 M 8 8 L 16 8',
  Research.scout:
      'M 3 18 L 7 10 L 12 13 L 17 5 L 21 18 Z M 14 9 L 17 11 L 19 10',
};

final _paths = _marks.map((item, path) => MapEntry(item, compileVector(path)));

class ResearchArtwork extends StatelessWidget {
  const ResearchArtwork(this.research, {required this.palette, super.key});

  final Research research;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 44,
      child: CustomPaint(painter: _ResearchPainter(research, palette)),
    ),
  );
}

class _ResearchPainter extends CustomPainter {
  const _ResearchPainter(this.research, this.palette);

  final Research research;
  final BoardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 28, size.height / 28);
    canvas.drawCircle(const Offset(14, 14), 13, Paint()..color = palette.tile);
    canvas.translate(2, 2);
    canvas.drawPath(
      _paths[research]!,
      Paint()
        ..color = palette.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ResearchPainter oldDelegate) =>
      oldDelegate.research != research || oldDelegate.palette != palette;
}
