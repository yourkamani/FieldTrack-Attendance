import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// =====================================================================
// DATA MODELS
// =====================================================================
enum FilterType { all, halts, gaps }

abstract class TrackItem {
  final GlobalKey key = GlobalKey();
  DateTime get primaryTime;
}

class StartEvent extends TrackItem {
  final LatLng location;
  final DateTime time;
  StartEvent({required this.location, required this.time});
  @override
  DateTime get primaryTime => time;
}

class StopEvent extends TrackItem {
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

/// A halt is a merged region (not a run of individual dots). It carries a
/// sequential number shown on the map + a lazily-resolved area name
/// ("Kurla", "Mulund", etc.) fetched via reverse geocoding.
class HaltEvent extends TrackItem {
  final LatLng location;
  final DateTime startTime;
  final DateTime endTime;
  final int haltNumber;
  String? areaName; // filled in after reverse geocoding resolves
  bool isResolvingArea = false;

  HaltEvent({
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.haltNumber,
  });

  Duration get duration => endTime.difference(startTime);

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

// =====================================================================
// STICKY HEADER DELEGATE
// =====================================================================
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  _StickyHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: height, child: child);
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) => true;
}

// =====================================================================
// GEO MATH HELPERS (replaces latlong2's Distance())
// =====================================================================
class _GeoUtils {
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

// =====================================================================
// MAIN SCREEN
// =====================================================================
class MapMonitorScreen extends StatefulWidget {
  final String userId;
  final String sessionId;

  const MapMonitorScreen({Key? key, required this.userId, required this.sessionId}) : super(key: key);

  @override
  State<MapMonitorScreen> createState() => _MapMonitorScreenState();
}

class _MapMonitorScreenState extends State<MapMonitorScreen> {
  final _supabase = Supabase.instance.client;
  GoogleMapController? _mapController;

  // Timeline / map data
  List<TrackItem> finalItems = [];
  List<LatLng> rawRoute = [];
  List<LocationPoint> fullTrajectory = []; // every raw point + time, used for playback interpolation
  FilterType currentFilter = FilterType.all;
  TrackItem? selectedItem;
  bool isLoading = true;

  // Marker bitmap caches (Google Maps only accepts BitmapDescriptor, not raw widgets)
  BitmapDescriptor? _startIcon;
  BitmapDescriptor? _stopIcon;
  BitmapDescriptor? _gapIcon;
  BitmapDescriptor? _dotIcon;
  BitmapDescriptor? _dotIconSelected;
  BitmapDescriptor? _walkerIcon;
  final Map<int, BitmapDescriptor> _haltIcons = {}; // keyed by halt number
  final Map<int, BitmapDescriptor> _arrowIcons = {}; // keyed by bearing rounded to nearest 15deg

  // Playback / "summary walk-through" state
  bool _summaryMode = false;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0; // 1x, 2x, 4x
  double _progress = 0.0; // 0..1
  Timer? _playbackTimer;
  LatLng? _walkerPosition;
  DateTime? _walkerTime;
  static const double _basePlaybackSeconds = 60.0; // full route takes 60s at 1x

  String get _googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    _buildStaticIcons().then((_) => _fetchRouteData());
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // DATA FETCH + PROCESSING
  // -------------------------------------------------------------------
  Future<void> _fetchRouteData() async {
    final response = await _supabase
        .from('location_tracks')
        .select()
        .eq('user_id', widget.userId)
        .eq('session_id', widget.sessionId)
        .order('timestamp', ascending: true);

    List<TrackItem> rawTimeline = [];
    List<LatLng> routePoints = [];
    List<LocationPoint> trajectory = [];
    DateTime? lastTime;
    LatLng? lastLoc;

    for (var i = 0; i < response.length; i++) {
      var row = response[i];
      LatLng currentLoc = LatLng(row['latitude'], row['longitude']);
      DateTime currentTime = DateTime.parse(row['timestamp']);

      routePoints.add(currentLoc);
      trajectory.add(LocationPoint(location: currentLoc, time: currentTime));

      if (lastTime != null && currentTime.difference(lastTime).inMinutes > 5) {
        rawTimeline.add(TimeGap(startTime: lastTime, endTime: currentTime, lastKnownLocation: lastLoc!));
      }

      rawTimeline.add(LocationPoint(location: currentLoc, time: currentTime));
      lastTime = currentTime;
      lastLoc = currentLoc;
    }

    List<TrackItem> processedItems = [];
    List<TrackItem> buffer = [];
    LatLng? currentCenter;
    int haltCounter = 0;

    void flushBuffer() {
      if (buffer.isEmpty) return;
      var locs = buffer.whereType<LocationPoint>().toList();
      var gaps = buffer.whereType<TimeGap>().toList();

      if (locs.isNotEmpty && locs.last.time.difference(locs.first.time).inMinutes >= 15) {
        haltCounter++;
        processedItems.add(HaltEvent(
          location: locs.first.location,
          startTime: locs.first.time,
          endTime: locs.last.time,
          haltNumber: haltCounter,
        ));
        processedItems.addAll(gaps);
      } else {
        processedItems.addAll(buffer);
      }
      buffer.clear();
    }

    for (var item in rawTimeline) {
      if (item is TimeGap) {
        buffer.add(item);
      } else if (item is LocationPoint) {
        if (currentCenter == null) {
          currentCenter = item.location;
          buffer.add(item);
        } else {
          double distanceMeters = _GeoUtils.distanceMeters(currentCenter, item.location);
          if (distanceMeters <= 100) {
            buffer.add(item);
          } else {
            flushBuffer();
            currentCenter = item.location;
            buffer.add(item);
          }
        }
      }
    }
    flushBuffer();

    processedItems.sort((a, b) => a.primaryTime.compareTo(b.primaryTime));

    if (routePoints.isNotEmpty && rawTimeline.isNotEmpty) {
      processedItems.insert(0, StartEvent(location: routePoints.first, time: rawTimeline.first.primaryTime));
      if (routePoints.length > 1) {
        processedItems.add(StopEvent(location: routePoints.last, time: rawTimeline.last.primaryTime));
      }
    }

    setState(() {
      finalItems = processedItems;
      rawRoute = routePoints;
      fullTrajectory = trajectory;
      isLoading = false;
    });

    await _buildHaltIcons();
    _resolveHaltAreaNames(); // fire and forget, updates UI as results come in
  }

  // -------------------------------------------------------------------
  // REVERSE GEOCODING (Google Geocoding API, uses the same key)
  // -------------------------------------------------------------------
  Future<void> _resolveHaltAreaNames() async {
    for (final item in finalItems) {
      if (item is! HaltEvent) continue;
      if (_googleApiKey.isEmpty) {
        item.areaName = 'Set GOOGLE_MAPS_API_KEY in .env';
        continue;
      }
      item.isResolvingArea = true;
      if (mounted) setState(() {});

      final name = await _reverseGeocode(item.location);
      item.areaName = name ?? 'Unknown area';
      item.isResolvingArea = false;
      if (mounted) setState(() {});
    }
  }

  Future<String?> _reverseGeocode(LatLng point) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${point.latitude},${point.longitude}&key=$_googleApiKey',
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data['status'] != 'OK' || (data['results'] as List).isEmpty) return null;

      // Prefer sublocality (e.g. "Kurla West") then locality (e.g. "Mumbai")
      for (final result in data['results']) {
        final components = result['address_components'] as List;
        String? sublocality;
        String? locality;
        for (final c in components) {
          final types = List<String>.from(c['types']);
          if (types.contains('sublocality_level_1') || types.contains('sublocality')) {
            sublocality ??= c['long_name'];
          }
          if (types.contains('locality')) {
            locality ??= c['long_name'];
          }
        }
        if (sublocality != null && locality != null) return '$sublocality, $locality';
        if (sublocality != null) return sublocality;
        if (locality != null) return locality;
      }
      return data['results'][0]['formatted_address'] as String?;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------
  // MARKER BITMAP GENERATION
  // -------------------------------------------------------------------
  Future<BitmapDescriptor> _drawMarker({
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

    // Soft shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(Offset(radius, radius + 2), radius - 4, shadowPaint);

    // Outer ring
    if (withRing) {
      final ringPaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(radius, radius), radius, ringPaint);
    }

    // Fill
    final fillPaint = Paint()..color = background;
    canvas.drawCircle(Offset(radius, radius), radius - (withRing ? 6 : 0), fillPaint);

    if (text != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: foreground, fontSize: diameter * 0.42, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(radius - tp.width / 2, radius - tp.height / 2));
    } else if (icon != null) {
      final tp = TextPainter(textDirection: TextDirection.ltr);
      tp.text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: diameter * 0.5,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: foreground,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(radius - tp.width / 2, radius - tp.height / 2));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(diameter.toInt(), diameter.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

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

    final paint = Paint()..color = color;
    canvas.drawPath(path, paint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _buildStaticIcons() async {
    _startIcon = await _drawMarker(icon: Icons.play_arrow_rounded, background: const Color(0xFF2E7D32), diameter: 84);
    _stopIcon = await _drawMarker(icon: Icons.flag_rounded, background: const Color(0xFFC62828), diameter: 84);
    _gapIcon = await _drawMarker(icon: Icons.wifi_off_rounded, background: const Color(0xFFD84315), diameter: 78);
    _dotIcon = await _drawMarker(text: '', background: const Color(0xFF1E3A8A), diameter: 26, withRing: false);
    _dotIconSelected = await _drawMarker(text: '', background: const Color(0xFF1E3A8A), diameter: 40);
    _walkerIcon = await _drawMarker(icon: Icons.directions_walk_rounded, background: const Color(0xFF6A1B9A), diameter: 88);
  }

  Future<void> _buildHaltIcons() async {
    for (final item in finalItems) {
      if (item is HaltEvent && !_haltIcons.containsKey(item.haltNumber)) {
        _haltIcons[item.haltNumber] = await _drawMarker(
          text: '${item.haltNumber}',
          background: const Color(0xFFEF6C00),
          diameter: 88,
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _arrowIconFor(double bearing) async {
    final bucket = (bearing / 15).round() * 15 % 360;
    if (_arrowIcons.containsKey(bucket)) return _arrowIcons[bucket]!;
    final icon = await _drawArrow(bucket.toDouble());
    _arrowIcons[bucket] = icon;
    return icon;
  }

  // -------------------------------------------------------------------
  // MARKERS BUILD (rebuilt reactively from state)
  // -------------------------------------------------------------------
  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    for (final item in finalItems) {
      if (item is StartEvent && _startIcon != null) {
        markers.add(Marker(
          markerId: const MarkerId('start'),
          position: item.location,
          icon: _startIcon!,
          anchor: const Offset(0.5, 0.5),
          onTap: () => _onPointTapped(item),
        ));
      } else if (item is StopEvent && _stopIcon != null) {
        markers.add(Marker(
          markerId: const MarkerId('stop'),
          position: item.location,
          icon: _stopIcon!,
          anchor: const Offset(0.5, 0.5),
          onTap: () => _onPointTapped(item),
        ));
      } else if (item is TimeGap && _gapIcon != null) {
        markers.add(Marker(
          markerId: MarkerId('gap_${item.startTime.millisecondsSinceEpoch}'),
          position: item.lastKnownLocation,
          icon: _gapIcon!,
          anchor: const Offset(0.5, 0.5),
          onTap: () => _onPointTapped(item),
        ));
      } else if (item is HaltEvent) {
        final icon = _haltIcons[item.haltNumber];
        if (icon == null) continue;
        markers.add(Marker(
          markerId: MarkerId('halt_${item.haltNumber}'),
          position: item.location,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          zIndex: 5,
          onTap: () => _onPointTapped(item),
        ));
      } else if (item is LocationPoint && !_summaryMode) {
        final isSelected = selectedItem == item;
        final icon = isSelected ? _dotIconSelected : _dotIcon;
        if (icon == null) continue;
        markers.add(Marker(
          markerId: ObjectKey(item).toString().isEmpty
              ? MarkerId('pt_${item.time.millisecondsSinceEpoch}')
              : MarkerId('pt_${item.time.millisecondsSinceEpoch}'),
          position: item.location,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          onTap: () => _onPointTapped(item),
        ));
      }
    }

    if (_summaryMode && _walkerPosition != null && _walkerIcon != null) {
      markers.add(Marker(
        markerId: const MarkerId('walker'),
        position: _walkerPosition!,
        icon: _walkerIcon!,
        anchor: const Offset(0.5, 0.5),
        zIndex: 10,
      ));
    }

    return markers;
  }

  // -------------------------------------------------------------------
  // INTERACTION
  // -------------------------------------------------------------------
  void _onPointTapped(TrackItem item) {
    setState(() => selectedItem = item);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (item.key.currentContext != null) {
        Scrollable.ensureVisible(
          item.key.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
  }

  void _onListItemTapped(TrackItem item, LatLng mapLocation) {
    setState(() => selectedItem = item);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(mapLocation, 16.5));
  }

  String formatTime(DateTime d) => "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  // -------------------------------------------------------------------
  // SUMMARY PLAYBACK ("person walking along the path")
  // -------------------------------------------------------------------
  void _toggleSummaryMode() {
    setState(() {
      _summaryMode = !_summaryMode;
      selectedItem = null;
      if (!_summaryMode) {
        _stopPlayback();
        _walkerPosition = null;
        _walkerTime = null;
        _progress = 0;
      } else if (fullTrajectory.isNotEmpty) {
        _walkerPosition = fullTrajectory.first.location;
        _walkerTime = fullTrajectory.first.time;
      }
    });
  }

  void _togglePlayPause() {
    if (fullTrajectory.length < 2) return;
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _startPlayback();
    } else {
      _playbackTimer?.cancel();
    }
  }

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
  }

  void _startPlayback() {
    _playbackTimer?.cancel();
    const tick = Duration(milliseconds: 80);
    _playbackTimer = Timer.periodic(tick, (timer) {
      final durationAtSpeed = _basePlaybackSeconds / _playbackSpeed;
      final step = tick.inMilliseconds / 1000.0 / durationAtSpeed;

      setState(() {
        _progress += step;
        if (_progress >= 1.0) {
          _progress = 1.0;
          _isPlaying = false;
          timer.cancel();
        }
        _updateWalkerFromProgress();
      });

      if (_walkerPosition != null && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(_walkerPosition!));
      }
    });
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _isPlaying = false;
  }

  void _onScrubbed(double value) {
    setState(() {
      _progress = value;
      _updateWalkerFromProgress();
    });
  }

  void _updateWalkerFromProgress() {
    if (fullTrajectory.length < 2) return;
    final start = fullTrajectory.first.time;
    final end = fullTrajectory.last.time;
    final totalMicros = end.difference(start).inMicroseconds;
    final targetTime = start.add(Duration(microseconds: (totalMicros * _progress).round()));

    // Binary-search-ish scan for bracketing points (trajectory is time-sorted)
    LocationPoint before = fullTrajectory.first;
    LocationPoint after = fullTrajectory.last;
    for (int i = 0; i < fullTrajectory.length - 1; i++) {
      if (!fullTrajectory[i].time.isAfter(targetTime) && !fullTrajectory[i + 1].time.isBefore(targetTime)) {
        before = fullTrajectory[i];
        after = fullTrajectory[i + 1];
        break;
      }
    }

    final segmentMicros = after.time.difference(before.time).inMicroseconds;
    final frac = segmentMicros == 0 ? 0.0 : (targetTime.difference(before.time).inMicroseconds / segmentMicros).clamp(0.0, 1.0);

    _walkerPosition = LatLng(
      before.location.latitude + (after.location.latitude - before.location.latitude) * frac,
      before.location.longitude + (after.location.longitude - before.location.longitude) * frac,
    );
    _walkerTime = targetTime;
  }

  // -------------------------------------------------------------------
  // BUILD
  // -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    List<TrackItem> filteredList = finalItems.where((item) {
      if (currentFilter == FilterType.halts) return item is HaltEvent;
      if (currentFilter == FilterType.gaps) return item is TimeGap;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Travel Route & Details'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _summaryMode ? 'Exit summary' : 'Play summary',
            icon: Icon(_summaryMode ? Icons.map_rounded : Icons.directions_walk_rounded),
            onPressed: _toggleSummaryMode,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) => _mapController = c,
            initialCameraPosition: CameraPosition(
              target: rawRoute.isNotEmpty ? rawRoute.first : const LatLng(0, 0),
              zoom: 14.0,
            ),
            markers: _buildMarkers(),
            polylines: {
              Polyline(
                polylineId: const PolylineId('route'),
                points: rawRoute,
                color: const Color(0xFF2962FF),
                width: 5,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            padding: const EdgeInsets.only(bottom: 220, top: 90),
          ),

          // --- FLOATING INFO CARD (selected item OR playback time) ---
          if (selectedItem != null && !_summaryMode) _buildSelectedItemCard(),
          if (_summaryMode) _buildPlaybackBar(),

          // --- SLIDING BOTTOM PANEL ---
          if (!_summaryMode)
            DraggableScrollableSheet(
              initialChildSize: 0.32,
              minChildSize: 0.1,
              maxChildSize: 0.65,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                    boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 16, spreadRadius: 2)],
                  ),
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _StickyHeaderDelegate(height: 126, child: _buildSheetHeader()),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildTile(filteredList[index]),
                          childCount: filteredList.length,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSheetHeader() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 46,
            height: 5,
            decoration: BoxDecoration(color: Colors.grey[350], borderRadius: BorderRadius.circular(10)),
          ),
          const Text("Timeline Details", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16),
            child: SegmentedButton<FilterType>(
              segments: const [
                ButtonSegment(value: FilterType.all, label: Text('All')),
                ButtonSegment(value: FilterType.halts, label: Text('Halts')),
                ButtonSegment(value: FilterType.gaps, label: Text('Gaps')),
              ],
              selected: {currentFilter},
              onSelectionChanged: (s) => setState(() => currentFilter = s.first),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildTile(TrackItem item) {
    if (item is StartEvent) {
      return _tile(
        key: item.key,
        color: const Color(0xFFE8F5E9),
        icon: Icons.play_circle_fill_rounded,
        iconColor: const Color(0xFF2E7D32),
        title: "Trip Started",
        subtitle: "At ${formatTime(item.time)}",
        onTap: () => _onListItemTapped(item, item.location),
      );
    }
    if (item is StopEvent) {
      return _tile(
        key: item.key,
        color: const Color(0xFFFFEBEE),
        icon: Icons.flag_circle_rounded,
        iconColor: const Color(0xFFC62828),
        title: "Trip Ended",
        subtitle: "At ${formatTime(item.time)}",
        onTap: () => _onListItemTapped(item, item.location),
      );
    }
    if (item is TimeGap) {
      return _tile(
        key: item.key,
        color: const Color(0xFFFFF3E0),
        icon: Icons.wifi_off_rounded,
        iconColor: const Color(0xFFD84315),
        title: "No Signal / App Closed",
        subtitle: "From ${formatTime(item.startTime)} to ${formatTime(item.endTime)}",
        onTap: () => _onListItemTapped(item, item.lastKnownLocation),
      );
    }
    if (item is HaltEvent) {
      final durationMin = item.duration.inMinutes;
      final subtitleParts = [
        "From ${formatTime(item.startTime)} to ${formatTime(item.endTime)} · ${durationMin}m",
        if (item.isResolvingArea) "Locating area..." else if (item.areaName != null) item.areaName!,
      ];
      return _tile(
        key: item.key,
        color: const Color(0xFFFFF3E0),
        icon: Icons.location_history_rounded,
        iconColor: const Color(0xFFEF6C00),
        title: "Halt #${item.haltNumber}",
        subtitle: subtitleParts.join('\n'),
        onTap: () => _onListItemTapped(item, item.location),
      );
    }
    if (item is LocationPoint) {
      final isSelected = selectedItem == item;
      return _tile(
        key: item.key,
        color: isSelected ? const Color(0xFFE3EAFD) : Colors.white,
        icon: Icons.my_location_rounded,
        iconColor: const Color(0xFF1E3A8A),
        title: formatTime(item.time),
        subtitle: "Moving",
        onTap: () => _onListItemTapped(item, item.location),
      );
    }
    return const SizedBox();
  }

  Widget _tile({
    required Key key,
    required Color color,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(backgroundColor: Colors.white, child: Icon(icon, color: iconColor)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSelectedItemCard() {
    String text;
    if (selectedItem is TimeGap) {
      final g = selectedItem as TimeGap;
      text = "Signal Lost: ${formatTime(g.startTime)} - ${formatTime(g.endTime)}";
    } else if (selectedItem is HaltEvent) {
      final h = selectedItem as HaltEvent;
      final area = h.isResolvingArea ? "locating..." : (h.areaName ?? "unknown area");
      text = "Halt #${h.haltNumber} · ${formatTime(h.startTime)}-${formatTime(h.endTime)} · $area";
    } else if (selectedItem is StartEvent) {
      text = "Trip Started at ${formatTime((selectedItem as StartEvent).time)}";
    } else if (selectedItem is StopEvent) {
      text = "Trip Ended at ${formatTime((selectedItem as StopEvent).time)}";
    } else {
      text = "Location at ${formatTime((selectedItem as LocationPoint).time)}";
    }

    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF1E3A8A),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                onPressed: () => setState(() => selectedItem = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackBar() {
    final timeLabel = _walkerTime != null ? formatTime(_walkerTime!) : '--:--';
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF6A1B9A).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(timeLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6A1B9A))),
                  ),
                  const Spacer(),
                  ...[1.0, 2.0, 4.0].map((s) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text('${s.toInt()}x'),
                          selected: _playbackSpeed == s,
                          onSelected: (_) => _setSpeed(s),
                          selectedColor: const Color(0xFF6A1B9A),
                          labelStyle: TextStyle(color: _playbackSpeed == s ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
                        ),
                      )),
                ],
              ),
              Slider(
                value: _progress.clamp(0.0, 1.0),
                onChanged: (v) => _onScrubbed(v),
                activeColor: const Color(0xFF6A1B9A),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 42,
                    icon: Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, color: const Color(0xFF6A1B9A)),
                    onPressed: _togglePlayPause,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}