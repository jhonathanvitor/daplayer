import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'postgres_service.dart';

class PlaylistService extends ChangeNotifier {
  static const _storageKey = 'daplayer_user_playlists';
  List<Playlist> _playlists = [];
  String? _activeUserId;

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  PlaylistService() {
    loadPlaylists();
  }

  /// Vincula o usuário logado e sincroniza as coletâneas diretamente com o PostgreSQL (Neon)
  Future<void> setActiveUser(String? userId) async {
    if (_activeUserId == userId) return;
    _activeUserId = userId;
    if (userId != null && PostgresService.instance.isConfigured) {
      final remotePlaylists = await PostgresService.instance.fetchUserPlaylists(userId);
      if (remotePlaylists != null) {
        if (remotePlaylists.isNotEmpty) {
          _playlists = remotePlaylists;
          await _saveToStorage(syncRemote: false);
          notifyListeners();
        } else if (_playlists.isNotEmpty) {
          // Se o banco PostgreSQL do usuário ainda está vazio, envia as coletâneas locais
          unawaited(PostgresService.instance.syncUserPlaylists(userId, _playlists));
        }
      }
    }
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
    if (_activeUserId != null && PostgresService.instance.isConfigured) {
      unawaited(PostgresService.instance.deleteUserPlaylist(_activeUserId!, playlistId));
    }
    notifyListeners();
  }

  Future<void> renamePlaylist(String playlistId, String newName, {String? description}) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final current = _playlists[index];
      _playlists[index] = current.copyWith(
        name: trimmed,
        description: description?.trim() ?? current.description,
      );
      await _saveToStorage();
      notifyListeners();
    }
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

  Future<void> _saveToStorage({bool syncRemote = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(_playlists.map((p) => p.toMap()).toList());
      await prefs.setString(_storageKey, encoded);

      if (syncRemote && _activeUserId != null && PostgresService.instance.isConfigured) {
        unawaited(
          PostgresService.instance.syncUserPlaylists(
            _activeUserId!,
            List<Playlist>.from(_playlists),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao salvar playlists no storage: $e');
    }
  }

  /// Gera um link clicável universal (funciona no WhatsApp, navegador e importa tudo no DaPlayer)
  static String generateShareCode(Playlist playlist) {
    final compact = {
      'n': playlist.name,
      'd': playlist.description,
      't': playlist.tracks
          .map((t) => [t.id, t.title, t.artist, t.duration.inSeconds])
          .toList(),
    };
    final jsonBytes = utf8.encode(json.encode(compact));
    final compressed = zlib.encode(jsonBytes);
    final b64 = base64Url.encode(compressed);
    final videoIds = playlist.tracks.take(50).map((t) => t.id).join(',');
    if (videoIds.isNotEmpty) {
      return 'https://www.youtube.com/watch_videos?video_ids=$videoIds&daplayer=$b64';
    }
    return 'https://www.youtube.com/watch_videos?daplayer=$b64';
  }

  /// Gera uma mensagem formatada com link clicável para enviar no WhatsApp / Redes Sociais
  static String generateShareMessage(Playlist playlist) {
    final shareLink = generateShareCode(playlist);
    final buffer = StringBuffer();
    buffer.writeln('🎵 Coletânea DaPlayer: *${playlist.name}* (${playlist.tracks.length} músicas)');
    if (playlist.description.trim().isNotEmpty) {
      buffer.writeln(playlist.description.trim());
    }
    buffer.writeln('');
    buffer.writeln('▶️ *Clique no link abaixo para ouvir ou importar a coletânea completa:*');
    buffer.writeln(shareLink);
    buffer.writeln('');
    for (int i = 0; i < playlist.tracks.length; i++) {
      final t = playlist.tracks[i];
      buffer.writeln('${i + 1}. ${t.title} - ${t.artist}');
      buffer.writeln('   https://youtu.be/${t.id}');
    }
    return buffer.toString();
  }

  /// Verifica se o texto contém um link/código de coletânea compartilhada do DaPlayer
  static bool isShareCode(String input) {
    return input.contains('daplayer://playlist/') ||
        input.contains('daplayer=') ||
        input.contains('watch_videos?video_ids=');
  }

  /// Decodifica um link/código compartilhado (ou mensagem do WhatsApp contendo o link) em uma Playlist completa
  static Playlist? decodeShareCode(String input) {
    try {
      final match = RegExp(r'(?:daplayer://playlist/|[?&]daplayer=)([A-Za-z0-9_\-=]+)')
          .firstMatch(input);
      if (match == null) return null;
      final token = match.group(1)!;
      final compressed = base64Url.decode(base64Url.normalize(token));
      final jsonStr = utf8.decode(zlib.decode(compressed));
      final map = json.decode(jsonStr) as Map<String, dynamic>;

      final name = (map['n'] as String?) ?? 'Coletânea Compartilhada';
      final desc = (map['d'] as String?) ?? '';
      final rawTracks = (map['t'] as List<dynamic>?) ?? [];

      final tracks = <Track>[];
      for (final item in rawTracks) {
        if (item is List && item.length >= 3) {
          final videoId = item[0].toString();
          final title = item[1].toString();
          final artist = item[2].toString();
          final durSec = item.length >= 4 ? (int.tryParse(item[3].toString()) ?? 0) : 0;
          tracks.add(
            Track(
              id: videoId,
              title: title,
              artist: artist,
              thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
              duration: Duration(seconds: durSec),
            ),
          );
        }
      }

      return Playlist(
        id: 'pl_shared_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: desc,
        tracks: tracks,
      );
    } catch (e) {
      debugPrint('Erro ao decodificar coletânea compartilhada: $e');
      return null;
    }
  }
}
