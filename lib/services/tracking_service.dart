import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

class TrackingService {
  /// Initializes App Tracking Transparency request on iOS
  /// Returns the current tracking status
  Future<TrackingStatus> initializeATT() async {
    // Only run on iOS, no-op on other platforms
    if (!kIsWeb && Platform.isIOS) {
      // Check current status
      TrackingStatus status =
          await AppTrackingTransparency.trackingAuthorizationStatus;

      // Only show request dialog if status is not determined
      if (status == TrackingStatus.notDetermined) {
        // Delay a bit to ensure app UI is fully loaded - recommended by Apple
        await Future.delayed(const Duration(milliseconds: 200));

        // Request permission
        status = await AppTrackingTransparency.requestTrackingAuthorization();
      }

      return status;
    }

    // Return authorized for non-iOS platforms
    return TrackingStatus.authorized;
  }

  /// Check if app tracking is authorized
  Future<bool> isTrackingAuthorized() async {
    if (!kIsWeb && Platform.isIOS) {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      return status == TrackingStatus.authorized;
    }
    return true; // Always return true for non-iOS platforms
  }
}
