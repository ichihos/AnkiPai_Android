import 'package:anki_pai/models/memory_technique.dart';
import 'package:anki_pai/services/ai_service_interface.dart';

/// オフラインモード用のダミーAIサービス
/// オフラインモード時にGeminiServiceの代わりに使用される
class DummyAIService implements AIServiceInterface {
  @override
  bool get hasValidApiKey => false;

  DummyAIService() {
    print('DummyAIService initialized for offline mode');
  }
  
  @override
  Future<String> generateText({
    required String prompt,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }
  
  @override
  Future<String> getFeedback(String userExplanation, {String? contentTitle, String? contentText}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }
  
  @override
  Future<Map<String, dynamic>> detectMultipleItems(String content) async {
    return {
      'status': 'error',
      'message': 'オフラインモードでは利用できません',
      'items': [],
    };
  }
  
  @override
  Future<String> generateThinkingModeExplanation({
    required String content,
    String? title,
  }) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }
  
  @override
  Future<List<Map<String, dynamic>>> generateMemoryTechniquesForMultipleItems(
      List<dynamic> items,
      {Function(double progress, int processedItems, int totalItems)?
          progressCallback,
      bool isQuickDetection = false,
      int? itemCount,
      String? rawContent,
      bool isThinkingMode = false,
      bool isMultiAgentMode = false,
      int batchOffset = 0}) async {
    // オフラインモードでは空のリストを返す
    if (progressCallback != null) {
      progressCallback(1.0, 0, 0); // 完了を通知
    }
    return [];
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateMemoryTechnique(String content, String type, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateMemoryTechniqueWithFeedback(String content, String type, String feedback, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateFlashcards(String content, {int count = 5, String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateFlashcardsWithFeedback(String content, String feedback, {int count = 5, String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateExplanation(String content, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateExplanationWithFeedback(String content, String feedback, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateQuiz(String content, {int count = 5, String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateQuizWithFeedback(String content, String feedback, {int count = 5, String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateSummary(String content, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateSummaryWithFeedback(String content, String feedback, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateMindMap(String content, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateMindMapWithFeedback(String content, String feedback, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateWithMultiAgent(String content, String type, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateWithMultiAgentFeedback(String content, String type, String feedback, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateWithThinking(String content, String type, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> generateWithThinkingFeedback(String content, String type, String feedback, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<String> extractTextFromImage(String base64Image, {String? language}) async {
    return 'オフラインモードでは利用できません。インターネット接続を確認してください。';
  }

  // AIServiceInterfaceには定義されていないが、実装クラスで必要なメソッド
  Future<MemoryTechnique> parseMemoryTechnique(String jsonString) async {
    // オフラインモードでは空のメモリーテクニックを返す
    return MemoryTechnique(
      name: 'オフラインモード',
      description: 'オフラインモードでは利用できません。インターネット接続を確認してください。',
      id: 'offline',
      type: 'offline',
      isPublic: false,
    );
  }
}
