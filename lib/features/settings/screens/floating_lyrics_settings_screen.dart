import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/floating_lyrics_service.dart';

class FloatingLyricsSettingsScreen extends StatefulWidget {
  const FloatingLyricsSettingsScreen({super.key});

  @override
  State<FloatingLyricsSettingsScreen> createState() =>
      _FloatingLyricsSettingsScreenState();
}

class _FloatingLyricsSettingsScreenState
    extends State<FloatingLyricsSettingsScreen>
    with WidgetsBindingObserver {
  bool _awaitingPermission = false;
  bool _busy = false;
  String _label(String en, String zh) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPermission) {
      _awaitingPermission = false;
      unawaited(_enableAfterPermission());
    }
  }

  Future<void> _enableAfterPermission() async {
    final service = context.read<FloatingLyricsService>();
    final allowed = await service.setEnabled(true);
    if (!mounted || allowed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _label(
            'Allow display over other apps, then enable floating lyrics.',
            '请允许显示在其他应用上层，然后开启悬浮歌词。',
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final service = context.read<FloatingLyricsService>();
    try {
      await service.ready;
      if (!value) {
        await service.setEnabled(false);
      } else if (await service.hasPermission()) {
        await service.setEnabled(true);
      } else {
        _awaitingPermission = true;
        await service.requestPermission();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    String display,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title: $display'),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min == 1) ? 100 : (max - min).round(),
            label: display,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<FloatingLyricsService>();
    return Scaffold(
      appBar: AppBar(title: Text(_label('Floating lyrics', '悬浮歌词'))),
      body: !service.supported
          ? Center(child: Text(_label('Available on Android.', '仅支持 Android。')))
          : ListView(
              children: [
                SwitchListTile(
                  title: Text(_label('Floating lyrics', '悬浮歌词')),
                  subtitle: Text(
                    _label(
                      'Show timed lyrics over other apps while Aurora plays.',
                      'Aurora 播放时，在其他应用上方显示同步歌词。',
                    ),
                  ),
                  value: service.enabled,
                  onChanged: _busy ? null : _toggle,
                ),
                if (service.error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      service.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: service.backgroundOpacity,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _label('Floating lyrics preview', '悬浮歌词预览'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: service.fontSize,
                        color: Color(service.textColor)
                            .withValues(alpha: service.textOpacity),
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 3),
                        ],
                      ),
                    ),
                  ),
                ),
                _slider(
                  _label('Text opacity', '文字不透明度'),
                  service.textOpacity,
                  0,
                  1,
                  '${(service.textOpacity * 100).round()}%',
                  (v) => unawaited(service.updateStyle(textOpacity: v)),
                ),
                _slider(
                  _label('Background opacity', '背景不透明度'),
                  service.backgroundOpacity,
                  0,
                  1,
                  '${(service.backgroundOpacity * 100).round()}%',
                  (v) => unawaited(service.updateStyle(backgroundOpacity: v)),
                ),
                _slider(
                  _label('Font size', '字号'),
                  service.fontSize,
                  12,
                  36,
                  service.fontSize.round().toString(),
                  (v) => unawaited(service.updateStyle(fontSize: v)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_label('Text colour', '文字颜色')),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final color in [
                      0xFFFFFFFF,
                      0xFFFFEB3B,
                      0xFF80DEEA,
                      0xFFFF80AB,
                      0xFF000000,
                    ])
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Semantics(
                          label: _label('Select colour', '选择颜色'),
                          selected: service.textColor == color,
                          child: InkWell(
                            onTap: () => unawaited(
                              service.updateStyle(textColor: color),
                            ),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Color(color),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: service.textColor == color
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey,
                                  width: service.textColor == color ? 4 : 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SwitchListTile(
                  title: Text(_label('Show next line', '显示下一行')),
                  value: service.twoLines,
                  onChanged: (v) => unawaited(service.updateStyle(twoLines: v)),
                ),
                SwitchListTile(
                  title: Text(_label('Lock position', '锁定位置')),
                  subtitle: Text(
                    _label(
                      'The Unlock and Close buttons remain available.',
                      '仍可使用解锁和关闭按钮。',
                    ),
                  ),
                  value: service.locked,
                  onChanged: (v) => unawaited(service.updateStyle(locked: v)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _label(
                      'Drag the handle or lyric text to move the window. Settings are saved automatically. '
                          'Cached lyrics work offline. Some apps may hide overlays.',
                      '拖动手柄或歌词可移动窗口。设置自动保存，缓存歌词可离线使用。部分应用可能隐藏悬浮窗。',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
