import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;
import '../models/track.dart';
import '../models/playlist.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Extrai o ID do vídeo de uma URL ou ID solto
  static String? extractVideoId(String input) {
    try {
      return VideoId(input.trim()).value;
    } catch (_) {
      final regExp = RegExp(r'(?:v=|\/)([0-9A-Za-z_-]{11})(?:\?|&|/|$)');
      final match = regExp.firstMatch(input.trim());
      return match?.group(1);
    }
  }

  /// Extrai o ID da playlist de uma URL ou ID solto
  static String? extractPlaylistId(String input) {
    try {
      return PlaylistId(input.trim()).value;
    } catch (_) {
      final regExp = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)');
      final match = regExp.firstMatch(input.trim());
      return match?.group(1);
    }
  }

  /// Verifica se uma string é um link do YouTube
  static bool isYouTubeUrl(String input) {
    final text = input.trim().toLowerCase();
    return text.contains('youtube.com') || text.contains('youtu.be');
  }

  /// Busca músicas ou coletâneas no YouTube
  Future<List<Track>> search(String query) async {
    try {
      final searchList = await _yt.search.search(query);
      final tracks = <Track>[];

      for (final video in searchList) {
        if (video.duration == null) continue;

        tracks.add(
          Track(
            id: video.id.value,
            title: video.title,
            artist: video.author,
            thumbnailUrl: video.thumbnails.highResUrl,
            duration: video.duration ?? Duration.zero,
          ),
        );
      }
      return tracks;
    } catch (e) {
      debugPrint('Erro na busca do YouTube: $e');
      return [];
    }
  }

  /// Obtém os dados de uma música pelo link direto ou ID (Sem necessidade de login)
  Future<Track?> getTrackFromUrl(String urlOrId) async {
    final videoId = extractVideoId(urlOrId);
    if (videoId == null) return null;

    try {
      final video = await _yt.videos.get(videoId);
      return Track(
        id: video.id.value,
        title: video.title,
        artist: video.author,
        thumbnailUrl: video.thumbnails.highResUrl,
        duration: video.duration ?? Duration.zero,
      );
    } catch (e) {
      debugPrint('Erro ao obter música do link $urlOrId: $e');
      return null;
    }
  }

  /// Importa uma playlist pública/não-listada do YouTube pelo link sem precisar de login
  Future<Playlist?> importPlaylistFromUrl(String playlistUrl) async {
    final playlistId = extractPlaylistId(playlistUrl);
    if (playlistId == null) return null;

    try {
      final ytPlaylist = await _yt.playlists.get(playlistId);
      final tracks = <Track>[];

      await for (final video in _yt.playlists.getVideos(playlistId)) {
        if (video.duration == null) continue;
        tracks.add(
          Track(
            id: video.id.value,
            title: video.title,
            artist: video.author,
            thumbnailUrl: video.thumbnails.highResUrl,
            duration: video.duration ?? Duration.zero,
          ),
        );
      }

      return Playlist(
        id: 'pl_imported_${DateTime.now().millisecondsSinceEpoch}',
        name: ytPlaylist.title.trim().isNotEmpty ? ytPlaylist.title : 'Coletânea Importada',
        description: ytPlaylist.description,
        tracks: tracks,
      );
    } catch (e) {
      debugPrint('Erro ao importar playlist do link $playlistUrl: $e');
      return null;
    }
  }

  /// Obtém a URL direta do stream de áudio apenas (M4A / Opus) com maior bitrate
  Future<String?> getAudioOnlyStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      return audioStreamInfo.url.toString();
    } catch (e) {
      debugPrint('Erro ao extrair áudio de $videoId: $e');
      return null;
    }
  }

  /// Obtém coletâneas populares / sugestões iniciais
  Future<List<Track>> getTrendingMusic() async {
    return search('melhores musicas coletanea 2026');
  }

  void dispose() {
    _yt.close();
  }
}
