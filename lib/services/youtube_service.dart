import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Busca músicas ou coletâneas no YouTube
  Future<List<Track>> search(String query) async {
    try {
      final searchList = await _yt.search.search(query);
      final tracks = <Track>[];

      for (final video in searchList) {
        // Ignora transmissões ao vivo sem duração finita
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

  /// Obtém a URL direta do stream de áudio apenas (M4A / Opus) com maior bitrate
  Future<String?> getAudioOnlyStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      
      // Filtra apenas faixas de áudio e pega o bitrate mais alto
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
