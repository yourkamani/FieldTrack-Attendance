import 'package:flutter/material.dart';

class PlaybackBar extends StatelessWidget {
  final String timeLabel;
  final double progress;
  final bool isPlaying;
  final double speed;
  final ValueChanged<double> onScrub;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSpeedChange;

  const PlaybackBar({
    Key? key,
    required this.timeLabel,
    required this.progress,
    required this.isPlaying,
    required this.speed,
    required this.onScrub,
    required this.onTogglePlay,
    required this.onSpeedChange,
  }) : super(key: key);

  static const _accent = Color(0xFF6A1B9A);

  @override
  Widget build(BuildContext context) {
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
                    decoration: BoxDecoration(color: _accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(timeLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: _accent)),
                  ),
                  const Spacer(),
                  ...[1.0, 2.0, 4.0].map((s) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text('${s.toInt()}x'),
                          selected: speed == s,
                          onSelected: (_) => onSpeedChange(s),
                          selectedColor: _accent,
                          labelStyle: TextStyle(color: speed == s ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
                        ),
                      )),
                ],
              ),
              Slider(value: progress.clamp(0.0, 1.0), onChanged: onScrub, activeColor: _accent),
              IconButton(
                iconSize: 42,
                icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, color: _accent),
                onPressed: onTogglePlay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
