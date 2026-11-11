import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'youtube_service.dart';

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._internal();
  DownloadService._internal() {
    init();
  }

  static const String _prefsKey = 'daplayer_offline_downloads_v1';
  final YouTubeService _ytService = YouTubeService();

  final Map<String, String> _localFiles = {};
  final Map<String, Track> _downloadedTracks = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingPlaylists = {};

  bool _initialized = false;

  List<Track> get downloadedTracks => _downloadedTracks.values.toList(growable: false);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        bool changed = false;
        for (final entry in decoded.entries) {
          final trackId = entry.key;
          final data = entry.value as Map<String, dynamic>;
          final filePath = data['filePath'] as String?;
          final trackMap = data['track'] as Map<String, dynamic>?;
          if (filePath != null && File(filePath).existsSync()) {
            _localFiles[trackId] = filePath;
            if (trackMap != null) {
              _downloadedTracks[trackId] = Track.fromMap(trackMap);
            }
          } else {
            changed = true;
          }
        }
        if (changed) {
          await _saveIndex();
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao inicializar DownloadService: $e');
    }
  }

  bool isDownloaded(String trackId) {
    final path = _localFiles[trackId];
    if (path == null) return false;
    if (File(path).existsSync()) return true;
    _localFiles.remove(trackId);
    _downloadedTracks.remove(trackId);
    return false;
  }

  bool isDownloading(String trackId) => _downloadProgress.containsKey(trackId);

  double getProgress(String trackId) => _downloadProgress[trackId] ?? 0.0;

  bool isDownloadingPlaylist(String playlistId) =>
      _downloadingPlaylists.contains(playlistId);

  int getPlaylistDownloadedCount(Playlist playlist) {
    int count = 0;
    for (final t in playlist.tracks) {
      if (isDownloaded(t.id)) count++;
    }
    return count;
  }

  bool isPlaylistFullyDownloaded(Playlist playlist) {
    if (playlist.tracks.isEmpty) return false;
    return playlist.tracks.every((t) => isDownloaded(t.id));
  }

  /// Retorna o caminho do arquivo local caso a música já esteja baixada no dispositivo
  String? getLocalFilePath(String trackId) {
    final path = _localFiles[trackId];
    if (path != null && File(path).existsSync()) {
      return path;
    }
    return null;
  }

  Future<Directory> _getOfflineDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'offline_tracks'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Baixa uma música individualmente para armazenamento local
  Future<bool> downloadTrack(Track track) async {
    if (isDownloaded(track.id)) return true;
    if (isDownloading(track.id)) return false;

    _downloadProgress[track.id] = 0.01;
    notifyListeners();

    try {
      final dir = await _getOfflineDir();
      final safeId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
      final destFile = File(p.join(dir.path, '$safeId.m4a'));

      int lastNotifiedPct = 0;
      final success = await _ytService.downloadAudioToFile(
        track.id,
        destFile,
        onProgress: (progress) {
          _downloadProgress[track.id] = progress;
          final pct = (progress * 100).round();
          if (pct - lastNotifiedPct >= 5 || pct == 100) {
            lastNotifiedPct = pct;
            notifyListeners();
          }
        },
      );

      _downloadProgress.remove(track.id);

      if (success && await destFile.exists()) {
        _localFiles[track.id] = destFile.path;
        _downloadedTracks[track.id] = track;
        await _saveIndex();
        notifyListeners();
        return true;
      } else {
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('Erro ao baixar música ${track.title}: $e');
      _downloadProgress.remove(track.id);
      notifyListeners();
      return false;
    }
  }

  /// Baixa todas as músicas de uma coletânea (playlist) que ainda não estão baixadas localmente
  Future<int> downloadPlaylist(Playlist playlist) async {
    if (playlist.tracks.isEmpty) return 0;
    if (_downloadingPlaylists.contains(playlist.id)) return 0;

    _downloadingPlaylists.add(playlist.id);
    notifyListeners();

    int successCount = 0;
    try {
      for (final track in playlist.tracks) {
        if (isDownloaded(track.id)) {
          successCount++;
          continue;
        }
        final ok = await downloadTrack(track);
        if (ok) successCount++;
      }
    } finally {
      _downloadingPlaylists.remove(playlist.id);
      notifyListeners();
    }

    return successCount;
  }

  /// Remove o arquivo baixado localmente de uma música
  Future<void> removeDownload(String trackId) async {
    final path = _localFiles.remove(trackId);
    _downloadedTracks.remove(trackId);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Erro ao excluir arquivo local $path: $e');
      }
    }
    await _saveIndex();
    notifyListeners();
  }

  Future<void> _saveIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      for (final entry in _localFiles.entries) {
        final track = _downloadedTracks[entry.key];
        map[entry.key] = {
          'filePath': entry.value,
          if (track != null) 'track': track.toMap(),
        };
      }
      await prefs.setString(_prefsKey, json.encode(map));
    } catch (e) {
      debugPrint('Erro ao salvar índice de downloads: $e');
    }
  }
}
