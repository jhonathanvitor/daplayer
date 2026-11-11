import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;
import '../models/track.dart';
import '../models/playlist.dart';

class _StreamCacheEntry {
  final Uri url;
  final int totalBytes;
  final String mimeType;
  final DateTime createdAt;

  _StreamCacheEntry({
    required this.url,
    required this.totalBytes,
    required this.mimeType,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().difference(createdAt).inMinutes >= 20;
}

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();
  static final Map<String, _StreamCacheEntry> _streamCache = {};
  static HttpServer? _proxyServer;
  static final HttpClient _upstreamHttpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30);

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

  static const String _visionUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  static final _visionClient = YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent': _visionUserAgent,
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'hl': 'en',
        'gl': 'US',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      }
    }
  }, 'https://www.youtube.com/youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc&prettyPrint=false');

  /// Seleciona o melhor stream de áudio, priorizando M4A (audio/mp4, itag 140)
  /// por possuir decodificação de hardware nativa e indexação rápida no Android
  AudioOnlyStreamInfo _selectBestAudioStream(Iterable<AudioOnlyStreamInfo> audioList) {
    final mp4Streams = audioList
        .where((s) => s.codec.mimeType.toLowerCase().contains('mp4'))
        .toList();
    if (mp4Streams.isNotEmpty) {
      final itag140 = mp4Streams.where((s) => s.tag == 140).toList();
      if (itag140.isNotEmpty) {
        return itag140.first;
      }
      mp4Streams.sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      return mp4Streams.first;
    }
    return audioList.withHighestBitrate();
  }

  Future<_StreamCacheEntry?> _resolveStreamEntry(String videoId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _streamCache[videoId];
      if (cached != null && !cached.isExpired) {
        return cached;
      }
    }

    // 1. Tenta via cliente VISIONOS (sem bloqueio 403 / PoToken)
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [_visionClient],
      );
      final audioList = manifest.audioOnly;
      if (audioList.isNotEmpty) {
        final chosen = _selectBestAudioStream(audioList);
        final entry = _StreamCacheEntry(
          url: chosen.url,
          totalBytes: chosen.size.totalBytes,
          mimeType: chosen.codec.mimeType,
          createdAt: DateTime.now(),
        );
        _streamCache[videoId] = entry;
        return entry;
      }
    } catch (e) {
      debugPrint('Aviso: falha com cliente VISIONOS para $videoId: $e. Tentando padrão...');
    }

    // 2. Fallback para cliente padrão
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioList = manifest.audioOnly;
      if (audioList.isNotEmpty) {
        final chosen = _selectBestAudioStream(audioList);
        final entry = _StreamCacheEntry(
          url: chosen.url,
          totalBytes: chosen.size.totalBytes,
          mimeType: chosen.codec.mimeType,
          createdAt: DateTime.now(),
        );
        _streamCache[videoId] = entry;
        return entry;
      }
    } catch (e) {
      debugPrint('Erro ao extrair áudio de $videoId: $e');
    }
    return null;
  }

  /// Inicia um proxy HTTP local em loopback que força requisições Range em blocos,
  /// eliminando o throttling de ~30 KB/s do YouTube quando o ExoPlayer omite o header Range.
  Future<HttpServer?> _ensureProxyServer() async {
    if (_proxyServer != null) return _proxyServer;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: true,
      );
      _proxyServer = server;
      server.listen(
        _handleProxyRequest,
        onError: (e) => debugPrint('Erro no proxy de áudio: $e'),
      );
      return server;
    } catch (e) {
      debugPrint('Não foi possível iniciar proxy local: $e');
      return null;
    }
  }

  Future<void> _handleProxyRequest(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments[0] != 'stream') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final videoId = segments[1];
      var entry = await _resolveStreamEntry(videoId);
      if (entry == null || entry.totalBytes <= 0) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }

      final totalBytes = entry.totalBytes;
      int start = 0;
      int end = totalBytes - 1;
      bool hasRange = false;

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        hasRange = true;
        final parts = rangeHeader.substring(6).split('-');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          start = int.tryParse(parts[0]) ?? 0;
        }
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? (totalBytes - 1);
        }
      }

      start = start.clamp(0, totalBytes - 1);
      end = end.clamp(start, totalBytes - 1);
      final contentLength = end - start + 1;

      request.response.statusCode =
          hasRange ? HttpStatus.partialContent : HttpStatus.ok;
      request.response.headers.set(HttpHeaders.contentTypeHeader, entry.mimeType);
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentLengthHeader, contentLength);
      if (hasRange) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$totalBytes',
        );
      }

      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }

      // Baixa em blocos de 512 KB com header Range explícito para velocidade máxima sem throttling
      const int chunkSize = 512 * 1024;
      int current = start;
      bool refreshedOnce = false;

      while (current <= end) {
        final chunkEnd = (current + chunkSize - 1).clamp(current, end);
        final upstreamReq = await _upstreamHttpClient.getUrl(entry!.url);
        upstreamReq.headers.set(HttpHeaders.userAgentHeader, _visionUserAgent);
        upstreamReq.headers.set(HttpHeaders.rangeHeader, 'bytes=$current-$chunkEnd');
        final upstreamResp = await upstreamReq.close();

        if (upstreamResp.statusCode == HttpStatus.forbidden && !refreshedOnce) {
          refreshedOnce = true;
          await upstreamResp.drain<void>();
          entry = await _resolveStreamEntry(videoId, forceRefresh: true);
          if (entry == null) break;
          continue;
        }

        if (upstreamResp.statusCode != HttpStatus.partialContent &&
            upstreamResp.statusCode != HttpStatus.ok) {
          await upstreamResp.drain<void>();
          break;
        }

        int receivedInChunk = 0;
        await for (final data in upstreamResp) {
          request.response.add(data);
          receivedInChunk += data.length;
        }
        await request.response.flush();

        if (receivedInChunk <= 0) break;
        current += receivedInChunk;
      }
    } catch (_) {
      // Cliente (ExoPlayer) fechou a conexão ao buscar/trocar de faixa
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Obtém a URL de stream de áudio otimizada (via proxy local anti-throttling)
  Future<String?> getAudioOnlyStreamUrl(String videoId) async {
    final entry = await _resolveStreamEntry(videoId);
    if (entry == null) return null;

    final server = await _ensureProxyServer();
    if (server != null) {
      return 'http://127.0.0.1:${server.port}/stream/$videoId';
    }
    return entry.url.toString();
  }

  /// Baixa o áudio completo da música para um arquivo local em blocos de 512 KB (sem throttling)
  Future<bool> downloadAudioToFile(
    String videoId,
    File destinationFile, {
    void Function(double progress)? onProgress,
  }) async {
    var entry = await _resolveStreamEntry(videoId);
    if (entry == null || entry.totalBytes <= 0) return false;

    final tempFile = File('${destinationFile.path}.part');
    IOSink? sink;
    try {
      await destinationFile.parent.create(recursive: true);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      sink = tempFile.openWrite();

      final totalBytes = entry.totalBytes;
      const int chunkSize = 512 * 1024;
      int current = 0;
      bool refreshedOnce = false;

      while (current < totalBytes) {
        final chunkEnd = (current + chunkSize - 1).clamp(current, totalBytes - 1);
        final upstreamReq = await _upstreamHttpClient.getUrl(entry!.url);
        upstreamReq.headers.set(HttpHeaders.userAgentHeader, _visionUserAgent);
        upstreamReq.headers.set(HttpHeaders.rangeHeader, 'bytes=$current-$chunkEnd');
        final upstreamResp = await upstreamReq.close();

        if (upstreamResp.statusCode == HttpStatus.forbidden && !refreshedOnce) {
          refreshedOnce = true;
          await upstreamResp.drain<void>();
          entry = await _resolveStreamEntry(videoId, forceRefresh: true);
          if (entry == null) {
            await sink.close();
            return false;
          }
          continue;
        }

        if (upstreamResp.statusCode != HttpStatus.partialContent &&
            upstreamResp.statusCode != HttpStatus.ok) {
          await upstreamResp.drain<void>();
          await sink.close();
          return false;
        }

        int receivedInChunk = 0;
        await for (final data in upstreamResp) {
          sink.add(data);
          receivedInChunk += data.length;
          final totalReceived = current + receivedInChunk;
          onProgress?.call((totalReceived / totalBytes).clamp(0.0, 1.0));
        }

        if (receivedInChunk <= 0) break;
        current += receivedInChunk;
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (current >= totalBytes) {
        if (await destinationFile.exists()) {
          await destinationFile.delete();
        }
        await tempFile.rename(destinationFile.path);
        onProgress?.call(1.0);
        return true;
      } else {
        if (await tempFile.exists()) await tempFile.delete();
        return false;
      }
    } catch (e) {
      debugPrint('Erro ao baixar áudio local para $videoId: $e');
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      return false;
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
