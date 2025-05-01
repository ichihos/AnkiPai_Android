import 'package:flutter/material.dart';
import 'package:anki_pai/widgets/image_crop_ocr_widget.dart';
import 'package:image_picker/image_picker.dart';

/// MISTRAL OCRとimage_cropの使用例を示す画面
class OcrExampleScreen extends StatefulWidget {
  const OcrExampleScreen({super.key});

  @override
  _OcrExampleScreenState createState() => _OcrExampleScreenState();
}

class _OcrExampleScreenState extends State<OcrExampleScreen> {
  String _extractedText = '';
  bool _isProcessing = false;

  /// OCR処理が完了したときのコールバック
  void _handleOcrCompleted(String text) {
    setState(() {
      _extractedText = text;
      _isProcessing = false;
    });
  }

  /// OCR画像選択ダイアログを表示
  void _showOcrImagePicker() {
    setState(() {
      _isProcessing = true;
    });
    
    // ギャラリーから選択するデフォルト設定
    showImageCropOcrDialog(
      context: context,
      onOcrCompleted: _handleOcrCompleted,
      imageSource: ImageSource.gallery,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MISTRALのOCR例'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 説明テキスト
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MISTRAL OCRを使った画像解析',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '画像を選択してトリミングし、MISTRAL OCRを使って'
                      'テキストを抽出することができます。',
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // OCR画像選択ボタン
            ElevatedButton.icon(
              icon: const Icon(Icons.image),
              label: const Text('画像を選択してOCRを実行'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _isProcessing ? null : _showOcrImagePicker,
            ),
            
            const SizedBox(height: 24),
            
            // 処理中インジケーター
            if (_isProcessing)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('処理中...'),
                  ],
                ),
              ),
            
            // 抽出されたテキスト表示
            if (_extractedText.isNotEmpty)
              Expanded(
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '抽出されたテキスト:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(_extractedText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
            // テキストが空の場合のガイド表示
            if (_extractedText.isEmpty && !_isProcessing)
              const Expanded(
                child: Center(
                  child: Text(
                    '画像を選択してOCRを実行してください',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
