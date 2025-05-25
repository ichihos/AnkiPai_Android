import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Service to handle language-specific functions for the app
class LanguageService {
  static const String _localeKey = 'app_locale';
  static bool _isInitialized = false;
  static String? _cachedLocale;
  static Future<void>? _initFuture;
  static DateTime? _lastLocaleCheck;

  /// Initialize the language service with the device's locale
  /// This can be called during app startup but will not block the UI
  static Future<void> initialize() async {
    // Return cached future if initialization is in progress
    if (_initFuture != null) return _initFuture!;

    // Return immediately if already initialized
    if (_isInitialized) return Future.value();

    // Create initialization future
    _initFuture = _doInitialize();
    return _initFuture!;
  }

  /// Internal method that does the actual initialization work
  static Future<void> _doInitialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString(_localeKey);

      if (savedLocale != null) {
        _cachedLocale = savedLocale;
      } else {
        // Get locale safely (works in both foreground and background, and on web)
        String deviceLocale = 'en'; // Default to English

        try {
          if (kIsWeb) {
            // For Web platform, try to get browser language
            // First try to get from navigator.language
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
            // Use PlatformDispatcher which is the modern replacement for window
            // This is safer for iOS background processing
            final locale = PlatformDispatcher.instance.locale;
            deviceLocale = locale.languageCode;
            print('Native platform detected language: $deviceLocale');
          }
        } catch (e) {
          // Fallback in case of any issues accessing locale in background
          print('Could not access locale: $e');
        }

        // Only set if it's one of our supported languages
        if (deviceLocale == 'ja' ||
            deviceLocale == 'zh' ||
            deviceLocale == 'en') {
          _cachedLocale = deviceLocale;
        } else {
          // Default to English for unsupported languages
          _cachedLocale = 'en';
        }
        
        print('Language initialized to: $_cachedLocale');

        // Perform write operation without awaiting to avoid blocking
        prefs.setString(_localeKey, _cachedLocale!).catchError((error) {
          // Log error but don't crash if preferences can't be written
          print('Error saving locale preference: $error');
          return true; // Error was handled
        });
      }

      _isInitialized = true;
      _lastLocaleCheck = DateTime.now();
    } finally {
      _initFuture = null;
    }
  }

  /// Refresh the cached locale from SharedPreferences
  static Future<void> refreshLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLocale = prefs.getString(_localeKey);

    if (savedLocale != null) {
      _cachedLocale = savedLocale;
      _lastLocaleCheck = DateTime.now();
    }
  }

  /// Get the language prompt for AI services based on the current app language
  /// This is optimized to minimize impact on app performance and works offline
  static Future<String> getAILanguagePrompt() async {
    try {
      // Start initialization if needed but don't wait for completion now
      if (!_isInitialized) {
        // Use microtask to not block the current execution
        Future.microtask(() => initialize());

        // Wait until explicitly initialized or a timeout occurs
        for (int i = 0; i < 50; i++) {
          if (_isInitialized) break;
          await Future.delayed(Duration(milliseconds: 10));
        }

        // If still not initialized after timeout, wait for full initialization
        if (!_isInitialized) {
          await initialize();
        }
      } else {
        // Check if we need to refresh the locale
        // Refresh if it's been more than 1 second since we last checked
        // This allows for frequent calls to getAILanguagePrompt() without performance penalty
        final now = DateTime.now();
        if (_lastLocaleCheck == null ||
            now.difference(_lastLocaleCheck!).inSeconds > 1) {
          // Try to refresh but don't block if it fails (offline mode)
          try {
            await refreshLocale();
          } catch (e) {
            print('⚠️ ロケール更新中にエラーが発生しました (オフラインモード): $e');
            // Continue with cached locale
          }
        }
      }
    } catch (e) {
      print('⚠️ 言語サービス初期化中にエラーが発生しました: $e');
      // If we can't initialize, use a default locale
      if (_cachedLocale == null) {
        _cachedLocale = 'en';
        print('⚠️ デフォルト言語（英語）を使用します');
      }
    }

    // Use cached locale for better performance
    final locale = _cachedLocale!;

    if (locale == 'ja') {
      return 'IMPORTANT: You must respond in Japanese (日本語). Your entire response including all examples, explanations, and memory techniques must be written in Japanese only for Japanese speaking users.';
    } else if (locale == 'zh') {
      return 'IMPORTANT: You must respond in Chinese (中文). Your entire response including all examples, explanations, and memory techniques must be written in Chinese only for Chinese speaking users.';
    } else {
      return 'IMPORTANT: You must respond in English only. Your entire response including all examples, explanations, and memory techniques must be written in English only for English speaking users.';
    }
  }

  /// Get the current language code
  /// This is optimized to minimize impact on app performance
  static Future<String> getCurrentLanguageCode() async {
    if (!_isInitialized) {
      // Use microtask to not block the current execution
      Future.microtask(() => initialize());
      await initialize(); // We need the result for this call
    } else {
      // Always refresh locale when explicitly requesting the current language code
      await refreshLocale();
    }

    // Return cached locale directly
    return _cachedLocale!;
  }
}
