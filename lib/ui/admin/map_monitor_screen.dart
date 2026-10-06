import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/geocoding_service.dart';

import '../../models/track_models.dart';
import '../../widgets/marker_icon_factory.dart';
import '../../widgets/route_narrative.dart';
import '../../widgets/playback_bar.dart';
import '../../widgets/timeline_widgets.dart';

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
  final _icons = MarkerIconFactory();

  // Timeline / map data
  List<TrackItem> finalItems = [];
  List<LatLng> rawRoute = [];
  List<LocationPoint> fullTrajectory = []; // every raw point + time, used for playback interpolation
  List<HaltEvent> _halts = [];
  List<List<LatLng>> _movingSegments = []; // polyline pieces, broken around halt regions
  FilterType currentFilter = FilterType.all;
  TrackItem? selectedItem;
  bool isLoading = true;

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
    _icons.buildStaticIcons().then((_) => _fetchRouteData());
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
          double distanceMeters = GeoUtils.distanceMeters(currentCenter, item.location);
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

    final halts = processedItems.whereType<HaltEvent>().toList();

    setState(() {
      finalItems = processedItems;
      rawRoute = routePoints;
      fullTrajectory = trajectory;
      _halts = halts;
      _movingSegments = _buildMovingSegments(trajectory, halts);
      isLoading = false;
    });

    for (final h in halts) {
      await _icons.haltIcon(h.haltNumber);
    }
    if (mounted) setState(() {}); // repaint markers now that numbered halt icons exist

    _resolveAllAreaNames(); // fire and forget, updates UI as results arrive
  }

  /// Breaks the route into segments that stop right before a halt region
  /// and resume right after it, so the polyline never draws through a
  /// halt — the numbered circle represents that stretch instead.
  List<List<LatLng>> _buildMovingSegments(List<LocationPoint> trajectory, List<HaltEvent> halts) {
    bool inHalt(DateTime t) => halts.any((h) => !t.isBefore(h.startTime) && !t.isAfter(h.endTime));

    final segments = <List<LatLng>>[];
    var current = <LatLng>[];
    for (final p in trajectory) {
      if (inHalt(p.time)) {
        if (current.length > 1) segments.add(List.of(current));
        current = [];
      } else {
        current.add(p.location);
      }
    }
    if (current.length > 1) segments.add(current);
    return segments;
  }

  // -------------------------------------------------------------------
  // REVERSE GEOCODING (Google Geocoding API, uses the same key)
  // -------------------------------------------------------------------
  Future<void> _resolveAllAreaNames() async {
    for (final item in finalItems.whereType<StartEvent>()) {
      await _resolveOne(item, item.location);
    }
    for (final h in _halts) {
      await _resolveOne(h, h.location);
    }
    for (final item in finalItems.whereType<StopEvent>()) {
      await _resolveOne(item, item.location);
    }
  }

  Future<void> _resolveOne(AreaResolvable item, LatLng location) async {
    item.isResolvingArea = true;
    if (mounted) setState(() {});

    try {
      item.areaName = await GeocodingService.reverseGeocode(location.latitude, location.longitude);
    } catch (e) {
      item.areaName = 'Unknown area';
    }
    item.isResolvingArea = false;
    if (mounted) setState(() {});
  }

  Future<String?> _reverseGeocode(LatLng point) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${point.latitude},${point.longitude}&key=$_googleApiKey',
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data['status'] != 'OK' || (data['results'] as List).isEmpty) return null;

      for (final result in data['results']) {
        final components = result['address_components'] as List;
        String? sublocality;
        String? locality;
        for (final c in components) {
          final types = List<String>.from(c['types']);
          if (types.contains('sublocality_level_1') || types.contains('sublocality')) sublocality ??= c['long_name'];
          if (types.contains('locality')) locality ??= c['long_name'];
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
  // MARKERS / OVERLAYS
  // -------------------------------------------------------------------
  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    // Other markers fade during summary mode so the walker is the one
    // unmistakable focal point — nothing overlaps or competes with it.
    final otherAlpha = _summaryMode ? 0.55 : 1.0;

    for (final item in finalItems) {
      if (item is StartEvent && _icons.startIcon != null) {
        markers.add(Marker(
          markerId: const MarkerId('start'),
          position: item.location,
          icon: _icons.startIcon!,
          anchor: const Offset(0.5, 0.5),
          alpha: otherAlpha,
          onTap: () => _onPointTapped(item),
        ));
      } else if (item is StopEvent && _icons.stopIcon != null) {
        markers.add(Marker(
          markerId: const MarkerId('stop'),
          position: item.location,
          icon: _icons.stopIcon!,
          anchor: const Offset(0.5, 0.5),
          alpha: otherAlpha,
          onTap: () => _onPointTapped(item),
        ));
      } else if (item is TimeGap && _icons.gapIcon != null) {
        markers.add(Marker(
          markerId: MarkerId('gap_${item.startTime.millisecondsSinceEpoch}'),
          position: item.lastKnownLocation,
          icon: _icons.gapIcon!,
          anchor: const Offset(0.5, 0.5),
          alpha: otherAlpha,
          onTap: () => _onPointTapped(item),
        ));
      } else if (item is HaltEvent) {
        final icon = _icons.cachedHaltIcon(item.haltNumber) ?? _icons.dotIconSelected;
        if (icon == null) continue;
        markers.add(Marker(
          markerId: MarkerId('halt_${item.haltNumber}'),
          position: item.location,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          zIndex: 5,
          alpha: otherAlpha,
          onTap: () => _onPointTapped(item),
        ));
      } else if (item is LocationPoint && !_summaryMode) {
        final isSelected = selectedItem == item;
        final icon = isSelected ? _icons.dotIconSelected : _icons.dotIcon;
        if (icon == null) continue;
        markers.add(Marker(
          markerId: MarkerId('pt_${item.time.millisecondsSinceEpoch}'),
          position: item.location,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          onTap: () => _onPointTapped(item),
        ));
      }
    }

    if (_summaryMode && _walkerPosition != null && _icons.walkerIcon != null) {
      markers.add(Marker(
        markerId: const MarkerId('walker'),
        position: _walkerPosition!,
        icon: _icons.walkerIcon!,
        anchor: walkerMarkerAnchor,
        zIndex: 100, // always drawn above everything else
      ));
    }

    return markers;
  }

  Set<Circle> _buildHaltCircles() {
    return _halts
        .map((h) => Circle(
              circleId: CircleId('halt_region_${h.haltNumber}'),
              center: h.location,
              radius: h.regionRadiusMeters,
              fillColor: const Color(0xFFEF6C00).withOpacity(0.18),
              strokeColor: const Color(0xFFEF6C00).withOpacity(0.6),
              strokeWidth: 2,
            ))
        .toSet();
  }

  Set<Polyline> _buildPolylines() {
    return {
      for (int i = 0; i < _movingSegments.length; i++)
        Polyline(
          polylineId: PolylineId('segment_$i'),
          points: _movingSegments[i],
          color: const Color(0xFF2962FF),
          width: 5,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };
  }

  // -------------------------------------------------------------------
  // INTERACTION
  // -------------------------------------------------------------------
  void _onPointTapped(TrackItem item) {
    setState(() => selectedItem = item);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (item.key.currentContext != null) {
        Scrollable.ensureVisible(item.key.currentContext!, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut, alignment: 0.5);
      }
    });
  }

  void _onListItemTapped(TrackItem item, LatLng mapLocation) {
    setState(() => selectedItem = item);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(mapLocation, 16.5));
  }

  String formatTime(DateTime d) => "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  // -------------------------------------------------------------------
  // SUMMARY PLAYBACK
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

  void _setSpeed(double speed) => setState(() => _playbackSpeed = speed);

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
            initialCameraPosition: CameraPosition(target: rawRoute.isNotEmpty ? rawRoute.first : const LatLng(0, 0), zoom: 14.0),
            markers: _buildMarkers(),
            circles: _buildHaltCircles(),
            polylines: _buildPolylines(),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            padding: const EdgeInsets.only(bottom: 220, top: 90),
          ),

          if (selectedItem != null && !_summaryMode)
            SelectedItemCard(item: selectedItem!, formatTime: formatTime, onClose: () => setState(() => selectedItem = null)),

          if (_summaryMode)
            PlaybackBar(
              timeLabel: _walkerTime != null ? formatTime(_walkerTime!) : '--:--',
              progress: _progress,
              isPlaying: _isPlaying,
              speed: _playbackSpeed,
              onScrub: _onScrubbed,
              onTogglePlay: _togglePlayPause,
              onSpeedChange: _setSpeed,
            ),

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
                        delegate: _SheetHeaderDelegate(
                          height: 126,
                          child: TimelineSheetHeader(currentFilter: currentFilter, onFilterChanged: (f) => setState(() => currentFilter = f)),
                        ),
                      ),
                      if (currentFilter == FilterType.summary)
                        SliverToBoxAdapter(child: RouteSummaryList(entries: buildRouteNarrative(finalItems, formatTime)))
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => TimelineTile(
                              item: filteredList[index],
                              isSelected: selectedItem == filteredList[index],
                              formatTime: formatTime,
                              onTap: _onListItemTapped,
                            ),
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
}

class _SheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  _SheetHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox(height: height, child: child);

  @override
  bool shouldRebuild(covariant _SheetHeaderDelegate oldDelegate) => true;
}
