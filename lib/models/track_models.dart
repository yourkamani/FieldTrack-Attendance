import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;

// =====================================================================
// SHARED CONTRACTS
// =====================================================================

/// Anything that can be shown as a stop on the map / timeline.
abstract class TrackItem {
  final GlobalKey key = GlobalKey();
  DateTime get primaryTime;
}

/// Mixin for items that get a reverse-geocoded place name lazily resolved
/// after the route loads (Start, Stop, Halt all use this).
mixin AreaResolvable {
  String? areaName;
  bool isResolvingArea = false;
}

// =====================================================================
// TRACK ITEMS
// =====================================================================
class StartEvent extends TrackItem with AreaResolvable {
  final LatLng location;
  final DateTime time;
  StartEvent({required this.location, required this.time});
  @override
  DateTime get primaryTime => time;
}

class StopEvent extends TrackItem with AreaResolvable {
  final LatLng location;
  final DateTime time;
  StopEvent({required this.location, required this.time});
  @override
  DateTime get primaryTime => time;
}

class LocationPoint extends TrackItem {
  final LatLng location;
  final DateTime time;
  LocationPoint({required this.location, required this.time});
  @override
  DateTime get primaryTime => time;
}

/// A halt is rendered as a numbered circular *region* on the map, not a
/// cluster of individual points — see MapMonitorScreen's polyline/circle
/// building for how the route line is broken around it.
class HaltEvent extends TrackItem with AreaResolvable {
  final LatLng location;
  final DateTime startTime;
  final DateTime endTime;
  final int haltNumber;

  HaltEvent({
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.haltNumber,
  });

  Duration get duration => endTime.difference(startTime);

  /// Region radius on the map, scaled gently by how long the halt was.
  double get regionRadiusMeters => (30 + math.min(duration.inMinutes, 60)).toDouble();

  @override
  DateTime get primaryTime => startTime;
}

class TimeGap extends TrackItem {
  final LatLng lastKnownLocation;
  final DateTime startTime;
  final DateTime endTime;
  TimeGap({required this.lastKnownLocation, required this.startTime, required this.endTime});
  @override
  DateTime get primaryTime => startTime;
}

enum FilterType { all, halts, gaps, summary }

// =====================================================================
// GEO MATH (replaces latlong2's Distance())
// =====================================================================
class GeoUtils {
  static const double _earthRadius = 6371000; // meters

  static double _rad(double deg) => deg * math.pi / 180;

  static double distanceMeters(LatLng a, LatLng b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final lat1 = _rad(a.latitude);
    final lat2 = _rad(b.latitude);

    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return _earthRadius * c;
  }

  static double bearingDegrees(LatLng a, LatLng b) {
    final lat1 = _rad(a.latitude);
    final lat2 = _rad(b.latitude);
    final dLng = _rad(b.longitude - a.longitude);

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }
}
