import 'dart:io';
import 'dart:convert';
import 'package:get_it/get_it.dart';
import 'vision_service.dart';
import 'ai_service_interface.dart';
import 'gemini_service.dart';

/// 画像解析サービス
/// Vision APIを使って画像を解析し、OpenAI APIで投稿文を生成する
class ImageAnalysisService {
  late final VisionService _visionService;
  late final AIServiceInterface _aiService;
  bool _servicesAvailable = true;

  ImageAnalysisService() {
    try {
      _visionService = GetIt.instance<VisionService>();
      _aiService = GetIt.instance<GeminiService>();
      _servicesAvailable = true;
    } catch (e) {
      print('Failed to initialize ImageAnalysisService: $e');
      _servicesAvailable = false;
    }
  }

  /// 画像を解析して情報を抽出し、AIによる投稿文を生成する
  Future<Map<String, dynamic>> analyzeImageAndGenerateContent(
      File imageFile) async {
    if (!_servicesAvailable) {
      return {
        'success': false,
        'error': 'AI分析サービスが利用できません',
      };
    }

    try {
      // Vision APIで画像を解析
      final analysisResult = await _visionService.analyzeImage(imageFile);

      if (!analysisResult['success']) {
        return {
          'success': false,
          'error': analysisResult['error'] ?? '画像の解析に失敗しました',
        };
      }

      // APIキーが設定されていない場合のハンドリング
      if (!_aiService.hasValidApiKey) {
        return {
          'success': true,
          'title': '画像メモ',
          'content': 'OpenAI APIキーが設定されていないため、AIによる説明を生成できません。',
          'labels': analysisResult['labels'] ?? [],
          'extractedText': analysisResult['text'] ?? '',
          'memoryTechniques': [],
        };
      }

      // 解析結果から投稿文を生成
      final content = await _generateContentFromAnalysis(analysisResult);

      // AIが提案した暗記法を変換
      final techniques = await _generateMemoryTechniquesForImage(
          analysisResult['labels'], analysisResult['text'], content);

      return {
        'success': true,
        'title': content['title'],
        'content': content['description'],
        'labels': analysisResult['labels'],
        'extractedText': analysisResult['text'],
        'memoryTechniques': techniques,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 画像解析結果からAIによる投稿文を生成
  Future<Map<String, String>> _generateContentFromAnalysis(
      Map<String, dynamic> analysis) async {
    final labels = analysis['labels'] as List<String>;
    final extractedText = analysis['text'] as String;

    // ラベルとテキスト情報を元にプロンプトを構成
    final prompt = '''
あなたは画像解析アシスタントです。以下の情報は画像解析の結果です。
このデータを元に、この画像の内容を説明する日本語の文章を作成してください。

検出されたラベル:
${labels.join(', ')}

抽出されたテキスト:
${extractedText.isEmpty ? 'なし' : extractedText}

出力形式:
1. タイトル（20文字以内）
2. 説明文（150文字以内）

JSON形式で返してください:
{
  "title": "タイトル",
  "description": "説明文"
}
''';

    try {
      final response = await _aiService.generateText(
        prompt: prompt,
        temperature: 0.7,
        maxTokens: 300,
      );

      // APIキーエラーの場合
      if (response.contains('APIキーが設定されていない')) {
        return {
          'title': '画像メモ',
          'description': 'OpenAI APIキーが設定されていないため、AIによる説明を生成できません。',
        };
      }

      // JSONをパース
      try {
        final jsonResponse = _parseJsonResponse(response);
        return {
          'title': jsonResponse['title'] ?? '画像メモ',
          'description': jsonResponse['description'] ?? '説明情報を生成できませんでした',
        };
      } catch (e) {
        print('JSON解析エラー: $e');
        // JSONパースに失敗した場合、テキスト全体をdescriptionとして返す
        return {
          'title': '画像メモ',
          'description': response.length > 150
              ? '${response.substring(0, 147)}...'
              : response,
        };
      }
    } catch (e) {
      print('テキスト生成エラー: $e');
      return {
        'title': '画像メモ',
        'description': 'AIによる説明を生成できませんでした',
      };
    }
  }

  /// レスポンスからJSONを抽出するヘルパーメソッド
  Map<String, dynamic> _parseJsonResponse(String text) {
    // JSONの開始と終了の位置を探す
    final startBrace = text.indexOf('{');
    final endBrace = text.lastIndexOf('}');

    if (startBrace == -1 || endBrace == -1 || startBrace > endBrace) {
      throw Exception('有効なJSONフォーマットが見つかりません');
    }

    // JSONの部分だけを抽出
    final jsonString = text.substring(startBrace, endBrace + 1);
    return json.decode(jsonString);
  }

  /// 画像データに基づいた暗記法を生成
  Future<List<Map<String, String>>> _generateMemoryTechniquesForImage(
      List<String> labels,
      String extractedText,
      Map<String, String> content) async {
    final prompt = '''
あなたは暗記法専門のAIアシスタントです。以下の情報を元に、3つの異なる暗記法を考案してください。

画像に含まれる要素:
${labels.join(', ')}

画像から抽出されたテキスト:
${extractedText.isEmpty ? 'なし' : extractedText}

画像の内容説明:
${content['description']}

暗記法は以下の形式のJSON配列で提供してください:
[
  {
    "name": "暗記法の名前（例：「イメージ連想法」）",
    "description": "暗記法の詳細な説明と手順"
  },
  ...
]
''';

    try {
      final response = await _aiService.generateText(
        prompt: prompt,
        temperature: 0.8,
        maxTokens: 800,
      );

      try {
        // JSONの開始と終了の位置を探す
        final startBracket = response.indexOf('[');
        final endBracket = response.lastIndexOf(']');

        if (startBracket == -1 ||
            endBracket == -1 ||
            startBracket > endBracket) {
          // 有効なJSONフォーマットがない場合はデフォルト値を返す
          return _getDefaultMemoryTechniques();
        }

        // JSONの部分だけを抽出してパース
        final jsonString = response.substring(startBracket, endBracket + 1);
        final List<dynamic> parsedTechniques = json.decode(jsonString);

        // 解析したJSONから適切なマップに変換
        final List<Map<String, String>> techniques = [];
        for (var tech in parsedTechniques) {
          if (tech is Map) {
            techniques.add({
              'name': tech['name']?.toString() ?? '暗記法',
              'description': tech['description']?.toString() ?? '説明がありません',
            });
          }
        }

        return techniques.isNotEmpty
            ? techniques
            : _getDefaultMemoryTechniques();
      } catch (e) {
        print('暗記法JSON解析エラー: $e');
        // デフォルト値を返す
        return _getDefaultMemoryTechniques();
      }
    } catch (e) {
      print('暗記法生成エラー: $e');
      return _getDefaultMemoryTechniques();
    }
  }

  /// デフォルトの暗記法を返す
  List<Map<String, String>> _getDefaultMemoryTechniques() {
    return [
      {
        'name': '視覚記憶法',
        'description': '画像の特徴的な要素に注目し、それらを鮮明に脳内でイメージすることで記憶を定着させましょう。',
      },
      {
        'name': 'キーワード連想法',
        'description': '画像から抽出した重要なキーワードを相互に関連付け、ストーリーや文脈を作成して記憶を強化します。',
      }
    ];
  }
}
