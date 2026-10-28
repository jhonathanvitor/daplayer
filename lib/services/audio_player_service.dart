import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import 'youtube_service.dart';
import 'tray_service.dart';

class AudioPlayerService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final YouTubeService _ytService;
  final TrayService _trayService;

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
    _player.playerStateStream.listen((state) {
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        _updateTray();
        notifyListeners();
      }

      if (state.processingState == ProcessingState.completed) {
        next();
      }
    });

    _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    });
  }

  Future<void> playTrack(Track track) async {
    _currentTrack = track;
    _isLoading = true;
    notifyListeners();

    _updateTray();

    try {
      final audioUrl = await _ytService.getAudioOnlyStreamUrl(track.id);
      if (audioUrl != null) {
        await _player.setUrl(audioUrl);
        await _player.play();
      } else {
        debugPrint('Não foi possível obter áudio para ${track.title}');
      }
    } catch (e) {
      debugPrint('Erro ao reproduzir áudio: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
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
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _isPlaying = _player.playing;
    _updateTray();
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
    await _player.seek(pos);
  }

  Future<void> setVolume(double vol) async {
    _volume = vol.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    notifyListeners();
  }

  void _updateTray() {
    if (_currentTrack != null) {
      _trayService.updateTrayInfo(
        title: _currentTrack!.title,
        artist: _currentTrack!.artist,
        isPlaying: _isPlaying,
      );
    } else {
      _trayService.updateTrayInfo(
        title: 'Nenhuma música',
        artist: '',
        isPlaying: false,
      );
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
