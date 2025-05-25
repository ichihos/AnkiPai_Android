import 'dart:async';
import 'dart:js' as js;
import 'package:js/js_util.dart' as js_util;
import 'firebase_functions_interface.dart';

/// Web implementation of Firebase Functions interface
class FirebaseFunctionsService implements FirebaseFunctionsInterface {
  @override
  Future<Map<String, dynamic>> callFunction(String functionName, Map<String, dynamic> data) async {
    try {
      print('Web: Calling Firebase Function: $functionName');
      
      // Create a completer to handle the async call
      final Completer<Map<String, dynamic>> completer = Completer<Map<String, dynamic>>();
      
      // Convert the Dart map to a JS object
      final jsData = js_util.jsify(data);
      
      // Access the Firebase Functions object from JS
      // This assumes the function has been initialized in index.html
      final functions = js_util.getProperty(js.context, 'firebaseFunctions');
      
      if (functions == null) {
        print('Web: Firebase Functions not initialized');
        throw Exception('Firebase Functions not initialized');
      }
      
      // Create timeout options object (5 minutes = 300000 milliseconds)
      final timeoutOptions = js_util.jsify({'timeout': 300000});

      // Call the httpsCallable method with timeout options
      final callable = js_util.callMethod(functions, 'httpsCallable', [functionName, timeoutOptions]);
      
      // Call the function and handle the promise
      final promise = js_util.callMethod(callable, 'call', [jsData]);
      
      // Handle the response
      js_util.promiseToFuture(promise).then((result) {
        // Extract the data from the result
        final resultData = js_util.getProperty(result, 'data');
        final Map<String, dynamic> dartResult = 
            Map<String, dynamic>.from(js_util.dartify(resultData) as Map);
        completer.complete(dartResult);
      }).catchError((error) {
        print('Web: Firebase Function error: $error');
        completer.completeError(error);
      });
      
      return completer.future;
    } catch (e) {
      print('Web: Error calling Firebase Function: $e');
      throw Exception('Failed to call Firebase Function on web: $e');
    }
  }
}
