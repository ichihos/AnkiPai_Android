import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  static const String _darkModeKey = 'dark_mode';

  // 初期化処理
  Future<void> initialize() async {
    await _loadThemeSettings();
  }

  // テーマ設定を読み込む
  Future<void> _loadThemeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_darkModeKey) ?? false;
      notifyListeners();
    } catch (e) {
      print('テーマ設定の読み込みに失敗しました: $e');
    }
  }

  // ダークモード設定を切り替える
  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkModeKey, _isDarkMode);
    } catch (e) {
      print('テーマ設定の保存に失敗しました: $e');
    }
  }

  // ダークモード設定を直接更新する
  Future<void> updateDarkMode(bool isDark) async {
    if (_isDarkMode != isDark) {
      _isDarkMode = isDark;
      notifyListeners();
      
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_darkModeKey, _isDarkMode);
      } catch (e) {
        print('テーマ設定の保存に失敗しました: $e');
      }
    }
  }
}
