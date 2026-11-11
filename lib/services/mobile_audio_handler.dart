import 'package:audio_service/audio_service.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'download_service.dart';
import 'playlist_service.dart';
import 'youtube_service.dart';

class DaPlayerAudioHandler extends BaseAudioHandler with SeekHandler, QueueHandler {
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  Future<void> Function(Duration)? onSeek;
  Future<void> Function(Playlist playlist, {int startIndex})? onPlayPlaylist;
  Future<void> Function(List<Track> tracks, {int startIndex})? onPlayQueue;
  List<Track> Function()? getCurrentQueue;

  final PlaylistService? playlistService;
  final DownloadService? downloadService;
  final YouTubeService? ytService;

  static const String _tabPlaylistsId = 'tab_playlists';
  static const String _tabOfflineId = 'tab_offline';
  static const String _tabQueueId = 'tab_queue';

  DaPlayerAudioHandler({
    this.onPlay,
    this.onPause,
    this.onNext,
    this.onPrevious,
    this.onSeek,
    this.onPlayPlaylist,
    this.onPlayQueue,
    this.getCurrentQueue,
    this.playlistService,
    this.downloadService,
    this.ytService,
  }) {
    // Inicializa estado base para que o Android Auto reconheça os controles imediatamente
    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.playFromMediaId,
          MediaAction.playFromSearch,
          MediaAction.skipToQueueItem,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  MediaItem _trackToMediaItem(Track track, {String? customId, String? albumName}) {
    return MediaItem(
      id: customId ?? track.id,
      album: albumName ?? 'DaPlayer',
      title: track.title,
      artist: track.artist,
      duration: track.duration,
      artUri: Uri.tryParse(track.thumbnailUrl),
      playable: true,
    );
  }

  void updateTrack(Track track, {bool hasNext = false, bool hasPrevious = false}) {
    final currentQueueTracks = getCurrentQueue?.call() ?? [];
    if (currentQueueTracks.isNotEmpty) {
      queue.add(currentQueueTracks.map((t) => _trackToMediaItem(t)).toList());
    }

    mediaItem.add(_trackToMediaItem(track));

    updatePlaybackState(
      isPlaying: true,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
  }

  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration bufferedPosition,
    required bool hasNext,
    required bool hasPrevious,
    bool isLoading = false,
  }) {
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.playFromMediaId,
          MediaAction.playFromSearch,
          MediaAction.skipToQueueItem,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isLoading
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
      ),
    );
  }

  /// Árvore de navegação para a tela multimídia do carro (Android Auto)
  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    // 1. Raiz do Android Auto: exibe as abas principais no painel do carro
    if (parentMediaId == AudioService.browsableRootId || parentMediaId == 'root') {
      final offlineCount = downloadService?.downloadedTracks.length ?? 0;
      final plCount = playlistService?.playlists.length ?? 0;
      return [
        MediaItem(
          id: _tabPlaylistsId,
          title: 'Minhas Coletâneas ($plCount)',
          displaySubtitle: 'Suas playlists salvas',
          playable: false,
        ),
        MediaItem(
          id: _tabOfflineId,
          title: 'Músicas Baixadas ($offlineCount)',
          displaySubtitle: 'Tocar offline sem internet',
          playable: false,
        ),
        const MediaItem(
          id: _tabQueueId,
          title: 'Fila Atual',
          displaySubtitle: 'Músicas em reprodução',
          playable: false,
        ),
      ];
    }

    // 2. Lista de Coletâneas do Usuário
    if (parentMediaId == _tabPlaylistsId) {
      final playlists = playlistService?.playlists ?? [];
      return playlists.map<MediaItem>((pl) {
        final firstThumb = pl.tracks.isNotEmpty ? pl.tracks.first.thumbnailUrl : null;
        return MediaItem(
          id: 'pl:${pl.id}',
          title: pl.name,
          displaySubtitle: '${pl.tracks.length} músicas',
          artUri: firstThumb != null ? Uri.tryParse(firstThumb) : null,
          playable: false,
        );
      }).toList();
    }

    // 3. Músicas dentro de uma Coletânea específica
    if (parentMediaId.startsWith('pl:')) {
      final plId = parentMediaId.substring(3);
      final playlists = playlistService?.playlists ?? [];
      final index = playlists.indexWhere((p) => p.id == plId);
      if (index == -1) return [];
      final pl = playlists[index];

      return List.generate(pl.tracks.length, (i) {
        final t = pl.tracks[i];
        return _trackToMediaItem(
          t,
          customId: 'pl_track:${pl.id}:$i',
          albumName: pl.name,
        );
      });
    }

    // 4. Músicas Baixadas Offline
    if (parentMediaId == _tabOfflineId) {
      final offlineTracks = downloadService?.downloadedTracks ?? [];
      return List.generate(offlineTracks.length, (i) {
        final t = offlineTracks[i];
        return _trackToMediaItem(
          t,
          customId: 'offline_track:$i',
          albumName: 'Baixadas Offline',
        );
      });
    }

    // 5. Fila de Reprodução Atual
    if (parentMediaId == _tabQueueId) {
      final currentQueue = getCurrentQueue?.call() ?? [];
      return List.generate(currentQueue.length, (i) {
        final t = currentQueue[i];
        return _trackToMediaItem(
          t,
          customId: 'queue_track:$i',
          albumName: 'Fila Atual',
        );
      });
    }

    return [];
  }

  /// Chamado quando o motorista toca em uma música ou playlist no painel do Android Auto
  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    if (mediaId.startsWith('pl_track:')) {
      final parts = mediaId.split(':');
      if (parts.length >= 3) {
        final plId = parts[1];
        final trackIdx = int.tryParse(parts[2]) ?? 0;
        final playlists = playlistService?.playlists ?? [];
        final plIndex = playlists.indexWhere((p) => p.id == plId);
        if (plIndex != -1 && onPlayPlaylist != null) {
          await onPlayPlaylist!(playlists[plIndex], startIndex: trackIdx);
        }
      }
      return;
    }

    if (mediaId.startsWith('offline_track:')) {
      final idx = int.tryParse(mediaId.substring('offline_track:'.length)) ?? 0;
      final offlineTracks = downloadService?.downloadedTracks ?? [];
      if (offlineTracks.isNotEmpty && onPlayQueue != null) {
        await onPlayQueue!(offlineTracks, startIndex: idx);
      }
      return;
    }

    if (mediaId.startsWith('queue_track:')) {
      final idx = int.tryParse(mediaId.substring('queue_track:'.length)) ?? 0;
      final currentQueue = getCurrentQueue?.call() ?? [];
      if (currentQueue.isNotEmpty && onPlayQueue != null) {
        await onPlayQueue!(currentQueue, startIndex: idx);
      }
      return;
    }
  }

  /// Chamado quando o motorista usa comando de voz no Android Auto ("Ok Google, tocar X no DaPlayer")
  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      final offlineTracks = downloadService?.downloadedTracks ?? [];
      if (offlineTracks.isNotEmpty && onPlayQueue != null) {
        await onPlayQueue!(offlineTracks, startIndex: 0);
      }
      return;
    }

    // 1. Verifica se bate com o nome de alguma coletânea do usuário
    final playlists = playlistService?.playlists ?? [];
    for (final pl in playlists) {
      if (pl.name.toLowerCase().contains(trimmed.toLowerCase()) && pl.tracks.isNotEmpty) {
        if (onPlayPlaylist != null) {
          await onPlayPlaylist!(pl, startIndex: 0);
          return;
        }
      }
    }

    // 2. Verifica se bate com alguma música já baixada offline
    final offlineTracks = downloadService?.downloadedTracks ?? [];
    final matchingOffline = offlineTracks
        .where((t) =>
            t.title.toLowerCase().contains(trimmed.toLowerCase()) ||
            t.artist.toLowerCase().contains(trimmed.toLowerCase()))
        .toList();
    if (matchingOffline.isNotEmpty && onPlayQueue != null) {
      await onPlayQueue!(matchingOffline, startIndex: 0);
      return;
    }

    // 3. Pesquisa no YouTube e inicia a reprodução
    if (ytService != null && onPlayQueue != null) {
      final results = await ytService!.search(trimmed);
      if (results.isNotEmpty) {
        await onPlayQueue!(results, startIndex: 0);
      }
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final currentQueue = getCurrentQueue?.call() ?? [];
    if (index >= 0 && index < currentQueue.length && onPlayQueue != null) {
      await onPlayQueue!(currentQueue, startIndex: index);
    }
  }

  @override
  Future<void> play() async {
    if (onPlay != null) await onPlay!();
  }

  @override
  Future<void> pause() async {
    if (onPause != null) await onPause!();
  }

  @override
  Future<void> skipToNext() async {
    if (onNext != null) await onNext!();
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPrevious != null) await onPrevious!();
  }

  @override
  Future<void> seek(Duration position) async {
    if (onSeek != null) await onSeek!(position);
  }

  @override
  Future<void> stop() async {
    if (onPause != null) await onPause!();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await super.stop();
  }
}
