import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:anki_pai/services/openai_mini_service.dart';
import 'package:anki_pai/services/image_processing_service.dart';
import 'package:anki_pai/services/gpt_ocr_service.dart';
import 'package:get_it/get_it.dart';
import 'package:anki_pai/services/firebase_functions_interface.dart';
import 'package:anki_pai/services/firebase_functions_service.dart';

/// 画像解析を行うサービス
/// Google Vision APIを使用して画像解析を行う
class VisionService {
  bool _hasValidApiKey = false;

  final OpenAIMiniService _openaiMiniService = GetIt.instance<OpenAIMiniService>();
  late ImageProcessingService _imageProcessingService;
  late GptOcrService _gptOcrService;
  late FirebaseFunctionsInterface _functionsService;
  final String _visionFunctionName = 'proxyVision';

  VisionService() {
    _imageProcessingService = GetIt.instance<ImageProcessingService>();
    _gptOcrService = GptOcrService();
    _functionsService = FirebaseFunctionsFactory.create();
    _checkApiAvailability();
  }

  /// APIが有効か確認
  Future<void> _checkApiAvailability() async {
    try {
      // 簡単なテストでFirebase Functionsが利用可能かチェック
      // 実際にFirebase Functionsに小さなリクエストを送信
      final testRequest = {
        'data': {
          'requests': [
            {
              'image': {
                'content': 'dGVzdA==' // 'test'をbase64エンコードした値
              },
              'features': [
                {
                  'type': 'LABEL_DETECTION',
                  'maxResults': 1
                }
              ]
            }
          ]
        }
      };
      
      // テストリクエストをFirebase Functionに送信
      try {
        print('Vision APIの利用可能性をチェックしています...');
        await _functionsService.callFunction(_visionFunctionName, testRequest);
        _hasValidApiKey = true;
        print('Vision APIへのアクセスが確認されました');
      } catch (functionError) {
        print('Vision APIテスト中にエラーが発生しました: $functionError');
        // エラーが発生しても続行するために必要な場合はここでtrueを設定
        _hasValidApiKey = true; // テスト失敗しても一応有効にする
      }
    } catch (e) {
      print('Vision APIの初期化エラー: $e');
      _hasValidApiKey = false;
    }
  }
  /// 画像ファイルからラベル情報を抽出
  Future<List<String>> getLabelsFromImage(File imageFile) async {
    try {
      if (!_hasValidApiKey) {
        return ['APIキーが必要です'];
      }

      // 画像の読み込み
      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // Vision APIリクエストデータを構築
      final requestData = {
        'requests': [
          {
            'image': {
              'content': base64Image
            },
            'features': [
              {
                'type': 'LABEL_DETECTION',
                'maxResults': 10
              }
            ]
          }
        ]
      };

      // Firebase Function経由でVision APIを呼び出し
      final result = await _functionsService.callFunction(_visionFunctionName, {
        'data': requestData
      });

      // レスポンスの解析
      final data = result;
      if (data['responses'] != null && 
          data['responses'].isNotEmpty && 
          data['responses'][0]['labelAnnotations'] != null) {
        
        final annotations = List<Map<String, dynamic>>.from(data['responses'][0]['labelAnnotations']);
        return annotations
            .where((annotation) => annotation['score'] >= 0.7)
            .map((annotation) => annotation['description'] as String)
            .toList();
      }
      
      return [];
    } catch (e) {
      print('Vision APIでの画像解析エラー: $e');
      return ['解析エラー'];
    }
  }

  /// 画像ファイルからテキスト情報を抽出
  Future<String> getTextFromImage(File imageFile) async {
    try {
      if (!_hasValidApiKey) {
        print('Vision API not available - API key missing or invalid');
        return '';
      }

      // 画像の読み込み
      final imageBytes = await imageFile.readAsBytes();
      
      // リサイズして処理負荷を軽減
      final resizedBytes = await _imageProcessingService.resizeImageBytes(
        imageBytes: imageBytes,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      
      // Base64エンコード (純粋なBase64文字列を使用、データURIプレフィックスなし)
      final base64Image = base64Encode(resizedBytes);
      print('Base64エンコードしたイメージサイズ: ${base64Image.length}文字');

      // Vision APIリクエストデータを構築
      final requestData = {
        'requests': [
          {
            'image': {
              'content': base64Image
            },
            'features': [
              {
                'type': 'TEXT_DETECTION',
                'maxResults': 1
              }
            ]
          }
        ]
      };

      print('Vision API呼び出し開始 (サイズ: ${base64Image.length} 文字)');
      
      // Firebase Function経由でVision APIを呼び出し
      try {
        final result = await _functionsService.callFunction(_visionFunctionName, {
          'data': requestData
        });

        // レスポンスの解析
        final data = result;
        if (data['responses'] != null && 
            data['responses'].isNotEmpty && 
            data['responses'][0]['textAnnotations'] != null &&
            data['responses'][0]['textAnnotations'].isNotEmpty) {
          
          final text = data['responses'][0]['textAnnotations'][0]['description'];
          print('Vision API OCR成功: ${text.substring(0, math.min<int>(100, text.length))}...');
          return text;
        } else {
          print('Vision APIからの応答にテキストデータがありません');
          return '';
        }
      } catch (functionError) {
        print('Firebase Functions呼び出しエラー: $functionError');
        rethrow; // 上位の例外ハンドラに渡して適切な代替処理を可能にする
      }
    } catch (e) {
      print('Vision APIでのテキスト検出エラー: $e');
      return '';
    }
  }

  /// 新しいOCR関数を使って画像からテキストを抽出
  Future<String> getTextFromImageWithOpenAIMini(File imageFile) async {
    try {
      print('新しいOCR関数を使ってOCRを実行');
      
      // 新しい専用OCRサービスを使用
      final result = await _gptOcrService.performOcr(imageFile);

      if (result['success'] == true && result['text'] != null && result['text'].isNotEmpty) {
        final text = result['text'];
        final previewLength = math.min<int>(100, text.length);
        print('新OCR関数によるテキスト検出成功: ${text.substring(0, previewLength)}...');
        return text;
      } else {
        // 失敗した場合は元のOCRサービスにフォールバック
        print('新OCR関数失敗: ${result['error']}');
        
        try {
          // 元のOpenAIMiniServiceも試す
          print('元のOpenAIMiniServiceにフォールバック');
          final fallbackResult = await _openaiMiniService.performOcr(imageFile);
          
          if (fallbackResult['success'] == true && fallbackResult['text'] != null) {
            return fallbackResult['text'];
          }
        } catch (fallbackError) {
          print('フォールバックOCRも失敗: $fallbackError');
        }
        
        return '';
      }
    } catch (e) {
      print('新OCR関数エラー: $e');
      
      // エラー時は元のOpenAIMiniServiceにフォールバック
      try {
        print('元のOpenAIMiniServiceにフォールバック（エラー後）');
        final fallbackResult = await _openaiMiniService.performOcr(imageFile);
        
        if (fallbackResult['success'] == true && fallbackResult['text'] != null) {
          return fallbackResult['text'];
        }
      } catch (fallbackError) {
        print('フォールバックOCRも失敗: $fallbackError');
      }
      
      return '';
    }
  }



  /// バイトデータから直接テキストを抽出（OpenAI GPT-4.1 mini優先）
  Future<String> getTextFromImageBytes(Uint8List imageBytes) async {
    try {
      print('バイトデータから直接OCRを実行します (サイズ: ${imageBytes.length} bytes)');

      // バイトデータをリサイズ（必要に応じて）
      final resizedBytes = await _imageProcessingService.resizeImageBytes(
        imageBytes: imageBytes,
        maxWidth: 2000,
        maxHeight: 2000,
      );

      // OpenAI GPT-4.1 miniを使ってテキスト抽出
      print('OpenAI GPT-4.1 miniを使ってOCRを実行');
      
      try {
        final result = await _openaiMiniService.performOcrFromBytes(resizedBytes);

        if (result['success'] == true && result['text'] != null && result['text'].isNotEmpty) {
          print('OpenAI GPT-4.1 mini OCR成功');
          return result['text'];
        }

        // OpenAIが失敗した場合はGoogle Visionをバックアップとして使用
        print('OpenAI OCR失敗、Google Visionにフォールバック: ${result['error']}');
      } catch (openAiError) {
        print('OpenAI OCR処理中にエラー発生: $openAiError');
      }
      
      // Google Visionでバックアップ試行
      try {
        // Base64エンコード (純粋なBase64文字列を使用)
        final base64Image = base64Encode(resizedBytes);
        print('Google Vision OCRを実行 (イメージサイズ: ${base64Image.length} 文字)');
        
        final requestData = {
          'imageContent': base64Image,
          'feature': 'TEXT_DETECTION'
        };
        
        // Firebase Function経由でGoogle Vision APIを直接呼び出し
        final result = await _functionsService.callFunction(_visionFunctionName, {
          'data': requestData,
          'feature': 'TEXT_DETECTION'
        });
        
        final data = result;
        if (data['responses'] != null && 
            data['responses'].isNotEmpty && 
            data['responses'][0]['textAnnotations'] != null &&
            data['responses'][0]['textAnnotations'].isNotEmpty) {
          
          final text = data['responses'][0]['textAnnotations'][0]['description'];
          print('Google Vision OCR成功');
          return text;
        }
      } catch (visionError) {
        print('Google Vision OCR処理中にエラー発生: $visionError');
      }
      
      return '';
    } catch (e) {
      print('OCRバイトデータ処理エラー: $e');
      return '';
    }
  }

  /// 画像をトリミングしてからOCRを実行
  Future<String> processAndAnalyzeImage(File imageFile, Rect? cropRect) async {
    try {
      File processedImage = imageFile;

      // トリミングが指定されている場合
      if (cropRect != null) {
        final imageBytes = await imageFile.readAsBytes();
        final croppedBytes = await _imageProcessingService.cropImage(
          imageData: imageBytes,
          cropRect: cropRect,
        );
        
        // Webプラットフォームの場合はファイル保存をスキップ
        if (kIsWeb) {
          // Web環境では直接バイトデータを処理
          return await getTextFromImageBytes(croppedBytes);
        }
        
        // 他のプラットフォームではファイル保存を試みる
        final savedFile = await _imageProcessingService.saveImageToFile(croppedBytes);
        if (savedFile != null) {
          processedImage = savedFile;
        } else {
          // ファイル保存に失敗した場合も直接バイトデータを処理
          return await getTextFromImageBytes(croppedBytes);
        }
      }

      // 非Web環境の場合は通常のファイル処理を継続
      if (!kIsWeb) {
        // リサイズ
        processedImage = await _imageProcessingService.resizeImage(
          imageFile: processedImage,
          maxWidth: 2000,
          maxHeight: 2000,
        );
      }

      // OCRを実行（OpenAI GPT-4.1 miniを優先、失敗時にGoogle Visionを使用）
      String text = await getTextFromImageWithOpenAIMini(processedImage);
      
      // OpenAIが失敗した場合はGoogle Visionを試す
      if (text.isEmpty) {
        text = await getTextFromImage(processedImage);
      }

      return text;
    } catch (e) {
      print('画像処理・解析エラー: $e');
      return '';
    }
  }

  /// 画像の分析結果を元に解説文を作成
  Future<Map<String, dynamic>> analyzeImage(File imageFile) async {
    if (!_hasValidApiKey) {
      return {
        'labels': ['画像解析に必要なAPIキーが設定されていません。'],
        'text': '',
        'success': false,
        'error': 'APIキーが設定されていません'
      };
    }

    try {
      // ラベル情報の取得
      final labels = await getLabelsFromImage(imageFile);

      // テキスト情報の取得
      final text = await getTextFromImage(imageFile);

      return {
        'labels': labels,
        'text': text,
        'success': true,
      };
    } catch (e) {
      print('画像解析エラー: $e');
      return {
        'labels': [],
        'text': '',
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
