import 'dart:typed_data';

/// OCRモードの選択肢
enum OcrMode {
  photo, // 写真モード (Google Vision API使用)
  openai // OpenAI 4.1 mini モード (推奨)
}

/// 画像解析による自動OCRモード判別サービス
/// 現在は常にOpenAI GPT-4.1 miniを使用
class AutoOcrModeDetector {
  /// 画像を解析して最適なOCRモードを判定する
  /// 現在は常にOpenAIのGPT-4.1 miniを使用する
  static Future<OcrMode> detectMode(Uint8List imageBytes) async {
    print('OpenAIのGPT-4.1 miniを使用してOCRを実行します');
    return OcrMode.openai;
  }
}
