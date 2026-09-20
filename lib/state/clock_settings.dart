import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Which colour the clock digits use.
enum ClockInk {
  ink('月白'),
  amber('琥珀'),
  ice('冰蓝'),
  mint('薄荷'),
  rose('绯粉'),
  cover('封面取色');

  const ClockInk(this.label);

  final String label;

  /// Resolves to a concrete colour. [cover] follows the album palette.
  Color resolve(List<Color> cover) {
    switch (this) {
      case ClockInk.ink:
        return AppColors.ink;
      case ClockInk.amber:
        return AppColors.accent;
      case ClockInk.ice:
        return const Color(0xFF9CC7E8);
      case ClockInk.mint:
        return const Color(0xFF9AD9BD);
      case ClockInk.rose:
        return const Color(0xFFE8A8B8);
      case ClockInk.cover:
        return cover.isEmpty ? AppColors.ink : cover.first;
    }
  }
}

/// How the digits are filled.
enum ClockFace {
  solid('实心'),
  translucent('半透明'),
  frosted('毛玻璃');

  const ClockFace(this.label);

  final String label;
}

/// What sits behind the clock.
enum ClockBackdrop {
  night('夜色'),
  cover('封面取色');

  const ClockBackdrop(this.label);

  final String label;
}

/// User-tunable clock appearance, persisted across launches.
class ClockSettings extends ChangeNotifier {
  static const _key = 'clock.settings.v1';

  /// Null means the platform default sans.
  static const fonts = <String, String?>{
    'system': null,
    'mono': 'monospace',
    'serif': 'serif',
    'condensed': 'sans-serif-condensed',
  };

  static const weights = <FontWeight>[
    FontWeight.w200,
    FontWeight.w300,
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
  ];

  String _font = 'system';
  int _weight = 0;
  ClockInk _ink = ClockInk.ink;
  ClockFace _face = ClockFace.solid;
  ClockBackdrop _backdrop = ClockBackdrop.night;
  double _scale = 1.0;

  String get font => _font;
  String? get fontFamily => fonts[_font];
  FontWeight get weight => weights[_weight.clamp(0, weights.length - 1)];
  int get weightIndex => _weight;
  ClockInk get ink => _ink;
  ClockFace get face => _face;
  ClockBackdrop get backdrop => _backdrop;
  double get scale => _scale;

  set font(String value) {
    if (!fonts.containsKey(value) || value == _font) return;
    _font = value;
    _commit();
  }

  set weightIndex(int value) {
    final next = value.clamp(0, weights.length - 1);
    if (next == _weight) return;
    _weight = next;
    _commit();
  }

  set ink(ClockInk value) {
    if (value == _ink) return;
    _ink = value;
    _commit();
  }

  set face(ClockFace value) {
    if (value == _face) return;
    _face = value;
    _commit();
  }

  set backdrop(ClockBackdrop value) {
    if (value == _backdrop) return;
    _backdrop = value;
    _commit();
  }

  set scale(double value) {
    final next = value.clamp(0.8, 1.25);
    if ((next - _scale).abs() < 0.001) return;
    _scale = next;
    _commit();
  }

  void reset() {
    _font = 'system';
    _weight = 0;
    _ink = ClockInk.ink;
    _face = ClockFace.solid;
    _backdrop = ClockBackdrop.night;
    _scale = 1.0;
    _commit();
  }

  void _commit() {
    notifyListeners();
    // Fire and forget: the sheet stays responsive and a failed write is not
    // worth interrupting the user over.
    unawaited(save());
  }

  /// Restores the last used look. Safe to call before the first frame.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _font = fonts.containsKey(map['font']) ? map['font'] as String : _font;
      _weight = (map['weight'] as num?)?.toInt().clamp(0, weights.length - 1) ??
          _weight;
      _ink = _enumByName(ClockInk.values, map['ink'], _ink);
      _face = _enumByName(ClockFace.values, map['face'], _face);
      _backdrop = _enumByName(ClockBackdrop.values, map['backdrop'], _backdrop);
      _scale = ((map['scale'] as num?)?.toDouble() ?? _scale).clamp(0.8, 1.25);
      notifyListeners();
    } catch (_) {
      // A corrupt or unavailable store just means the defaults stand.
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'font': _font,
          'weight': _weight,
          'ink': _ink.name,
          'face': _face.name,
          'backdrop': _backdrop.name,
          'scale': _scale,
        }),
      );
    } catch (_) {
      // Persisting is best-effort.
    }
  }

  static T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
    if (name is! String) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
