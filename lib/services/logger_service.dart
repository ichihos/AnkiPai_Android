import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/connectivity_service.dart';

class LoggerService {
  static LoggerService? _instance;
  static LoggerService get instance => _instance ??= LoggerService._internal();

  LoggerService._internal();

  // ConnectivityServiceのインスタンスを取得
  final ConnectivityService _connectivityService = ConnectivityService();

  File? _logFile;
  bool _initialized = false;
  bool _isWeb = kIsWeb; // Web環境かどうかのフラグ
  String _inMemoryLog = ''; // Web環境用のメモリ内ログ保存

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Web環境の場合はメモリ内ログのみを使用
      if (_isWeb) {
        print('📑 Web環境では、メモリ内ログを使用します');
        _inMemoryLog =
            '=== Log started at ${DateTime.now()} (Web Environment) ===\n';
        _initialized = true;
        log('🔵 LoggerService initialized in Web environment');
        return;
      }

      // オフラインモードの場合はログファイルの作成をスキップする可能性がある
      final isOffline = _connectivityService.isOffline;
      if (isOffline) {
        print('📑 オフラインモードでは、ログファイルの作成をスキップする場合があります');
      }

      try {
        final directory = await getApplicationDocumentsDirectory();
        final path = directory.path;
        final now = DateTime.now();
        final formatter = DateFormat('yyyy-MM-dd');
        final fileName = 'anki_pai_log_${formatter.format(now)}.txt';

        final logFilePath = '$path/$fileName';
        _logFile = File(logFilePath);

        // ファイルが存在しない場合は作成する
        if (!await _logFile!.exists()) {
          try {
            await _logFile!.create(recursive: true);
            print('📑 ログファイルを新規作成しました: $logFilePath');

            // 初期ログを書き込み
            await _logFile!
                .writeAsString('=== Log started at ${DateTime.now()} ===\n');
          } catch (e) {
            print('❌ ログファイルの作成に失敗しました: $e');
            // オフラインモードの場合はエラーを無視
            if (isOffline) {
              print('📑 オフラインモード: ログファイルエラーを無視します');
              _inMemoryLog =
                  '=== Log started at ${DateTime.now()} (Offline Mode) ===\n';
              _initialized = true;
              return;
            }
          }
        }

        // ログファイルの場所を表示
        print('📑 ログファイルの場所: $logFilePath');
        print(
            '📑 ログファイルの存在確認: ${await _logFile!.exists() ? "存在します" : "存在しません"}');
      } catch (e) {
        print('❌ ログファイル初期化エラー: $e');
        // オフラインモードの場合はエラーを無視
        if (isOffline) {
          print('📑 オフラインモード: ログファイルエラーを無視します');
          _inMemoryLog =
              '=== Log started at ${DateTime.now()} (Offline Mode) ===\n';
        } else {
          throw e; // オンラインモードではエラーを再スロー
        }
      }

      _initialized = true;
      log('🔵 LoggerService initialized');
    } catch (e) {
      print('❌ Failed to initialize LoggerService: $e');
      // 初期化に失敗してもメモリ内ログは使用可能にする
      _inMemoryLog =
          '=== Log started at ${DateTime.now()} (Initialization Failed) ===\n';
      _inMemoryLog += '❌ Error: $e\n';
      _initialized = true; // エラーが発生してもサービスは使用可能にする
    }
  }

  Future<void> log(String message) async {
    final timestamp = DateTime.now().toString();
    final logMessage = '[$timestamp] $message\n';

    // Always print to console
    print(logMessage);

    // Web環境の場合はメモリ内ログに保存
    if (_isWeb) {
      _inMemoryLog += logMessage;
      return;
    }

    // オフラインモードの場合もメモリ内ログに保存
    final isOffline = _connectivityService.isOffline;
    if (isOffline) {
      _inMemoryLog += logMessage;
    }

    // Write to file if initialized and not in web environment
    if (_initialized && _logFile != null && !_isWeb) {
      try {
        // ファイルが存在しない場合は作成
        if (!await _logFile!.exists()) {
          try {
            await _logFile!.create(recursive: true);
            print('📑 ログファイルを作成しました: ${_logFile!.path}');
          } catch (e) {
            print('❌ ログファイルの作成に失敗しました: $e');
            // オフラインモードの場合はメモリ内ログに保存して終了
            if (isOffline) {
              return;
            }
          }
        }

        // 安全な文字列に変換してから書き込み
        try {
          // 非ASCII文字を安全に変換
          final safeMessage = _ensureSafeString(logMessage);
          await _logFile!.writeAsString(safeMessage, mode: FileMode.append);
        } catch (e) {
          print('❌ ログファイルへの書き込み失敗: $e');

          // ファイルの権限情報を表示
          try {
            final stat = await _logFile!.stat();
            print('📑 ファイル情報: $stat');
          } catch (statError) {
            print('❌ ファイル情報の取得に失敗: $statError');
          }
        }
      } catch (e) {
        print('❌ ログ処理中にエラーが発生: $e');
        // エラーが発生した場合はメモリ内ログに保存
        _inMemoryLog += logMessage;
      }
    } else if (!_initialized) {
      print('⚠️ LoggerServiceが初期化されていません');
      // 初期化されていない場合もメモリ内ログに保存
      _inMemoryLog += logMessage;
    }
  }

  /// ログファイルの内容を取得する
  Future<String> getLogContent() async {
    if (!_initialized) {
      return 'Logger not initialized';
    }

    // Web環境の場合はメモリ内ログを返す
    if (_isWeb) {
      return _inMemoryLog.isEmpty
          ? 'No logs available in web environment'
          : _inMemoryLog;
    }

    // オフラインモードでファイルがない場合はメモリ内ログを返す
    final isOffline = _connectivityService.isOffline;
    if (isOffline && (_logFile == null || !(await _logFile!.exists()))) {
      return _inMemoryLog.isEmpty
          ? 'No logs available in offline mode'
          : _inMemoryLog;
    }

    // 通常のファイルからの読み込み
    try {
      if (_logFile != null && await _logFile!.exists()) {
        try {
          // UTF-8でファイルを読み込む
          final fileContent = await _logFile!.readAsString();
          // メモリ内ログもあれば結合する
          if (_inMemoryLog.isNotEmpty) {
            return fileContent + '\n--- Memory Log ---\n' + _inMemoryLog;
          }
          return fileContent;
        } catch (decodeError) {
          // UTF-8デコードに失敗した場合、バイナリとして読み込んで安全に表示
          try {
            final bytes = await _logFile!.readAsBytes();
            // バイト配列を安全に文字列に変換
            final safeString = _bytesToSafeString(bytes);
            return 'Note: UTF-8 decode error occurred. Displaying safe representation:\n$safeString';
          } catch (binaryError) {
            return 'Failed to read log file as binary: $binaryError';
          }
        }
      } else if (_inMemoryLog.isNotEmpty) {
        // ファイルがないがメモリ内ログがある場合
        return _inMemoryLog;
      } else {
        return 'Log file does not exist and no memory logs available';
      }
    } catch (e) {
      // ファイル読み込みエラーの場合、メモリ内ログを返す
      if (_inMemoryLog.isNotEmpty) {
        return 'Error reading log file: $e\n\n--- Memory Log ---\n$_inMemoryLog';
      }
      return 'Error accessing log file: $e';
    }
  }

  /// バイト配列を安全な文字列に変換する
  String _bytesToSafeString(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      // 印刷可能なASCII文字のみを表示
      if (byte >= 32 && byte <= 126) {
        buffer.write(String.fromCharCode(byte));
      } else if (byte == 10 || byte == 13) {
        // 改行コードはそのまま表示
        buffer.write(String.fromCharCode(byte));
      } else {
        // その他の文字はヘキサ表記
        buffer.write('\\x${byte.toRadixString(16).padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }

  /// 文字列が安全にログに書き込めることを確認
  String _ensureSafeString(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      final codeUnit = char.codeUnitAt(0);

      // ASCII文字と改行コードのみを許可
      if ((codeUnit >= 32 && codeUnit <= 126) ||
          codeUnit == 10 ||
          codeUnit == 13) {
        buffer.write(char);
      } else {
        // 非ASCII文字はヘキサ表記に変換
        buffer.write('\\u${codeUnit.toRadixString(16).padLeft(4, '0')}');
      }
    }
    return buffer.toString();
  }

  /// ログファイルのパスを取得する
  Future<String> getLogFilePath() async {
    if (!_initialized || _logFile == null) {
      return 'Logger not initialized';
    }

    return _logFile!.path;
  }

  /// ログファイルの内容をコンソールに出力する
  Future<void> printLogToConsole() async {
    if (!_initialized || _logFile == null) {
      print('❌ Logger not initialized');
      return;
    }

    try {
      if (await _logFile!.exists()) {
        final content = await _logFile!.readAsString();
        print(
            '\n=== LOG FILE CONTENTS ===\n$content\n=== END OF LOG FILE ===\n');
      } else {
        print('❌ Log file does not exist');
      }
    } catch (e) {
      print('❌ Error reading log file: $e');
    }
  }

  Future<void> clearLog() async {
    if (!_initialized || _logFile == null) {
      return;
    }

    try {
      if (await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
    } catch (e) {
      print('❌ Failed to clear log file: $e');
    }
  }
}
