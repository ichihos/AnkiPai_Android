import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:anki_pai/providers/language_provider.dart';

/// Utility class for language-related functions
class LanguageUtils {
  /// Gets the current language prompt based on the app's language setting
  static String getCurrentLanguagePrompt(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    return languageProvider.aiLanguagePrompt;
  }
  
  /// Static method to get the language prompt when context is not available
  /// This is a fallback and should be used only when BuildContext is not available
  static Future<String> getLanguagePromptFromPrefs() async {
    final provider = LanguageProvider();
    await Future.delayed(Duration.zero); // Allow provider to initialize
    return provider.aiLanguagePrompt;
  }

  /// Returns a language instruction to be added to AI prompts
  static String getLanguageInstruction(BuildContext? context) {
    if (context != null) {
      try {
        return getCurrentLanguagePrompt(context);
      } catch (e) {
        // Fall back to the default language if context doesn't have the provider
        return 'Respond in the same language as this prompt';
      }
    } else {
      // When context is not available, provide a general instruction
      return 'Respond in the same language as this prompt';
    }
  }
}
