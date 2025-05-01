import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional import for web-specific code
import 'web_ad_widget_web.dart' if (dart.library.io) 'web_ad_widget_stub.dart';

/// A widget that displays advertisements on web platforms.
/// This widget will only show ads on web platforms and will be invisible on other platforms.
class WebAdWidget extends StatelessWidget {
  /// Creates a web advertisement widget
  ///
  /// [adId] is a unique identifier for this ad instance
  /// [height] is the height of the ad container in logical pixels
  /// [width] is the width of the ad container in logical pixels
  /// [adSrc] is the HTML file path for the ad content (relative to web/)
  const WebAdWidget({
    super.key,
    required this.adId,
    required this.height,
    required this.width,
    required this.adSrc,
  });

  /// Unique identifier for this ad instance
  final String adId;
  
  /// Height of the ad container in logical pixels
  final double height;
  
  /// Width of the ad container in logical pixels
  final double width;
  
  /// HTML file path for the ad content (relative to web/)
  final String adSrc;

  @override
  Widget build(BuildContext context) {
    // Only show ads on web platform
    if (!kIsWeb) {
      // Return an empty container on non-web platforms
      return const SizedBox.shrink();
    }
    
    // Delegate to the platform-specific implementation
    return createWebAdView(
      adId: adId,
      height: height,
      width: width,
      adSrc: adSrc,
    );
  }
}
