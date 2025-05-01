import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 画像処理サービス
/// 画像のリサイズやトリミングなどの処理を行う
class ImageProcessingService {
  /// 画像ファイルをリサイズする
  /// [imageFile] リサイズする画像ファイル
  /// [maxWidth] 最大幅
  /// [maxHeight] 最大高さ
  /// [quality] 画質（0-100）
  /// Returns リサイズされた画像ファイル
  Future<File> resizeImage({
    required File imageFile,
    int maxWidth = 1200,
    int maxHeight = 1200,
    int quality = 90,
  }) async {
    try {
      // 画像をデコード
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // リサイズの必要があるか確認
      if (image.width <= maxWidth && image.height <= maxHeight) {
        return imageFile; // すでに十分小さい場合
      }

      // アスペクト比を維持しながらリサイズ
      img.Image resized;
      if (image.width > image.height) {
        resized = img.copyResize(
          image,
          width: maxWidth,
          height: (maxWidth / image.width * image.height).round(),
          interpolation: img.Interpolation.linear,
        );
      } else {
        resized = img.copyResize(
          image,
          width: (maxHeight / image.height * image.width).round(),
          height: maxHeight,
          interpolation: img.Interpolation.linear,
        );
      }

      // エンコードして保存
      final resizedBytes = img.encodeJpg(resized, quality: quality);
      final tempDir = await getApplicationDocumentsDirectory();
      final tempFile = File(
          '${tempDir.path}/resized_${DateTime.now().millisecondsSinceEpoch}.jpg');

      return await tempFile.writeAsBytes(resizedBytes);
    } catch (e) {
      print('Image resizing error: $e');
      return imageFile; // エラー時はオリジナルを返す
    }
  }

  /// 画像バイトデータをリサイズする
  /// [imageBytes] リサイズする画像バイトデータ
  /// [maxWidth] 最大幅
  /// [maxHeight] 最大高さ
  /// [quality] 画質（0-100）
  /// Returns リサイズされた画像バイトデータ
  Future<Uint8List> resizeImageBytes({
    required Uint8List imageBytes,
    int maxWidth = 1200,
    int maxHeight = 1200,
    int quality = 90,
  }) async {
    try {
      // 画像をデコード
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Failed to decode image from bytes');
      }

      // リサイズの必要があるか確認
      if (image.width <= maxWidth && image.height <= maxHeight) {
        return imageBytes; // すでに十分小さい場合
      }

      // アスペクト比を維持しながらリサイズ
      final resized = _resizeImageToFit(
        image,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );

      // エンコードして返す
      return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    } catch (e) {
      print('Image bytes resizing error: $e');
      return imageBytes; // エラー時はオリジナルを返す
    }
  }

  /// 画像を指定サイズに合わせてリサイズする（アスペクト比を維持）
  /// [image] リサイズする画像
  /// [maxWidth] 最大幅
  /// [maxHeight] 最大高さ
  /// Returns リサイズされた画像
  img.Image _resizeImageToFit(
    img.Image image, {
    required int maxWidth,
    required int maxHeight,
  }) {
    // アスペクト比を維持しながらリサイズ
    if (image.width > image.height) {
      // 横長の画像
      if (image.width > maxWidth) {
        return img.copyResize(
          image,
          width: maxWidth,
          height: (maxWidth / image.width * image.height).round(),
          interpolation: img.Interpolation.linear,
        );
      }
    } else {
      // 縦長の画像
      if (image.height > maxHeight) {
        return img.copyResize(
          image,
          width: (maxHeight / image.height * image.width).round(),
          height: maxHeight,
          interpolation: img.Interpolation.linear,
        );
      }
    }

    // サイズ変更の必要がない場合
    return image;
  }

  /// 画像をメモリ上でトリミングする
  /// [imageData] トリミングする画像データ
  /// [cropRect] トリミング範囲（x, y, width, height）
  /// Returns トリミングされた画像データ
  Future<Uint8List> cropImage({
    required Uint8List imageData,
    required Rect cropRect,
  }) async {
    try {
      // 画像をデコード
      final image = img.decodeImage(imageData);

      if (image == null) {
        throw Exception('Failed to decode image for cropping');
      }

      // 境界チェック
      final x = cropRect.left.round().clamp(0, image.width - 1);
      final y = cropRect.top.round().clamp(0, image.height - 1);
      final width = cropRect.width.round().clamp(1, image.width - x);
      final height = cropRect.height.round().clamp(1, image.height - y);

      // トリミング
      final cropped = img.copyCrop(
        image,
        x: x,
        y: y,
        width: width,
        height: height,
      );

      // JPEGとしてエンコード
      return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
    } catch (e) {
      print('Image cropping error: $e');
      return imageData; // エラー時はオリジナルを返す
    }
  }

  /// トリミングされた画像をファイルとして保存
  /// [imageData] 画像データ
  /// Returns 保存された画像ファイル
  Future<File?> saveImageToFile(Uint8List imageData) async {
    // Webプラットフォームではファイル保存をスキップ
    if (kIsWeb) {
      print('Webプラットフォームではファイル保存をスキップします。');
      return null;
    }
    
    try {
      // プラットフォーム固有のファイル処理を実行
      if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
        print('サポートされていないプラットフォームではファイル保存をスキップします');
        return null;
      }

      try {
        // getApplicationDocumentsDirectoryを動的に判定して実行
        final tempDir = await getApplicationDocumentsDirectory();
        final tempFile = File(
            '${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');

        return await tempFile.writeAsBytes(imageData);
      } catch (docDirError) {
        // getApplicationDocumentsDirectoryが失敗した場合は一時ディレクトリを使用
        print('DocumentsDirectory取得エラー: $docDirError');
        print('一時ディレクトリを使用します');
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
            '${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');

        return await tempFile.writeAsBytes(imageData);
      }
    } catch (e) {
      print('Image saving error: $e');
      print('画像の保存に失敗しました: $e');
      return null;
    }
  }
}
