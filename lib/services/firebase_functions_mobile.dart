import 'package:cloud_functions/cloud_functions.dart';
import 'firebase_functions_interface.dart';

/// Mobile implementation of Firebase Functions interface
class FirebaseFunctionsService implements FirebaseFunctionsInterface {
  @override
  Future<Map<String, dynamic>> callFunction(String functionName, Map<String, dynamic> data) async {
    try {
      print('Mobile: Calling Firebase Function: $functionName');
      
      // Set timeout to 300 seconds (5 minutes)
      final FirebaseFunctions functions = FirebaseFunctions.instance;
      
      // Call Firebase Function using the native plugin with increased timeout
      final HttpsCallable callable = functions.httpsCallable(
        functionName,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 300))
      );
      final result = await callable.call(data);
      
      return result.data as Map<String, dynamic>;
    } catch (e) {
      print('Mobile: Error calling Firebase Function: $e');
      throw Exception('Failed to call Firebase Function on mobile: $e');
    }
  }
}
