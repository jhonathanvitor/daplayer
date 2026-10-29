import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/track.dart';

class PlaylistService extends ChangeNotifier {
  static const _storageKey = 'daplayer_user_playlists';
  List<Playlist> _playlists = [];

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  PlaylistService() {
    loadPlaylists();
  }

  Future<void> loadPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawData = prefs.getString(_storageKey);
      if (rawData != null && rawData.isNotEmpty) {
        final List<dynamic> decoded = json.decode(rawData);
        _playlists = decoded
            .map((item) => Playlist.fromMap(item as Map<String, dynamic>))
            .toList();
      } else {
        // Inicializa com uma coletânea de boas-vindas
        _playlists = [
          Playlist(
            id: 'default_collection',
            name: 'Minha Primeira Coletânea',
            description: 'Coletânea inicial para suas músicas favoritas',
            tracks: [],
          ),
        ];
        await _saveToStorage();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao carregar playlists: $e');
    }
  }

  Future<Playlist> createPlaylist(String name, {String description = ''}) async {
    final newPlaylist = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Nova Coletânea' : name.trim(),
      description: description.trim(),
      tracks: [],
    );

    _playlists.add(newPlaylist);
    await _saveToStorage();
    notifyListeners();
    return newPlaylist;
  }

  Future<void> addPlaylist(Playlist playlist) async {
    _playlists.add(playlist);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    _playlists.removeWhere((p) => p.id == playlistId);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      if (!playlist.tracks.any((t) => t.id == track.id)) {
        final updatedTracks = List<Track>.from(playlist.tracks)..add(track);
        _playlists[index] = playlist.copyWith(tracks: updatedTracks);
        await _saveToStorage();
        notifyListeners();
      }
    }
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      final updatedTracks = List<Track>.from(playlist.tracks)
        ..removeWhere((t) => t.id == trackId);
      _playlists[index] = playlist.copyWith(tracks: updatedTracks);
      await _saveToStorage();
      notifyListeners();
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(_playlists.map((p) => p.toMap()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('Erro ao salvar playlists no storage: $e');
    }
  }
}
