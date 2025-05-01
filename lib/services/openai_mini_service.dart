import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:get_it/get_it.dart';
import 'vision_service.dart';

/// Gemini Flash API を使用した OCR サービス
class OpenAIMiniService {
  static const String _modelName =
      'gemini-2.5-flash-preview-04-17'; // Gemini Flash モデル

  // Firebase Functionsの参照
  final HttpsCallable _geminiFunction = FirebaseFunctions.instance
      .httpsCallable('proxyGemini'); // Geminiプロキシー関数を使用

  /// サービスの初期化状態を確認
  Future<bool> initialize() async {
    // Firebase Functionsを使用するため、APIキーは不要
    // Firebase Functionsの設定でキーが管理されている
    return true;
  }

  /// 画像からOCRでテキストを抽出
  Future<Map<String, dynamic>> performOcr(File imageFile) async {
    try {
      // ファイルをバイトとして読み込み
      final bytes = await imageFile.readAsBytes();
      return performOcrFromBytes(bytes);
    } catch (e) {
      print('OpenAI OCRファイル読み込みエラー: $e');
      return _createErrorResponse('画像ファイルの読み込みに失敗しました: $e');
    }
  }

  /// バイトデータからOCRでテキストを抽出し、特別な形式（単語リスト、数式）を検出
  Future<Map<String, dynamic>> performOcrFromBytes(Uint8List imageBytes) async {
    try {
      print('画像バイトデータを処理します (サイズ: ${imageBytes.length} bytes)');

      // 画像をbase64にエンコード
      final base64Image = base64Encode(imageBytes);
      print('Base64エンコード完了 (長さ: ${base64Image.length})');

      // システムプロンプト：OCRと特別な形式の検出
      const systemPrompt = '''
あなたは記憶法生成の専門家に情報を渡すOCRアシスタントです。画像内のテキストを正確に抽出し、暗記法生成に適した形で返してください。
読み取った情報量が多い場合は、重要でユーザーが暗記したい部分だけを返してください。
以下の特別な形式があれば検出し、フォーマットを保持してください：

1. 単語リスト（例：英単語：意味：追加情報）
2. 数式（必ず \$ 記号で数式を囲むLaTeX形式で表記してください。例: \$E=mc^2\$ や \$\\frac{a}{b}\$ など）

抽出したテキストだけを返し、自分の言葉や分析を追加しないでください。追加解説は不要です。
単語リストや数式の構造が明らかな場合は、それを適切に整形して返してください。
【重要】単語リスト等の場合、各単語（見出し）の先頭にだけ - をつけること。
数式が認識された場合、必ず \$ 記号で囲んでください。インライン数式は \$...\$ 、ブロック数式は \$\$...\$\$ で囲んでください。
''';

      // Geminiモデルにリクエスト
      // Geminiのメッセージ形式に変換
      final contents = [
        {
          'role': 'user',
          'parts': [
            {
              'text': '$systemPrompt\n\n画像内のテキストを抽出してください。単語リストや数式があれば適切に構造化してください。'
            },
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image}
            }
          ]
        }
      ];

      print('Gemini FlashでOCRを実行します（失敗時はGoogle Visionを使用）');

      try {
        // Firebase Functions経由でリクエストを送信
        final requestData = {
          'model': _modelName,
          'contents': contents,
          'generation_config': {
            'max_output_tokens': 1500,
            'temperature': 0.1,
          }
        };

        print(
            'リクエスト開始（サイズ）: ${imageBytes.length} bytes, タイムスタンプ: ${DateTime.now().toIso8601String()}');

        // Firebase Functions経由でGemini APIを呼び出す
        final result = await _geminiFunction.call({'data': requestData});
        final responseData = result.data;

        print('レスポンス受信成功');

        // レスポンスからテキストを抽出 (Geminiの形式に合わせて変更)
        if (responseData != null && responseData['text'] is String) {
          final extractedText = responseData['text'] as String;

          print(
              '抽出されたテキスト (長さ: ${extractedText.length}): ${extractedText.substring(0, extractedText.length > 100 ? 100 : extractedText.length)}...');

          // 特定のパターンを検出
          final Map<String, dynamic> detectionResult =
              _detectSpecialPatterns(extractedText);

          return {
            'text': extractedText,
            'success': true,
            'isVocabularyList': detectionResult['isVocabularyList'],
            'hasMathFormula': detectionResult['hasMathFormula'],
          };
        }

        // テキストが検出されなかった場合
        return _createErrorResponse('画像からテキストを抽出できませんでした');
      } catch (functionError) {
        print('Firebase Functions呼び出しエラー: $functionError');
        print('Gemini API呼び出し中にエラー発生、代替手段へフォールバックします');
        print('エラー種別: ${functionError.runtimeType}');

        // 特定のエラー条件をチェックして詳細表示
        if (functionError.toString().contains('PERMISSION_DENIED')) {
          print('❗権限エラー: Firebase Functionsへのアクセス権限不足');
        } else if (functionError.toString().contains('NOT_FOUND')) {
          print('❗関数エラー: proxyGemini関数が見つかりません');
        } else if (functionError.toString().contains('UNAUTHENTICATED')) {
          print('❗認証エラー: Firebase認証が必要です');
        } else if (functionError.toString().contains('internal')) {
          print('❗内部エラー: Firebase Functions内でエラー発生 - 時間が経ってから再度お試しください');
        } else if (functionError.toString().contains('timeout')) {
          print('❗タイムアウト: リクエストがタイムアウトしました - 画像サイズを小さくして再度お試しください');
        }

        // Google Visionサービスをフォールバックとして使用
        return _tryVisionServiceFallback(imageBytes, functionError);
      }
    } catch (e) {
      print('OCRエラー: $e');
      return _createErrorResponse(e.toString());
    }
  }

  /// 特別なパターンを検出する
  Map<String, dynamic> _detectSpecialPatterns(String text) {
    bool isVocabularyList = false;
    bool hasMathFormula = false;

    // 単語リストの検出
    // コロンで区切られた行が複数ある、または単語：意味の形式がある
    final lines = text.split('\n');
    int colonLines = 0;

    for (final line in lines) {
      if (line.contains(':') && line.split(':').length >= 2) {
        colonLines++;
      }
    }

    // 複数の行にコロンがある場合、単語リストと判断
    if (colonLines >= 3) {
      isVocabularyList = true;
    }

    // 数式の検出
    // TEX記法のパターン
    if (text.contains('\\frac') ||
        text.contains('\\sum') ||
        text.contains('\\int') ||
        text.contains('\\begin{') ||
        text.contains('\\end{') ||
        text.contains('\\mathbb') ||
        text.contains('\\sqrt') ||
        (text.contains('\$') && text.contains('^'))) {
      hasMathFormula = true;
    }

    return {
      'isVocabularyList': isVocabularyList,
      'hasMathFormula': hasMathFormula,
    };
  }

  /// エラーレスポンスの作成
  Map<String, dynamic> _createErrorResponse(String errorMessage) {
    return {
      'success': false,
      'error': errorMessage,
      'text': '',
      'isVocabularyList': false,
      'hasMathFormula': false,
    };
  }

  /// VisionServiceを使用したフォールバック処理
  Future<Map<String, dynamic>> _tryVisionServiceFallback(Uint8List imageBytes,
      [dynamic originalError]) async {
    try {
      // VisionService経由でGoogle Vision APIを使用
      final visionService = GetIt.instance<VisionService>();
      final visionResult =
          await visionService.getTextFromImageBytes(imageBytes);

      if (visionResult.isNotEmpty) {
        print('Google Vision APIからテキストを取得しました: ${visionResult.length} 文字');

        // 特定のパターンを検出
        final Map<String, dynamic> detectionResult =
            _detectSpecialPatterns(visionResult);

        return {
          'text': visionResult,
          'success': true,
          'isVocabularyList': detectionResult['isVocabularyList'],
          'hasMathFormula': detectionResult['hasMathFormula'],
          'usingFallback': true,
          'fallbackService': 'Google Vision API'
        };
      } else {
        return _createErrorResponse('画像からテキストを抽出できませんでした');
      }
    } catch (visionError) {
      print('Google Vision APIによるフォールバックも失敗しました: $visionError');
      final errorMessage = originalError != null
          ? '画像解析中にエラーが発生しました: $originalError. フォールバックエラー: $visionError'
          : 'Google Visionでの画像解析に失敗しました: $visionError';
      return _createErrorResponse(errorMessage);
    }
  }

  /// テキスト補完を実行する
  /// 記憶法生成やテキスト処理に使用（旧MistralService.getCompletionの代替）
  Future<Map<String, dynamic>> getCompletion(String prompt) async {
    try {
      print('Geminiでテキスト補完を実行します');

      // Geminiリクエストの形式で送信
      final requestData = {
        'model': _modelName,
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generation_config': {
          'max_output_tokens': 500,
          'temperature': 0.5,
        }
      };

      print('テキスト補完リクエスト送信');

      // Firebase Functions経由でリクエストを送信
      final result = await _geminiFunction.call({'data': requestData});

      // レスポンスを処理
      final responseData = result.data;
      if (responseData != null && responseData['text'] is String) {
        final text = responseData['text'] as String;
        return {
          'text': text,
          'success': true,
        };
      }

      return _createErrorResponse('テキスト生成中にエラーが発生しました');
    } catch (e) {
      print('テキスト補完エラー: $e');
      return _createErrorResponse('テキスト処理中にエラーが発生しました: $e');
    }
  }
}
