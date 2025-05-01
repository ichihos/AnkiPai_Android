import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:anki_pai/services/image_processing_service.dart';

/// GPT-4.1 mini を使用したOCR専用サービス
/// Firebase Functions経由でOpenAI APIに画像を送信し、テキストを抽出する
class GptOcrService {
  // Firebase Functionsの参照（新しいOCR専用関数）
  final HttpsCallable _ocrFunction = 
      FirebaseFunctions.instance.httpsCallable('performOcr');
  
  late ImageProcessingService _imageProcessingService;

  GptOcrService() {
    _imageProcessingService = GetIt.instance<ImageProcessingService>();
  }

  /// ファイルからOCRを実行
  Future<Map<String, dynamic>> performOcr(File imageFile) async {
    try {
      print('ファイルからOCRを実行: ${imageFile.path}');
      final bytes = await imageFile.readAsBytes();
      return performOcrFromBytes(bytes);
    } catch (e) {
      print('ファイル読み込みエラー: $e');
      return _createErrorResponse('ファイル読み込みエラー: $e');
    }
  }

  /// バイトデータからOCRを実行 - 最適化バージョン
  Future<Map<String, dynamic>> performOcrFromBytes(Uint8List imageBytes) async {
    try {
      print('バイトデータからOCRを実行 (サイズ: ${imageBytes.length} bytes)');
      print('OpenAI GPT-4.1 miniを使ってOCRを実行');
      
      // 画像を小さいサイズにリサイズして高速化
      Stopwatch stopwatch = Stopwatch()..start();
      imageBytes = await _resizeImageIfNeeded(imageBytes);
      print('画像リサイズ処理時間: ${stopwatch.elapsedMilliseconds}ms');
      
      // Base64エンコード
      stopwatch.reset();
      final base64Image = base64Encode(imageBytes);
      print('Base64エンコード完了 (サイズ: ${base64Image.length} 文字, 時間: ${stopwatch.elapsedMilliseconds}ms)');
      
      try {
        // 修正したOCR関数呼び出しパラメータ
        print('GPT-4.1 miniでOCRを実行します（失敗時はGoogle Visionを使用）');
        
        // リクエストタイムスタンプを追加してキャッシュを避ける
        String timestamp = DateTime.now().toIso8601String();
        print('リクエスト開始（サイズ）: ${imageBytes.length} bytes, タイムスタンプ: $timestamp');
        
        stopwatch.reset();
        final result = await _ocrFunction.call({
          'imageData': base64Image,
          'timestamp': timestamp,  // タイムスタンプを追加してキャッシュを避ける
          'fastMode': true,  // 高速モードを有効化
        });
        
        print('OCR API呼び出し時間: ${stopwatch.elapsedMilliseconds}ms');
        
        // レスポンスをパース
        final data = result.data;
        print('OCR処理完了');
        
        if (data != null && data['success'] == true && data['text'] != null) {
          return {
            'success': true,
            'text': data['text'],
            'model': data['model'] ?? 'gpt-4.1-mini',
            'processingTime': stopwatch.elapsedMilliseconds
          };
        } else {
          print('OCR処理でテキストの抽出に失敗: ${data.toString()}');
          return _createErrorResponse('テキスト抽出に失敗しました');
        }
      } catch (e) {
        print('OCR関数呼び出しエラー: $e');
        return _createErrorResponse('OCR処理中にエラーが発生しました: $e');
      }
    } catch (e) {
      print('OCR前処理エラー: $e');
      return _createErrorResponse('画像の前処理に失敗しました: $e');
    }
  }
  
  /// 画像のリサイズが必要な場合に処理
  /// すべての画像を一貫したサイズにリサイズする
  /// 最適化：より小さいサイズにリサイズし、品質も下げて処理を高速化
  Future<Uint8List> _resizeImageIfNeeded(Uint8List imageBytes) async {
    print('元の画像サイズ: ${imageBytes.length} bytes');
    
    try {
      // 高速化のための最適化パラメータ - 小さい画像でも満足なOCR品質が得られる
      int quality = 65;  // JPEG品質を下げてファイルサイズを削減
      int maxWidth = 800;  // OCRに十分な解像度
      int maxHeight = 800;
      
      // 1回のリサイズ処理で大幅にサイズを削減
      Uint8List resizedBytes = await _imageProcessingService.resizeImageBytes(
        imageBytes: imageBytes,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: quality
      );
      
      print('リサイズ後の画像サイズ: ${resizedBytes.length} bytes');
      
      // 特に大きい画像の場合はさらにサイズ削減
      if (resizedBytes.length > 300000) { // 300KB以上の場合はさらに圧縮
        quality = 50; // さらに品質を下げて高速化
        maxWidth = 600;
        maxHeight = 600;
        
        // 2回目のリサイズでさらに圧縮
        resizedBytes = await _imageProcessingService.resizeImageBytes(
          imageBytes: resizedBytes,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          quality: quality
        );
        
        print('最適化後の画像サイズ: ${resizedBytes.length} bytes');
      }
      
      print('画像リサイズ処理完了: ${resizedBytes.length} bytes');
      return resizedBytes;
    } catch (e) {
      print('画像リサイズエラー: $e');
      
      // リサイズに失敗した場合は元の画像を返す
      return imageBytes;
    }
  }
  
  /// エラーレスポンスの作成
  Map<String, dynamic> _createErrorResponse(String message) {
    return {
      'success': false,
      'error': message,
      'text': ''
    };
  }
}
