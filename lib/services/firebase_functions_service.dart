import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_functions_interface.dart';

// Conditional imports for platform-specific implementations
import 'firebase_functions_mobile.dart' if (dart.library.html) 'firebase_functions_web.dart';

/// Factory class for creating the appropriate Firebase Functions service implementation
/// based on the current platform (web or mobile)
class FirebaseFunctionsFactory {
  /// Create an instance of FirebaseFunctionsInterface
  /// Returns the web implementation on web platforms
  /// Returns the mobile implementation on mobile platforms
  static FirebaseFunctionsInterface create() {
    if (kIsWeb) {
      print('Creating web implementation of Firebase Functions service');
    } else {
      print('Creating mobile implementation of Firebase Functions service');
    }
    
    return FirebaseFunctionsService();
  }
}
