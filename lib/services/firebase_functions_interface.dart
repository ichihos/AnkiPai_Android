/// Interface for Firebase Functions service
/// Provides a consistent API for both web and mobile platforms
abstract class FirebaseFunctionsInterface {
  /// Call a Firebase Cloud Function
  /// 
  /// [functionName] is the name of the function to call
  /// [data] is the data to pass to the function
  /// 
  /// Returns a Future that completes with the function result as a Map
  Future<Map<String, dynamic>> callFunction(String functionName, Map<String, dynamic> data);
}
