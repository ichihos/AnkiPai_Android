import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

// Conditionally import dart:html for web platform
// This approach prevents compile errors on non-web platforms
import 'url_opener_web.dart' if (dart.library.io) 'url_opener_stub.dart';
import 'dart:io' show Platform;

/// Platform-agnostic URL opener utility
///
/// Handles opening URLs in a browser, with platform-specific
/// implementations for web and native platforms.
class UrlOpener {
  /// Opens the provided URL in the appropriate way for the platform
  ///
  /// On web: Opens in a new tab
  /// On native platforms: Opens in the system browser
  static Future<void> openUrl(String url) async {
    if (kIsWeb) {
      // Call the web implementation
      openUrlWeb(url);
    } else {
      // Use the native URL launcher for all other platforms
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(
        uri,
        mode: Platform.isAndroid || Platform.isIOS
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      )) {
        throw Exception('Could not launch $url');
      }
    }
  }
}
