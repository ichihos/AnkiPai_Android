import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// OpenAI 4.1 mini API を使用した OCR サービス
/// Firebase Functions を通じて安全に API アクセスを行う
class OpenAIService {
  bool _isInitialized = false;
  static const String _modelName = 'gpt-4.1-mini'; // OpenAI 4.1 mini モデル
  // Firebase Functions インスタンス
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// サービスの初期化状態を確認
  Future<bool> initialize() async {
    if (_isInitialized) {
      return true;
    }

    try {
      // Firebase 認証確認
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('ユーザーが認証されていません');
        return false;
      }
      
      _isInitialized = true;
      return true;
    } catch (e) {
      print('OpenAI サービス初期化エラー: $e');
      return false;
    }
  }

  /// 画像からOCRでテキストを抽出
  Future<Map<String, dynamic>> performOcr(File imageFile) async {
    if (!await initialize()) {
      return _createErrorResponse('認証が必要です');
    }

    try {
      // ファイルをバイトとして読み込み
      final bytes = await imageFile.readAsBytes();
      return performOcrFromBytes(bytes);
    } catch (e) {
      print('OpenAI OCRファイル読み込みエラー: $e');
      return _createErrorResponse('画像ファイルの読み込みに失敗しました: $e');
    }
  }

  /// バイトデータからOCRでテキストを抽出
  Future<Map<String, dynamic>> performOcrFromBytes(Uint8List imageBytes) async {
    if (!await initialize()) {
      return _createErrorResponse('認証が必要です');
    }

    try {
      print('画像バイトデータを処理します (サイズ: ${imageBytes.length} bytes)');

      // 画像をbase64にエンコード
      final base64Image = base64Encode(imageBytes);
      print('Base64エンコード完了 (長さ: ${base64Image.length})');

      // GPT-4.1 mini モデルにリクエスト用のメッセージを作成
      final messages = [
        {
          'role': 'system',
          'content': '次の画像からテキストを抽出してください。レイアウトは保持せず、純粋なテキストのみを返してください。'
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': '画像のテキストを抽出してください。',
            },
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
              },
            }
          ]
        }
      ];

      // Firebase Function を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('proxyOpenAI');
      final requestData = {
        'endpoint': 'chat/completions',
        'data': {
          'model': _modelName,
          'messages': messages,
          'max_tokens': 1000,
          'temperature': 0.1,
        }
      };
      
      final result = await callable.call(requestData);
      final data = result.data;
      print('OpenAI OCR API レスポンス受信');

      // レスポンスからテキストを抽出
      final choices = data['choices'];
      if (choices != null && choices.isNotEmpty) {
        final content = choices[0]['message']['content'];
        if (content != null) {
          print(
              '抽出されたテキスト (長さ: ${content.length}): ${content.substring(0, content.length > 100 ? 100 : content.length)}...');

          return {
            'text': content,
            'success': true,
          };
        }
      }

      // テキストが検出されなかった場合
      return {
        'text': '',
        'success': true,
      };
    } catch (e) {
      print('OpenAI OCRエラー: $e');
      return _createErrorResponse(e.toString());
    }
  }

  /// OpenAI の Chat API を使用してテキスト生成を実行
  Future<Map<String, dynamic>> getCompletion(String prompt) async {
    if (!await initialize()) {
      return _createErrorResponse('認証が必要です');
    }

    try {
      // Chat API のリクエスト形式
      final messages = [
        {'role': 'user', 'content': prompt}
      ];

      // Firebase Function を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('proxyOpenAI');
      final requestData = {
        'endpoint': 'chat/completions',
        'data': {
          'model': _modelName,
          'messages': messages,
          'temperature': 0.2,
          'max_tokens': 2000,
        }
      };
      
      final result = await callable.call(requestData);
      final data = result.data;
      
      // レスポンスからテキストを抽出
      final choices = data['choices'];
      if (choices != null && choices.isNotEmpty) {
        final content = choices[0]['message']['content'];
        if (content != null) {
          return {
            'success': true,
            'text': content,
          };
        }
      }

      return _createErrorResponse('無効なレスポンス形式');
    } catch (e) {
      return _createErrorResponse('OpenAIリクエストエラー: $e');
    }
  }

  /// 数式OCR特化処理
  Future<Map<String, dynamic>> performMathOcr(Uint8List imageBytes) async {
    if (!await initialize()) {
      return _createErrorResponse('認証が必要です');
    }

    try {
      // 画像をbase64にエンコード
      final base64Image = base64Encode(imageBytes);

      // 数式専用のプロンプト
      final messages = [
        {
          'role': 'system',
          'content': '次の画像から数式を抽出し、LaTeX形式で返してください。複数の数式がある場合は、各数式を改行で区切ってください。'
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': 'この画像から数式を抽出してLaTeX形式で提供してください。',
            },
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
              },
            }
          ]
        }
      ];

      // Firebase Function を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('proxyOpenAI');
      final requestData = {
        'endpoint': 'chat/completions',
        'data': {
          'model': _modelName,
          'messages': messages,
          'max_tokens': 1000,
          'temperature': 0.1,
        }
      };
      
      final result = await callable.call(requestData);
      final data = result.data;

      final choices = data['choices'];
      if (choices != null && choices.isNotEmpty) {
        final content = choices[0]['message']['content'];
        if (content != null) {
          return {
            'text': content,
            'success': true,
          };
        }
      }

      return {
        'text': '',
        'success': true,
      };
    } catch (e) {
      return _createErrorResponse('OpenAI数式OCRエラー: $e');
    }
  }

  /// 英単語帳OCR結果を構造化する
  Future<Map<String, dynamic>> structureVocabulary(String rawText) async {
    if (!await initialize()) {
      return _createErrorResponse('認証が必要です');
    }

    try {
      // 単語帳構造化用のプロンプト
      final prompt = '''
      次の英単語帳OCR結果から単語と意味を抽出し、以下のシンプルな形式で返してください。
      
      非常に重要: JSONではなく、単語と意味のペアをプレーンテキストで返してください。
      バックティックやマークダウン要素は含めないでください。
      
      以下の形式で返答してください（各行は「単語:意味」とコロンで区切られ、リストはセミコロンで区切られます）:
      
      wash:洗う;
      volume:音量, 分量;
      listen:聞く;
      
      各単語に対して意味はカンマ区切りで一行にして、最後にセミコロンを付けてください。
      形式に従っていない行や余分な説明は含めないでください。
      
      OCR結果:
      $rawText
      ''';

      final messages = [
        {'role': 'user', 'content': prompt}
      ];

      // Firebase Function を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('proxyOpenAI');
      final requestData = {
        'endpoint': 'chat/completions',
        'data': {
          'model': _modelName,
          'messages': messages,
          'temperature': 0.2,
          'max_tokens': 2000,
        }
      };
      
      final result = await callable.call(requestData);
      final data = result.data;

      final choices = data['choices'];
      if (choices != null && choices.isNotEmpty) {
        final content = choices[0]['message']['content'];
        if (content != null) {
          return {
            'success': true,
            'text': content,
          };
        }
      }

      return _createErrorResponse('無効なレスポンス形式');
    } catch (e) {
      return _createErrorResponse('単語帳構造化エラー: $e');
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
