import UIKit
import Flutter
import FirebaseCore
import GoogleSignIn
import FirebaseAuth
import AuthenticationServices

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register Flutter plugins first to ensure all dependencies are ready
    GeneratedPluginRegistrant.register(with: self)
    
    // Firebase initialization is handled by the firebase_core Flutter plugin
    // Only perform manual initialization if necessary for specific native functionality
    // configureFirebaseSafely() - Commented out because firebase_core Flutter plugin should handle Firebase initialization
    // and we want to avoid any potential interference between native and Flutter-managed initialization
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Safe Firebase configuration with multiple fallbacks
  // Note: This is only a fallback mechanism as firebase_core Flutter plugin 
  // should handle the initialization automatically in most cases
  private func configureFirebaseSafely() {
    // Method 1: Standard try-catch approach
    do {
      // Check if Firebase is already configured
      if FirebaseApp.app() == nil {
        // Try to initialize with default options
        // FirebaseApp.configure() - Commented out as firebase_core plugin handles this
        print("Firebase already initialized by firebase_core plugin or not needed")
      } else {
        print("Firebase was already configured, using existing instance")
      }
      return // Exit if successful
    } catch let error as NSError {
      print("Firebase configuration failed with error: \(error.localizedDescription)")
      // Continue to fallback methods
    }
    
    // Method 2: Try with explicit options
    do {
      if FirebaseApp.app() == nil {
        // Create options explicitly
        if let filePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: filePath) {
          // FirebaseApp.configure(options: options) - Commented out as firebase_core plugin handles this
          print("Firebase already initialized by firebase_core plugin or not needed")
          return // Exit if successful
        }
      }
    } catch {
      print("Firebase configuration with explicit options failed")
    }
    
    // Method 3: Last resort - try to reset and configure
    do {
      // Attempt to get the default app and delete it if it exists but is in a bad state
      if let app = FirebaseApp.app() {
        try? (app as AnyObject).delete()
      }
      
      // Try one last time with default options
      // FirebaseApp.configure() - Commented out as firebase_core plugin handles this
      print("Relying on firebase_core plugin for initialization")
    } catch let finalError {
      print("All Firebase configuration attempts failed: \(finalError.localizedDescription)")
      // Log that Firebase is not available but app will continue
      print("WARNING: App will continue without Firebase services")
    }
  }
  
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    return GIDSignIn.sharedInstance.handle(url)
  }
}
