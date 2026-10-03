import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/timed_lyrics.dart';
import '../utils/lyric_timing.dart';
import 'audio_player_service.dart';
import 'lyrics_service.dart';

/// App-scoped lyric synchronization. Never depends on a player screen being
/// mounted, and samples the current player so crossfade hand-offs are followed.
class FloatingLyricsService extends ChangeNotifier {
  FloatingLyricsService(this._audio) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'closed') await setEnabled(false);
      if (call.method == 'lockChanged') {
        locked = call.arguments as bool;
        await _save();
        notifyListeners();
      }
    });
    ready = _initialize();
  }

  static const _channel = MethodChannel('aurora/floating_lyrics');
  final AudioPlayerService _audio;
  final TimedLyricsService _lyricsService = TimedLyricsService();
  late final Future<void> ready;
  Timer? _timer;
  SharedPreferences? _prefs;
  List<TimedLyric> _lyrics = [];
  String? _songKey;
  String? _lastPayload;
  int _generation = 0;
  bool _disposed = false;
  bool _sending = false;
  bool _visible = false;
  bool _loading = false;
  bool enabled = false;
  bool locked = false;
  bool twoLines = true;
  double textOpacity = 1;
  double backgroundOpacity = .25;
  double fontSize = 20;
  int textColor = 0xFFFFFFFF;
  String? error;
  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    enabled = _prefs!.getBool('floatingLyrics.enabled') ?? false;
    locked = _prefs!.getBool('floatingLyrics.locked') ?? false;
    twoLines = _prefs!.getBool('floatingLyrics.twoLines') ?? true;
    textOpacity = (_prefs!.getDouble('floatingLyrics.textOpacity') ?? 1)
        .clamp(0, 1)
        .toDouble();
    backgroundOpacity =
        (_prefs!.getDouble('floatingLyrics.backgroundOpacity') ?? .25)
            .clamp(0, 1)
            .toDouble();
    fontSize = (_prefs!.getDouble('floatingLyrics.fontSize') ?? 20)
        .clamp(12, 36)
        .toDouble();
    textColor = _prefs!.getInt('floatingLyrics.textColor') ?? 0xFFFFFFFF;
    if (!supported) {
      enabled = false;
      notifyListeners();
      return;
    }
    if (enabled && !await hasPermission()) {
      enabled = false;
      await _save();
    }
    if (_disposed) return;
    _lyricsService.lyricsRevisionNotifier.addListener(_invalidateLyrics);
    _startTimer();
    notifyListeners();
  }

  Future<bool> hasPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on PlatformException catch (e) {
      error = e.message;
      return false;
    } on MissingPluginException {
      error = 'Floating lyrics are unavailable in this build.';
      return false;
    }
  }

  Future<void> requestPermission() async {
    await ready;
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } on PlatformException catch (e) {
      error = e.message;
      notifyListeners();
    }
  }

  Future<bool> setEnabled(bool value) async {
    await ready;
    if (_disposed) return false;
    if (value && !await hasPermission()) return false;
    if (_disposed) return false;
    enabled = value;
    error = null;
    _lastPayload = null;
    _generation++;
    _songKey = null;
    await _save();
    if (_disposed) return false;
    _startTimer();
    if (!value) await _hide();
    notifyListeners();
    return true;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = enabled && supported
        ? Timer.periodic(const Duration(milliseconds: 150), (_) => _tick())
        : null;
    if (enabled) unawaited(_tick());
  }

  Future<void> updateStyle({
    double? textOpacity,
    double? backgroundOpacity,
    double? fontSize,
    int? textColor,
    bool? locked,
    bool? twoLines,
  }) async {
    await ready;
    if (_disposed) return;
    this.textOpacity = (textOpacity ?? this.textOpacity).clamp(0, 1).toDouble();
    this.backgroundOpacity = (backgroundOpacity ?? this.backgroundOpacity)
        .clamp(0, 1)
        .toDouble();
    this.fontSize = (fontSize ?? this.fontSize).clamp(12, 36).toDouble();
    this.textColor = textColor ?? this.textColor;
    this.locked = locked ?? this.locked;
    this.twoLines = twoLines ?? this.twoLines;
    _lastPayload = null;
    notifyListeners();
    await _save();
    if (enabled) await _tick();
  }

  Future<void> _save() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await Future.wait([
      prefs.setBool('floatingLyrics.enabled', enabled),
      prefs.setBool('floatingLyrics.locked', locked),
      prefs.setBool('floatingLyrics.twoLines', twoLines),
      prefs.setDouble('floatingLyrics.textOpacity', textOpacity),
      prefs.setDouble('floatingLyrics.backgroundOpacity', backgroundOpacity),
      prefs.setDouble('floatingLyrics.fontSize', fontSize),
      prefs.setInt('floatingLyrics.textColor', textColor),
    ]);
  }

  void _invalidateLyrics() {
    _generation++;
    _songKey = null;
    _lastPayload = null;
  }

  Future<void> _loadLyrics(String key) async {
    final song = _audio.currentSong;
    if (song == null) return;
    final generation = ++_generation;
    _loading = true;
    _lyrics = [];
    try {
      final artist = (song.artist ?? '').trim();
      final title = song.title.trim();
      final result = await _lyricsService.fetchTimedLyrics(
        artist.isEmpty ? 'Unknown' : artist,
        title.isEmpty ? 'Unknown' : title,
        songDuration: _audio.audioPlayer.duration,
      );
      if (_disposed || generation != _generation || key != _songKey) return;
      _lyrics = List.of(result ?? [])..sort((a, b) => a.time.compareTo(b.time));
      _loading = false;
      _lastPayload = null;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _loading = false;
      debugPrint('Floating lyrics load failed: $e');
    }
  }

  Future<void> _tick() async {
    if (!enabled || _disposed || _sending) return;
    final song = _audio.currentSong;
    final player = _audio.audioPlayer;
    if (song == null ||
        player.processingState == ProcessingState.idle ||
        player.processingState == ProcessingState.completed) {
      if (_visible) {
        _lastPayload = null;
        await _hide();
      }
      return;
    }
    final key = '${song.id}|${song.artist}|${song.title}';
    if (key != _songKey) {
      _songKey = key;
      _lastPayload = null;
      unawaited(_loadLyrics(key));
    }
    final index = lyricIndexAt(_lyrics, player.position);
    final line = index >= 0
        ? _lyrics[index].text
        : (_loading
              ? 'Loading lyrics…'
              : (_lyrics.isEmpty ? 'No timed lyrics' : ''));
    final next = twoLines && index + 1 < _lyrics.length
        ? _lyrics[index + 1].text
        : '';
    final payload =
        '$key|$line|$next|$textOpacity|$backgroundOpacity|$fontSize|$textColor|$locked';
    if (payload == _lastPayload) return;
    _sending = true;
    try {
      await _channel.invokeMethod<void>('update', {
        'line': line,
        'next': next,
        'textOpacity': textOpacity,
        'backgroundOpacity': backgroundOpacity,
        'fontSize': fontSize,
        'textColor': textColor,
        'locked': locked,
      });
      _visible = true;
      if (_disposed || !enabled) {
        await _hide();
      } else if (key == _songKey) {
        _lastPayload = payload;
      }
    } on PlatformException catch (e) {
      await _disableOnError(e.message ?? 'Unable to show floating lyrics.');
    } on MissingPluginException {
      await _disableOnError('Floating lyrics are unavailable in this build.');
    } finally {
      _sending = false;
    }
  }

  Future<void> _disableOnError(String message) async {
    if (_disposed) return;
    enabled = false;
    error = message;
    _timer?.cancel();
    await _save();
    await _hide();
    if (!_disposed) notifyListeners();
  }

  Future<void> _hide() async {
    _visible = false;
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException catch (_) {
      // Permission may have been revoked while the overlay was visible.
    } on MissingPluginException catch (_) {
      // Non-Android tests and builds have no native overlay.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _lyricsService.lyricsRevisionNotifier.removeListener(_invalidateLyrics);
    _channel.setMethodCallHandler(null);
    unawaited(_hide());
    super.dispose();
  }
}
