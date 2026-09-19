String formatClock(Duration d, {bool forceHours = false}) {
  final total = d.inSeconds.abs();
  final sign = d.isNegative ? '-' : '';
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (forceHours || h > 0) {
    return '$sign$h:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
  return '$sign$m:${s.toString().padLeft(2, '0')}';
}

String formatRemainingLabel(Duration d) {
  if (d.isNegative || d.inMilliseconds == 0) return '00:00';
  return formatClock(d);
}
