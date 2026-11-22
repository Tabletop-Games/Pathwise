import 'package:material_ui/material_ui.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({required this.background, required this.ink, super.key});

  final Color background;
  final Color ink;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MarkPainter(background, ink),
    size: const Size.square(48),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.background, this.ink);
  final Color background, ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 48, 48),
        const Radius.circular(15),
      ),
      Paint()..color = background,
    );
    final route = Path()
      ..moveTo(13, 35)
      ..lineTo(13, 21)
      ..quadraticBezierTo(13, 17, 17, 17)
      ..lineTo(22, 17)
      ..quadraticBezierTo(25, 17, 25, 20)
      ..lineTo(25, 26)
      ..quadraticBezierTo(25, 29, 28, 29)
      ..lineTo(31, 29)
      ..quadraticBezierTo(35, 29, 35, 25)
      ..lineTo(35, 13);
    canvas.drawPath(
      route,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.3
        ..strokeCap = StrokeCap.round,
    );
    final node = Paint()..color = ink;
    canvas.drawCircle(const Offset(13, 35), 3.6, node);
    canvas.drawCircle(const Offset(35, 13), 3.6, node);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      background != oldDelegate.background || ink != oldDelegate.ink;
}
