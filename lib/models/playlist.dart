import 'dart:convert';
import 'track.dart';

class Playlist {
  final String id;
  final String name;
  final String description;
  final List<Track> tracks;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    this.description = '',
    List<Track>? tracks,
    DateTime? createdAt,
  })  : tracks = tracks ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'tracks': tracks.map((t) => t.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Minha Coletânea',
      description: map['description'] as String? ?? '',
      tracks: (map['tracks'] as List<dynamic>?)
              ?.map((t) => Track.fromMap(t as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory Playlist.fromJson(String source) =>
      Playlist.fromMap(json.decode(source) as Map<String, dynamic>);

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    List<Track>? tracks,
    DateTime? createdAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      tracks: tracks ?? List.from(this.tracks),
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
