import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import 'youtube_service.dart';
import 'tray_service.dart';
import 'linux_gst_player.dart';
import 'mobile_audio_handler.dart';

class AudioPlayerService extends ChangeNotifier {
  final AudioPlayer? _justAudioPlayer = !Platform.isLinux ? AudioPlayer() : null;
  final LinuxGstPlayer? _gstPlayer = Platform.isLinux ? LinuxGstPlayer() : null;
  final YouTubeService _ytService;
  final TrayService _trayService;
  DaPlayerAudioHandler? _mobileHandler;

  Track? _currentTrack;
  List<Track> _queue = [];
  int _currentIndex = -1;

  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;

  // Getters
  Track? get currentTrack => _currentTrack;
  List<Track> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;

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
        final playing = state.playing && state.processingState != ProcessingState.completed;
        if (_isPlaying != playing) {
          _isPlaying = playing;
          _updateTray();
          _updateMobileMedia();
          notifyListeners();
        }

        if (state.processingState == ProcessingState.completed) {
          next();
        }
      });

      _justAudioPlayer.positionStream.listen((pos) {
        _position = pos;
        _updateMobileMedia();
        notifyListeners();
      });

      _justAudioPlayer.durationStream.listen((dur) {
        _duration = dur ?? Duration.zero;
        _updateMobileMedia();
        notifyListeners();
      });
    }
  }

  Future<void> playTrack(Track track) async {
    _currentTrack = track;
    _isLoading = true;
    _position = Duration.zero;
    _duration = track.duration;
    notifyListeners();

    _updateTray();
    if (_mobileHandler != null) {
      final hasNext = _queue.isNotEmpty && _currentIndex + 1 < _queue.length;
      final hasPrevious = _queue.isNotEmpty && _currentIndex > 0;
      _mobileHandler!.updateTrack(track, hasNext: hasNext, hasPrevious: hasPrevious);
    }

    try {
      final audioUrl = await _ytService.getAudioOnlyStreamUrl(track.id);
      if (audioUrl != null) {
        if (Platform.isLinux && _gstPlayer != null) {
          await _gstPlayer.setUrl(audioUrl);
          await _gstPlayer.play();
          _isPlaying = true;
        } else if (_justAudioPlayer != null) {
          await _justAudioPlayer.setUrl(audioUrl);
          _justAudioPlayer.play();
          _isPlaying = true;
        }
      } else {
        debugPrint('Não foi possível obter áudio para ${track.title}');
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

    _queue = List.from(playlist.tracks);
    _currentIndex = startIndex.clamp(0, _queue.length - 1);
    await playTrack(_queue[_currentIndex]);
  }

  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _queue = List.from(tracks);
    _currentIndex = startIndex.clamp(0, _queue.length - 1);
    await playTrack(_queue[_currentIndex]);
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
      await playTrack(_queue[_currentIndex]);
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
