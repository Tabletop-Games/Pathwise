import 'package:material_ui/material_ui.dart';

/// Compiles the restricted, absolute SVG vocabulary used by the authored
/// artwork. Keep compiled paths out of paint loops.
Path compileVector(String data) {
  final path = Path();
  if (data.isEmpty) return path;
  final tokens = data.split(' ');
  var next = 0;
  double number() => double.parse(tokens[next++]);
  while (next < tokens.length) {
    switch (tokens[next++]) {
      case 'M':
        path.moveTo(number(), number());
      case 'L':
        path.lineTo(number(), number());
      case 'Q':
        path.quadraticBezierTo(number(), number(), number(), number());
      case 'C':
        path.cubicTo(
          number(),
          number(),
          number(),
          number(),
          number(),
          number(),
        );
      case 'Z':
        path.close();
      default:
        throw FormatException('Unexpected artwork command', data);
    }
  }
  return path;
}
