import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music_v01/shared/models/timed_lyrics.dart';
import 'package:aurora_music_v01/shared/utils/lyric_timing.dart';

void main() {
  test('preserves fractional timestamps, repeated lines and signed offset', () {
    final parsed = parseTimedLyrics(
      '[ar:Artist]\n[offset:-100]\n[00:05.25][00:10.125]repeated\n'
      '[00:20]final [bracket]\n[00:25.5]\n',
    );
    expect(parsed.map((line) => line.time.inMilliseconds), [
      5150,
      10025,
      19900,
      25400,
    ]);
    expect(parsed.map((line) => line.text), [
      'repeated',
      'repeated',
      'final [bracket]',
      '',
    ]);
  });
  final lyrics = [
    TimedLyric(time: const Duration(seconds: 5), text: 'first'),
    TimedLyric(time: const Duration(seconds: 10), text: 'second'),
    TimedLyric(time: const Duration(seconds: 20), text: 'last'),
  ];
  test('does not show a future line before the first timestamp', () {
    expect(lyricIndexAt(lyrics, Duration.zero), -1);
    expect(lyricIndexAt([], const Duration(seconds: 8)), -1);
  });
  test('changes lines at the exact timestamp and keeps the final line', () {
    expect(lyricIndexAt(lyrics, const Duration(seconds: 5)), 0);
    expect(lyricIndexAt(lyrics, const Duration(milliseconds: 9999)), 0);
    expect(lyricIndexAt(lyrics, const Duration(seconds: 10)), 1);
    expect(lyricIndexAt(lyrics, const Duration(seconds: 90)), 2);
  });
  test('recomputes after forward and backward seeks', () {
    expect(lyricIndexAt(lyrics, const Duration(seconds: 21)), 2);
    expect(lyricIndexAt(lyrics, const Duration(seconds: 7)), 0);
    expect(lyricIndexAt(lyrics, Duration.zero), -1);
  });
}
