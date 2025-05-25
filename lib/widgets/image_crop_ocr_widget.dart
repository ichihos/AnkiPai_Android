import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:get_it/get_it.dart';
import 'package:anki_pai/services/image_processing_service.dart';
import 'package:image/image.dart' as img_lib;
import 'package:anki_pai/services/google_vision_service.dart';
import 'package:anki_pai/services/ocr_detect_service.dart';
import 'package:anki_pai/services/openai_mini_service.dart';
import 'dart:math';
import 'dart:async';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// ocr_detect_service.dartからOcrModeをインポートして使用

/// 画像の選択・トリミング・OCR解析を行うウィジェット
class ImageCropOcrWidget extends StatefulWidget {
  /// OCR処理後のテキストを受け取るコールバック
  final Function(String text) onOcrCompleted;

  /// ウィジェットを閉じるためのコールバック
  final VoidCallback? onClose;

  /// OCR完了後、自動的に送信を行うためのコールバック
  /// nullの場合は自動送信を行わない
  final VoidCallback? onSubmit;

  /// 最大の高さ制限
  final double? maxHeight;

  /// イメージソース（カメラまたはギャラリー）
  final ImageSource imageSource;

  /// OCR完了後に自動で送信するかどうか
  final bool autoSubmit;

  const ImageCropOcrWidget({
    super.key,
    required this.onOcrCompleted,
    required this.imageSource,
    this.onClose,
    this.maxHeight,
    this.onSubmit,
    this.autoSubmit = false,
  });

  @override
  _ImageCropOcrWidgetState createState() => _ImageCropOcrWidgetState();
}

class _ImageCropOcrWidgetState extends State<ImageCropOcrWidget> {
  // For text translation, based on the user's language
  String _getLocalizedText(BuildContext context, String key,
      [Map<String, String>? params]) {
    // The keys match the ones we added to the ARB files
    final Map<String, Map<String, String>> translations = {
      'en': {
        'imageLoadingText': 'Loading image...',
        'fileLoadError':
            'Failed to load the file. Please try a different image.',
        'imageSelectionError':
            'An error occurred while selecting the image: {error}',
        'imageLoaded':
            'Image loaded. Please trim or perform OCR analysis as needed.',
        'detectingOcrMode': 'Detecting OCR mode automatically...',
        'modeDetectionFailed':
            'Mode detection failed. Using default photo mode.',
        'trimmingInProgress': 'Trimming in progress. Please wait.',
        'preparingTrimming': 'Preparing to trim...',
        'adjustThenTrimPrompt': 'Adjust the size then press the Trim button.',
        'trimmingExecutionError': 'Trimming execution error: {error}',
        'manualTrimmingSuccess': 'Manual trimming successful!',
        'missingTrimmingInfo': 'Missing information needed for trimming.',
        'trimmingError': 'Trimming error: {error}',
        'structuringVocabularyData': 'Structuring vocabulary data...',
        'vocabularyAndMathDetected':
            'Vocabulary list and formulas detected. Formatted appropriately.',
        'vocabularyDetected':
            'Vocabulary list detected. Formatted automatically.',
        'mathDetected': 'Formulas detected. Output in TeX format.',
        'ocrCompleted': 'OCR analysis completed. Closing widget...',
        'ocrAnalysisError': 'Error occurred during OCR analysis: {error}',
        'trimmingSuccess': 'Trimming successful. Image has been updated.',
        'trimmingFailed': 'Trimming failed: {error}',
        'trimmingProcessingError':
            'There was a problem processing the trimming result.',
        'trimmingCancelled': 'Trimming cancelled.',
        'executeTrimmingButton': 'Execute Trim',
        'trimmingButton': 'Trim',
        'readButton': 'Send', // Changed from 'Read' to 'Send'
        'cancelButton': 'Cancel',
        'reselectImageButton': 'Reselect Image'
      },
      'ja': {
        'imageLoadingText': '画像を読み込んでいます...',
        'fileLoadError': 'ファイルの読み込みに失敗しました。別の画像をお試しください。',
        'imageSelectionError': '画像の選択中にエラーが発生しました: {error}',
        'imageLoaded': '画像が読み込まれました。必要に応じてトリミングやOCR解析を行ってください。',
        'detectingOcrMode': 'OCRモードを自動判別中...',
        'modeDetectionFailed': 'モード判別に失敗しました。デフォルトの写真モードを使用します。',
        'trimmingInProgress': 'トリミングが進行中です。しばらくお待ちください。',
        'preparingTrimming': 'トリミングの準備中...',
        'adjustThenTrimPrompt': '大きさを調整後にトリミングボタンを押してください。',
        'trimmingExecutionError': 'トリミング実行エラー: {error}',
        'manualTrimmingSuccess': '手動トリミング成功!',
        'missingTrimmingInfo': 'トリミングに必要な情報が不足しています。',
        'trimmingError': 'トリミングエラー: {error}',
        'structuringVocabularyData': '単語帳データを構造化中...',
        'vocabularyAndMathDetected': '単語リストと数式が検出されました。適切な形式で整形しました。',
        'vocabularyDetected': '単語リストが検出されました。自動的に整形しました。',
        'mathDetected': '数式が検出されました。TeX形式で出力しました。',
        'ocrCompleted': 'OCR解析が完了しました。ウィジェットを閉じます...',
        'ocrAnalysisError': 'OCR解析中にエラーが発生しました: {error}',
        'trimmingSuccess': 'トリミング成功。画像が更新されました。',
        'trimmingFailed': 'トリミングに失敗しました: {error}',
        'trimmingProcessingError': 'トリミング結果の処理に問題がありました。',
        'trimmingCancelled': 'トリミングをキャンセルしました。',
        'executeTrimmingButton': 'トリミング実行',
        'trimmingButton': 'トリミング',
        'readButton': '送信', // 読み取りから送信に変更
        'cancelButton': 'キャンセル',
        'reselectImageButton': '画像を再選択'
      }
    };

    // Get current locale
    final locale = Localizations.localeOf(context).languageCode;

    // Get translation for current locale with fallback to English
    final localizedStrings = translations[locale] ?? translations['en']!;
    var text = localizedStrings[key] ?? translations['en']![key] ?? key;

    // Apply parameters if provided
    if (params != null) {
      params.forEach((paramKey, paramValue) {
        text = text.replaceAll('{$paramKey}', paramValue);
      });
    }

    return text;
  }

  final ImagePicker _picker = ImagePicker();
  final ImageProcessingService _imageProcessingService =
      ImageProcessingService();
  final GoogleVisionService _googleVisionService =
      GetIt.instance<GoogleVisionService>();
  final OpenAIMiniService _openAiMiniService =
      GetIt.instance<OpenAIMiniService>();

  // OCRモード選択
  OcrMode _selectedOcrMode = OcrMode.photo; // デフォルトは写真モード

  // 数式モード
  final bool _isMathMode = false; // デフォルトは無効

  // 画像データ
  Uint8List? _selectedImageBytes;
  Uint8List? _croppedImageBytes;

  // 処理状態
  bool _isCropping = false; // トリミング処理中
  bool _isAnalyzing = false; // OCR処理中
  String _errorMessage = '';

  // 特別なパターンの自動検出
  bool _isVocabularyDetected = false; // 単語リストの自動検出結果
  bool _hasMathFormula = false; // 数式の自動検出結果
  final bool _enableAutoDetect = true; // 自動検出機能を有効化

  // トリミング管理
  final CropController _cropController = CropController();
  bool _showCropInterface = false;
  bool _cropRequested = false; // トリミングリクエストフラグ
  bool _cropWidgetReady = false; // クロップウィジェットが準備完了か
  final bool _cropModified = false; // ユーザーがトリミング範囲を変更したか
  Rect? _userSpecifiedCropArea; // ユーザー指定のトリミングエリア
  Size? _originalImageSize; // 元画像のサイズ
  bool _isInTrimmingMode = false; // トリミングモード中かどうか

  @override
  void initState() {
    super.initState();
    // 初期化時に自動的に画像選択を開始
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pickImage(widget.imageSource);
    });
  }

  @override
  void dispose() {
    // リソースの解放（特に必要なければ空でもOK）
    super.dispose();
  }

  /// 画像を選択
  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() {
        _errorMessage = '';
      });

      final XFile? pickedImage = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );

      if (pickedImage == null) {
        if (widget.onClose != null) {
          widget.onClose!();
        }
        return;
      }

      try {
        // 安全にファイルを読み込む
        final bytes = await pickedImage.readAsBytes();
        // 画像をセットして初期トリミング範囲を設定
        _setImageBytes(bytes);
      } catch (fileError) {
        print('ファイル読み込みエラー: $fileError');
        setState(() {
          _errorMessage = _getLocalizedText(context, 'fileLoadError');
        });
      }
    } catch (e) {
      print('画像選択エラー: $e');
      setState(() {
        _errorMessage = _getLocalizedText(
            context, 'imageSelectionError', {'error': e.toString()});
      });
    }
  }

  /// 画像データをセットして初期トリミング範囲を設定
  void _setImageBytes(Uint8List imageBytes) {
    if (!mounted) return;

    setState(() {
      _selectedImageBytes = imageBytes;
      _showCropInterface = true;
      _errorMessage = _getLocalizedText(context, 'imageLoaded');
      // 初期時点でクロップ済みデータもそのまま画像を設定する
      _croppedImageBytes = imageBytes;
      // 新しい画像を設定するときはCropウィジェットがまだ準備完了していないとマーク
      _cropWidgetReady = false;

      // 常に自動判別を行う
      _detectOcrMode(imageBytes);
    });
  }

  // 自動判別メソッドを追加
  Future<void> _detectOcrMode(Uint8List imageBytes) async {
    try {
      setState(() {
        _errorMessage = _getLocalizedText(context, 'detectingOcrMode');
      });

      // 判別サービスを使用してモードを検出
      final detectedMode = await AutoOcrModeDetector.detectMode(imageBytes);

      if (mounted) {
        setState(() {
          _selectedOcrMode = detectedMode; // キャスト不要 (detectModeはOcrMode型を返す)
          _errorMessage = ''; // メッセージを非表示に変更
        });
      }
    } catch (e) {
      print('モード自動判別エラー: $e');
      // エラー時はデフォルトで写真モード
      if (mounted) {
        setState(() {
          _selectedOcrMode = OcrMode.photo;
          _errorMessage = _getLocalizedText(context, 'modeDetectionFailed');
        });
      }
    }
  }

  /// 画像をトリミング
  void _cropImage() {
    if (_selectedImageBytes == null) return;

    // トリミングモード中の場合はトリミングを実行
    if (_isInTrimmingMode) {
      // 二重クリックを防止
      if (_isCropping) {
        print('トリミングが既に進行中です');
        setState(() {
          _errorMessage = _getLocalizedText(context, 'trimmingInProgress');
        });
        return;
      }

      print('トリミングを実行します');

      // トリミング状態を設定
      setState(() {
        _cropRequested = true; // トリミングリクエストフラグを設定
        _isCropping = true;
        _errorMessage = _getLocalizedText(context, 'preparingTrimming');
      });

      // Cropウィジェットが準備完了している場合はすぐにトリミングを実行
      if (_cropWidgetReady) {
        _executeCrop();
      }
      return;
    }

    // トリミングモードでない場合は、トリミングモードに入る
    print('トリミングモードを開始します');
    setState(() {
      _isInTrimmingMode = true;
      _errorMessage = _getLocalizedText(context, 'adjustThenTrimPrompt');
    });
  }

  /// トリミングを実行するメソッド
  void _executeCrop() {
    if (!mounted) return;

    try {
      print('実際にトリミングを実行します');

      // トリミング前に元の画像サイズを記録
      if (_selectedImageBytes != null) {
        final image = img_lib.decodeImage(_selectedImageBytes!);
        if (image != null) {
          _originalImageSize =
              Size(image.width.toDouble(), image.height.toDouble());
          print('元の画像サイズを記録: $_originalImageSize');
        }
      }

      // トリミング実行 - 長方形トリミングのみ
      _cropController.crop();

      print('トリミングリクエストを送信しました - onCroppedコールバックでトリミング結果が取得されます');
    } catch (e) {
      print('トリミング実行エラー: $e');
      setState(() {
        _isCropping = false;
        _cropRequested = false; // トリミングリクエストを完了状態に設定
        _errorMessage = _getLocalizedText(
            context, 'trimmingExecutionError', {'error': e.toString()});
      });
    }
  }

  /// 非中央的なトリミング領域を生成
  void _createCustomCropArea() {
    try {
      if (_selectedImageBytes != null) {
        final decodedImage = img_lib.decodeImage(_selectedImageBytes!);
        if (decodedImage != null) {
          final imgWidth = decodedImage.width.toDouble();
          final imgHeight = decodedImage.height.toDouble();

          // 非中央的な長方形領域を設定 - より自然な読み取り領域を想定
          final leftOffset = imgWidth * 0.1; // 左端から10%の位置
          final topOffset = imgHeight * 0.1; // 上端から10%の位置
          final rectWidth = imgWidth * 0.8; // 画像幅の80%
          final rectHeight = imgHeight * 0.7; // 画像高さの70%

          _userSpecifiedCropArea = Rect.fromLTWH(
            leftOffset,
            topOffset,
            rectWidth,
            rectHeight,
          );
          print('カスタムトリミング領域を生成: $_userSpecifiedCropArea');
        }
      }
    } catch (e) {
      print('カスタムトリミング領域の生成中にエラー: $e');
    }
  }

  /// 手動で画像をトリミング (ImageProcessingServiceを使用)
  Future<void> _performManualCrop() async {
    try {
      if (_selectedImageBytes != null && _userSpecifiedCropArea != null) {
        print('手動トリミングを実行します: ${_userSpecifiedCropArea.toString()}');

        final croppedImage = await _imageProcessingService.cropImage(
          imageData: _selectedImageBytes!,
          cropRect: _userSpecifiedCropArea!,
        );

        if (mounted) {
          setState(() {
            _isCropping = false;
            _cropRequested = false; // トリミングリクエストを完了状態に設定
            _selectedImageBytes = croppedImage;
            _croppedImageBytes = croppedImage;
            _errorMessage = _getLocalizedText(context, 'manualTrimmingSuccess');
          });
        }
      } else {
        setState(() {
          _isCropping = false;
          _errorMessage = _getLocalizedText(context, 'missingTrimmingInfo');
        });
      }
    } catch (e) {
      print('手動トリミングエラー: $e');
      setState(() {
        _isCropping = false;
        _errorMessage = _getLocalizedText(
            context, 'trimmingError', {'error': e.toString()});
      });
    }
  }

  /// OCR結果が構造化処理を必要とするか判定するメソッド
  // 削除

  /// 英単語帳OCR結果を構造化する
  Future<String> structureVocabularyWithMistral(String rawText) async {
    try {
      setState(() {
        _errorMessage = _getLocalizedText(context, 'structuringVocabularyData');
      });

      // Mistralを使用して構造化
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

      final result = await _openAiMiniService.getCompletion(prompt);

      if (result['success'] == true && result['text'] != null) {
        final plainText = result['text'].trim();

        // デバッグ出力
        print('=== Mistralから受け取ったテキスト ===');
        print(plainText);

        // プレーンテキストから形式が正しいか確認
        final lines = plainText
            .split('\n')
            .where((line) => line.trim().isNotEmpty && line.contains(':'))
            .toList();

        if (lines.isEmpty) {
          print('有効な単語ペアが見つかりません。JSON形式を試みます。');
          // 形式が違う場合、JSONを試す
          try {
            final parsed = jsonDecode(plainText);
            print('予期せずJSONで返ってきた場合の処理');

            // JSON配列からテキストフォーマットに変換
            if (parsed is List) {
              final convertedText = parsed
                  .map((item) {
                    if (item is Map &&
                        item.containsKey('word') &&
                        item.containsKey('meaning')) {
                      return '${item["word"]}:${item["meaning"]};';
                    }
                    return null;
                  })
                  .where((item) => item != null)
                  .join('\n');

              if (convertedText.isNotEmpty) {
                print('=== JSONから変換されたテキスト ===');
                print(convertedText);
                return convertedText;
              }
            }
          } catch (e) {
            print('JSONパース試行中のエラー: $e');
          }

          // 上記の方法が失敗した場合はフォールバック
          return _createSimpleTextFormat(rawText);
        }

        // 結果をそのまま返す
        return plainText;
      } else {
        print('Mistralによる構造化エラー: ${result['error'] ?? "不明なエラー"}');
        return _createSimpleTextFormat(rawText); // エラーの場合はフォールバックを返す
      }
    } catch (e) {
      print('単語帳構造化エラー: $e');
      return _createSimpleTextFormat(rawText); // エラーの場合はフォールバックを返す
    }
  }

  /// フォールバック用のシンプルテキストフォーマットを作成
  String _createSimpleTextFormat(String rawText) {
    try {
      // 空白で区切られた行を分割
      final lines = rawText
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(10) // 最初の10行のみ対象
          .toList();

      if (lines.isEmpty) {
        return 'unknown:不明なテキスト;';
      }

      // 各行を単語とみなし、シンプルなフォーマットに変換
      return lines.map((line) => '${line.trim()}:意味不明;').join('\n');
    } catch (e) {
      print('シンプルテキストフォーマット生成エラー: $e');
      return 'error:データ変換エラー;';
    }
  }

  /// 読み取りのみを行うメソッド（送信は行わない）
  Future<void> _executeOcrOnly() async {
    if (!mounted || _isAnalyzing) return;

    print('読み取りのみを実行します');

    try {
      setState(() {
        _isAnalyzing = true;
        _errorMessage = "";
      });

      if (_selectedImageBytes == null) {
        throw Exception('画像データがありません');
      }

      // トリミングが必要か確認
      if (_cropModified && _croppedImageBytes == null) {
        // ユーザーがトリミング範囲を変更したが、まだトリミングが実行されていない場合
        print('トリミングが必要です。先にトリミングを実行します。');
        // トリミングを実行して完了を待つ
        _cropImage();
        // トリミングが完了するまで待機
        await Future.delayed(const Duration(milliseconds: 500));
        while (_isCropping) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      final imageBytes = _croppedImageBytes ?? _selectedImageBytes!;
      String ocrResult = '';

      // メインOCRとしてOpenAI 4.1 miniを使用
      print('OpenAI 4.1 miniでOCR解析を実行します');
      final result = await _openAiMiniService.performOcrFromBytes(imageBytes);

      if (result['success'] == true && result['text'] != null) {
        ocrResult = result['text'] as String;

        // 特別なパターンの自動検出結果を取得
        if (_enableAutoDetect) {
          _isVocabularyDetected = result['isVocabularyList'] as bool? ?? false;
          _hasMathFormula = result['hasMathFormula'] as bool? ?? false;

          if (_isVocabularyDetected && _hasMathFormula) {
            setState(() {
              _errorMessage =
                  _getLocalizedText(context, 'vocabularyAndMathDetected');
            });
          } else if (_isVocabularyDetected) {
            setState(() {
              _errorMessage = _getLocalizedText(context, 'vocabularyDetected');
            });
          } else if (_hasMathFormula) {
            setState(() {
              _errorMessage = _getLocalizedText(context, 'mathDetected');
            });
          }
        }
      } else {
        // OpenAI失敗時はバックアップとして使用するモードを選択
        // 数式モードかどうかでバックアップの処理を切り替え
        if (_isMathMode) {
          print('バックアップとしてvision apiを使用します');
          final backupResult =
              await _googleVisionService.performOcrFromBytes(imageBytes);
          ocrResult = backupResult['text'] as String? ?? '';
        } else {
          print('バックアップとしてGoogle Visionを使用します');
          final backupResult =
              await _googleVisionService.performOcrFromBytes(imageBytes);
          ocrResult = backupResult['text'] as String? ?? '';
        }
      }

      // OCR結果が空の場合
      if (ocrResult.trim().isEmpty) {
        setState(() {
          _isAnalyzing = false;
          _errorMessage = _getLocalizedText(context, 'noTextDetected');
        });
        return;
      }

      // 空白を整形
      var formattedText = ocrResult.trim();

      // 構造化が必要なデータか確認
      if (_isVocabularyDetected || _hasMathFormula) {
        setState(() {
          _errorMessage =
              _getLocalizedText(context, 'structuringVocabularyData');
        });

        // データ構造化を行う
        try {
          formattedText = await structureVocabularyWithMistral(formattedText);
        } catch (e) {
          print('構造化エラー: $e');
          // フォールバックとしてシンプルな形式を使用
          formattedText = _createSimpleTextFormat(ocrResult);
        }
      }

      // 結果をコールバックで返す
      widget.onOcrCompleted(formattedText);

      // 处理完成状態の更新（送信は行わない）
      setState(() {
        _isAnalyzing = false;
        _isInTrimmingMode = false; // OCR完了時にトリミングモードを終了
        _errorMessage = "読み取り完了\n編集後、「送信」ボタンを押してください";
      });

      // 読み取り完了後、ウィジェットを閉じる
      Future.delayed(const Duration(milliseconds: 300), () {
        if (widget.onClose != null && mounted) {
          widget.onClose!();
        }
      });
    } catch (e) {
      print('OCR解析エラー: $e');
      setState(() {
        _isAnalyzing = false;
        _isInTrimmingMode = false; // エラー発生時にもトリミングモードを終了
        _errorMessage = _getLocalizedText(
            context, 'ocrAnalysisError', {'error': e.toString()});
      });
    }
  }

  /// OCR解析を実行して送信処理も行う
  Future<void> _executeOcr() async {
    if (!mounted || _isAnalyzing) return;

    // 送信モードの場合はロギングを追加
    if (widget.autoSubmit) {
      print('自動送信モードでOCRを実行します');
    }

    try {
      setState(() {
        _isAnalyzing = true;
        _errorMessage = "";
      });

      if (_selectedImageBytes == null) {
        throw Exception('画像データがありません');
      }

      // トリミングが必要か確認
      if (_cropModified && _croppedImageBytes == null) {
        // ユーザーがトリミング範囲を変更したが、まだトリミングが実行されていない場合
        print('トリミングが必要です。先にトリミングを実行します。');
        // トリミングを実行して完了を待つ
        _cropImage();
        // トリミングが完了するまで待機
        await Future.delayed(const Duration(milliseconds: 500));
        while (_isCropping) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      final imageBytes = _croppedImageBytes ?? _selectedImageBytes!;
      String ocrResult = '';

      // メインOCRとしてOpenAI 4.1 miniを使用
      print('OpenAI 4.1 miniでOCR解析を実行します');
      final result = await _openAiMiniService.performOcrFromBytes(imageBytes);

      if (result['success'] == true && result['text'] != null) {
        ocrResult = result['text'] as String;

        // 特別なパターンの自動検出結果を取得
        if (_enableAutoDetect) {
          _isVocabularyDetected = result['isVocabularyList'] as bool? ?? false;
          _hasMathFormula = result['hasMathFormula'] as bool? ?? false;

          if (_isVocabularyDetected && _hasMathFormula) {
            setState(() {
              _errorMessage =
                  _getLocalizedText(context, 'vocabularyAndMathDetected');
            });
          } else if (_isVocabularyDetected) {
            setState(() {
              _errorMessage = _getLocalizedText(context, 'vocabularyDetected');
            });
          } else if (_hasMathFormula) {
            setState(() {
              _errorMessage = _getLocalizedText(context, 'mathDetected');
            });
          }
        }
      } else {
        // OpenAI失敗時はバックアップとして使用するモードを選択
        // 数式モードかどうかでバックアップの処理を切り替え
        if (_isMathMode) {
          print('バックアップとしてvision apiを使用します');
          final backupResult =
              await _googleVisionService.performOcrFromBytes(imageBytes);
          ocrResult = backupResult['text'] as String? ?? '';
        } else {
          print('バックアップとしてGoogle Visionを使用します');
          final backupResult =
              await _googleVisionService.performOcrFromBytes(imageBytes);
          ocrResult = backupResult['text'] as String? ?? '';
        }
      }

      // OCR結果をコールバックで返す
      widget.onOcrCompleted(ocrResult);

      // 状態を更新
      setState(() {
        _isAnalyzing = false;
        _isInTrimmingMode = false; // OCR完了時にトリミングモードを終了
        // 結果はコールバックで既に返しているので保存不要
        _errorMessage = _getLocalizedText(context, 'ocrCompleted');
      });

      // OCR処理完了後の処理
      if (widget.autoSubmit && widget.onSubmit != null) {
        // 自動送信モードの場合、送信コールバックを実行する
        print('自動送信を実行します');

        // 直接onSubmitを呼び出す
        // HomeScreen側でモーダルを閉じる処理を行うため、ここでは閉じる処理を行わない
        if (mounted) {
          widget.onSubmit!();
        }
      } else {
        // 自動送信モードでない場合は、通常通りウィジェットを閉じる
        Future.delayed(const Duration(milliseconds: 300), () {
          if (widget.onClose != null && mounted) {
            widget.onClose!();
          }
        });
      }
    } catch (e) {
      print('OCR解析エラー: $e');
      setState(() {
        _isAnalyzing = false;
        _isInTrimmingMode = false; // エラー発生時にもトリミングモードを終了
        _errorMessage = _getLocalizedText(
            context, 'ocrAnalysisError', {'error': e.toString()});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // タイトル削除してシンプルに
        title: Container(),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (widget.onClose != null) {
              widget.onClose!();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // エラーメッセージ表示
          if (_errorMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8.0),
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              decoration: BoxDecoration(
                color:
                    _errorMessage.contains('成功') || _errorMessage.contains('完了')
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                _errorMessage,
                style: TextStyle(
                  color: _errorMessage.contains('成功') ||
                          _errorMessage.contains('完了')
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ),

          // メインコンテンツ
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    // 読み込み中
    if (_selectedImageBytes == null) {
      // Removed const from Center since it contains a non-const child (Text widget with method call)
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_getLocalizedText(context, 'imageLoadingText')),
          ],
        ),
      );
    }

    // 処理中表示
    if (_isCropping || _isAnalyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // OCRアニメーション表示
            OcrScanAnimation(
              isAnalyzing: _isAnalyzing,
              isCropping: _isCropping,
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    // トリミングインターフェース
    if (_showCropInterface) {
      return Column(
        children: [
          // トリミングエリア または 一般画像表示
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 4.0),
                  child: _isInTrimmingMode
                      // トリミングモードの場合はトリミングフレームを表示
                      ? Crop(
                          image: _selectedImageBytes!,
                          controller: _cropController,
                          aspectRatio: null, // 自由なトリミング範囲を許可
                          withCircleUi: false, // 常に長方形のトリミング
                          baseColor: Colors.black.withOpacity(0.6),
                          maskColor: Colors.black.withOpacity(0.6),
                          cornerDotBuilder: (size, edgeAlignment) => Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: _selectedOcrMode == OcrMode.photo
                                  ? Colors.blue
                                  : Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),

                          // グリッドなしのシンプルなトリミングインターフェース

                          // トリミング結果コールバック
                          onCropped: (result) {
                            // 結果の型に応じた処理
                            if (result is CropSuccess) {
                              // 成功した場合
                              print(
                                  'トリミング成功: ${result.croppedImage.length} bytes');
                              setState(() {
                                _isCropping = false;
                                _cropRequested = false; // トリミングリクエストを完了状態に設定
                                _isInTrimmingMode = false; // トリミングモードを終了
                                _selectedImageBytes = result.croppedImage;
                                _croppedImageBytes = result.croppedImage;
                                _showCropInterface = true;
                                _errorMessage = _getLocalizedText(
                                    context, 'trimmingSuccess');
                              });
                            } else if (result is CropFailure) {
                              // 失敗した場合
                              print('トリミング失敗: ${result.cause}');
                              setState(() {
                                _isCropping = false;
                                _cropRequested = false; // トリミングリクエストを完了状態に設定
                                _isInTrimmingMode = false; // トリミングモードを終了
                                _errorMessage = _getLocalizedText(
                                    context,
                                    'trimmingFailed',
                                    {'error': result.cause.toString()});
                              });

                              // 自動失敗時は手動トリミングを試みる
                              _createCustomCropArea();
                              _performManualCrop();
                            } else {
                              // その他の結果型（将来的な互換性のため）
                              print('不明なトリミング結果型: ${result.runtimeType}');
                              setState(() {
                                _isCropping = false;
                                _cropRequested = false; // トリミングリクエストを完了状態に設定
                                _isInTrimmingMode = false; // トリミングモードを終了
                                _errorMessage = _getLocalizedText(
                                    context, 'trimmingProcessingError');
                              });
                            }
                          },

                          // ステータス変更コールバック
                          onStatusChanged: (status) {
                            print('クロップステータス変更: $status');

                            // トリミング中の場合は何もしない
                            if (status == CropStatus.cropping) {
                              print('トリミング中のステータス変更を検出');
                              return;
                            }

                            // 準備完了時の処理
                            if (status == CropStatus.ready) {
                              print('クロップウィジェットの準備が完了しました');
                              setState(() {
                                _cropWidgetReady = true;
                              });

                              // トリミングリクエストが保留中なら実行
                              if (_cropRequested && mounted) {
                                print('保留中のトリミングリクエストを検出 - トリミングを実行します');
                                // 非同期処理のためのマイクロタスクを通じて実行 - 処理を一度だけ実行
                                Future.microtask(() => _executeCrop());
                                // マイクロタスクを発行した時点でリクエストを初期化
                                setState(() {
                                  _cropRequested = false;
                                });
                              }
                            }
                          },
                        )
                      // 非トリミングモードの場合は通常の画像表示
                      : Image.memory(
                          _selectedImageBytes!,
                          fit: BoxFit.contain,
                        ),
                ),
              ],
            ),
          ),

          // コントロールパネル
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // ボタンレイアウト
                Column(
                  children: [
                    // トリミングモードの場合
                    if (_isInTrimmingMode) ...[
                      // トリミング実行とキャンセルボタンの行
                      Row(
                        children: [
                          // トリミング実行ボタン
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.crop),
                              label: Text(
                                  _getLocalizedText(context, 'executeTrimmingButton'),
                                  style: const TextStyle(color: Colors.black)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: Colors.blue.shade600,
                              ),
                              onPressed: _isCropping || _isAnalyzing ? null : _cropImage,
                            ),
                          ),

                          const SizedBox(width: 16),

                          // キャンセルボタン
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.cancel),
                              label: Text(
                                  _getLocalizedText(context, 'cancelButton'),
                                  style: const TextStyle(color: Colors.black)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: Colors.red.shade400,
                              ),
                              onPressed: _isCropping || _isAnalyzing
                                  ? null
                                  : () {
                                      // キャンセル処理
                                      setState(() {
                                        _isInTrimmingMode = false;
                                        _errorMessage = _getLocalizedText(
                                            context, 'trimmingCancelled');
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // トリミングボタンの行（幅いっぱい）
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.crop),
                          label: Text(
                              _getLocalizedText(context, 'trimmingButton'),
                              style: const TextStyle(color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: Colors.blue.shade400,
                          ),
                          onPressed: _isCropping || _isAnalyzing ? null : _cropImage,
                        ),
                      ),
                    
                      const SizedBox(height: 12),
                    
                      // 読み取りボタンと送信ボタンの行
                      Row(
                        children: [
                          // 読み取りのみボタン
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.document_scanner),
                              label: Text(
                                  AppLocalizations.of(context)!.readOnlyButton,
                                  style: const TextStyle(color: Colors.black)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: Colors.amber.shade400,
                              ),
                              onPressed: _isCropping || _isAnalyzing
                                  ? null
                                  : () {
                                      // 読み取りのみの処理
                                      _executeOcrOnly();
                                    },
                            ),
                          ),

                          const SizedBox(width: 16),

                          // 送信ボタン
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.send),
                              label: Text(
                                  AppLocalizations.of(context)!.readButton,
                                  style: const TextStyle(color: Colors.black)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: (_hasMathFormula ||
                                        _isMathMode)
                                    ? const Color.fromARGB(255, 193, 121, 206)
                                    : Colors.green.shade400,
                              ),
                              onPressed: _isCropping || _isAnalyzing
                                  ? null
                                  : () {
                                      // OCRと送信処理
                                      _executeOcr();
                                    },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                // 再選択ボタン
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label:
                        Text(_getLocalizedText(context, 'reselectImageButton')),
                    onPressed: _isCropping || _isAnalyzing
                        ? null
                        : () => _pickImage(widget.imageSource),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // デフォルトビュー（ここには到達しないはず）
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.add_photo_alternate),
        label: Text(_getLocalizedText(context, 'reselectImageButton')),
        onPressed: () => _pickImage(widget.imageSource),
      ),
    );
  }
}

/// OCRスキャンのアニメーションを表示するウィジェット
class OcrScanAnimation extends StatefulWidget {
  final bool isAnalyzing;
  final bool isCropping;

  const OcrScanAnimation({
    super.key,
    required this.isAnalyzing,
    required this.isCropping,
  });

  @override
  State<OcrScanAnimation> createState() => _OcrScanAnimationState();
}

class _OcrScanAnimationState extends State<OcrScanAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scanLineAnimation;
  final List<_RecognizedCharacter> _characters = [];
  final _random = Random();
  Timer? _characterTimer;

  // 認識される文字のサンプル
  final List<String> _sampleCharacters = [
    'A',
    'B',
    'C',
    '1',
    '2',
    '3',
    'あ',
    'い',
    'う',
    'え',
    'お',
    'か',
    '漢',
    '字',
    '文',
    '+',
    '-',
    '=',
    '×',
    '÷',
    'α',
    'β',
    'γ',
    '∑',
    '∫',
    '√',
    'π',
  ];

  @override
  void initState() {
    super.initState();

    // アニメーションコントローラーの初期化
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    // スキャンラインのアニメーション
    _scanLineAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    // 文字が認識されるアニメーションのタイマー
    _characterTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && widget.isAnalyzing) {
        _addCharacter();
        // 文字の数が一定数を超えたら古い文字を削除
        if (_characters.length > 15) {
          setState(() {
            _characters.removeAt(0);
          });
        }
      }
    });
  }

  // ランダムな位置に文字を追加
  void _addCharacter() {
    final randomChar =
        _sampleCharacters[_random.nextInt(_sampleCharacters.length)];
    final xPos = 0.2 + _random.nextDouble() * 0.6; // 20%〜80%の範囲
    final yPos = _scanLineAnimation.value -
        0.05 +
        _random.nextDouble() * 0.1; // スキャンライン付近

    if (mounted) {
      setState(() {
        _characters.add(_RecognizedCharacter(
          character: randomChar,
          position: Offset(xPos, yPos),
          size: 14.0 + _random.nextDouble() * 10.0, // 14〜24pxのサイズ
          opacity: 0.7 + _random.nextDouble() * 0.3, // 70%〜100%の透明度
        ));
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _characterTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        children: [
          // 背景の書類イメージ
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),

          // スキャンライン
          AnimatedBuilder(
            animation: _scanLineAnimation,
            builder: (context, child) {
              return Positioned(
                top: _scanLineAnimation.value * 200,
                left: 0,
                right: 0,
                child: Container(
                  height: 2.0,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.isAnalyzing
                          ? [
                              Colors.blue.withOpacity(0.0),
                              Colors.blue,
                              Colors.blue.withOpacity(0.0)
                            ]
                          : [
                              Colors.green.withOpacity(0.0),
                              Colors.green,
                              Colors.green.withOpacity(0.0)
                            ],
                    ),
                  ),
                ),
              );
            },
          ),

          // 認識された文字
          ...(_characters.map((char) {
            return Positioned(
              left: char.position.dx * 200,
              top: char.position.dy * 200,
              child: AnimatedOpacity(
                opacity: char.opacity,
                duration: const Duration(milliseconds: 300),
                child: Text(
                  char.character,
                  style: TextStyle(
                    color: widget.isAnalyzing ? Colors.blue : Colors.green,
                    fontSize: char.size,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }).toList()),

          // 中央のアイコン
          Center(
            child: widget.isAnalyzing
                ? const Icon(Icons.document_scanner,
                    size: 40, color: Colors.blue)
                : const Icon(Icons.crop, size: 40, color: Colors.green),
          ),
        ],
      ),
    );
  }
}

/// アニメーションに使用する認識された文字クラス
class _RecognizedCharacter {
  final String character;
  final Offset position; // 0.0-1.0の相対位置
  final double size;
  final double opacity;

  _RecognizedCharacter({
    required this.character,
    required this.position,
    required this.size,
    required this.opacity,
  });
}

/// 画像を選択してOCR処理を行うダイアログを表示
Future<void> showImageCropOcrDialog({
  required BuildContext context,
  required Function(String text) onOcrCompleted,
  required ImageSource imageSource,
  VoidCallback? onSubmit,
  bool autoSubmit = false,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: ImageCropOcrWidget(
            onOcrCompleted: (String text) {
              onOcrCompleted(text);
              Navigator.of(context).pop();
            },
            imageSource: imageSource,
            onClose: () => Navigator.of(context).pop(),
            onSubmit: onSubmit,
            autoSubmit: autoSubmit,
          ),
        ),
      );
    },
  );
}
