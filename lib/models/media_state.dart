import 'dart:convert';

class MediaState {
  const MediaState({
    this.playing = false,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.source = '',
    this.artworkUrl = '',
    this.artworkDataUrl = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.volume = 0.5,
    this.updatedAtMs = 0,
  });

  final bool playing;
  final String title;
  final String artist;
  final String album;
  final String source;
  final String artworkUrl;
  final String artworkDataUrl;
  final int positionMs;
  final int durationMs;
  final double volume;
  final int updatedAtMs;

  bool get hasTrack => title.isNotEmpty;
  bool get hasDuration => durationMs > 0;

  double get progress {
    if (!hasDuration) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  int get remainingMs => (durationMs - positionMs).clamp(0, durationMs);

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);
  Duration get remaining => Duration(milliseconds: remainingMs);

  MediaState copyWith({
    bool? playing,
    String? title,
    String? artist,
    String? album,
    String? source,
    String? artworkUrl,
    String? artworkDataUrl,
    int? positionMs,
    int? durationMs,
    double? volume,
    int? updatedAtMs,
  }) {
    return MediaState(
      playing: playing ?? this.playing,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      source: source ?? this.source,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      artworkDataUrl: artworkDataUrl ?? this.artworkDataUrl,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      volume: volume ?? this.volume,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  factory MediaState.fromJson(
    Map<String, dynamic> json, {
    MediaState? previous,
  }) {
    final hasArt = json.containsKey('artwork');
    final hasArtUrl = json.containsKey('artworkUrl');
    return MediaState(
      playing: json['playing'] == true,
      title: (json['title'] as String?) ?? '',
      artist: (json['artist'] as String?) ?? '',
      album: (json['album'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
      artworkUrl: hasArtUrl
          ? ((json['artworkUrl'] as String?) ?? '')
          : (previous?.artworkUrl ?? ''),
      artworkDataUrl: hasArt
          ? ((json['artwork'] as String?) ?? '')
          : (previous?.artworkDataUrl ?? ''),
      positionMs: _asInt(json['positionMs']),
      durationMs: _asInt(json['durationMs']),
      volume: _asDouble(json['volume'], 0.5),
      updatedAtMs: _asInt(json['updatedAtMs']),
    );
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _asDouble(Object? v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  String encode() => jsonEncode({
    'playing': playing,
    'title': title,
    'artist': artist,
    'album': album,
    'source': source,
    'artworkUrl': artworkUrl,
    'artwork': artworkDataUrl,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'volume': volume,
    'updatedAtMs': updatedAtMs,
  });
}

const emptyMediaState = MediaState();
