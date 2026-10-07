# Floating lyrics (Android)

Open **Settings → Floating lyrics**, enable the switch and grant Android's
**Display over other apps** permission. After returning to Aurora, the switch
is enabled automatically if permission was granted. Play a song to display the
window; the Now Playing screen does not need to be open.

## Controls

- Controls start hidden. Tap the lyrics, even while locked, to show the handle,
  Lock/Unlock and Close for 5 seconds. Tap again to restart the timer.
- Drag the handle or lyric text to reposition the unlocked window.
- Lock/Unlock fixes or releases the position; Close disables floating lyrics.
- Text opacity and background opacity are independent, from 0–100%.
  Revealed controls remain opaque even when both are at 0%.
- Choose a text colour, font size (12–36), and whether to show the next line.
- Style and enabled state are saved in Flutter preferences. Window position
  is saved in Android preferences and clamped back onto the screen.

## Implementation

`FloatingLyricsService` is an eager, app-scoped provider, independent of the
player screens. While enabled it samples the active audio player every 150 ms,
so seeks, playback-speed changes, pauses and crossfade player replacements
use the same authoritative position as playback. Only changed lyric/style
payloads cross the platform channel. It reuses `TimedLyricsService` and its
LRCLIB/disk cache; it does not embed or alter music files.

`FloatingLyricsPlugin` is attached to the Flutter engine rather than the
activity. It uses an application-context `WindowManager` overlay and the
existing `audio_service` background playback lifetime, without starting a
second player or foreground service. It removes its window on engine detach,
disable, playback completion/idle, or permission errors. A paused track keeps
its current lyric visible. No accessibility or notification-listener access
is requested.

LRC parsing preserves millisecond fractions, repeated timestamps, global
offsets and blank timed lines. This also fixes the original lyric parser's
loss of fractional seconds. Lyric selection uses a binary search and does
not display the first line before its timestamp (the optional next-line
preview can still be visible).

## Validation

- New regression tests: `flutter test test/lyric_timing_test.dart`.
- Inspect/analyze the changed Dart files and build an Android APK in a configured
  Flutter environment before merging.
- Device checks: enable/deny/revoke permission; open another app; pause/resume;
  seek forward/back; change playback speed; skip tracks; use crossfade; rotate;
  lock/unlock/close; restart Aurora and check saved styles and position; play
  cached lyrics offline; stop playback and verify the window disappears.
- Test large system text on the settings page, plus tap/reveal/auto-hide,
  dragging, locked taps, closing and reopening the overlay on a device.
- Background lyric and overlay behavior still needs actual Android testing.
  OEM battery policies and apps that hide overlays may affect visibility.

The settings page provides English and Chinese text; native window controls
currently use English. The existing app build/signing configuration is unchanged.
