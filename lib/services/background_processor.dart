import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// WorkManager用グローバルコールバック
// このコールバックはトップレベルで定義する必要があります
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    print('🔄 バックグラウンドタスクが開始されました: $taskName');
    try {
      switch (taskName) {
        case 'ankipaiPeriodicBackgroundTask':
          // 定期実行タスクの処理
          await _executePeriodicTask();
          break;
        case 'ankipaiInitBackgroundTask':
          // 初期化タスクの処理
          await _executeInitTask();
          break;
        default:
          print('⚠️ 未知のタスクタイプです: $taskName');
          return Future.value(false);
      }
      return Future.value(true);
    } catch (e) {
      print('⚠️ バックグラウンドタスク実行中にエラーが発生しました: $e');
      return Future.value(false);
    }
  });
}

// 定期実行タスクの処理
Future<void> _executePeriodicTask() async {
  final prefs = await SharedPreferences.getInstance();
  final lastRun = prefs.getInt('lastBackgroundTaskRun') ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  
  // 最終実行から現在までの経過時間をチェック
  await prefs.setInt('lastBackgroundTaskRun', now);
  
  // このタスクでは暗記Paiのデータ同期や通知処理などを実行
  print('✅ 定期実行タスクが完了しました');
}

// 初期化タスクの処理
Future<void> _executeInitTask() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('backgroundTaskInitialized', 1);
  
  // アプリ起動時の初期化処理をここで実行
  print('✅ 初期化タスクが完了しました');
}

// AlarmManager用のコールバック
@pragma('vm:entry-point')
void _periodicAlarmCallback() {
  print('⏰ アラームマネージャーが起動しました');
  // ここで必要な処理を実行
  // 例: 復習通知の送信
}

// ForegroundTask用のコールバック
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(ForegroundTaskHandler());
}

// ForegroundTask用のハンドラー
class ForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    print('🚀 フォアグラウンドタスクが開始されました');
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    // 定期的に実行される処理
    print('🔄 フォアグラウンドタスクのイベントが発生しました');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    print('🛑 フォアグラウンドタスクが停止されました');
    // 必要に応じてクリーンアップ処理を実行
  }

  @override
  void onButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.stopService();
    }
  }
}

/// バックグラウンドプロセッサ
/// Android向けバックグラウンド処理を実行するためのクラス
/// WorkManager, AlarmManager, ForegroundTaskを組み合わせて使用
class BackgroundProcessor {
  static final BackgroundProcessor _instance = BackgroundProcessor._internal();
  factory BackgroundProcessor() => _instance;
  BackgroundProcessor._internal();
  
  // 初期化フラグ
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  // バックグラウンド処理が利用可能か
  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;
  
  // ワーカー識別子
  static const String _workManagerTaskName = 'com.ankipai.backgroundTask';
  static const String _foregroundTaskId = 'ankipaiBackgroundTaskService';
  static const int _alarmManagerTaskId = 75647382; // 一意のID
  
  // 通知プラグイン
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  // バックグラウンド処理のキュー（メモリ内）
  final Map<String, Map<String, dynamic>> _taskQueue = {};
  
  // Firebase認証とデータベース
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // UUID生成
  final Uuid _uuid = Uuid();

  /// 初期化
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 通知の初期化
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();

      await _notifications.initialize(
        const InitializationSettings(android: androidSettings, iOS: iosSettings),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // 通知タップの処理
          print('📣 通知がタップされました: ${response.payload}');
        },
      );

      // Androidの場合のみバックグラウンド処理を初期化
      if (!kIsWeb && Platform.isAndroid) {
        // WorkManagerの初期化
        await Workmanager().initialize(
          _callbackDispatcher,  // グローバル関数が必要
          isInDebugMode: kDebugMode,
        );

        // AlarmManagerの初期化
        await AndroidAlarmManager.initialize();

        // ForegroundTaskの設定
        _initForegroundTask();

        _isAvailable = true;
        print('✅ Androidバックグラウンドプロセッサが正常に初期化されました');
      } else {
        print('⚠️ 現在のプラットフォームではバックグラウンド処理を実行できません');
        _isAvailable = false;
      }

      _isInitialized = true;
    } catch (e) {
      print('⚠️ バックグラウンドプロセッサの初期化に失敗しました: $e');
      _isAvailable = false;
      rethrow;
    }
  }

  /// ForegroundTaskの初期化
  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ankipai_foreground_task',
        channelName: 'AnkiPaiバックグラウンドタスク',
        channelDescription: 'バックグラウンドで実行中のタスクを通知',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
        buttons: [
          const NotificationButton(id: 'stop', text: '停止'),
        ],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,  // 5秒間隔
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// バックグラウンド処理の開始
  Future<void> startBackgroundProcessing() async {
    if (!_isInitialized) {
      print('⚠️ バックグラウンドプロセッサが初期化されていません');
      return;
    }

    if (!_isAvailable) {
      print('⚠️ 現在のプラットフォームではバックグラウンド処理が利用できません');
      return;
    }

    try {
      // 1. 定期的なタスクをWorkManagerで登録
      await Workmanager().registerPeriodicTask(
        _workManagerTaskName,
        'ankipaiPeriodicBackgroundTask',
        frequency: const Duration(hours: 1),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      // 2. または即時に実行する必要があるタスクを登録することも可能
      await Workmanager().registerOneOffTask(
        '${_workManagerTaskName}_init',
        'ankipaiInitBackgroundTask',
        initialDelay: const Duration(seconds: 10),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      // 3. 先軌タスクの場合は、AlarmManagerで設定
      await AndroidAlarmManager.periodic(
        const Duration(hours: 6),
        _alarmManagerTaskId,
        _periodicAlarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );

      // 4. ForegroundServiceを開始 (特定の処理で必要な場合)
      await _startForegroundService();

      print('✅ バックグラウンド処理が開始されました');
    } catch (e) {
      print('⚠️ バックグラウンド処理の開始に失敗しました: $e');
      rethrow;
    }
  }

  /// ForegroundServiceの開始
  Future<void> _startForegroundService() async {
    if (!FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        notificationTitle: '暗記Pai バックグラウンド処理',
        notificationText: '処理をバックグラウンドで実行中...',
        callback: _foregroundTaskCallback,
      );
    }
  }

  /// バックグラウンド処理の停止
  Future<void> stopBackgroundProcessing() async {
    if (!_isInitialized || !_isAvailable) {
      print('⚠️ バックグラウンドプロセッサを停止できません');
      return;
    }

    try {
      // 1. WorkManagerタスクをキャンセル
      await Workmanager().cancelByTag(_workManagerTaskName);
      await Workmanager().cancelByTag('${_workManagerTaskName}_init');

      // 2. AlarmManagerのタイマーをキャンセル
      await AndroidAlarmManager.cancel(_alarmManagerTaskId);

      // 3. ForegroundServiceを停止
      await FlutterForegroundTask.stopService();

      print('✅ バックグラウンド処理が停止されました');
    } catch (e) {
      print('⚠️ バックグラウンド処理の停止に失敗しました: $e');
      rethrow;
    }
  }

  /// タスクをバックグラウンドで実行（フォアグラウンドシミュレーション）
  Future<String> runTaskInBackground(
      String taskType, Map<String, dynamic> data) async {
    if (!_isInitialized) {
      throw Exception('バックグラウンドプロセッサが初期化されていません');
    }

    return _processTaskInForeground(taskType, data);
  }

  /// 既存コードとの互換性のためのメソッド
  /// startTaskのシグネチャを保持しつつ、内部でrunTaskInBackgroundを呼び出す
  Future<String> startTask(Map<String, dynamic> taskData) async {
    if (!_isInitialized) {
      throw Exception('バックグラウンドプロセッサが初期化されていません');
    }

    // タスクデータからタイプとデータを抽出
    final String taskType = taskData['type'] as String;

    return _processTaskInForeground(taskType, taskData);
  }

  /// 内部的にタスクを処理するための共通メソッド
  Future<String> _processTaskInForeground(
      String taskType, Map<String, dynamic> data) async {
    // タスクIDを生成
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();

    // タスクをキューに追加（メモリ内のみ）
    _taskQueue[taskId] = {
      'taskId': taskId,
      'taskType': taskType,
      'data': data,
      'status': 'pending',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };

    // タスク開始を通知
    _showTaskNotification(
        taskId, '処理を開始しました', '${_getTaskTypeName(taskType)}処理を開始しました');

    // 進捗情報を保存
    await _saveTaskProgress(taskId, 0.0, 'processing');

    try {
      // フォアグラウンドでタスクを実行（バックグラウンド実行のシミュレーション）
      await _processTask(taskId, taskType, data);

      // 完了を通知
      _showTaskNotification(
          taskId, '処理が完了しました', '${_getTaskTypeName(taskType)}処理が完了しました');

      // 完了状態を保存
      await _saveTaskProgress(taskId, 1.0, 'completed');

      return taskId;
    } catch (e) {
      print('⚠️ タスク処理中にエラーが発生しました: $e');

      // エラーを通知
      _showTaskNotification(taskId, '処理中にエラーが発生しました',
          '${_getTaskTypeName(taskType)}処理でエラーが発生しました');

      // エラー状態を保存
      await _saveTaskProgress(taskId, 0.0, 'error', error: e.toString());

      rethrow;
    }
  }

  /// タスク進捗の取得
  Future<Map<String, dynamic>> getTaskProgress(String taskId) async {
    if (!_isInitialized) {
      return {
        'status': 'error',
        'message': 'バックグラウンドプロセッサが初期化されていません',
      };
    }

    // メモリ内キューから確認
    if (_taskQueue.containsKey(taskId)) {
      return _taskQueue[taskId]!;
    }

    // SharedPreferencesから取得
    final prefs = await SharedPreferences.getInstance();
    final progressJson = prefs.getString('task_progress_$taskId');

    if (progressJson == null) {
      return {
        'status': 'error',
        'message': '指定されたタスクIDの進捗情報が見つかりません',
      };
    }

    try {
      return json.decode(progressJson) as Map<String, dynamic>;
    } catch (e) {
      return {
        'status': 'error',
        'message': '進捗情報の解析に失敗しました: $e',
      };
    }
  }

  /// タスク進捗の保存
  Future<void> _saveTaskProgress(String taskId, double progress, String status,
      {String? error}) async {
    // メモリ内キューの更新
    if (_taskQueue.containsKey(taskId)) {
      _taskQueue[taskId]!['status'] = status;
      _taskQueue[taskId]!['progress'] = progress;
      _taskQueue[taskId]!['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

      if (error != null) {
        _taskQueue[taskId]!['error'] = error;
      }
    }

    // SharedPreferencesに保存
    final prefs = await SharedPreferences.getInstance();
    final progressData = {
      'taskId': taskId,
      'status': status,
      'progress': progress,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    if (error != null) {
      progressData['error'] = error;
    }

    await prefs.setString('task_progress_$taskId', json.encode(progressData));

    // Firestoreにも保存（ユーザーがログインしている場合）
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('tasks')
            .doc(taskId)
            .set({
          'status': status,
          'progress': progress,
          'updatedAt': FieldValue.serverTimestamp(),
          if (error != null) 'error': error,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('⚠️ Firestoreへの進捗保存に失敗しました: $e');
    }
  }

  /// タスク処理（フォアグラウンドでシミュレーション）
  Future<void> _processTask(
      String taskId, String taskType, Map<String, dynamic> data) async {
    print('🔄 タスク処理を開始します: $taskType, ID: $taskId');

    // タスクタイプに応じた処理
    switch (taskType) {
      case 'generateTechnique':
        // 暗記法生成処理（シミュレーション）
        await Future.delayed(const Duration(seconds: 2));
        await _saveTaskProgress(taskId, 0.5, 'processing');

        // 実際の処理は行わず、短い遅延のみ
        await Future.delayed(const Duration(seconds: 2));
        break;

      case 'createFlashcards':
        // フラッシュカード作成処理（シミュレーション）
        await Future.delayed(const Duration(seconds: 2));
        await _saveTaskProgress(taskId, 0.5, 'processing');

        // 実際の処理は行わず、短い遅延のみ
        await Future.delayed(const Duration(seconds: 2));
        break;

      case 'analyzePerformance':
        // 学習分析処理（シミュレーション）
        await Future.delayed(const Duration(seconds: 2));
        await _saveTaskProgress(taskId, 0.5, 'processing');

        // 実際の処理は行わず、短い遅延のみ
        await Future.delayed(const Duration(seconds: 2));
        break;

      default:
        throw Exception('不明なタスクタイプです: $taskType');
    }

    print('✅ タスク処理が完了しました: $taskType, ID: $taskId');
  }

  /// タスク通知の表示
  void _showTaskNotification(String taskId, String title, String message) {
    // 通知の表示（Androidのみ）
    if (!kIsWeb && Platform.isAndroid) {
      _notifications.show(
        int.parse(taskId.substring(taskId.length - 8), radix: 16),
        title,
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'background_task_channel',
            'バックグラウンドタスク',
            channelDescription: 'バックグラウンドタスクの状態を通知します',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }
  }

  /// タスクタイプ名の取得
  String _getTaskTypeName(String taskType) {
    switch (taskType) {
      case 'generateTechnique':
        return '暗記法生成';
      case 'createFlashcards':
        return 'フラッシュカード作成';
      case 'analyzePerformance':
        return '学習分析';
      default:
        return '処理';
    }
  }
}
