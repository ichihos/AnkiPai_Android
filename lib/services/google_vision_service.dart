import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Google Cloud Vision APIを使用して画像解析を行うサービス
class GoogleVisionService {
  static const String _baseUrl =
      'https://vision.googleapis.com/v1/images:annotate';
  bool _isInitialized = false;
  bool _hasValidApiKey = false;
  String? _apiKey;

  /// プラットフォーム別のAPIキーを取得
  String? get apiKey {
    if (_apiKey != null) {
      return _apiKey;
    }

    // プラットフォームごとに異なるAPIキーを使用
    if (kIsWeb) {
      return dotenv.env['GOOGLE_BROWSER_KEY'];
    } else if (Platform.isIOS) {
      return dotenv.env['GOOGLE_IOS_KEY'];
    } else if (Platform.isAndroid) {
      return dotenv.env['GOOGLE_ANDROID_KEY'];
    }

    // デフォルトはブラウザキーを返す
    return dotenv.env['GOOGLE_BROWSER_KEY'];
  }

  /// サービスの初期化状態を確認
  Future<bool> initialize() async {
    if (_isInitialized) {
      return _hasValidApiKey;
    }

    try {
      final key = apiKey;
      if (key == null || key.isEmpty) {
        print('Google Cloud Vision API key was not found in .env file');
        _isInitialized = true;
        _hasValidApiKey = false;
        return false;
      }

      _apiKey = key;
      _isInitialized = true;
      _hasValidApiKey = true;
      return true;
    } catch (e) {
      print('Failed to initialize Google Cloud Vision API: $e');
      _isInitialized = true;
      _hasValidApiKey = false;
      return false;
    }
  }

  /// 画像からOCRでテキストを抽出
  Future<Map<String, dynamic>> performOcr(File imageFile) async {
    if (!await initialize()) {
      return _createErrorResponse('Google Cloud Vision APIの設定が必要です');
    }

    try {
      // ファイルをバイトとして読み込み
      final bytes = await imageFile.readAsBytes();
      return performOcrFromBytes(bytes);
    } catch (e) {
      print('Vision OCRファイル読み込みエラー: $e');
      return _createErrorResponse('画像ファイルの読み込みに失敗しました: $e');
    }
  }

  /// バイトデータからOCRでテキストを抽出
  Future<Map<String, dynamic>> performOcrFromBytes(Uint8List imageBytes) async {
    if (!await initialize()) {
      return _createErrorResponse('Google Cloud Vision APIの設定が必要です');
    }

    try {
      print('画像バイトデータを処理します (サイズ: ${imageBytes.length} bytes)');

      // 画像をbase64にエンコード
      final base64Image = base64Encode(imageBytes);
      print('Base64エンコード完了 (長さ: ${base64Image.length})');

      // 画像サイズの最適化（必要に応じて実装）
      // Google Vision APIの制限：10MB以下、画像の最大サイズは20MP

      // Vision APIリクエストボディの作成
      final requestBody = {
        'requests': [
          {
            'image': {'content': base64Image},
            'features': [
              {'type': 'TEXT_DETECTION', 'maxResults': 10}
            ],
            'imageContext': {
              'languageHints': ['ja', 'en'] // 日本語と英語の認識に最適化
            }
          }
        ]
      };

      // APIリクエストを送信
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        // UTF-8で明示的にデコードして文字化けを防止
        final responseBody = utf8.decode(response.bodyBytes);
        final result = jsonDecode(responseBody);
        print('Vision OCR API レスポンス受信');

        // レスポンスからテキストを抽出
        final responses = result['responses'];
        if (responses != null && responses.isNotEmpty) {
          final firstResponse = responses[0];

          // フルテキスト検出（全体のテキスト）
          final textAnnotations = firstResponse['textAnnotations'];
          if (textAnnotations != null && textAnnotations.isNotEmpty) {
            final extractedText = textAnnotations[0]['description'] ?? '';

            print(
                '抽出されたテキスト (長さ: ${extractedText.length}): ${extractedText.substring(0, extractedText.length > 100 ? 100 : extractedText.length)}...');

            return {
              'text': extractedText,
              'success': true,
            };
          }
        }

        // テキストが検出されなかった場合
        return {
          'text': '',
          'success': true,
        };
      } else {
        print('Vision OCR API error: ${response.statusCode}');
        print('Error response: ${response.body}');
        return _createErrorResponse(
            'Vision OCR APIエラー: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Vision OCRエラー: $e');
      return _createErrorResponse(e.toString());
    }
  }


  /// エラーレスポンスを生成
  Map<String, dynamic> _createErrorResponse(String errorMessage) {
    return {
      'text': '',
      'success': false,
      'error': errorMessage,
    };
  }
}
