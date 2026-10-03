import '../models/timed_lyrics.dart';

/// Line-level LRC timestamps, including fractional seconds, repeated lines,
/// and the standard global millisecond offset.
List<TimedLyric> parseTimedLyrics(String lrc) {
  final timestamp = RegExp(r'\[(\d+):([0-5]\d)(?:[.:](\d{1,3}))?\]');
  final offsetMatch = RegExp(
    r'\[offset:([+-]?\d+)\]',
    caseSensitive: false,
  ).firstMatch(lrc);
  final offset = int.tryParse(offsetMatch?.group(1) ?? '') ?? 0;
  final result = <TimedLyric>[];
  for (final line in lrc.split('\n')) {
    final matches = timestamp.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final text = line.substring(matches.last.end).trim();
    for (final match in matches) {
      final fraction = (match.group(3) ?? '').padRight(3, '0');
      final ms =
          int.parse(match.group(1)!) * 60000 +
          int.parse(match.group(2)!) * 1000 +
          int.parse(fraction) +
          offset;
      result.add(
        TimedLyric(
          time: Duration(milliseconds: ms),
          text: text,
        ),
      );
    }
  }
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

/// Last line whose timestamp is at or before [position], or -1 before vocals.
/// Input must be sorted by timestamp. Handles seeks in either direction.
int lyricIndexAt(List<TimedLyric> lyrics, Duration position) {
  var low = 0;
  var high = lyrics.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (lyrics[mid].time <= position) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low - 1;
}
