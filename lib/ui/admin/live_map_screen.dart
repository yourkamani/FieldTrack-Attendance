import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/supabase_client.dart';

/// Shows every employee's latest known location on one map, updating in realtime.
class LiveMapScreen extends StatefulWidget {
  /// If set, the map opens zoomed in on this employee instead of fitting everyone.
  final String? focusUserId;
  const LiveMapScreen({Key? key, this.focusUserId}) : super(key: key);
  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  static const _staleAfter = Duration(minutes: 3);

  GoogleMapController? _map;
  Map<String, Map<String, dynamic>> _users = {}; // id -> user row
  Stream<List<Map<String, dynamic>>>? _stream;
  Timer? _ticker;
  bool _loading = true;
  bool _fitted = false;
  String? _selectedId;
  String _roleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _init();
    // Re-evaluate "stale" status even when no new rows arrive.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final bid = prefs.getString('business_id');
    if (bid == null) return;
    final rows = await SB.client.from('users').select('id, name, phone, role').eq('business_id', bid);
    if (!mounted) return;
    setState(() {
      _users = {for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r)};
      _stream = SB.client.from('live_locations').stream(primaryKey: ['user_id']).eq('business_id', bid);
      _loading = false;
    });
  }

  _Status _statusOf(Map<String, dynamic> row) {
    if (row['gps_enabled'] != true) return _Status.gpsOff;
    if (row['latitude'] == null || row['longitude'] == null) return _Status.gpsOff;
    final updated = DateTime.tryParse('${row['updated_at']}')?.toLocal();
    if (updated == null || DateTime.now().difference(updated) > _staleAfter) return _Status.stale;
    return _Status.live;
  }

  String _ago(Map<String, dynamic> row) {
    final t = DateTime.tryParse('${row['updated_at']}')?.toLocal();
    if (t == null) return 'unknown';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  double _hue(_Status s) => switch (s) {
        _Status.live => BitmapDescriptor.hueGreen,
        _Status.stale => BitmapDescriptor.hueAzure,
        _Status.gpsOff => BitmapDescriptor.hueOrange,
      };

  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> rows) => rows
      .where((r) => _users.containsKey(r['user_id']))
      .where((r) => _roleFilter == 'all' || _users[r['user_id']]!['role'] == _roleFilter)
      .toList();

  void _focus(Map<String, dynamic> row) {
    setState(() => _selectedId = row['user_id']);
    if (row['latitude'] == null) return;
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng((row['latitude'] as num).toDouble(), (row['longitude'] as num).toDouble()), 16));
  }

  void _fitAll(List<Map<String, dynamic>> rows) {
    final pts = rows
        .where((r) => r['latitude'] != null && r['longitude'] != null)
        .map((r) => LatLng((r['latitude'] as num).toDouble(), (r['longitude'] as num).toDouble()))
        .toList();
    if (pts.isEmpty || _map == null) return;
    if (pts.length == 1) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    final south = pts.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final north = pts.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final west = pts.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final east = pts.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    _map!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)), 80));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _stream == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final roles = {for (final u in _users.values) (u['role'] ?? '').toString()}..remove('');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Map'),
        actions: [
          if (roles.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filter by role',
              onSelected: (v) => setState(() => _roleFilter = v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'all', child: Text('All roles')),
                for (final r in roles) PopupMenuItem(value: r, child: Text(r.toUpperCase())),
              ],
            ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load live locations: ${snap.error}'));
          final rows = _visible(snap.data ?? []);

          if (!_fitted && rows.any((r) => r['latitude'] != null)) {
            _fitted = true;
            final focus = widget.focusUserId == null
                ? null
                : rows.where((r) => r['user_id'] == widget.focusUserId && r['latitude'] != null).toList();
            if (focus != null && focus.isNotEmpty) {
              _selectedId = widget.focusUserId;
              WidgetsBinding.instance.addPostFrameCallback((_) => _focus(focus.first));
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll(rows));
            }
          }

          final markers = <Marker>{
            for (final r in rows)
              if (r['latitude'] != null && r['longitude'] != null)
                Marker(
                  markerId: MarkerId(r['user_id']),
                  position: LatLng((r['latitude'] as num).toDouble(), (r['longitude'] as num).toDouble()),
                  icon: BitmapDescriptor.defaultMarkerWithHue(_hue(_statusOf(r))),
                  infoWindow: InfoWindow(title: _users[r['user_id']]!['name'], snippet: 'Updated ${_ago(r)}'),
                  onTap: () => setState(() => _selectedId = r['user_id']),
                ),
          };

          // People with no live row at all (never started tracking).
          final seen = rows.map((r) => r['user_id']).toSet();
          final silent = _users.values
              .where((u) => !seen.contains(u['id']) && (_roleFilter == 'all' || u['role'] == _roleFilter))
              .toList();

          return Stack(children: [
            GoogleMap(
              onMapCreated: (c) => _map = c,
              initialCameraPosition: const CameraPosition(target: LatLng(20.5937, 78.9629), zoom: 4),
              markers: markers,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              padding: const EdgeInsets.only(bottom: 150),
            ),
            Positioned(
              right: 12, top: 12,
              child: FloatingActionButton.small(
                heroTag: 'fit',
                tooltip: 'Show everyone',
                onPressed: () => _fitAll(rows),
                child: const Icon(Icons.zoom_out_map),
              ),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                height: 140,
                color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
                child: rows.isEmpty && silent.isEmpty
                    ? const Center(child: Text('No personnel yet.'))
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(8),
                        children: [
                          for (final r in rows) _chip(r),
                          for (final u in silent) _silentChip(u),
                        ],
                      ),
              ),
            ),
            const Positioned(left: 12, top: 12, child: _Legend()),
          ]);
        },
      ),
    );
  }

  Widget _chip(Map<String, dynamic> r) {
    final s = _statusOf(r);
    final u = _users[r['user_id']]!;
    final color = switch (s) { _Status.live => Colors.green, _Status.stale => Colors.blue, _Status.gpsOff => Colors.orange };
    final label = switch (s) { _Status.live => 'Live', _Status.stale => 'Offline · ${_ago(r)}', _Status.gpsOff => 'GPS off' };
    return GestureDetector(
      onTap: () => _focus(r),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _selectedId == r['user_id'] ? color : Colors.transparent, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 150,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${u['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${u['role'] ?? ''}'.toUpperCase(), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 6),
              Row(children: [Icon(Icons.circle, size: 10, color: color), const SizedBox(width: 6), Flexible(child: Text(label, style: TextStyle(color: color, fontSize: 12)))]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _silentChip(Map<String, dynamic> u) => Card(
        color: Colors.grey.shade200,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 150,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${u['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('No location yet', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
        ),
      );
}

enum _Status { live, stale, gpsOff }

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 10, color: c), const SizedBox(width: 4), Text(t, style: const TextStyle(fontSize: 11)),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
            children: [dot(Colors.green, 'Live'), dot(Colors.blue, 'Offline'), dot(Colors.orange, 'GPS off')]),
      ),
    );
  }
}
