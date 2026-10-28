import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

class TrayService {
  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();

  VoidCallback? onPlayPausePressed;
  VoidCallback? onNextPressed;
  VoidCallback? onPreviousPressed;

  bool _initialized = false;
  String _currentTitle = 'Nenhuma música tocando';
  String _currentArtist = '';
  bool _isPlaying = false;

  Future<void> initTray({
    VoidCallback? onPlayPause,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
  }) async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
      return;
    }

    onPlayPausePressed = onPlayPause;
    onNextPressed = onNext;
    onPreviousPressed = onPrevious;

    try {
      final iconPath = Platform.isWindows ? 'assets/icon.ico' : 'assets/tray_icon.png';

      await _systemTray.initSystemTray(
        title: "DaPlayer",
        iconPath: iconPath,
        toolTip: "DaPlayer - Tocando música em segundo plano",
      );

      // Evento de clique no ícone da barra de sistema (abre/restaura o app)
      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          windowManager.show();
          windowManager.focus();
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray.popUpContextMenu();
        }
      });

      await _rebuildMenu();
      _initialized = true;
    } catch (e) {
      debugPrint('Aviso: Falha ao inicializar System Tray: $e');
    }
  }

  Future<void> updateTrayInfo({
    required String title,
    required String artist,
    required bool isPlaying,
  }) async {
    _currentTitle = title;
    _currentArtist = artist;
    _isPlaying = isPlaying;

    if (!_initialized) return;

    try {
      final tooltip = artist.isNotEmpty
          ? 'DaPlayer: $title - $artist'
          : 'DaPlayer: $title';
      await _systemTray.setToolTip(tooltip);
      await _rebuildMenu();
    } catch (e) {
      debugPrint('Erro ao atualizar bandeja do sistema: $e');
    }
  }

  Future<void> _rebuildMenu() async {
    final songLabel = _currentArtist.isNotEmpty
        ? '🎵 $_currentTitle ($_currentArtist)'
        : '🎵 $_currentTitle';

    await _menu.buildFrom([
      MenuItemLabel(label: songLabel, enabled: false),
      MenuSeparator(),
      MenuItemLabel(
        label: _isPlaying ? '⏸  Pausar' : '▶  Reproduzir',
        onClicked: (menuItem) => onPlayPausePressed?.call(),
      ),
      MenuItemLabel(
        label: '⏭  Próxima Faixa',
        onClicked: (menuItem) => onNextPressed?.call(),
      ),
      MenuItemLabel(
        label: '⏮  Faixa Anterior',
        onClicked: (menuItem) => onPreviousPressed?.call(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '🪟  Abrir DaPlayer',
        onClicked: (menuItem) {
          windowManager.show();
          windowManager.focus();
        },
      ),
      MenuItemLabel(
        label: '❌  Sair',
        onClicked: (menuItem) {
          windowManager.destroy();
        },
      ),
    ]);

    await _systemTray.setContextMenu(_menu);
  }
}
