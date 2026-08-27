import 'dart:math' as math; // ADDED for rotation math
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- DATA MODELS ---
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

class HaltEvent extends TrackItem {
  final LatLng location;
  final DateTime startTime;
  final DateTime endTime;
  HaltEvent({required this.location, required this.startTime, required this.endTime});
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

// --- DELEGATE FOR STICKY DRAGGABLE HEADER ---
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

// --- MAIN SCREEN ---
class MapMonitorScreen extends StatefulWidget {
  final String userId;
  final String sessionId;

  const MapMonitorScreen({Key? key, required this.userId, required this.sessionId}) : super(key: key);

  @override
  _MapMonitorScreenState createState() => _MapMonitorScreenState();
}

class _MapMonitorScreenState extends State<MapMonitorScreen> {
  final _supabase = Supabase.instance.client;
  final MapController _mapController = MapController();
  
  List<TrackItem> finalItems = [];
  List<LatLng> rawRoute = [];
  FilterType currentFilter = FilterType.all;
  TrackItem? selectedItem;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRouteData();
  }

  Future<void> _fetchRouteData() async {
    final response = await _supabase
        .from('location_tracks')
        .select()
        .eq('user_id', widget.userId)
        .eq('session_id', widget.sessionId)
        .order('timestamp', ascending: true);

    List<TrackItem> rawTimeline = [];
    List<LatLng> routePoints = [];
    DateTime? lastTime;
    LatLng? lastLoc;

    for (var i = 0; i < response.length; i++) {
      var row = response[i];
      LatLng currentLoc = LatLng(row['latitude'], row['longitude']);
      DateTime currentTime = DateTime.parse(row['timestamp']);
      
      routePoints.add(currentLoc);

      if (lastTime != null && currentTime.difference(lastTime).inMinutes > 5) {
        rawTimeline.add(TimeGap(
          startTime: lastTime,
          endTime: currentTime,
          lastKnownLocation: lastLoc!,
        ));
      }
      
      rawTimeline.add(LocationPoint(location: currentLoc, time: currentTime));
      
      lastTime = currentTime;
      lastLoc = currentLoc;
    }

    List<TrackItem> processedItems = [];
    List<TrackItem> buffer = [];
    LatLng? currentCenter;

    void flushBuffer() {
      if (buffer.isEmpty) return;
      
      var locs = buffer.whereType<LocationPoint>().toList();
      var gaps = buffer.whereType<TimeGap>().toList();

      if (locs.isNotEmpty && locs.last.time.difference(locs.first.time).inMinutes >= 15) {
        processedItems.add(HaltEvent(
          location: locs.first.location,
          startTime: locs.first.time,
          endTime: locs.last.time,
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
          double distanceMeters = const Distance().distance(currentCenter, item.location);
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
      processedItems.insert(0, StartEvent(
        location: routePoints.first,
        time: rawTimeline.first.primaryTime,
      ));
      
      if (routePoints.length > 1) {
        processedItems.add(StopEvent(
          location: routePoints.last,
          time: rawTimeline.last.primaryTime,
        ));
      }
    }

    setState(() {
      finalItems = processedItems;
      rawRoute = routePoints;
      isLoading = false;
    });
  }

  // --- NEW METHOD: Generates directional arrows along the route ---
// --- UPDATED METHOD: Generates an arrow exactly in between every 2 points ---
  List<Marker> _generateArrowMarkers() {
    List<Marker> arrows = [];
    if (rawRoute.length < 2) return arrows;

    final Distance distanceCalc = const Distance();

    for (int i = 0; i < rawRoute.length - 1; i++) {
      LatLng p1 = rawRoute[i];
      LatLng p2 = rawRoute[i + 1];
      
      // Skip if the points are identical to avoid zero-distance errors
      if (p1.latitude == p2.latitude && p1.longitude == p2.longitude) continue;

      // Calculate the angle from p1 to p2
      double bearing = distanceCalc.bearing(p1, p2);
      
      // Calculate the exact midpoint between p1 and p2
      LatLng midPoint = LatLng(
        (p1.latitude + p2.latitude) / 2,
        (p1.longitude + p2.longitude) / 2,
      );
      
      arrows.add(
        Marker(
          point: midPoint, // Placed exactly in the middle of the segment
          width: 16, 
          height: 16,
          child: Transform.rotate(
            angle: bearing * math.pi / 180, // Convert bearing to radians
            child: const Icon(
              Icons.navigation, 
              color: Colors.white, 
              size: 14, // Small arrow size
            ),
          ),
        ),
      );
    }
    return arrows;
  }

  void _onPointTapped(TrackItem item) {
    setState(() {
      selectedItem = item;
      currentFilter = FilterType.all; 
    });
    
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
    _mapController.move(mapLocation, 16.0);
  }

  String formatTime(DateTime d) {
    return "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    List<TrackItem> filteredList = finalItems.where((item) {
      if (currentFilter == FilterType.halts) return item is HaltEvent;
      if (currentFilter == FilterType.gaps) return item is TimeGap;
      return true; 
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Travel Route & Details')),
      body: Stack(
        children: [
          // --- THE MAP ---
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: rawRoute.isNotEmpty ? rawRoute.first : const LatLng(0, 0),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.attendance_tracker',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(points: rawRoute, color: Colors.blueAccent, strokeWidth: 8.0),
                ],
              ),
              
              // --- ARROWS LAYER (Placed BELOW the interactive points) ---
              MarkerLayer(
                markers: _generateArrowMarkers(),
              ),

              // --- MAIN INTERACTIVE MARKERS LAYER ---
              MarkerLayer(
                markers: finalItems.map((item) {
                  Widget markerIcon;
                  LatLng markerPoint;

                  if (item is StartEvent) {
                    markerIcon = const Icon(Icons.play_circle_fill, color: Colors.green, size: 35);
                    markerPoint = item.location;
                  } else if (item is StopEvent) {
                    markerIcon = const Icon(Icons.flag_circle, color: Colors.red, size: 35);
                    markerPoint = item.location;
                  } else if (item is TimeGap) {
                    markerIcon = const Icon(Icons.warning, color: Colors.red, size: 35);
                    markerPoint = item.lastKnownLocation;
                  } else if (item is HaltEvent) {
                    markerIcon = const Icon(Icons.stop_circle, color: Colors.orange, size: 35);
                    markerPoint = item.location;
                  } else {
                    markerIcon = Container(
                      decoration: BoxDecoration(
                        color: selectedItem == item ? Colors.black.withOpacity(0.3) : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.circle, color: selectedItem == item ? Colors.white : Colors.blue[900]!, size: selectedItem == item ? 20 : 12),
                    );
                    markerPoint = (item as LocationPoint).location;
                  }

                  return Marker(
                    point: markerPoint,
                    width: 40, height: 40,
                    child: GestureDetector(
                      onTap: () => _onPointTapped(item),
                      child: markerIcon,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // --- FLOATING TIME DISPLAY ---
          if (selectedItem != null)
            Positioned(
              top: 20, left: 20, right: 20,
              child: Card(
                color: Colors.blue[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Center(
                    child: Text(
                      selectedItem is TimeGap 
                        ? "Signal Lost: ${formatTime((selectedItem as TimeGap).startTime)} - ${formatTime((selectedItem as TimeGap).endTime)}"
                        : selectedItem is HaltEvent 
                          ? "Halted: ${formatTime((selectedItem as HaltEvent).startTime)} - ${formatTime((selectedItem as HaltEvent).endTime)}"
                          : selectedItem is StartEvent
                            ? "Trip Started at ${formatTime((selectedItem as StartEvent).time)}"
                            : selectedItem is StopEvent
                              ? "Trip Ended at ${formatTime((selectedItem as StopEvent).time)}"
                              : "Location at ${formatTime((selectedItem as LocationPoint).time)}",
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),

          // --- SLIDING BOTTOM PANEL WITH CUSTOM SCROLL VIEW ---
          DraggableScrollableSheet(
            initialChildSize: 0.3,
            minChildSize: 0.1,
            maxChildSize: 0.6,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, spreadRadius: 2)],
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _StickyHeaderDelegate(
                        height: 120, 
                        child: Container(
                          color: Colors.white, 
                          child: Column(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 10, bottom: 10),
                                width: 50, height: 5,
                                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10)),
                              ),
                              const Text("Timeline Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10),
                                child: SegmentedButton<FilterType>(
                                  segments: const [
                                    ButtonSegment(value: FilterType.all, label: Text('All')),
                                    ButtonSegment(value: FilterType.halts, label: Text('Halts')),
                                    ButtonSegment(value: FilterType.gaps, label: Text('Gaps')),
                                  ],
                                  selected: {currentFilter},
                                  onSelectionChanged: (Set<FilterType> newSelection) {
                                    setState(() => currentFilter = newSelection.first);
                                  },
                                ),
                              ),
                              const Divider(height: 1),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = filteredList[index];

                          if (item is StartEvent) {
                            return ListTile(
                              key: item.key,
                              tileColor: Colors.green[50],
                              leading: const Icon(Icons.play_circle_fill, color: Colors.green),
                              title: Text("Trip Started", style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold)),
                              subtitle: Text("At ${formatTime(item.time)}"),
                              onTap: () => _onListItemTapped(item, item.location),
                            );
                          }

                          if (item is StopEvent) {
                            return ListTile(
                              key: item.key,
                              tileColor: Colors.red[50],
                              leading: const Icon(Icons.flag_circle, color: Colors.red),
                              title: Text("Trip Ended", style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold)),
                              subtitle: Text("At ${formatTime(item.time)}"),
                              onTap: () => _onListItemTapped(item, item.location),
                            );
                          }

                          if (item is TimeGap) {
                            return ListTile(
                              key: item.key,
                              tileColor: Colors.red[50],
                              leading: const Icon(Icons.warning, color: Colors.red),
                              title: Text("No Signal / App Closed", style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold)),
                              subtitle: Text("From ${formatTime(item.startTime)} to ${formatTime(item.endTime)}"),
                              onTap: () => _onListItemTapped(item, item.lastKnownLocation),
                            );
                          }

                          if (item is HaltEvent) {
                            return ListTile(
                              key: item.key,
                              tileColor: Colors.orange[50],
                              leading: const Icon(Icons.stop_circle, color: Colors.orange),
                              title: Text("Halt (Merged)", style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold)),
                              subtitle: Text("From ${formatTime(item.startTime)} to ${formatTime(item.endTime)}"),
                              onTap: () => _onListItemTapped(item, item.location),
                            );
                          }

                          if (item is LocationPoint) {
                            return ListTile(
                              key: item.key,
                              tileColor: selectedItem == item ? Colors.blue[100] : Colors.white,
                              leading: const Icon(Icons.my_location, color: Colors.blue),
                              title: Text(formatTime(item.time), style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text("Moving"),
                              onTap: () => _onListItemTapped(item, item.location),
                            );
                          }
                          return const SizedBox();
                        },
                        childCount: filteredList.length,
                      ),
                    ),
                  ],
                ),
              );
            },
          )
        ],
      ),
    );
  }
}