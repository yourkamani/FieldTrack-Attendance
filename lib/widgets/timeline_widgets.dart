import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/track_models.dart';

// =====================================================================
// FLOATING CARD FOR THE CURRENTLY SELECTED ITEM
// =====================================================================
class SelectedItemCard extends StatelessWidget {
  final TrackItem item;
  final String Function(DateTime) formatTime;
  final VoidCallback onClose;

  const SelectedItemCard({Key? key, required this.item, required this.formatTime, required this.onClose}) : super(key: key);

  String _text() {
    final it = item;
    if (it is TimeGap) return "Signal Lost: ${formatTime(it.startTime)} - ${formatTime(it.endTime)}";
    if (it is HaltEvent) {
      final area = it.isResolvingArea ? "locating..." : (it.areaName ?? "unknown area");
      return "Halt #${it.haltNumber} · ${formatTime(it.startTime)}-${formatTime(it.endTime)} · $area";
    }
    if (it is StartEvent) return "Trip Started at ${formatTime(it.time)}";
    if (it is StopEvent) return "Trip Ended at ${formatTime(it.time)}";
    if (it is LocationPoint) return "Location at ${formatTime(it.time)}";
    return "";
  }

  @override
  Widget build(BuildContext context) {
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
              Expanded(child: Text(_text(), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
              IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), onPressed: onClose),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// STICKY SHEET HEADER (drag handle + filter segments)
// =====================================================================
class TimelineSheetHeader extends StatelessWidget {
  final FilterType currentFilter;
  final ValueChanged<FilterType> onFilterChanged;

  const TimelineSheetHeader({Key? key, required this.currentFilter, required this.onFilterChanged}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                ButtonSegment(value: FilterType.summary, label: Text('Summary')),
              ],
              selected: {currentFilter},
              onSelectionChanged: (s) => onFilterChanged(s.first),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

// =====================================================================
// SINGLE TIMELINE TILE
// =====================================================================
class TimelineTile extends StatelessWidget {
  final TrackItem item;
  final bool isSelected;
  final String Function(DateTime) formatTime;
  final void Function(TrackItem item, LatLng location) onTap;

  const TimelineTile({
    Key? key,
    required this.item,
    required this.isSelected,
    required this.formatTime,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final it = item;

    if (it is StartEvent) {
      return _tile(
        color: const Color(0xFFE8F5E9),
        icon: Icons.play_circle_fill_rounded,
        iconColor: const Color(0xFF2E7D32),
        title: "Trip Started",
        subtitle: "At ${formatTime(it.time)}",
        onTap: () => onTap(it, it.location),
      );
    }
    if (it is StopEvent) {
      return _tile(
        color: const Color(0xFFFFEBEE),
        icon: Icons.flag_circle_rounded,
        iconColor: const Color(0xFFC62828),
        title: "Trip Ended",
        subtitle: "At ${formatTime(it.time)}",
        onTap: () => onTap(it, it.location),
      );
    }
    if (it is TimeGap) {
      return _tile(
        color: const Color(0xFFFFF3E0),
        icon: Icons.wifi_off_rounded,
        iconColor: const Color(0xFFD84315),
        title: "No Signal / App Closed",
        subtitle: "From ${formatTime(it.startTime)} to ${formatTime(it.endTime)}",
        onTap: () => onTap(it, it.lastKnownLocation),
      );
    }
    if (it is HaltEvent) {
      final subtitleParts = [
        "From ${formatTime(it.startTime)} to ${formatTime(it.endTime)} · ${it.duration.inMinutes}m",
        if (it.isResolvingArea) "Locating area..." else if (it.areaName != null) it.areaName!,
      ];
      return _tile(
        color: const Color(0xFFFFF3E0),
        icon: Icons.location_history_rounded,
        iconColor: const Color(0xFFEF6C00),
        title: "Halt #${it.haltNumber}",
        subtitle: subtitleParts.join('\n'),
        onTap: () => onTap(it, it.location),
      );
    }
    if (it is LocationPoint) {
      return _tile(
        color: isSelected ? const Color(0xFFE3EAFD) : Colors.white,
        icon: Icons.my_location_rounded,
        iconColor: const Color(0xFF1E3A8A),
        title: formatTime(it.time),
        subtitle: "Moving",
        onTap: () => onTap(it, it.location),
      );
    }
    return const SizedBox();
  }

  Widget _tile({
    required Color color,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      key: item.key,
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
}
