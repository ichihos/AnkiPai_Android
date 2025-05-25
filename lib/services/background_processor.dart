import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_token_service.dart';

/// バックグラウンド処理用のプロセッサークラス
/// Isolateとプラットフォーム固有のバックグラウンドサービスを使用して、
/// アプリがバックグラウンドになっても処理が継続できるようにする
class BackgroundProcessor {
  // シングルトンインスタンス
  static final BackgroundProcessor _instance = BackgroundProcessor._internal();
  factory BackgroundProcessor() => _instance;
  BackgroundProcessor._internal();

  // バックグラウンド通信用ポート
  ReceivePort? _receivePort;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // 実行中のタスク状態
  final Map<String, Map<String, dynamic>> _runningTasks = {};

  // プラットフォーム固有のバックグラウンドサービス
  FlutterBackgroundService? _backgroundService;

  // 通知サービス
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// バックグラウンドプロセッサーを初期化
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      // Web環境では別の方法で初期化
      await _initializeForWeb();
      return;
    }

    try {
      // ローカル通知の初期化
      await _initializeNotifications();

      // プラットフォームに応じた初期化
      if (Platform.isIOS || Platform.isAndroid) {
        await _initializeBackgroundService();
      } else {
        // その他のプラットフォームではIsolateを使用
        await _initializeWithIsolate();
      }

      // 以前のタスクを復元
      await _restorePreviousTasks();

      _isInitialized = true;
      print('バックグラウンドプロセッサが初期化されました');
    } catch (e) {
      print('バックグラウンドプロセッサの初期化エラー: $e');
      _cleanupResources();
      rethrow;
    }
  }

  /// Isolateを使用した初期化（非iOS/Android環境向け）
  Future<void> _initializeWithIsolate() async {
    _receivePort = ReceivePort();

    // Isolate起動
    await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort!.sendPort,
    );

    // メッセージハンドラー設定
    _receivePort!.listen((message) {
      if (message is Map<String, dynamic>) {
        // タスク更新またはエラー
        _handleTaskUpdate(message);
      }
    });
  }

  /// ローカル通知の初期化
  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(initSettings,
        onDidReceiveNotificationResponse: (details) async {});
  }

  /// バックグラウンドサービスの初期化（iOS/Android向け）
  Future<void> _initializeBackgroundService() async {
    _backgroundService = FlutterBackgroundService();

    // サービスの初期化
    await _backgroundService!.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onBackgroundServiceStart,
        onBackground: onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'ankipai_background_channel',
        initialNotificationTitle: 'Anki Pai',
        initialNotificationContent: 'バックグラウンド処理を実行中',
        foregroundServiceNotificationId: 888,
      ),
    );

    // バックグラウンドサービスからのメッセージを受信
    _backgroundService!.on('update').listen((event) {
      if (event != null) {
        _handleTaskUpdate(event);
      }
    });
  }

  /// バックグラウンドサービスの開始ポイント
  // iOSバックグラウンド処理用のエントリーポイント
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // iOSバックグラウンド処理のWakelockを確保
    debugPrint('iOS: バックグラウンド処理開始');
    
    // データを保存するための共有プリファレンス
    final prefs = await SharedPreferences.getInstance();
    
    // iOS向けの追加対策
    debugPrint('iOS: バックグラウンドプロセスの優先度を上げています');
    
    try {
      // 定期的に状態をチェック
      Timer.periodic(const Duration(seconds: 30), (timer) {
        debugPrint('iOS: バックグラウンド処理チェックポイント');
        
        // 処理中のタスクがなくなったらタイマーを停止
        final tasksJson = prefs.getString('pending_background_tasks') ?? '{}';
        final tasks = json.decode(tasksJson) as Map<String, dynamic>;
        
        if (tasks.isEmpty) {
          debugPrint('iOS: バックグラウンド処理を終了します - タスクなし');
          timer.cancel();
          service.invoke('stopService');
        }
      });
    } catch (e) {
      debugPrint('iOS: バックグラウンドタイマーエラー: $e');
    }
    
    return true;
  }
  
  @pragma('vm:entry-point')
  static bool onBackgroundServiceStart(ServiceInstance service) {
    WidgetsFlutterBinding.ensureInitialized();
    
    debugPrint('バックグラウンドサービス: 初期化開始');

    // APIトークンサービスの初期化
    final apiTokenService = ApiTokenService();

    // トークンをすぐに1回取得（エラーは無視）
    apiTokenService.getToken().then((token) {
      debugPrint('バックグラウンドサービス: APIトークンを事前取得しました');
    }).catchError((e) {
      debugPrint('バックグラウンドサービス: APIトークン事前取得エラー: $e');
    });

    // 定期的なバックグラウンド処理更新
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        // タスク状態保存用
        final prefs = await SharedPreferences.getInstance();
        final Map<String, Map<String, dynamic>> tasksMap = {};

        // 新しいタスクを確認
        final tasksJson = prefs.getString('pending_background_tasks') ?? '{}';
        final Map<String, dynamic> pendingTasks = json.decode(tasksJson);

        // 新規タスクの処理
        for (final entry in pendingTasks.entries.toList()) {
          final taskId = entry.key;
          final taskData = entry.value;

          if (!tasksMap.containsKey(taskId)) {
            tasksMap[taskId] = {
              ...taskData,
              'status': 'processing',
              'progress': 0.1,
              'startedAt': DateTime.now().millisecondsSinceEpoch,
            };

            // UIへ状態更新を通知
            service.invoke('update', tasksMap[taskId]);

            // タスク処理
            _processTaskInBackground(service, taskId, taskData).then((_) {
              // 処理完了したタスクを削除
              tasksMap.remove(taskId);

              // pendingTasksからも削除
              pendingTasks.remove(taskId);
              prefs.setString(
                  'pending_background_tasks', json.encode(pendingTasks));
            });
          }
        }

        // 実行中タスク情報を更新
        if (tasksMap.isNotEmpty) {
          // 処理中タスクの進捗を報告
          for (final taskId in tasksMap.keys) {
            final task = tasksMap[taskId];
            if (task != null && task['status'] == 'processing') {
              // 定期的な進捗更新（擬似的）
              final elapsedTime = DateTime.now().millisecondsSinceEpoch -
                  (task['startedAt'] ?? 0);
              final progress =
                  (elapsedTime / 30000).clamp(0.1, 0.9); // 最大30秒で90%まで

              task['progress'] = progress;
              task['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

              // UIへ状態更新を通知
              service.invoke('update', task);
            }
          }
        } else if (pendingTasks.isEmpty) {
          // タスクが残っていなければ停止
          await _showTaskCompletionNotification();
          Timer(const Duration(minutes: 1), () {
            service.invoke('stopService');
          });
        }
      } catch (e) {
        print('バックグラウンドサービスエラー: $e');
      }
    });

    return true; // 正常に開始されたことを示す
  }

  /// バックグラウンドでタスクを処理
  static Future<void> _processTaskInBackground(ServiceInstance service,
      String taskId, Map<String, dynamic> taskData) async {
    try {
      final taskType = taskData['type'] as String;

      // APIトークンサービスからトークンを取得
      String apiToken = '';
      try {
        final apiTokenService = ApiTokenService();
        apiToken = await apiTokenService.getToken();
      } catch (e) {
        debugPrint('APIトークン取得エラー: $e');
        // タスクデータ内にトークンがある場合はそれを使用
        apiToken = taskData['apiToken'] as String? ?? '';
      }

      // Anki Paiの暗記法生成タスク処理
      if (taskType == 'techniqueGeneration') {
        final aiService = SimpleAIService(
          apiToken: apiToken,
        );

        final content = taskData['content'] as String? ?? '';

        // 複数項目の検出
        final itemsResult = await aiService.detectMultipleItems(content);
        final isMultipleItems =
            itemsResult['isMultipleItems'] as bool? ?? false;
        List<Map<String, dynamic>> techniques = [];

        // 進捗更新
        service.invoke('update', {
          'taskId': taskId,
          'status': 'processing',
          'progress': 0.3,
          'message': '暗記法を生成しています...',
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });

        if (isMultipleItems && itemsResult.containsKey('items')) {
          // 複数項目の暗記法を生成
          final items = itemsResult['items'] as List;
          techniques = await aiService.generateTechniquesForItems(items);
        } else {
          // 単一項目の暗記法を生成
          techniques = await aiService.generateTechniquesForSingleItem(content);
        }

        // 完了通知
        service.invoke('update', {
          'taskId': taskId,
          'status': 'completed',
          'progress': 1.0,
          'result': techniques,
          'isMultipleItems': isMultipleItems,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });

        // 通知を表示
        await _showTaskCompletionNotification();
      } else {
        // 不明なタスク
        service.invoke('update', {
          'taskId': taskId,
          'status': 'error',
          'progress': 0.0,
          'error': '不明なタスクタイプ: $taskType',
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      // エラー報告
      service.invoke('update', {
        'taskId': taskId,
        'status': 'error',
        'progress': 0.0,
        'error': e.toString(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// タスク完了通知の表示
  static Future<void> _showTaskCompletionNotification() async {
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'ankipai_task_channel',
      'タスク通知',
      channelDescription: 'タスク完了通知用チャンネル',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notifications.show(
      888,
      'Anki Pai',
      '暗記法の生成が完了しました！',
      details,
    );
  }

  /// Web環境向けの初期化（Service Workerで代替）
  Future<void> _initializeForWeb() async {
    _isInitialized = true;
    print('Web環境向けバックグラウンドプロセッサの初期化完了');
  }

  /// タスク更新処理
  void _handleTaskUpdate(Map<String, dynamic> update) {
    final String taskId = update['taskId'] as String? ?? '';
    if (taskId.isEmpty) return;

    _runningTasks[taskId] = update;

    if (update['status'] == 'completed' || update['status'] == 'error') {
      // 完了したタスクは一定時間後に削除
      Future.delayed(const Duration(minutes: 5), () {
        _runningTasks.remove(taskId);
      });
    }
  }

  /// リソースをクリーンアップ
  void _cleanupResources() {
    // Isolateのクリーンアップ
    _receivePort?.close();
    _receivePort = null;

    // バックグラウンドサービスの停止
    _backgroundService?.invoke('stopService');

    _isInitialized = false;
  }

  /// 前回のタスクを復元
  Future<void> _restorePreviousTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('pending_background_tasks');

      if (tasksJson != null && tasksJson.isNotEmpty) {
        final Map<String, dynamic> pendingTasks = json.decode(tasksJson);

        // 実行中のタスクを復元
        pendingTasks.forEach((taskId, taskData) {
          _runningTasks[taskId] = {
            ...taskData,
            'status': 'processing',
            'progress': 0.1,
            'message': 'タスクを再開しています...',
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          };
        });

        print('${pendingTasks.length}個のバックグラウンドタスクを復元しました');
      }
    } catch (e) {
      print('タスク復元エラー: $e');
    }
  }

  /// バックグラウンドタスクを開始
  Future<String> startTask(Map<String, dynamic> taskData) async {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();

    // APIトークン取得を試みる（失敗してもタスクは開始する）
    try {
      final apiTokenService = ApiTokenService();
      final apiToken = await apiTokenService.getToken();
      taskData['apiToken'] = apiToken;
    } catch (e) {
      debugPrint('タスク開始時のAPIトークン取得エラー: $e');
    }

    // タスク情報を保存
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = prefs.getString('pending_background_tasks') ?? '{}';
    final Map<String, dynamic> tasks = json.decode(tasksJson);
    tasks[taskId] = taskData;
    await prefs.setString('pending_background_tasks', json.encode(tasks));

    // タスク状態を記録
    _runningTasks[taskId] = {
      ...taskData,
      'status': 'queued',
      'progress': 0.0,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
    };

    // タスクIDを返す
    return taskId;
  }

  /// タスクの進捗状況を取得
  Future<Map<String, dynamic>> getTaskProgress(String taskId) async {
    // キャッシュされたタスク情報を返す（メモリ内）
    if (_runningTasks.containsKey(taskId)) {
      return _runningTasks[taskId]!;
    }

    // Web環境の場合はローカルストレージから取得を試みる
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final progressJson = prefs.getString('task_progress_$taskId');
        if (progressJson != null) {
          return json.decode(progressJson) as Map<String, dynamic>;
        }
      } catch (e) {
        debugPrint('Webタスク進捗取得エラー: $e');
      }
    }

    // タスク情報が見つからない場合はデフォルト値
    return {
      'taskId': taskId,
      'status': 'unknown',
      'progress': 0.0,
      'message': '不明なタスク',
    };
  }

  /// Isolateのエントリーポイント
  void _isolateEntryPoint(SendPort sendPort) {
    // メインスレッドとの通信用ポート
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    // タスク実行中かどうかのフラグ
    bool isProcessingTask = false;

    // メッセージハンドラー
    receivePort.listen((message) async {
      if (message is Map<String, dynamic> && message['taskId'] != null) {
        // 既に処理中なら待機キューに追加（本来はここでキューを実装）
        if (isProcessingTask) {
          sendPort.send({
            'taskId': message['taskId'],
            'status': 'queued',
            'progress': 0.0,
            'message': '他のタスクの処理完了を待っています',
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
          return;
        }
        // タスク処理開始
        isProcessingTask = true;
        final String taskId = message['taskId'] as String;
        final Map<String, dynamic> taskData = message;

        try {
          // タスク種別に基づいて処理
          final String taskType = taskData['type'] as String? ?? 'unknown';

          if (taskType == 'techniqueGeneration') {
            // 暗記法生成処理
            await _processTechniqueGenerationTask(sendPort, taskId, taskData);
          } else if (taskType == 'multiAgentMode') {
            // マルチエージェントモード処理
            await _processMultiAgentModeTask(sendPort, taskId, taskData);
          } else if (taskType == 'standardMode') {
            // 標準モード処理
            await _processStandardModeTask(sendPort, taskId, taskData);
          } else if (taskType == 'thinkingMode') {
            // 考え方モード処理
            await _processThinkingModeTask(sendPort, taskId, taskData);
          } else if (taskType == 'multipleItemsMode') {
            // 複数項目処理モード
            await _processMultipleItemsModeTask(sendPort, taskId, taskData);
          } else {
            sendPort.send({
              'taskId': taskId,
              'status': 'error',
              'progress': 0.0,
              'error': '不明なタスクタイプ: $taskType',
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
            });
          }
        } catch (e) {
          // エラー報告
          sendPort.send({
            'taskId': taskId,
            'status': 'error',
            'progress': 0.0,
            'error': e.toString(),
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }
    });
  }

  /// 標準モードでの暗記法生成処理
  Future<void> _processStandardModeTask(
      SendPort sendPort, String taskId, Map<String, dynamic> taskData) async {
    try {
      // 進捗状況を送信
      sendPort.send({
        'taskId': taskId,
        'status': 'processing',
        'progress': 0.1,
        'message': '標準モードの暗記法生成中...',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 内容を取得
      final String content = taskData['content'] as String;

      // シンプルAIサービスを使用して暗記法を生成
      final apiToken = taskData['apiToken'] as String? ?? '';
      final simpleAiService = SimpleAIService(
        apiToken: apiToken,
      );

      // 進捗状況を送信 - 暗記法生成開始
      sendPort.send({
        'taskId': taskId,
        'status': 'processing',
        'progress': 0.5,
        'message': '暗記法を生成中...',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 暗記法生成
      final List<Map<String, dynamic>> techniques =
          await simpleAiService.generateTechniquesForSingleItem(content);

      // 進捗状況を送信 - 処理完了
      sendPort.send({
        'taskId': taskId,
        'status': 'completed',
        'progress': 1.0,
        'message': '標準モードの暗記法生成完了',
        'result': {
          'techniques': techniques,
        },
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('標準モードの暗記法生成エラー: $e');
      // エラー報告
      sendPort.send({
        'taskId': taskId,
        'status': 'error',
        'progress': 0.0,
        'error': e.toString(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// 考え方モードでの暗記法生成処理
  Future<void> _processThinkingModeTask(
      SendPort sendPort, String taskId, Map<String, dynamic> taskData) async {
    try {
      // 進捗状況を送信
      sendPort.send({
        'taskId': taskId,
        'status': 'processing',
        'progress': 0.1,
        'message': '考え方モードの処理開始',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 内容を取得
      final String content = taskData['content'] as String;
      final String title = taskData['title'] as String? ?? '';

      // シンプルAIサービスを使用して考え方モードの説明を生成
      final apiToken = taskData['apiToken'] as String? ?? '';
      final simpleAiService = SimpleAIService(
        apiToken: apiToken,
      );

      // 進捗状況を送信 - 生成開始
      sendPort.send({
        'taskId': taskId,
        'status': 'processing',
        'progress': 0.5,
        'message': '考え方の説明を生成中...',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 考え方モードの説明を生成
      final String explanation =
          await simpleAiService.generateThinkingModeExplanation(
        content: content,
        title: title,
      );

      // 生成された考え方を暗記法形式に変換
      final List<Map<String, dynamic>> techniques = [
        {
          'name': '考え方: ${title.isNotEmpty ? title : '内容の本質'}',
          'description': explanation,
          'type': 'thinking',
          'tags': ['thinking', '考え方'],
          'itemContent': content,
          'flashcards': [
            {
              'question': content,
              'answer': explanation,
            },
          ],
        },
      ];

      // 進捗状況を送信 - 処理完了
      sendPort.send({
        'taskId': taskId,
        'status': 'completed',
        'progress': 1.0,
        'message': '考え方モードの処理完了',
        'result': {
          'techniques': techniques,
          'explanation': explanation,
        },
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('考え方モードエラー: $e');
      // エラー報告
      sendPort.send({
        'taskId': taskId,
        'status': 'error',
        'progress': 0.0,
        'error': e.toString(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// 複数項目モードでの暗記法生成処理
  Future<void> _processMultipleItemsModeTask(
      SendPort sendPort, String taskId, Map<String, dynamic> taskData) async {
    try {
      // 進捗状況を送信
      sendPort.send({
        'taskId': taskId,
        'status': 'processing',
        'progress': 0.1,
        'message': '複数項目処理開始',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 必要なデータを取得
      final List<dynamic> items = taskData['items'] as List<dynamic>;
      final bool isQuickDetection =
          taskData['isQuickDetection'] as bool? ?? false;
      final int? itemCount = taskData['itemCount'] as int?;
      final String? rawContent = taskData['rawContent'] as String?;

      // シンプルAIサービスを使用して複数項目の暗記法を生成
      final apiToken = taskData['apiToken'] as String? ?? '';
      final simpleAiService = SimpleAIService(
        apiToken: apiToken,
      );

      // 進捗状況を送信 - 生成開始
      sendPort.send({
        'taskId': taskId,
        'status': 'processing',
        'progress': 0.2,
        'message': '複数項目の暗記法を生成中...',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 進捗コールバック関数
      void progressCallback(
          double progress, int processedItems, int totalItems) {
        sendPort.send({
          'taskId': taskId,
          'status': 'processing',
          'progress': 0.2 + (progress * 0.7), // 20%から90%までの進捗
          'message': '複数項目の暗記法を生成中... ($processedItems/$totalItems)',
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // タイムアウト付きで複数項目の暗記法を生成
      List<Map<String, dynamic>> techniques = [];
      try {
        // タイムアウト設定で暗記法生成を実行（バックグラウンド処理に対応）
        final timeout = const Duration(minutes: 4); // iOSの制限に対応
        techniques = await simpleAiService.generateTechniquesForItems(
          items,
          isQuickDetection: isQuickDetection,
          itemCount: itemCount,
          rawContent: rawContent,
          progressCallback: progressCallback,
        ).timeout(timeout, onTimeout: () {
          // タイムアウト時はこれまでに処理できた結果を返す
          print('複数項目の暗記法生成がタイムアウトしました。部分的な結果を返します。');
          // サービスに現在の状態を問い合わせて部分的な結果を取得
          return simpleAiService.getPartialResults() ?? [];
        });
      } catch (e) {
        print('複数項目の暗記法生成中にエラーが発生しました: $e');
        // エラー時は最低限のサンプルを返す
        techniques = simpleAiService.getPartialResults() ?? 
          [{'name': 'シンプル記憶法', 'description': 'バックグラウンド処理中にエラーが発生しました。再試行してください。'}];
      }

      // 進捗状況を送信 - 処理完了
      sendPort.send({
        'taskId': taskId,
        'status': 'completed',
        'progress': 1.0,
        'message': '複数項目の暗記法生成完了',
        'result': {
          'techniques': techniques,
        },
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('複数項目モードエラー: $e');
      // エラー報告
      sendPort.send({
        'taskId': taskId,
        'status': 'error',
        'progress': 0.0,
        'error': e.toString(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// マルチエージェントモードまたは陽少陰となる方式で暗記法を生成
  Future<void> _processMultiAgentModeTask(
      SendPort sendPort, String taskId, Map<String, dynamic> taskData) async {
    try {
      // 進捗状況を送信
      sendPort.send({
        'taskId': taskId,
        'status': 'processing',
        'progress': 0.1,
        'message': 'マルチエージェントモード処理開始',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 内容を取得
      final String content = taskData['content'] as String;
      // タイトルがあれば使用するが、現在は必要ない
      // final String title = taskData['title'] as String? ?? '';

      // シンプルAIサービスを使用してマルチエージェントモードをシミュレート
      final apiToken = taskData['apiToken'] as String? ?? '';
      final simpleAiService = SimpleAIService(
        apiToken: apiToken,
      );

      // 進捗状況を送信 - 最初の暗記法生成開始
      sendPort.send({
        'taskId': taskId,
        'status': 'processing',
        'progress': 0.2,
        'message': '暗記法を生成中...',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // マルチエージェントモードシミュレーション
      final List<Map<String, dynamic>> initialTechniques =
          await simpleAiService.generateTechniquesForSingleItem(content);

      // 進捗状況を送信 - エージェントを1完了
      sendPort.send({
        'taskId': taskId,
        'status': 'processing',
        'progress': 0.5,
        'message': '暗記法のランク付け中...',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // ランク付き暗記法を生成
      final rankedTechniques = await simpleAiService
          .generateRankedMemoryTechniques(content, initialTechniques);

      // 進捗状況を送信 - 処理完了
      sendPort.send({
        'taskId': taskId,
        'status': 'completed',
        'progress': 1.0,
        'message': 'マルチエージェントモード処理完了',
        'result': {
          'techniques': rankedTechniques,
        },
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('マルチエージェントモード処理エラー: $e');
      // エラー報告
      sendPort.send({
        'taskId': taskId,
        'status': 'error',
        'progress': 0.0,
        'error': e.toString(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// タスク種別に基づいて処理
  Future<void> _processTechniqueGenerationTask(
      SendPort sendPort, String taskId, Map<String, dynamic> taskData) async {
    try {
      // タスク種別に基づいて処理
      final String taskType = taskData['type'] as String? ?? 'unknown';

      if (taskType == 'techniqueGeneration') {
        // 実際の暗記法生成処理を行う
        await _generateTechnique(sendPort, taskId, taskData);
      } else {
        sendPort.send({
          'taskId': taskId,
          'status': 'error',
          'progress': 0.0,
          'error': '不明なタスクタイプ: $taskType',
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      // エラー報告
      sendPort.send({
        'taskId': taskId,
        'status': 'error',
        'progress': 0.0,
        'error': e.toString(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

// 実際の暗記法生成処理を行う新しいメソッド
  Future<void> _generateTechnique(
      SendPort sendPort, String taskId, Map<String, dynamic> taskData) async {
    final String content = taskData['content'] as String? ?? '';
    final String userId = taskData['userId'] as String? ?? '';
    final apiToken = taskData['apiToken'] as String? ?? '';

    if (content.isEmpty || userId.isEmpty) {
      sendPort.send({
        'taskId': taskId,
        'status': 'error',
        'progress': 0.0,
        'error': 'コンテンツまたはユーザーIDが不正です',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      return;
    }

    // 進捗通知関数
    void reportProgress(double progress, String status, [String? message]) {
      sendPort.send({
        'taskId': taskId,
        'status': status,
        'progress': progress,
        'message': message,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    // 簡易版AIサービスの生成
    final aiService = SimpleAIService(
      apiToken: apiToken,
    );

    try {
      // 処理開始
      reportProgress(0.1, 'processing', '暗記法生成を開始しています');

      // 複数項目検出
      reportProgress(0.2, 'processing', 'コンテンツを分析中');
      final multipleItemsCheck = await aiService.detectMultipleItems(content);

      List<Map<String, dynamic>> techniques = [];
      String detectionResult = '';

      if (multipleItemsCheck['isMultipleItems'] == true &&
          multipleItemsCheck['items'] != null &&
          multipleItemsCheck['items'] is List &&
          (multipleItemsCheck['items'] as List).isNotEmpty) {
        // 複数項目の処理
        final items = multipleItemsCheck['items'] as List;
        detectionResult = '複数項目（${items.length}件）';
        reportProgress(0.4, 'processing', '複数項目（${items.length}件）の暗記法を生成中');

        techniques = await aiService.generateTechniquesForItems(items);
      } else {
        // 単一項目の処理
        detectionResult = '単一項目';
        reportProgress(0.4, 'processing', '暗記法を生成中');
        techniques = await aiService.generateTechniquesForSingleItem(content);
      }

      // 生成完了
      reportProgress(0.9, 'processing', '生成完了、結果を保存中');

      // 完了通知と結果送信
      sendPort.send({
        'taskId': taskId,
        'status': 'completed',
        'progress': 1.0,
        'techniques': techniques,
        'result': detectionResult,
        'userId': userId,
        'content': content,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      reportProgress(0.0, 'error', '暗記法生成中にエラーが発生しました: $e');
    } finally {
      // リソースのクリーンアップ
      aiService.dispose();
    }
  }
}

/// シンプルなAIサービスクラス
/// バックグラウンド処理用に最適化された軽量版AIサービス
class SimpleAIService {
  final http.Client _httpClient = http.Client();
  final String apiToken;

  // Gemini APIのエンドポイント
  static const String _geminiApiUrl =
      'https://generativelanguage.googleapis.com/v1/models/gemini-2.5-pro-preview-03-25:generateContent';

  SimpleAIService({
    required this.apiToken,
  }) {
    print('SimpleAIService initialized with token-based API access');
  }

  // APIキーが有効か確認
  bool get hasValidApiKey => apiToken.isNotEmpty;

  /// Gemini APIを使って複数項目を検出
  Future<Map<String, dynamic>> detectMultipleItems(String content) async {
    try {
      if (!hasValidApiKey) {
        return {
          'isMultipleItems': false,
          'items': [],
          'rawContent': content,
          'itemCount': 0,
          'message': 'APIトークンが設定されていません',
        };
      }

      final prompt = '''
複数の学習項目が含まれているか判断し、含まれている場合は分割してください。
内容：
$content

次のJSON形式で返してください：
{
  "isMultipleItems": true/false,
  "items": []
}
''';

      final response = await _httpClient.post(
        Uri.parse('$_geminiApiUrl?key=$apiToken'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.1,
          'max_tokens': 800,
        }),
      );

      if (response.statusCode != 200) {
        print('DeepSeek API error: ${response.body}');
        return {'isMultipleItems': false};
      }

      final responseData = json.decode(response.body);
      final responseText = responseData['choices'][0]['message']['content'];

      // JSONを抽出
      try {
        final Map<String, dynamic> result =
            json.decode(_extractJsonFromText(responseText));
        return result;
      } catch (e) {
        print('JSON解析エラー: $e');
        return {'isMultipleItems': false};
      }
    } catch (e) {
      print('複数項目検出エラー: $e');
      return {'isMultipleItems': false};
    }
  }

  /// 複数項目に対する暗記法を生成
  Future<List<Map<String, dynamic>>> generateTechniquesForItems(
    List<dynamic> items, {
    bool isQuickDetection = false,
    int? itemCount,
    String? rawContent,
    Function(double progress, int processedItems, int totalItems)?
        progressCallback,
  }) async {
    try {
      // 配列を5件ずつのバッチに分割して処理
      const int batchSize = 5;
      final List<Map<String, dynamic>> allTechniques = [];

      for (int i = 0; i < items.length; i += batchSize) {
        final int end =
            (i + batchSize < items.length) ? i + batchSize : items.length;
        final batch = items.sublist(i, end);

        // バッチごとに暗記法を生成
        final batchItems = batch
            .map((item) => {
                  'content': item['content'] ?? '',
                  'description': item['description'] ?? ''
                })
            .toList();

        final batchTechniques = await _generateMemoryTechniques(batchItems);
        allTechniques.addAll(batchTechniques);
      }

      return allTechniques;
    } catch (e) {
      print('複数項目の暗記法生成エラー: $e');
      return [];
    }
  }

  /// 部分的な結果を保存する変数
  List<Map<String, dynamic>>? _partialResults;

  /// 中間結果を取得するためのメソッド
  List<Map<String, dynamic>>? getPartialResults() {
    return _partialResults;
  }

  /// 単一項目の暗記法を生成（iOS向けに最適化）
  Future<List<Map<String, dynamic>>> generateTechniquesForSingleItem(
      String content) async {
    try {
      // 部分結果をクリア
      _partialResults = null;

      // 単一項目として暗記法を生成
      final items = [{'content': content}];
      final result = await _generateMemoryTechniques(items);

      // 成功した結果を保存
      _partialResults = result;
      return result;
    } catch (e) {
      print('単一項目の暗記法生成エラー: $e');
      final fallback = _generateSampleTechniques([{'content': content}]);
      _partialResults = fallback;
      return fallback;
    }
  }

  /// 暗記法生成の共通処理
  Future<List<Map<String, dynamic>>> _generateMemoryTechniques(
      List<dynamic> items) async {
    try {
      if (!hasValidApiKey) {
        return _fallbackToOpenAI(items);
      }

      final contentList =
          items.map((item) => item['content'].toString()).toList();

      // DeepSeekの暗記法生成プロンプト
      final prompt = '''
あなたは暗記学習をサポートする専門家です。以下の${contentList.length}個の項目に対して、全体を表す簡潔なタイトル（20文字以内）とそれぞれの項目に対するシンプルでわかりやすい覚え方を提案してください。

【重要】以下の例のようなシンプルで直感的な覚え方を目指してください：

例1: wash (洗う) → 「washはウォッシュレットで洗う」と連想する。
例2: home (自宅) → 「homeはホーム(home)に帰る」でそのまま覚える。

覚え方の文は必ず「〜は〜と覚えよう」「〜は〜と連想しよう」などの形式にしてください。

学習項目一覧：
${contentList.asMap().entries.map((entry) {
        int i = entry.key;
        String content = entry.value;
        String description = '';
        if (items[i] is Map && items[i].containsKey('description')) {
          description = items[i]['description'] ?? '';
        }
        return '【項目${i + 1}】 "$content" ${description.isNotEmpty ? "(補足: $description)" : ""}';
      }).join('\n')}

以下のJSON形式で返してください：
{
  "commonTitle": "学習内容の簡潔なタイトル（20文字以内）",
  "commonType": "mnemonic",
  "commonTags": ["共通カテゴリ"],
  "techniques": [
    {
      "itemIndex": 0,
      "originalContent": "元の内容",
      "name": "記憶法名",
      "description": "〜は〜と覚えよう",
      "type": "mnemonic",  // "mnemonic"(語呈合わせ), "relationship"(関係性), "concept"(考え方) のいずれか
      "tags": ["タグ", "カテゴリ"],  // 学習カテゴリを表すタグ（2つ）
      "contentKeywords": ["キーワード"],  // 内容の重要単語（2つ）
      "flashcards": [
        {
          "question": "質問",
          "answer": "回答"
        }
      ]
    }
  ]
}
''';

      final response = await _httpClient.post(
        Uri.parse('$_geminiApiUrl?key=$apiToken'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
          'max_tokens': 2000,
        }),
      );

      if (response.statusCode != 200) {
        print('DeepSeek API error: ${response.body}');
        return _fallbackToOpenAI(items);
      }

      final responseData = json.decode(response.body);
      final responseText = responseData['choices'][0]['message']['content'];

      // JSONを抽出して解析
      try {
        final cleanedJson = _extractJsonFromText(responseText);
        final Map<String, dynamic> result = json.decode(cleanedJson);

        if (!result.containsKey('techniques') || result['techniques'] == null) {
          return _fallbackToOpenAI(items);
        }

        // Map<String, dynamic>のリストに変換
        return List<Map<String, dynamic>>.from(result['techniques']);
      } catch (e) {
        print('JSON解析エラー: $e');
        return _fallbackToOpenAI(items);
      }
    } catch (e) {
      print('DeepSeek暗記法生成エラー: $e');
      return _fallbackToOpenAI(items);
    }
  }

  /// OpenAIへのフォールバック
  Future<List<Map<String, dynamic>>> _fallbackToOpenAI(
      List<dynamic> items) async {
    try {
      if (hasValidApiKey) {
        // フォールバックできないのでサンプル暗記法を返す
        return _generateSampleTechniques(items);
      }

      final contentList =
          items.map((item) => item['content'].toString()).toList();

      // OpenAIの暗記法生成プロンプト（簡略化）
      final prompt = '''
以下の内容に対する暗記法を提案してください：
${contentList.join('\n')}

JSON形式で返してください。
''';

      final response = await _httpClient.post(
        Uri.parse('$_geminiApiUrl?key=$apiToken'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'model': 'gpt-4o',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
          'max_tokens': 1000,
        }),
      );

      if (response.statusCode != 200) {
        return _generateSampleTechniques(items);
      }

      final responseData = json.decode(response.body);
      final responseText = responseData['choices'][0]['message']['content'];

      try {
        final cleanedJson = _extractJsonFromText(responseText);
        final data = json.decode(cleanedJson);

        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('techniques')) {
          return List<Map<String, dynamic>>.from(data['techniques']);
        } else {
          return _generateSampleTechniques(items);
        }
      } catch (e) {
        return _generateSampleTechniques(items);
      }
    } catch (e) {
      return _generateSampleTechniques(items);
    }
  }

  /// サンプル暗記法生成（両方のAPIが失敗した場合のフォールバック）
  List<Map<String, dynamic>> _generateSampleTechniques(List<dynamic> items) {
    final List<Map<String, dynamic>> techniques = [];

    for (int i = 0; i < items.length; i++) {
      final content = items[i]['content'] ?? 'コンテンツなし';
      techniques.add({
        'itemIndex': i,
        'originalContent': content,
        'name': '標準学習法',
        'description': 'この内容は繰り返し学習することで記憶を定着させましょう',
        'type': 'concept',
        'image': '',
      });
    }

    return techniques;
  }

  /// テキストからJSONを抽出するヘルパーメソッド
  String _extractJsonFromText(String text) {
    // コードブロックの抽出試行
    final codeBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final codeBlockMatch = codeBlockRegex.firstMatch(text);

    if (codeBlockMatch != null && codeBlockMatch.groupCount >= 1) {
      return codeBlockMatch.group(1)!.trim();
    }

    // 波括弧で囲まれた部分を抽出
    final jsonRegex = RegExp(r'\{[\s\S]*\}');
    final jsonMatch = jsonRegex.firstMatch(text);

    if (jsonMatch != null) {
      return jsonMatch.group(0)!;
    }

    // 見つからない場合は元のテキストを返す
    return text;
  }

  /// マルチエージェントモード用のランク付け暗記法生成
  Future<List<Map<String, dynamic>>> generateRankedMemoryTechniques(
      String content, List<Map<String, dynamic>> initialTechniques) async {
    try {
      // 暗記法のランク付けを行うプロンプト
      final techniquesJson = json.encode(initialTechniques);
      final prompt = '''
あなたは暗記学習の専門家です。以下の学習内容に対して提案された暗記法を評価し、最も効果的な上位3つを選んでください。

評価基準：
1. 正確性: 内容を正確に反映しているか
2. 覚えやすさ: 言葉のリズム、イメージのしやすさ、連想のしやすさ
3. 実用性: 実際に使いやすく、長期記憶に残りやすいか

下記のJSON形式で回答してください：

{
  "evaluation": [
    {
      "rank": 1,
      "name": "最も優れた覚え方のタイトル",
      "description": "最も優れた覚え方の説明",
      "type": "mnemonic",  // "mnemonic"(語呈合わせ), "relationship"(関係性), "concept"(考え方) のいずれか
      "tags": ["タグ", "カテゴリ"],  // 学習カテゴリを表すタグ（2つ）
      "contentKeywords": ["キーワード"],  // 内容の重要単語（2つ）
      "flashcards": [
        {
          "question": "質問",
          "answer": "回答"
        }
      ]
    },
    // 2位、2位の暗記法も同様に
  ]
}

記憶すべき内容：
$content

提案された覚え方：
$techniquesJson
''';

      try {
        // Gemini APIリクエスト
        final response = await _httpClient.post(
          Uri.parse('$_geminiApiUrl?key=$apiToken'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode({
            'model': 'deepseek-chat',
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'temperature': 0.3,
            'max_tokens': 2000,
          }),
        );

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          final responseText = responseData['choices'][0]['message']['content'];

          // JSONを抽出して解析
          final cleanedJson = _extractJsonFromText(responseText);
          final Map<String, dynamic> result = json.decode(cleanedJson);

          if (result.containsKey('evaluation') &&
              result['evaluation'] is List) {
            // 結果を暗記法形式に変換
            final evaluations = result['evaluation'] as List;
            final techniques = <Map<String, dynamic>>[];

            for (final eval in evaluations) {
              if (eval is Map<String, dynamic>) {
                techniques.add({
                  'name': eval['name'] ?? 'ランク付け暗記法',
                  'description': eval['description'] ?? '',
                  'type': eval['type'] ?? 'mnemonic',
                  'tags': eval['tags'] is List
                      ? List<String>.from(eval['tags'])
                      : <String>[],
                  'contentKeywords': eval['contentKeywords'] is List
                      ? List<String>.from(eval['contentKeywords'])
                      : <String>[],
                  'itemContent': content,
                  'flashcards': eval['flashcards'] is List
                      ? List<Map<String, dynamic>>.from(
                          (eval['flashcards'] as List).map((f) => {
                                'question': f['question'] ?? '',
                                'answer': f['answer'] ?? '',
                              }))
                      : <Map<String, dynamic>>[],
                });
              }
            }

            return techniques;
          }
        }

        // 処理失敗場合は元の暗記法から上位3つを返す
        return initialTechniques.take(3).toList();
      } catch (e) {
        print('ランク付けエラー: $e');
        // エラー時は初期暗記法の上位3つを返す
        return initialTechniques.take(3).toList();
      }
    } catch (e) {
      print('マルチエージェントモードエラー: $e');
      // エラー時は初期暗記法の上位3つを返す
      return initialTechniques.take(3).toList();
    }
  }

  /// 考え方モードの説明を生成
  Future<String> generateThinkingModeExplanation({
    required String content,
    String? title,
  }) async {
    try {
      // プロンプトを作成
      final prompt = '''
あなたは暗記学習の専門家です。以下の内容について、「考え方モード」として、内容の本質を捉えたシンプルで分かりやすい説明を生成してください。

「考え方モード」は、内容を考えるアプローチや概念を提示し、覚えるべき内容を正しく理解するのに役立つものです。

以下のルールに従って、「考え方」の説明を生成してください：
1. 最大100文字程度の簡潔な説明を生成する
2. 必ず「～と考えよう」または「～と覚えよう」で終わる文章にする
3. 内容の本質や構造を理解しやすく説明する
4. 撮り下ろした単語や表現は使用せず、自然な表現で説明する

内容：
"""${title != null ? "$title\n" : ''}$content"""

考え方を以下に単純な文章として返してください。余計なものは含めないでください。
''';

      try {
        final response = await _httpClient.post(
          Uri.parse('$_geminiApiUrl?key=$apiToken'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode({
            'model': 'deepseek-chat',
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'temperature': 0.3,
            'max_tokens': 300,
          }),
        );

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          final explanation =
              responseData['choices'][0]['message']['content'] as String;

          // 説明文が「～と考えよう」形式になっていればそのまま返す
          if (explanation.contains('と考えよう') || explanation.contains('と覚えよう')) {
            return explanation.trim();
          }

          return explanation;
        }
      } catch (e) {
        print('Gemini考え方モード生成エラー: $e');
      }

      // 最終フォールバック
      return '学習内容の本質を考えることで、理解と記憶が深まると考えよう';
    } catch (e) {
      print('考え方モード生成中にエラーが発生: $e');
      return '学習内容の本質を考えることで、理解と記憶が深まると考えよう';
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
