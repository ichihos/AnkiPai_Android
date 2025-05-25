import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider with ChangeNotifier {
  Locale _currentLocale = const Locale('en');
  static const String _localeKey = 'app_locale';

  Locale get currentLocale => _currentLocale;

  LanguageProvider() {
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLocale = prefs.getString(_localeKey);

    if (savedLocale != null) {
      _currentLocale = Locale(savedLocale);
      print('Loaded saved locale: ${_currentLocale.languageCode}');
    } else {
      // Detect system/browser locale and set appropriately
      String deviceLocale = 'en'; // Default to English

      try {
        if (kIsWeb) {
          // For Web platform, try to get browser language
          final languages = PlatformDispatcher.instance.locales;
          if (languages.isNotEmpty) {
            deviceLocale = languages.first.languageCode;
            print('Web browser detected language: $deviceLocale');
          } else {
            // Fallback to platform dispatcher locale
            deviceLocale = PlatformDispatcher.instance.locale.languageCode;
            print('Using platform dispatcher locale for web: $deviceLocale');
          }
        } else {
          // Native platform
          deviceLocale = PlatformDispatcher.instance.locale.languageCode;
          print('Native platform detected language: $deviceLocale');
        }
      } catch (e) {
        print('Error detecting locale: $e');
      }

      // Only set if it's one of our supported languages
      if (deviceLocale == 'ja' ||
          deviceLocale == 'zh' ||
          deviceLocale == 'en') {
        _currentLocale = Locale(deviceLocale);
      } else {
        // Default to English for unsupported languages
        _currentLocale = Locale('en');
      }

      // Save detected locale to preferences
      await prefs.setString(_localeKey, _currentLocale.languageCode);
      print('Language initialized to: ${_currentLocale.languageCode}');
    }
    notifyListeners();
  }

  Future<void> changeLocale(Locale locale) async {
    if (_currentLocale == locale) return;

    _currentLocale = locale;

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);

    notifyListeners();
  }

  // This getter will be used by AI services to know what language to respond in
  String get aiLanguagePrompt {
    switch (_currentLocale.languageCode) {
      case 'ja':
        return '日本語で回答してください';
      case 'zh':
        return '请用中文回答';
      case 'en':
      default:
        return 'Respond in English';
    }
  }
}
