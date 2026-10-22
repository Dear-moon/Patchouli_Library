import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A developable sheet rolled around a cylinder. Coordinates run from the
/// binding toward the free edge; front and back share the exact tangent.
class ReaderPaperGeometry {
  ReaderPaperGeometry({
    required this.size,
    required this.progress,
    required this.touchY,
    this.gap = 0,
  }) {
    front = _surface(back: false, textured: false);
    back = _surface(back: true, textured: false);
    frontInk = _surface(back: false, textured: true);
    backInk = _surface(back: true, textured: true);
    sheet = ui.Path.combine(
      ui.PathOperation.union,
      front.outline,
      back.outline,
    );
  }
  final ui.Size size;
  final double progress, touchY, gap;
  double get width => size.width + gap;
  late final double lift = math.sin(math.pi * progress);
  late final double radius = width * .12 * lift;
  late final double start = width * (1 - progress) - math.pi * radius / 2;
  late final double angle = (1 - 2 * touchY) * .20 * lift;
  late final double _cos = math.cos(angle), _sin = math.sin(angle);
  late final ReaderPaperMesh front, back, frontInk, backInk;
  late final ui.Path sheet;
  double _tangent(double y) =>
      start + (math.pi * radius / 2 + (y - size.height / 2) * _sin) / _cos;
  ({ui.Offset point, double normal}) project(double u, double y) {
    final c = _cos, s = _sin;
    final d = (u - start) * c - (y - size.height / 2) * s;
    final along = (u - start) * s + (y - size.height / 2) * c;
    final theta = radius < .00001
        ? (d <= 0 ? 0.0 : math.pi)
        : (d / radius).clamp(0.0, math.pi);
    final rolled = d <= 0
        ? d
        : d <= math.pi * radius
        ? radius * math.sin(theta)
        : math.pi * radius - d;
    final z = radius * (1 - math.cos(theta));
    final perspective = width * 4 / (width * 4 - z);
    return (
      point: ui.Offset(
        (start + c * rolled + s * along) * perspective,
        size.height / 2 + (-s * rolled + c * along) * perspective,
      ),
      normal: math.cos(theta),
    );
  }

  static const _columns = 48, _rows = 12;
  static final _indices = Uint16List.fromList([
    for (var row = 0; row < _rows; row++)
      for (var column = 0; column < _columns; column++) ...[
        row * (_columns + 1) + column,
        (row + 1) * (_columns + 1) + column,
        row * (_columns + 1) + column + 1,
        row * (_columns + 1) + column + 1,
        (row + 1) * (_columns + 1) + column,
        (row + 1) * (_columns + 1) + column + 1,
      ],
  ]);
  ReaderPaperMesh _surface({required bool back, required bool textured}) {
    const columns = _columns, rows = _rows;
    final count = (columns + 1) * (rows + 1);
    final positions = Float32List(count * 2),
        uv = Float32List(count * 2),
        normals = Float32List(count);
    final minU = textured ? gap : 0.0;
    for (var row = 0; row <= rows; row++) {
      final y = size.height * row / rows;
      final tangent = _tangent(y).clamp(minU, width);
      final a = back ? tangent : minU, b = back ? width : tangent;
      for (var column = 0; column <= columns; column++) {
        final u = a + (b - a) * column / columns;
        final point = project(u, y);
        final index = row * (columns + 1) + column;
        positions[index * 2] = point.point.dx;
        positions[index * 2 + 1] = point.point.dy;
        uv[index * 2] = (u - gap).clamp(0.0, size.width);
        uv[index * 2 + 1] = y;
        normals[index] = point.normal;
      }
    }
    // Outline follows the same quantized positions as the rasterized mesh.
    // Sharing those edges avoids a thin gap between front/back clip planes.
    ui.Offset pointAt(int index) =>
        ui.Offset(positions[index * 2], positions[index * 2 + 1]);
    final outline = ui.Path()..moveTo(positions[0], positions[1]);
    for (var column = 1; column <= columns; column++) {
      final point = pointAt(column);
      outline.lineTo(point.dx, point.dy);
    }
    for (var row = 1; row <= rows; row++) {
      final point = pointAt(row * (columns + 1) + columns);
      outline.lineTo(point.dx, point.dy);
    }
    for (var column = columns - 1; column >= 0; column--) {
      final point = pointAt(rows * (columns + 1) + column);
      outline.lineTo(point.dx, point.dy);
    }
    for (var row = rows - 1; row > 0; row--) {
      final point = pointAt(row * (columns + 1));
      outline.lineTo(point.dx, point.dy);
    }
    outline.close();
    return ReaderPaperMesh(positions, uv, normals, _indices, outline);
  }
}

class ReaderPaperMesh {
  ReaderPaperMesh(
    this.positions,
    this.uv,
    this.normals,
    this.indices,
    this.outline,
  );
  final Float32List positions, uv, normals;
  final Uint16List indices;
  final ui.Path outline;
}
