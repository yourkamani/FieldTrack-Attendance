import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Builds and caches every BitmapDescriptor used on the map. Google Maps
/// markers can't render arbitrary widgets (unlike flutter_map), so every
/// icon has to be pre-rendered to a bitmap once and reused.
class MarkerIconFactory {
  BitmapDescriptor? startIcon;
  BitmapDescriptor? stopIcon;
  BitmapDescriptor? gapIcon;
  BitmapDescriptor? dotIcon;
  BitmapDescriptor? dotIconSelected;
  BitmapDescriptor? walkerIcon;

  final Map<int, BitmapDescriptor> _haltIcons = {}; // keyed by halt number
  final Map<int, BitmapDescriptor> _arrowIcons = {}; // keyed by bearing bucket

  Future<void> buildStaticIcons() async {
    startIcon = await _drawFlatMarker(icon: Icons.play_arrow_rounded, background: const Color(0xFF2E7D32), diameter: 84);
    stopIcon = await _drawFlatMarker(icon: Icons.flag_rounded, background: const Color(0xFFC62828), diameter: 84);
    gapIcon = await _drawFlatMarker(icon: Icons.wifi_off_rounded, background: const Color(0xFFD84315), diameter: 78);
    dotIcon = await _drawFlatMarker(text: '', background: const Color(0xFF1E3A8A), diameter: 26, withRing: false);
    dotIconSelected = await _drawFlatMarker(text: '', background: const Color(0xFF1E3A8A), diameter: 40);
    walkerIcon = await _drawWalker3D();
  }

  Future<BitmapDescriptor> haltIcon(int number) async {
    if (_haltIcons.containsKey(number)) return _haltIcons[number]!;
    final icon = await _drawFlatMarker(text: '$number', background: const Color(0xFFEF6C00), diameter: 88);
    _haltIcons[number] = icon;
    return icon;
  }

  /// Synchronous lookup for a halt icon already built by [haltIcon]. Used
  /// when rebuilding the marker set on every rebuild/tick — returns null
  /// only on the very first frame before icons finish generating.
  BitmapDescriptor? cachedHaltIcon(int number) => _haltIcons[number];

  Future<BitmapDescriptor> arrowIcon(double bearingDeg) async {
    final bucket = (bearingDeg / 15).round() * 15 % 360;
    if (_arrowIcons.containsKey(bucket)) return _arrowIcons[bucket]!;
    final icon = await _drawArrow(bucket.toDouble());
    _arrowIcons[bucket] = icon;
    return icon;
  }

  // -------------------------------------------------------------------
  // FLAT CIRCLE MARKER (start / stop / gap / halt-number / dots)
  // -------------------------------------------------------------------
  Future<BitmapDescriptor> _drawFlatMarker({
    IconData? icon,
    String? text,
    required Color background,
    Color foreground = Colors.white,
    double diameter = 90,
    bool withRing = true,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final radius = diameter / 2;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(Offset(radius, radius + 2), radius - 4, shadowPaint);

    if (withRing) {
      canvas.drawCircle(Offset(radius, radius), radius, Paint()..color = Colors.white);
    }
    canvas.drawCircle(Offset(radius, radius), radius - (withRing ? 6 : 0), Paint()..color = background);

    if (text != null && text.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: foreground, fontSize: diameter * 0.42, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(radius - tp.width / 2, radius - tp.height / 2));
    } else if (icon != null) {
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontSize: diameter * 0.5, fontFamily: icon.fontFamily, package: icon.fontPackage, color: foreground),
        )
        ..layout();
      tp.paint(canvas, Offset(radius - tp.width / 2, radius - tp.height / 2));
    }

    return _finish(recorder, diameter.toInt(), diameter.toInt());
  }

  // -------------------------------------------------------------------
  // DIRECTIONAL ARROW
  // -------------------------------------------------------------------
  Future<BitmapDescriptor> _drawArrow(double bearingDeg, {Color color = Colors.white}) async {
    const double size = 40;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(size / 2, size / 2);
    canvas.rotate(bearingDeg * math.pi / 180);

    final path = Path()
      ..moveTo(0, -size * 0.35)
      ..lineTo(size * 0.22, size * 0.28)
      ..lineTo(0, size * 0.12)
      ..lineTo(-size * 0.22, size * 0.28)
      ..close();
    canvas.drawPath(path, Paint()..color = color);

    return _finish(recorder, size.toInt(), size.toInt());
  }

  // -------------------------------------------------------------------
  // "3D" WALKER MARKER — elevated ball-on-a-shadow so it always reads as
  // the single focal object during summary playback. The anchor is set
  // low (near the shadow) so the sphere appears to float just above the
  // actual coordinate, which is what sells the 3D/object look.
  // -------------------------------------------------------------------
  Future<BitmapDescriptor> _drawWalker3D() async {
    const double w = 120;
    const double h = 156;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final groundY = h - 22;
    final sphereCenter = Offset(w / 2, h - 62);
    const sphereRadius = 40.0;

    // Ground shadow (sells the "floating object" depth)
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.32)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawOval(Rect.fromCenter(center: Offset(w / 2, groundY), width: 46, height: 16), shadowPaint);

    // Outer glow ring so it pops against any marker underneath it
    canvas.drawCircle(sphereCenter, sphereRadius + 8, Paint()..color = Colors.white.withOpacity(0.9));

    // Sphere body with a radial gradient for a 3D look
    final gradient = ui.Gradient.radial(
      sphereCenter.translate(-sphereRadius * 0.35, -sphereRadius * 0.35),
      sphereRadius * 1.5,
      [const Color(0xFF9C4DCC), const Color(0xFF4A0072)],
      [0.0, 1.0],
    );
    canvas.drawCircle(sphereCenter, sphereRadius, Paint()..shader = gradient);

    // Highlight glint
    canvas.drawCircle(
      sphereCenter.translate(-sphereRadius * 0.35, -sphereRadius * 0.4),
      sphereRadius * 0.28,
      Paint()..color = Colors.white.withOpacity(0.35),
    );

    // Person glyph
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.directions_walk_rounded.codePoint),
        style: TextStyle(
          fontSize: sphereRadius * 1.15,
          fontFamily: Icons.directions_walk_rounded.fontFamily,
          package: Icons.directions_walk_rounded.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    tp.paint(canvas, sphereCenter - Offset(tp.width / 2, tp.height / 2));

    return _finish(recorder, w.toInt(), h.toInt());
  }

  Future<BitmapDescriptor> _finish(ui.PictureRecorder recorder, int w, int h) async {
    final picture = recorder.endRecording();
    final img = await picture.toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }
}

/// Anchor to pair with [MarkerIconFactory.walkerIcon] — the geographic
/// point should land near the shadow, not the bitmap's center.
const Offset walkerMarkerAnchor = Offset(0.5, 0.86);
