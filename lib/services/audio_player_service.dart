import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import 'youtube_service.dart';
import 'download_service.dart';
import 'tray_service.dart';
import 'linux_gst_player.dart';
import 'mobile_audio_handler.dart';

class AudioPlayerService extends ChangeNotifier {
  final AudioPlayer? _justAudioPlayer = !Platform.isLinux
      ? AudioPlayer(
          handleInterruptions: false,
          androidApplyAudioAttributes: false,
          handleAudioSessionActivation: false,
          audioLoadConfiguration: const AudioLoadConfiguration(
            androidLoadControl: AndroidLoadControl(
              minBufferDuration: Duration(seconds: 25),
              maxBufferDuration: Duration(seconds: 120),
              bufferForPlaybackDuration: Duration(milliseconds: 1000),
              bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
            ),
          ),
        )
      : null;
  final LinuxGstPlayer? _gstPlayer = Platform.isLinux ? LinuxGstPlayer() : null;
  final YouTubeService _ytService;
  final TrayService _trayService;
  DaPlayerAudioHandler? _mobileHandler;

  Track? _currentTrack;
  List<Track> _queue = [];
  int _currentIndex = -1;

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isBuffering = false;
  bool _isPlayingOffline = false;
  bool _isSmartRelatedMode = false;
  bool _isFetchingRelated = false;
  final Set<String> _playedTrackIds = {};
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;

  // Getters
  Track? get currentTrack => _currentTrack;
  List<Track> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get isBuffering => _isLoading || _isBuffering;
  bool get isPlayingOffline => _isPlayingOffline;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  Duration get duration => _duration;
  double get volume => _volume;
  int get bufferPercent => _duration.inMilliseconds > 0
      ? ((_bufferedPosition.inMilliseconds / _duration.inMilliseconds) * 100)
          .clamp(0, 100)
          .round()
      : 0;

  AudioPlayerService({
    required YouTubeService ytService,
    required TrayService trayService,
  })  : _ytService = ytService,
        _trayService = trayService {
    _initListeners();
    _trayService.initTray(
      onPlayPause: togglePlayPause,
      onNext: next,
      onPrevious: previous,
    );
  }

  void _initListeners() {
    if (Platform.isLinux && _gstPlayer != null) {
      _gstPlayer.isPlayingStream.listen((playing) {
        if (_isPlaying != playing) {
          _isPlaying = playing;
          _updateTray();
          notifyListeners();
        }
      });

      _gstPlayer.positionStream.listen((pos) {
        _position = pos;
        notifyListeners();
      });

      _gstPlayer.durationStream.listen((dur) {
        _duration = dur;
        notifyListeners();
      });

      _gstPlayer.onCompleted = () {
        next();
      };
    } else if (_justAudioPlayer != null) {
      _justAudioPlayer.playerStateStream.listen((state) {
        final buffering = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        bool shouldNotify = false;
        if (_isBuffering != buffering) {
          _isBuffering = buffering;
          shouldNotify = true;
        }

        if (!_isLoading) {
          final playing =
              state.playing && state.processingState != ProcessingState.completed;
          if (_isPlaying != playing) {
            _isPlaying = playing;
            _updateTray();
            _updateMobileMedia();
            shouldNotify = true;
          }
        }

        if (shouldNotify) {
          notifyListeners();
        }

        if (state.processingState == ProcessingState.completed) {
          next();
        }
      });

      _justAudioPlayer.positionStream.listen((pos) {
        if ((pos - _position).abs().inMilliseconds >= 500 || pos == Duration.zero) {
          _position = pos;
          notifyListeners();
        }
      });

      _justAudioPlayer.bufferedPositionStream.listen((bufferedPos) {
        if ((bufferedPos - _bufferedPosition).abs().inMilliseconds >= 500 ||
            bufferedPos == Duration.zero ||
            bufferedPos >= _duration) {
          _bufferedPosition = bufferedPos;
          notifyListeners();
        }
      });

      _justAudioPlayer.durationStream.listen((dur) {
        _duration = dur ?? Duration.zero;
        if (!_isLoading) {
          _updateMobileMedia();
        }
        notifyListeners();
      });
    }
  }

  Future<void> playTrack(Track track) async {
    final localFilePath = DownloadService.instance.getLocalFilePath(track.id);
    final hasLocalFile = localFilePath != null;

    _currentTrack = track;
    _isLoading = !hasLocalFile;
    _isBuffering = !hasLocalFile;
    _isPlayingOffline = hasLocalFile;
    _isPlaying = true;
    _position = Duration.zero;
    _bufferedPosition = hasLocalFile ? track.duration : Duration.zero;
    _duration = track.duration;
    notifyListeners();

    _updateTray();
    if (_mobileHandler != null) {
      final hasNext = _queue.isNotEmpty && _currentIndex + 1 < _queue.length;
      final hasPrevious = _queue.isNotEmpty && _currentIndex > 0;
      _mobileHandler!.updateTrack(track, hasNext: hasNext, hasPrevious: hasPrevious);
    }

    try {
      // 1. Se a música já foi baixada localmente, reproduz direto do arquivo local (Offline-First!)
      if (hasLocalFile) {
        if (Platform.isLinux && _gstPlayer != null) {
          final fileUri = Uri.file(localFilePath).toString();
          await _gstPlayer.setUrl(fileUri);
          await _gstPlayer.play();
          _isPlaying = true;
          _isBuffering = false;
          _bufferedPosition = _duration;
        } else if (_justAudioPlayer != null) {
          await _justAudioPlayer.setFilePath(localFilePath);
          _justAudioPlayer.play();
          _isPlaying = true;
          _isBuffering = false;
          _bufferedPosition = _duration;
        }
      } else {
        // 2. Caso não esteja baixada localmente, consome da internet via stream otimizado
        final audioUrl = await _ytService.getAudioOnlyStreamUrl(track.id);
        if (audioUrl != null) {
          if (Platform.isLinux && _gstPlayer != null) {
            await _gstPlayer.setUrl(audioUrl);
            await _gstPlayer.play();
            _isPlaying = true;
            _isBuffering = false;
            _bufferedPosition = _duration;
          } else if (_justAudioPlayer != null) {
            await _justAudioPlayer.setUrl(audioUrl);
            _justAudioPlayer.play();
            _isPlaying = true;
          }
        } else {
          debugPrint('Não foi possível obter áudio para ${track.title}');
        }
      }

      // Pré-carrega o manifesto da próxima faixa da fila se ela não estiver baixada localmente
      if (_queue.isNotEmpty && _currentIndex >= 0 && _currentIndex + 1 < _queue.length) {
        final nextTrack = _queue[_currentIndex + 1];
        if (!DownloadService.instance.isDownloaded(nextTrack.id)) {
          unawaited(_ytService.getAudioOnlyStreamUrl(nextTrack.id));
        }
      }
    } catch (e) {
      debugPrint('Erro ao reproduzir áudio: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      _updateTray();
      _updateMobileMedia();
    }
  }

  Future<void> playPlaylist(Playlist playlist, {int startIndex = 0}) async {
    if (playlist.tracks.isEmpty) return;

    // Modo Coletânea: mantém a sequência exata da playlist do usuário
    _isSmartRelatedMode = false;
    _queue = List.from(playlist.tracks);
    _currentIndex = startIndex.clamp(0, _queue.length - 1);
    await playTrack(_queue[_currentIndex]);
  }

  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool smartRelated = true,
  }) async {
    if (tracks.isEmpty) return;
    final selectedIndex = startIndex.clamp(0, tracks.length - 1);
    final selectedTrack = tracks[selectedIndex];

    if (smartRelated) {
      // Modo Descobrir / Busca: toca a música selecionada e monta fila com músicas relacionadas ao cantor/gênero
      _isSmartRelatedMode = true;
      _playedTrackIds.add(selectedTrack.id);
      _queue = [selectedTrack];
      _currentIndex = 0;
      await playTrack(selectedTrack);
      unawaited(_loadRelatedTracksFor(selectedTrack, replaceUpcoming: true));
    } else {
      _isSmartRelatedMode = false;
      _queue = List.from(tracks);
      _currentIndex = selectedIndex;
      await playTrack(_queue[_currentIndex]);
    }
  }

  Future<void> _loadRelatedTracksFor(
    Track seedTrack, {
    bool replaceUpcoming = false,
  }) async {
    if (_isFetchingRelated || !_isSmartRelatedMode) return;
    _isFetchingRelated = true;
    try {
      final related = await _ytService.getRelatedTracks(
        seedTrack,
        excludeIds: _playedTrackIds,
      );
      if (!_isSmartRelatedMode || related.isEmpty) return;

      if (replaceUpcoming && _currentIndex >= 0 && _currentIndex < _queue.length) {
        _queue = [
          ..._queue.sublist(0, _currentIndex + 1),
          ...related,
        ];
      } else {
        for (final t in related) {
          if (!_queue.any((q) => q.id == t.id)) {
            _queue.add(t);
          }
        }
      }

      // Pré-carrega o stream da próxima música relacionada
      if (_currentIndex + 1 < _queue.length) {
        final nextTrack = _queue[_currentIndex + 1];
        if (!DownloadService.instance.isDownloaded(nextTrack.id)) {
          unawaited(_ytService.getAudioOnlyStreamUrl(nextTrack.id));
        }
      }
      _updateMobileMedia();
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao carregar músicas relacionadas: $e');
    } finally {
      _isFetchingRelated = false;
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> pause() async {
    if (Platform.isLinux && _gstPlayer != null) {
      await _gstPlayer.pause();
    } else if (_justAudioPlayer != null) {
      await _justAudioPlayer.pause();
    }
    _isPlaying = false;
    _updateTray();
    _updateMobileMedia();
    notifyListeners();
  }

  Future<void> resume() async {
    if (Platform.isLinux && _gstPlayer != null) {
      await _gstPlayer.play();
    } else if (_justAudioPlayer != null) {
      _justAudioPlayer.play();
    }
    _isPlaying = true;
    _updateTray();
    _updateMobileMedia();
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isNotEmpty && _currentIndex + 1 < _queue.length) {
      _currentIndex++;
      final nextTrack = _queue[_currentIndex];
      _playedTrackIds.add(nextTrack.id);
      await playTrack(nextTrack);

      // Se estiver no modo Busca/Descobrir e restarem poucas músicas, busca mais relacionadas automaticamente
      if (_isSmartRelatedMode && (_queue.length - _currentIndex) <= 3) {
        unawaited(_loadRelatedTracksFor(nextTrack, replaceUpcoming: false));
      }
      return;
    }

    // Se acabou a fila no modo Busca/Descobrir, busca relacionadas da música atual imediatamente
    if (_isSmartRelatedMode && _currentTrack != null) {
      await _loadRelatedTracksFor(_currentTrack!, replaceUpcoming: false);
      if (_currentIndex + 1 < _queue.length) {
        _currentIndex++;
        final nextTrack = _queue[_currentIndex];
        _playedTrackIds.add(nextTrack.id);
        await playTrack(nextTrack);
      }
    }
  }

  Future<void> previous() async {
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_queue.isNotEmpty && _currentIndex > 0) {
      _currentIndex--;
      await playTrack(_queue[_currentIndex]);
    }
  }

  Future<void> seek(Duration pos) async {
    _position = pos;
    if (Platform.isLinux && _gstPlayer != null) {
      await _gstPlayer.seek(pos);
    } else if (_justAudioPlayer != null) {
      await _justAudioPlayer.seek(pos);
    }
    _updateMobileMedia();
    notifyListeners();
  }

  void attachMobileHandler(DaPlayerAudioHandler handler) {
    _mobileHandler = handler;
  }

  void _updateMobileMedia() {
    if (_mobileHandler != null && _currentTrack != null) {
      final hasNext = _queue.isNotEmpty && _currentIndex + 1 < _queue.length;
      final hasPrevious = _queue.isNotEmpty && _currentIndex > 0;
      _mobileHandler!.updatePlaybackState(
        isPlaying: _isPlaying,
        position: _position,
        bufferedPosition: _position,
        hasNext: hasNext,
        hasPrevious: hasPrevious,
        isLoading: _isLoading,
      );
    }
  }

  Future<void> setVolume(double vol) async {
    _volume = vol.clamp(0.0, 1.0);
    if (Platform.isLinux && _gstPlayer != null) {
      await _gstPlayer.setVolume(_volume);
    } else if (_justAudioPlayer != null) {
      await _justAudioPlayer.setVolume(_volume);
    }
    notifyListeners();
  }

  void _updateTray() {
    if (_currentTrack != null) {
      _trayService.updateTrayInfo(
        title: _currentTrack!.title,
        artist: _currentTrack!.artist,
        isPlaying: _isPlaying,
      );
    }
  }

  @override
  void dispose() {
    _gstPlayer?.dispose();
    _justAudioPlayer?.dispose();
    super.dispose();
  }
}
