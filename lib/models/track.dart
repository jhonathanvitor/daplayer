import 'dart:convert';

class Track {
  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final Duration duration;
  final String? album;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.duration,
    this.album,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'thumbnailUrl': thumbnailUrl,
      'durationMs': duration.inMilliseconds,
      'album': album,
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Sem título',
      artist: map['artist'] as String? ?? 'Artista desconhecido',
      thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
      duration: Duration(milliseconds: map['durationMs'] as int? ?? 0),
      album: map['album'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory Track.fromJson(String source) =>
      Track.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Track && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
