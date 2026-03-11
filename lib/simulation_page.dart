import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../models/server_model.dart';
import '../models/cooling_model.dart';
import '../services/simulation_engine.dart';
import '../widgets/server_tooltip.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════════

class _Particle {
  final double startX, startZ; // world origin
  final double phase;          // animation phase offset (0-1)
  final double speed;          // relative speed multiplier
  final double wobble;         // lateral sway amount
  final bool isHeat;           // true = heat, false = cool air

  const _Particle({
    required this.startX,
    required this.startZ,
    required this.phase,
    required this.speed,
    required this.wobble,
    required this.isHeat,
  });
}

// Server rack position in world space (x, z)
const List<(double, double)> kRackPositions = [
  (1.0, 1.0), (1.0, 3.0), (1.0, 5.0),
  (3.5, 1.0), (3.5, 3.0), (3.5, 5.0),
];

// Cooling unit position
const (double, double) kCoolingPos = (6.5, 3.0);

// Rack dimensions in world units
const double kRackW = 0.9, kRackD = 0.5, kRackH = 2.0;
// Cooling unit dimensions
const double kCoolW = 1.2, kCoolD = 0.9, kCoolH = 1.4;
// Floor size
const int kFloorSize = 10;

// ═══════════════════════════════════════════════════════════════════════════════
// SIMULATION PAGE
// ═══════════════════════════════════════════════════════════════════════════════

class SimulationPage extends StatefulWidget {
  const SimulationPage({super.key});

  @override
  State<SimulationPage> createState() => _SimulationPageState();
}

class _SimulationPageState extends State<SimulationPage>
    with TickerProviderStateMixin {
  late AnimationController _animCtrl;

  double _rotationY = -0.35;    // world rotation around Y
  double _zoom = 52.0;           // scale factor
  Offset _pan = const Offset(0, -80);  // camera pan

  Offset? _hoverPos;
  int? _hoveredServerId;

  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    _particles = _generateParticles();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  List<_Particle> _generateParticles() {
    final rng = math.Random(42);
    final particles = <_Particle>[];

    // Heat particles above each server rack (6 racks × 5 particles)
    for (final (rx, rz) in kRackPositions) {
      for (int p = 0; p < 6; p++) {
        particles.add(_Particle(
          startX: rx + kRackW / 2 + (rng.nextDouble() - 0.5) * kRackW * 0.8,
          startZ: rz + kRackD / 2 + (rng.nextDouble() - 0.5) * kRackD * 0.8,
          phase: rng.nextDouble(),
          speed: 0.6 + rng.nextDouble() * 0.8,
          wobble: (rng.nextDouble() - 0.5) * 0.3,
          isHeat: true,
        ));
      }
    }

    // Airflow particles from cooling unit (12 particles)
    for (int p = 0; p < 14; p++) {
      particles.add(_Particle(
        startX: kCoolingPos.$1 + kCoolW / 2,
        startZ: kCoolingPos.$2 + (rng.nextDouble() - 0.5) * kCoolD,
        phase: rng.nextDouble(),
        speed: 0.4 + rng.nextDouble() * 0.6,
        wobble: (rng.nextDouble() - 0.5) * 0.25,
        isHeat: false,
      ));
    }

    return particles;
  }

  // ─── Interaction helpers ───────────────────────────────────────────────────

  void _onPointerScroll(PointerScrollEvent e) {
    setState(() {
      _zoom = (_zoom - e.scrollDelta.dy * 0.5).clamp(20.0, 140.0);
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _rotationY += d.delta.dx * 0.008;
    });
  }

  void _onSecondaryDragUpdate(DragUpdateDetails d) {
    setState(() {
      _pan += d.delta;
    });
  }

  void _onHover(PointerHoverEvent e) {
    setState(() {
      _hoverPos = e.localPosition;
      _updateHoveredServer(e.localPosition);
    });
  }

  void _updateHoveredServer(Offset pos) {
    final engine = context.read<SimulationEngine>();
    final servers = engine.servers;
    final size = context.size ?? Size.zero;
    final center = Offset(size.width / 2 + _pan.dx, size.height / 2 + _pan.dy);

    for (final s in servers) {
      final (wx, wz) = kRackPositions[s.id];
      final topPoly = _rackTopPolygon(wx, wz, center);
      if (_pointInPolygon(pos, topPoly)) {
        _hoveredServerId = s.id;
        return;
      }
    }
    _hoveredServerId = null;
  }

  List<Offset> _rackTopPolygon(double wx, double wz, Offset center) {
    return [
      _project(wx, kRackH, wz, center),
      _project(wx + kRackW, kRackH, wz, center),
      _project(wx + kRackW, kRackH, wz + kRackD, center),
      _project(wx, kRackH, wz + kRackD, center),
    ];
  }

  Offset _project(double x, double y, double z, Offset center) {
    final rx = x * math.cos(_rotationY) - z * math.sin(_rotationY);
    final rz = x * math.sin(_rotationY) + z * math.cos(_rotationY);
    final sx = (rx - rz) * _zoom;
    final sy = (rx + rz) * _zoom * 0.4 - y * _zoom * 0.85;
    return center + Offset(sx, sy);
  }

  bool _pointInPolygon(Offset p, List<Offset> poly) {
    bool inside = false;
    int j = poly.length - 1;
    for (int i = 0; i < poly.length; i++) {
      if ((poly[i].dy > p.dy) != (poly[j].dy > p.dy) &&
          p.dx <
              (poly[j].dx - poly[i].dx) *
                      (p.dy - poly[i].dy) /
                      (poly[j].dy - poly[i].dy) +
                  poly[i].dx) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();
    final servers = engine.servers;
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2 + _pan.dx, size.height / 2 + _pan.dy);

    return Scaffold(
      backgroundColor: const Color(0xFF040410),
      body: Stack(
        children: [
          // ── 3D Canvas ────────────────────────────────────────────────────
          Positioned.fill(
            child: Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) _onPointerScroll(e);
              },
              child: MouseRegion(
                onHover: _onHover,
                onExit: (_) => setState(() {
                  _hoverPos = null;
                  _hoveredServerId = null;
                }),
                child: GestureDetector(
                  onPanUpdate: _onDragUpdate,
                  onSecondaryLongPressMoveUpdate: (d) {
                    setState(() => _pan += d.offsetFromOrigin);
                  },
                  child: AnimatedBuilder(
                    animation: _animCtrl,
                    builder: (ctx, _) {
                      return CustomPaint(
                        size: Size.infinite,
                        painter: _DataCenterPainter(
                          animValue: _animCtrl.value,
                          rotationY: _rotationY,
                          zoom: _zoom,
                          pan: _pan,
                          servers: servers,
                          cooling: engine.coolingModel,
                          particles: _particles,
                          hoveredServerId: _hoveredServerId,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // ── Top Bar ──────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _SimTopBar(onBack: () => Navigator.of(context).pop()),
          ),

          // ── Server List Panel ────────────────────────────────────────────
          Positioned(
            top: 56,
            right: 12,
            child: _ServerListPanel(servers: servers),
          ),

          // ── Controls Legend ──────────────────────────────────────────────
          Positioned(
            bottom: 12,
            left: 12,
            child: _ControlsLegend(),
          ),

          // ── Room Temp Badge ───────────────────────────────────────────────
          Positioned(
            bottom: 12,
            right: 12,
            child: _RoomTempBadge(engine: engine),
          ),

          // ── Server Tooltip ────────────────────────────────────────────────
          if (_hoveredServerId != null && _hoverPos != null)
            ServerTooltipOverlay(
              server: servers[_hoveredServerId!],
              screenPosition: _hoverPos!,
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3D PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _DataCenterPainter extends CustomPainter {
  final double animValue;
  final double rotationY;
  final double zoom;
  final Offset pan;
  final List<ServerModel> servers;
  final CoolingModel cooling;
  final List<_Particle> particles;
  final int? hoveredServerId;

  _DataCenterPainter({
    required this.animValue,
    required this.rotationY,
    required this.zoom,
    required this.pan,
    required this.servers,
    required this.cooling,
    required this.particles,
    required this.hoveredServerId,
  });

  // ─── Projection ────────────────────────────────────────────────────────────

  Offset _proj(double x, double y, double z, Offset center) {
    final rx = x * math.cos(rotationY) - z * math.sin(rotationY);
    final rz = x * math.sin(rotationY) + z * math.cos(rotationY);
    final sx = (rx - rz) * zoom;
    final sy = (rx + rz) * zoom * 0.4 - y * zoom * 0.85;
    return center + Offset(sx, sy);
  }

  double _depth(double wx, double wz) {
    final rx = wx * math.cos(rotationY) - wz * math.sin(rotationY);
    final rz = wx * math.sin(rotationY) + wz * math.cos(rotationY);
    return rx + rz;
  }

  // ─── Face Visibility ──────────────────────────────────────────────────────

  bool get _frontFaceVisible => math.cos(rotationY) - math.sin(rotationY) > 0;
  bool get _leftFaceVisible  => math.cos(rotationY) + math.sin(rotationY) > 0;

  // ─── Colour helpers ────────────────────────────────────────────────────────

  Color _darken(Color c, double amount) => Color.lerp(c, Colors.black, amount)!;
  Color _lighten(Color c, double amount) => Color.lerp(c, Colors.white, amount)!;

  // ─── Draw an isometric box ─────────────────────────────────────────────────

  void _drawBox(
    Canvas canvas,
    Offset center,
    double wx, double wy, double wz,
    double w, double h, double d,
    Color baseColor, {
    bool glow = false,
    Color? glowColor,
  }) {
    // 8 corners
    final p = [
      _proj(wx,     wy,     wz,     center), // 0 BLF bottom-left-front
      _proj(wx + w, wy,     wz,     center), // 1 BRF
      _proj(wx + w, wy,     wz + d, center), // 2 BRB
      _proj(wx,     wy,     wz + d, center), // 3 BLB
      _proj(wx,     wy + h, wz,     center), // 4 TLF top-left-front
      _proj(wx + w, wy + h, wz,     center), // 5 TRF
      _proj(wx + w, wy + h, wz + d, center), // 6 TRB
      _proj(wx,     wy + h, wz + d, center), // 7 TLB
    ];

    // Glow effect behind the box
    if (glow && glowColor != null) {
      final gCenter = _proj(wx + w / 2, wy + h / 2, wz + d / 2, center);
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [glowColor, Colors.transparent],
        ).createShader(
          Rect.fromCenter(center: gCenter, width: zoom * 3, height: zoom * 2),
        )
        ..blendMode = BlendMode.plus;
      canvas.drawRect(
        Rect.fromCenter(center: gCenter, width: zoom * 3.5, height: zoom * 2.5),
        glowPaint,
      );
    }

    final stroke = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    void drawFace(List<Offset> pts, Color color) {
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy)
        ..lineTo(pts[3].dx, pts[3].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, stroke);
    }

    // Top face (always visible)
    drawFace([p[4], p[5], p[6], p[7]], _lighten(baseColor, 0.22));

    // Two side faces depending on rotation
    if (_frontFaceVisible) {
      // Front face: z=wz side → pts 0,1,5,4
      drawFace([p[0], p[1], p[5], p[4]], baseColor);
    } else {
      // Back face: z=wz+d side → pts 3,2,6,7
      drawFace([p[3], p[2], p[6], p[7]], _darken(baseColor, 0.1));
    }

    if (_leftFaceVisible) {
      // Left face: x=wx side → pts 0,3,7,4
      drawFace([p[0], p[3], p[7], p[4]], _darken(baseColor, 0.25));
    } else {
      // Right face: x=wx+w side → pts 1,2,6,5
      drawFace([p[1], p[2], p[6], p[5]], _darken(baseColor, 0.15));
    }
  }

  // ─── Draw floor grid ───────────────────────────────────────────────────────

  void _drawFloor(Canvas canvas, Offset center) {
    final tilePaint = Paint()..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.08)
      ..strokeWidth = 0.8;

    for (int xi = 0; xi < kFloorSize; xi++) {
      for (int zi = 0; zi < kFloorSize; zi++) {
        final tl = _proj(xi.toDouble(),     0, zi.toDouble(),     center);
        final tr = _proj(xi + 1.0, 0, zi.toDouble(),     center);
        final br = _proj(xi + 1.0, 0, zi + 1.0, center);
        final bl = _proj(xi.toDouble(),     0, zi + 1.0, center);

        final path = Path()
          ..moveTo(tl.dx, tl.dy)
          ..lineTo(tr.dx, tr.dy)
          ..lineTo(br.dx, br.dy)
          ..lineTo(bl.dx, bl.dy)
          ..close();

        final checker = (xi + zi) % 2 == 0;
        tilePaint.color = checker
            ? const Color(0xFF0E0E22)
            : const Color(0xFF0A0A1C);
        canvas.drawPath(path, tilePaint);
        canvas.drawPath(path, linePaint);
      }
    }
  }

  // ─── Draw server rack ──────────────────────────────────────────────────────

  void _drawServerRack(Canvas canvas, Offset center, ServerModel server) {
    final (wx, wz) = kRackPositions[server.id];
    final isHovered = hoveredServerId == server.id;

    // Base rack colour
    final baseColor = Color.lerp(
      const Color(0xFF1A1A3A),
      server.statusColor,
      server.normalisedHeat * 0.45,
    )!;

    _drawBox(
      canvas, center,
      wx, 0, wz, kRackW, kRackH, kRackD,
      baseColor,
      glow: server.normalisedHeat > 0.3,
      glowColor: server.glowColor,
    );

    // ── Front face details (LED indicators, drive slots) ────────────────────
    if (_frontFaceVisible) {
      final topLeft = _proj(wx, kRackH, wz, center);
      final topRight = _proj(wx + kRackW, kRackH, wz, center);
      final botLeft = _proj(wx, 0, wz, center);

      // Draw LED dots on front face
      for (int row = 0; row < 8; row++) {
        final t = (row + 0.5) / 8.0;
        final ledPos = Offset(
          topLeft.dx + (topRight.dx - topLeft.dx) * 0.12 +
              (botLeft.dx - topLeft.dx) * t,
          topLeft.dy + (topRight.dy - topLeft.dy) * 0.12 +
              (botLeft.dy - topLeft.dy) * t,
        );
        final ledColor = row < 2
            ? server.statusColor
            : (row % 3 == 0
                ? const Color(0xFF00D4FF)
                : const Color(0xFF004466));
        canvas.drawCircle(ledPos, 1.8, Paint()..color = ledColor);
        if (row < 3) {
          canvas.drawCircle(
            ledPos,
            3.0,
            Paint()
              ..color = ledColor.withOpacity(0.3)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
        }
      }

      // Drive slot lines
      for (int row = 1; row < 10; row++) {
        final t = row / 10.0;
        final left = Offset(
          topLeft.dx + (botLeft.dx - topLeft.dx) * t,
          topLeft.dy + (botLeft.dy - topLeft.dy) * t,
        );
        final right = Offset(
          topLeft.dx + (topRight.dx - topLeft.dx) * 0.9 +
              (botLeft.dx - topLeft.dx) * t,
          topLeft.dy + (topRight.dy - topLeft.dy) * 0.9 +
              (botLeft.dy - topLeft.dy) * t,
        );
        canvas.drawLine(
          left + const Offset(4, 0),
          right,
          Paint()
            ..color = const Color(0xFF003355).withOpacity(0.7)
            ..strokeWidth = 0.8,
        );
      }
    }

    // ── Hover highlight ───────────────────────────────────────────────────
    if (isHovered) {
      final topPts = [
        _proj(wx, kRackH, wz, center),
        _proj(wx + kRackW, kRackH, wz, center),
        _proj(wx + kRackW, kRackH, wz + kRackD, center),
        _proj(wx, kRackH, wz + kRackD, center),
      ];
      final path = Path()
        ..moveTo(topPts[0].dx, topPts[0].dy)
        ..lineTo(topPts[1].dx, topPts[1].dy)
        ..lineTo(topPts[2].dx, topPts[2].dy)
        ..lineTo(topPts[3].dx, topPts[3].dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withOpacity(0.15)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // ── Server label ──────────────────────────────────────────────────────
    final labelPos = _proj(wx + kRackW / 2, kRackH + 0.15, wz + kRackD / 2, center);
    _drawLabel(canvas, labelPos, server.name, server.statusColor, fontSize: 9);
  }

  // ─── Draw cooling unit ────────────────────────────────────────────────────

  void _drawCoolingUnit(Canvas canvas, Offset center) {
    final (wx, wz) = kCoolingPos;
    const Color coolColor = Color(0xFF0A2A4A);

    _drawBox(
      canvas, center,
      wx, 0, wz, kCoolW, kCoolH, kCoolD,
      coolColor,
      glow: true,
      glowColor: const Color(0xFF00D4FF).withOpacity(0.2),
    );

    // ── Fan on top ────────────────────────────────────────────────────────
    final fanCenter = _proj(wx + kCoolW / 2, kCoolH + 0.02, wz + kCoolD / 2, center);
    _drawFan(canvas, fanCenter, cooling.rotationsPerSecond);

    // ── Vent lines on front face ──────────────────────────────────────────
    if (_frontFaceVisible) {
      final topLeft = _proj(wx, kCoolH, wz, center);
      final topRight = _proj(wx + kCoolW, kCoolH, wz, center);
      final botLeft = _proj(wx, 0, wz, center);

      for (int i = 1; i < 8; i++) {
        final t = i / 8.0;
        final l = Offset(
          topLeft.dx + (botLeft.dx - topLeft.dx) * t,
          topLeft.dy + (botLeft.dy - topLeft.dy) * t,
        );
        final r = Offset(
          topLeft.dx + (topRight.dx - topLeft.dx) * 0.95 +
              (botLeft.dx - topLeft.dx) * t,
          topLeft.dy + (topRight.dy - topLeft.dy) * 0.95 +
              (botLeft.dy - topLeft.dy) * t,
        );
        canvas.drawLine(
          l + const Offset(3, 0),
          r,
          Paint()
            ..color = const Color(0xFF00D4FF).withOpacity(0.4)
            ..strokeWidth = 1.2,
        );
      }
    }

    _drawLabel(
      canvas,
      _proj(wx + kCoolW / 2, kCoolH + 0.35, wz + kCoolD / 2, center),
      'COOLING UNIT',
      const Color(0xFF00D4FF),
      fontSize: 9,
    );
  }

  void _drawFan(Canvas canvas, Offset center, double rps) {
    final angle = animValue * 2 * math.pi * rps * 8;
    final r = zoom * 0.35;

    canvas.drawCircle(
      center,
      r + 4,
      Paint()
        ..color = const Color(0xFF001A2E)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      r + 4,
      Paint()
        ..color = const Color(0xFF00D4FF).withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 4 fan blades
    for (int i = 0; i < 4; i++) {
      final bladeAngle = angle + i * math.pi / 2;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(bladeAngle);

      final bladePath = Path()
        ..moveTo(0, 0)
        ..cubicTo(r * 0.3, -r * 0.2, r * 0.9, -r * 0.4, r * 0.85, -r * 0.1)
        ..cubicTo(r * 0.7, r * 0.2, r * 0.2, r * 0.1, 0, 0);

      final bladePaint = Paint()
        ..color = const Color(0xFF00D4FF).withOpacity(0.75)
        ..style = PaintingStyle.fill;

      canvas.drawPath(bladePath, bladePaint);
      canvas.restore();
    }

    // Hub
    canvas.drawCircle(
      center, 4,
      Paint()..color = const Color(0xFF00D4FF),
    );
  }

  // ─── Draw particles ───────────────────────────────────────────────────────

  void _drawParticles(Canvas canvas, Offset center) {
    for (final p in particles) {
      final t = (animValue * p.speed + p.phase) % 1.0;

      if (p.isHeat) {
        // Heat rises upward
        final (wx, wz) = _nearestRack(p.startX, p.startZ);
        final server = _serverAt(wx, wz);
        if (server == null) continue;
        final intensity = server.normalisedHeat;
        if (intensity < 0.1) continue;

        final worldY = kRackH + t * 2.5;
        final wobbleX = p.startX + math.sin(t * math.pi * 3 + p.phase * 6) * p.wobble;
        final pt = _proj(wobbleX, worldY, p.startZ, center);

        final opacity = (1.0 - t) * intensity * 0.8;
        final size = (1.0 - t) * 3.5 + 1.0;
        final color = Color.lerp(
          const Color(0xFFFFAA00),
          const Color(0xFFFF3300),
          intensity,
        )!
            .withOpacity(opacity);

        canvas.drawCircle(pt, size, Paint()..color = color);
        if (intensity > 0.6) {
          canvas.drawCircle(
            pt,
            size * 2.5,
            Paint()
              ..color = color.withOpacity(opacity * 0.3)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
        }
      } else {
        // Cool air flows from cooling unit toward racks
        final targetX = (kRackPositions[2].$1 + kRackPositions[5].$1) / 2;
        final targetZ = (kRackPositions[0].$2 + kRackPositions[5].$2) / 2;

        final wx = p.startX + (targetX - p.startX) * t;
        final wz = p.startZ +
            (targetZ - p.startZ) * t +
            math.sin(t * math.pi * 2 + p.phase * 4) * p.wobble;
        final wy = 0.3 + math.sin(t * math.pi) * 0.5;
        final pt = _proj(wx, wy, wz, center);

        final opacity = math.sin(t * math.pi) * 0.7;
        final size = 2.0 + (1 - t) * 2.0;
        final coolPaint = Paint()
          ..color = const Color(0xFF00D4FF).withOpacity(opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawCircle(pt, size, coolPaint);
      }
    }
  }

  // ─── Draw text label ──────────────────────────────────────────────────────

  void _drawLabel(
    Canvas canvas,
    Offset pos,
    String text,
    Color color, {
    double fontSize = 10,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          shadows: [
            Shadow(color: color.withOpacity(0.6), blurRadius: 6),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  (double, double) _nearestRack(double x, double z) {
    double best = double.infinity;
    (double, double) result = kRackPositions[0];
    for (final r in kRackPositions) {
      final d = math.sqrt(math.pow(x - r.$1, 2) + math.pow(z - r.$2, 2));
      if (d < best) { best = d; result = r; }
    }
    return result;
  }

  ServerModel? _serverAt(double wx, double wz) {
    for (int i = 0; i < kRackPositions.length; i++) {
      if (kRackPositions[i].$1 == wx && kRackPositions[i].$2 == wz) {
        return i < servers.length ? servers[i] : null;
      }
    }
    return null;
  }

  // ─── Main paint ───────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2 + pan.dx, size.height / 2 + pan.dy);

    // Background gradient
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF04040F), Color(0xFF070718)],
        ).createShader(Offset.zero & size),
    );

    // ── Sort all scene objects by depth (back to front) ──────────────────
    final items = <(double, VoidCallback)>[];

    // Floor goes first
    items.add((_depth(5, 5) + 100, () => _drawFloor(canvas, center)));

    // Cooling unit
    final (cx, cz) = kCoolingPos;
    items.add((
      _depth(cx + kCoolW / 2, cz + kCoolD / 2),
      () => _drawCoolingUnit(canvas, center),
    ));

    // Server racks
    for (final server in servers) {
      final (rx, rz) = kRackPositions[server.id];
      items.add((
        _depth(rx + kRackW / 2, rz + kRackD / 2),
        () => _drawServerRack(canvas, center, server),
      ));
    }

    // Sort by depth descending (farthest first)
    items.sort((a, b) => b.$1.compareTo(a.$1));

    // Draw all objects
    for (final item in items) { item.$2(); }

    // ── Particles on top ─────────────────────────────────────────────────
    _drawParticles(canvas, center);
  }

  @override
  bool shouldRepaint(_DataCenterPainter old) =>
      old.animValue != animValue ||
      old.rotationY != rotationY ||
      old.zoom != zoom ||
      old.pan != pan ||
      old.hoveredServerId != hoveredServerId;
}

// ═══════════════════════════════════════════════════════════════════════════════
// UI OVERLAYS
// ═══════════════════════════════════════════════════════════════════════════════

class _SimTopBar extends StatelessWidget {
  final VoidCallback onBack;
  const _SimTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1E).withOpacity(0.9),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF00D4FF).withOpacity(0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onBack,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D4FF).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00D4FF).withOpacity(0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_back_ios,
                        size: 12, color: Color(0xFF00D4FF)),
                    SizedBox(width: 4),
                    Text(
                      'DASHBOARD',
                      style: TextStyle(
                        color: Color(0xFF00D4FF),
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          const Icon(Icons.view_in_ar, color: Color(0xFF00D4FF), size: 18),
          const SizedBox(width: 10),
          const Text(
            '3D DATA CENTER SIMULATION',
            style: TextStyle(
              color: Color(0xFF00D4FF),
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),
          const Spacer(),
          _AnimatedBadge(
            label: 'LIVE',
            color: const Color(0xFF00FF88),
          ),
          const SizedBox(width: 16),
          const Text(
            'Drag: Rotate  |  Scroll: Zoom  |  Hover: Info',
            style: TextStyle(
              color: Color(0xFF444466),
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBadge extends StatefulWidget {
  final String label;
  final Color color;
  const _AnimatedBadge({required this.label, required this.color});

  @override
  State<_AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<_AnimatedBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.1 + 0.05 * _c.value),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: widget.color.withOpacity(0.2 * _c.value),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withOpacity(0.5 + 0.5 * (1 - _c.value)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ServerListPanel extends StatelessWidget {
  final List<ServerModel> servers;
  const _ServerListPanel({required this.servers});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF080818).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00D4FF).withOpacity(0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'SERVER STATUS',
              style: TextStyle(
                color: Color(0xFF00D4FF),
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...servers.map((s) => _ServerStatusRow(server: s)),
        ],
      ),
    );
  }
}

class _ServerStatusRow extends StatelessWidget {
  final ServerModel server;
  const _ServerStatusRow({required this.server});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: server.statusColor,
              boxShadow: [
                BoxShadow(
                  color: server.statusColor.withOpacity(0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            server.name,
            style: const TextStyle(
              color: Color(0xFFCCCCCC),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${server.temperature.toStringAsFixed(0)}°C',
            style: TextStyle(
              color: server.statusColor,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 40,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: server.cpuUtilization / 100,
                backgroundColor: const Color(0xFF1A1A3A),
                valueColor: AlwaysStoppedAnimation<Color>(server.statusColor),
                minHeight: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF080818).withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF222244)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          _LegendItem(icon: Icons.mouse, label: 'Drag = Rotate'),
          SizedBox(width: 14),
          _LegendItem(icon: Icons.open_with, label: 'Scroll = Zoom'),
          SizedBox(width: 14),
          _LegendItem(icon: Icons.info_outline, label: 'Hover = Info'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _LegendItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 13, color: const Color(0xFF555577)),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF555577),
          fontSize: 11,
        ),
      ),
    ],
  );
}

class _RoomTempBadge extends StatelessWidget {
  final SimulationEngine engine;
  const _RoomTempBadge({required this.engine});

  @override
  Widget build(BuildContext context) {
    final temp = engine.estimatedRoomTemp;
    final color = temp < 24
        ? const Color(0xFF00D4FF)
        : temp < 28
            ? const Color(0xFF00FF88)
            : temp < 32
                ? const Color(0xFFFFCC00)
                : const Color(0xFFFF3333);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF080818).withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.15), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'ROOM TEMPERATURE',
            style: TextStyle(
              color: Color(0xFF666688),
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${temp.toStringAsFixed(1)} °C',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Heat: ${engine.estimatedHeatOutput.toStringAsFixed(2)} kW',
            style: TextStyle(color: color.withOpacity(0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
