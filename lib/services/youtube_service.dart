import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  /// Converte string de duração (ex: '3:45' ou '1:02:30') em Duration com segurança
  static Duration _parseDurationString(String text) {
    try {
      final parts = text.trim().split(':');
      if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final s = int.parse(parts[1]);
        return Duration(minutes: m, seconds: s);
      } else if (parts.length == 3) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final s = int.parse(parts[2]);
        return Duration(hours: h, minutes: m, seconds: s);
      }
    } catch (_) {}
    return Duration.zero;
  }

  /// Busca músicas ou coletâneas no YouTube usando Innertube API com fallback
  Future<List<Track>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // 1. Busca nativa via Innertube API (rápida, sem problemas de parsing ou locale)
    try {
      final url = Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false');
      final body = json.encode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20240101.00.00',
            'hl': 'pt',
            'gl': 'BR',
          }
        },
        'query': cleanQuery,
        'params': 'EgIQAQ%3D%3D', // Filtro: Vídeos
      });

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final contents = data['contents']?['twoColumnSearchResultsRenderer']?['primaryContents']?['sectionListRenderer']?['contents'];
        if (contents is List) {
          final tracks = <Track>[];
          for (final section in contents) {
            final itemSection = section['itemSectionRenderer']?['contents'];
            if (itemSection is List) {
              for (final item in itemSection) {
                final vr = item['videoRenderer'];
                if (vr != null) {
                  final videoId = vr['videoId'] as String?;
                  if (videoId == null || videoId.isEmpty) continue;

                  final title = (vr['title']?['runs']?[0]?['text'] ?? vr['title']?['simpleText'] ?? '') as String;
                  final author = (vr['ownerText']?['runs']?[0]?['text'] ?? vr['longBylineText']?['runs']?[0]?['text'] ?? '') as String;
                  final durationStr = (vr['lengthText']?['simpleText'] ?? vr['lengthText']?['runs']?[0]?['text'] ?? '') as String;

                  // Se for transmissão ao vivo ativa (sem duração definida), ignora
                  final isLive = vr['badges']?.toString().contains('LIVE') == true || durationStr.isEmpty;
                  if (isLive) continue;

                  final duration = _parseDurationString(durationStr);

                  tracks.add(
                    Track(
                      id: videoId,
                      title: title,
                      artist: author,
                      thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                      duration: duration,
                    ),
                  );
                }
              }
            }
          }
          if (tracks.isNotEmpty) {
            return tracks;
          }
        }
      }
    } catch (e) {
      debugPrint('Aviso: busca via Innertube falhou ($e), tentando fallback...');
    }

    // 2. Fallback via YoutubeExplode
    try {
      final searchList = await _yt.search.search(cleanQuery);
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

  static final _visionClient = YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'hl': 'en',
        'gl': 'US',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      }
    }
  }, 'https://www.youtube.com/youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc&prettyPrint=false');

  /// Obtém a URL direta do stream de áudio apenas (M4A / Opus) com maior bitrate
  Future<String?> getAudioOnlyStreamUrl(String videoId) async {
    try {
      // 1. Tenta via cliente VISIONOS (sem bloqueio 403 / PoToken)
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [_visionClient],
      );
      final audioList = manifest.audioOnly;
      if (audioList.isNotEmpty) {
        return audioList.withHighestBitrate().url.toString();
      }
    } catch (e) {
      debugPrint('Aviso: falha com cliente VISIONOS para $videoId: $e. Tentando padrão...');
    }

    // 2. Fallback para cliente padrão
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioList = manifest.audioOnly;
      if (audioList.isNotEmpty) {
        return audioList.withHighestBitrate().url.toString();
      }
    } catch (e) {
      debugPrint('Erro ao extrair áudio de $videoId: $e');
    }
    return null;
  }

  /// Obtém coletâneas populares / sugestões iniciais
  Future<List<Track>> getTrendingMusic() async {
    return search('melhores musicas coletanea 2026');
  }

  void dispose() {
    _yt.close();
  }
}
