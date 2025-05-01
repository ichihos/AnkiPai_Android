/// AI service interface to abstract different AI providers
abstract class AIServiceInterface {
  bool get hasValidApiKey;

  /// テキスト生成のためのAPI呼び出しを行います
  Future<String> generateText({
    required String prompt,
    String model,
    double temperature,
    int maxTokens,
  });

  /// AIによるユーザーの暗記法説明評価
  Future<String> getFeedback(String userExplanation,
      {String? contentTitle, String? contentText});

  /// 入力内容から複数の項目を検出します
  Future<Map<String, dynamic>> detectMultipleItems(String content);

  /// 複数項目に対して個別に暗記法を生成します
  /// [progressCallback] 処理の進行状況を報告するコールバック関数（0.0～1.0の値で進捗率を示す）
  /// [isThinkingMode] 考え方モードかどうかを示すフラグ
  /// [isMultiAgentMode] マルチエージェントモードかどうかを示すフラグ
  Future<List<Map<String, dynamic>>> generateMemoryTechniquesForMultipleItems(
      List<dynamic> items,
      {Function(double progress, int processedItems, int totalItems)?
          progressCallback,
      bool isQuickDetection = false,
      int? itemCount,
      String? rawContent,
      bool isThinkingMode = false,
      bool isMultiAgentMode = false,
      int batchOffset = 0});

  /// 「考え方モード」で内容の本質を捕えた簡潔な説明を生成します
  Future<String> generateThinkingModeExplanation({
    required String content,
    String? title,
  });
}
