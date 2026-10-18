import 'package:flutter/material.dart';

/// Where the back should sit in the camera preview.
/// All values are fractions of the preview (0.0 to 1.0), so they work on
/// any screen size. The live checker uses these same numbers later.
class BackGuide {
  static const Rect box = Rect.fromLTRB(0.15, 0.08, 0.85, 0.92);
  static const double centerX = 0.5;
  static const double shoulderY = 0.28;
  static const double hipY = 0.72;
}

class AlignmentOverlayPainter extends CustomPainter {
  final Color color;
  const AlignmentOverlayPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      BackGuide.box.left * size.width,
      BackGuide.box.top * size.height,
      BackGuide.box.right * size.width,
      BackGuide.box.bottom * size.height,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));

    // Darken everything outside the guide box.
    final dimPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      dimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Corner brackets.
    const len = 28.0;
    void corner(Offset c, double dx, double dy) {
      canvas.drawLine(c, c.translate(dx * len, 0), stroke);
      canvas.drawLine(c, c.translate(0, dy * len), stroke);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);

    final thin = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2;

    // Dashed center line (the spine should follow it).
    final cx = BackGuide.centerX * size.width;
    for (double y = rect.top + 8; y < rect.bottom - 8; y += 16) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + 8), thin);
    }

    // Dashed shoulder and hip lines, with labels.
    void marker(double fraction, String label) {
      final y = fraction * size.height;
      for (double x = rect.left + 8; x < rect.right - 8; x += 16) {
        canvas.drawLine(Offset(x, y), Offset(x + 8, y), thin);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left + 12, y - tp.height - 4));
    }

    marker(BackGuide.shoulderY, 'Shoulders');
    marker(BackGuide.hipY, 'Hips');
  }

  @override
  bool shouldRepaint(covariant AlignmentOverlayPainter old) =>
      old.color != color;
}
