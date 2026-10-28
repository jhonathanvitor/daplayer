import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

enum AppWindowMode { full, mini, hidden }

class WindowModeService extends ChangeNotifier {
  AppWindowMode _currentMode = AppWindowMode.full;

  AppWindowMode get currentMode => _currentMode;
  bool get isMiniMode => _currentMode == AppWindowMode.mini;
  bool get isFullMode => _currentMode == AppWindowMode.full;

  Future<void> switchToMiniMode() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;

    _currentMode = AppWindowMode.mini;
    notifyListeners();

    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setResizable(false);
      await windowManager.setSize(const Size(460, 180));
      await windowManager.setAlwaysOnTop(true);

      // Posiciona no canto inferior direito próximo à barra de tarefas
      final display = await ScreenRetriever.instance.getPrimaryDisplay();
      final posX = display.visiblePosition?.dx ?? 0.0;
      final sizeW = display.visibleSize?.width ?? display.size.width;
      final posY = display.visiblePosition?.dy ?? 0.0;
      final sizeH = display.visibleSize?.height ?? display.size.height;

      final targetX = posX + sizeW - 480;
      final targetY = posY + sizeH - 200;
      await windowManager.setPosition(Offset(targetX, targetY));

      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('Erro ao alternar para modo mini: $e');
    }
  }

  Future<void> switchToFullMode() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;

    _currentMode = AppWindowMode.full;
    notifyListeners();

    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setResizable(true);
      await windowManager.setSize(const Size(1180, 750));
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setAlignment(Alignment.center);
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('Erro ao alternar para modo completo: $e');
    }
  }

  Future<void> hideToTray() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;

    _currentMode = AppWindowMode.hidden;
    notifyListeners();
    await windowManager.hide();
  }

  Future<void> toggleMiniOrRestore() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;

    if (_currentMode == AppWindowMode.hidden) {
      await switchToMiniMode();
    } else if (_currentMode == AppWindowMode.mini) {
      await hideToTray();
    } else {
      await switchToMiniMode();
    }
  }
}
