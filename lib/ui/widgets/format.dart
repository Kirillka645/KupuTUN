import 'package:flutter/material.dart';

/// Ping colours: green < 100 ms, yellow < 300 ms, red otherwise, grey = dead.
Color pingColor(int? ms) {
  if (ms == null) return Colors.grey;
  if (ms < 100) return const Color(0xFF2EB872);
  if (ms < 300) return const Color(0xFFF2B01E);
  return const Color(0xFFE5484D);
}

String formatBytes(num b) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

String formatRate(double bytesPerSec) => '${formatBytes(bytesPerSec)}/s';

String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

String formatMbps(double? v) => v == null ? '—' : '${v.toStringAsFixed(v >= 100 ? 0 : 1)} Mbit/s';

String formatDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
}

/// Server name without a leading flag emoji (the flag is already shown as
/// the row avatar, so "🇳🇱 The Netherlands" doesn't waste width twice).
String displayServerName(String name) {
  final runes = name.runes.toList();
  var i = 0;
  bool ri(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;
  while (i + 1 < runes.length && ri(runes[i]) && ri(runes[i + 1])) {
    i += 2;
    while (i < runes.length && (runes[i] == 0x20 || runes[i] == 0xFE0F || runes[i] == 0x7C)) {
      i++;
    }
  }
  final out = String.fromCharCodes(runes.sublist(i)).trim();
  return out.isEmpty ? name : out;
}
