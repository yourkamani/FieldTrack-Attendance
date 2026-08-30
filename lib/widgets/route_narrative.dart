import 'package:flutter/material.dart';
import '../models/track_models.dart';

class NarrativeEntry {
  final bool isHalt;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  NarrativeEntry({
    required this.isHalt,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

/// A resolved anchor point in the journey: the trip start, a halt, or the
/// trip end. Travel entries are generated for the gaps *between* anchors.
class _Anchor {
  final DateTime enterTime;
  final DateTime exitTime;
  final String areaLabel;
  final bool isHalt;
  final int? haltNumber;
  final Duration? haltDuration;

  _Anchor({
    required this.enterTime,
    required this.exitTime,
    required this.areaLabel,
    this.isHalt = false,
    this.haltNumber,
    this.haltDuration,
  });
}

String _labelFor(AreaResolvable item) {
  if (item.isResolvingArea) return 'locating…';
  return item.areaName ?? 'unknown area';
}

/// Builds the human-readable "10:15–10:40 stayed near Kurla, then traveled
/// to Mulund by 11:05" style narrative from the processed timeline.
List<NarrativeEntry> buildRouteNarrative(List<TrackItem> finalItems, String Function(DateTime) formatTime) {
  final anchors = <_Anchor>[];

  for (final item in finalItems) {
    if (item is StartEvent) {
      anchors.add(_Anchor(enterTime: item.time, exitTime: item.time, areaLabel: _labelFor(item)));
    } else if (item is HaltEvent) {
      anchors.add(_Anchor(
        enterTime: item.startTime,
        exitTime: item.endTime,
        areaLabel: _labelFor(item),
        isHalt: true,
        haltNumber: item.haltNumber,
        haltDuration: item.duration,
      ));
    } else if (item is StopEvent) {
      anchors.add(_Anchor(enterTime: item.time, exitTime: item.time, areaLabel: _labelFor(item)));
    }
  }

  final entries = <NarrativeEntry>[];

  for (int i = 0; i < anchors.length; i++) {
    final a = anchors[i];

    if (a.isHalt) {
      entries.add(NarrativeEntry(
        isHalt: true,
        icon: Icons.location_history_rounded,
        color: const Color(0xFFEF6C00),
        title: 'Halt #${a.haltNumber} · ${a.haltDuration != null ? "${a.haltDuration!.inMinutes} min" : ""}',
        subtitle: '${formatTime(a.enterTime)} – ${formatTime(a.exitTime)} in ${a.areaLabel}',
      ));
    }

    if (i < anchors.length - 1) {
      final next = anchors[i + 1];
      final travelStart = a.exitTime;
      final travelEnd = next.enterTime;
      if (travelEnd.isAfter(travelStart)) {
        entries.add(NarrativeEntry(
          isHalt: false,
          icon: Icons.alt_route_rounded,
          color: const Color(0xFF1E3A8A),
          title: 'Traveled from ${a.areaLabel} to ${next.areaLabel}',
          subtitle: '${formatTime(travelStart)} – ${formatTime(travelEnd)}',
        ));
      }
    }
  }

  return entries;
}

/// Renders the narrative as a vertical timeline of cards inside the
/// bottom sheet's "Summary" filter.
class RouteSummaryList extends StatelessWidget {
  final List<NarrativeEntry> entries;
  const RouteSummaryList({Key? key, required this.entries}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Not enough data yet to summarize this trip.')),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      child: Column(
        children: entries.map((e) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: e.color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: e.color, width: 3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(e.icon, color: e.color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, style: TextStyle(fontWeight: FontWeight.bold, color: e.color.withOpacity(0.9))),
                      const SizedBox(height: 2),
                      Text(e.subtitle, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
