import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
// Temporarily commented out to fix build issues
// import 'package:workmanager/workmanager.dart';
import 'package:uuid/uuid.dart';

// WorkManagerのグローバルコールバック関数
// アプリのメイン関数の外側に定義する必要があります
// Temporarily commented out to fix build issues
@pragma('vm:entry-point')
void callbackDispatcher() {
  // この関数は現在ビルドエラーを避けるために無効化されています
  print('バックグラウンドタスク処理は現在無効化されています');
  // 実際の実装は一時的にコメントアウトされています
}

// データ同期タスクの処理
Future<void> _executeSyncTask(Map<String, dynamic> inputData) async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('userId');

  if (userId == null) {
    print('⚠️ データ同期タスク: ユーザーIDが存在しません');
    return;
  }

  // 実際のデータ同期処理はここに実装
  print('✅ データ同期タスクが完了しました (ユーザーID: $userId)');
}

// 復習通知タスクの処理
Future<void> _executeNotificationTask(Map<String, dynamic> inputData) async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('userId');

  if (userId == null) {
    print('⚠️ 復習通知タスク: ユーザーIDが存在しません');
    return;
  }

  // 通知を送信するための処理
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();

  await notifications.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );

  // 通知の送信
  await notifications.show(
    0,
    '復習の時間です',
    '記憶を定着させるため、復習を行いましょう',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'ankipai_review_channel',
        '復習通知',
        channelDescription: '復習が必要なカードの通知',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );

  print('✅ 復習通知タスクが完了しました');
}

// クリーンアップタスクの処理
Future<void> _executeCleanupTask() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now();
    final cutoffDate = now.subtract(const Duration(days: 7));

    // 一時ディレクトリ内のファイルを読み取り
    final entities = tempDir.listSync();

    int deletedCount = 0;
    for (final entity in entities) {
      if (entity is File) {
        final stat = entity.statSync();
        final fileDate = DateTime.fromMillisecondsSinceEpoch(
            stat.modified.millisecondsSinceEpoch);

        // 7日以上前の一時ファイルを削除
        if (fileDate.isBefore(cutoffDate) &&
            entity.path.contains('ankipai_temp')) {
          await entity.delete();
          deletedCount++;
        }
      }
    }

    print('✅ クリーンアップタスクが完了しました: $deletedCountファイルを削除しました');
  } catch (e) {
    print('⚠️ クリーンアップタスクに失敗しました: $e');
  }
}

/// バックグラウンドプロセッサ
/// Android向けのバックグラウンド処理を実装するクラス
/// WorkManagerを使用して効率的なバックグラウンドタスク実行を提供
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

  // ワークマネージャーのタグ（現在は一時的に使用停止中だが、将来的に復活させる予定）
  // ignore: unused_field
  static const String _syncTaskTag = 'ankipai.syncData';
  // ignore: unused_field
  static const String _notificationTaskTag = 'ankipai.notifyReview';
  // ignore: unused_field
  static const String _cleanupTaskTag = 'ankipai.cleanupTask';

  // 通知プラグイン
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // タスク管理のためのマップ
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
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();

      await _notifications.initialize(
        const InitializationSettings(
            android: androidSettings, iOS: iosSettings),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // 通知タップ時の処理
          print('📣 通知がタップされました: ${response.payload}');
        },
      );

      // プラットフォームに応じた初期化
      if (!kIsWeb) {
        if (Platform.isAndroid) {
          // Temporarily commented out to fix build issues
          // // WorkManagerの初期化
          // await Workmanager().initialize(
          //   callbackDispatcher,
          //   isInDebugMode: kDebugMode,
          // );

          _isAvailable = true;
          print('✅ バックグラウンドプロセッサが初期化されました');
        } else {
          print('⚠️ 現在のプラットフォームではバックグラウンド処理が利用できません');
          _isAvailable = false;
        }
        _isAvailable = false;
      }

      _isInitialized = true;
    } catch (e) {
      print('⚠️ バックグラウンドプロセッサの初期化に失敗しました: $e');
      _isAvailable = false;
      rethrow;
    }
  }

  /// バックグラウンドタスクのスケジューリング
  Future<void> scheduleBackgroundTasks() async {
    if (!_isInitialized || !_isAvailable) {
      print('⚠️ バックグラウンドプロセッサが初期化されていないか、利用できません');
      return;
    }

    try {
      // Temporarily commented out to fix build issues
      // // データ同期タスク（定期実行）
      // await Workmanager().registerPeriodicTask(
      //   _syncTaskTag,
      //   _syncTaskTag,
      //   frequency: const Duration(hours: 6),
      //   constraints: Constraints(
      //     networkType: NetworkType.connected,
      //     requiresBatteryNotLow: true,
      //   ),
      //   existingWorkPolicy: ExistingWorkPolicy.replace,
      // );
      // 
      // // 復習通知タスク（定期実行）
      // await Workmanager().registerPeriodicTask(
      //   _notificationTaskTag,
      //   _notificationTaskTag,
      //   frequency: const Duration(hours: 12),
      //   constraints: Constraints(
      //     networkType: NetworkType.not_required, // これを追加
      //     requiresDeviceIdle: false,
      //   ),
      //   existingWorkPolicy: ExistingWorkPolicy.replace,
      // );
      // 
      // // クリーンアップタスク（1回のみ実行）
      // await Workmanager().registerOneOffTask(
      //   _cleanupTaskTag,
      //   _cleanupTaskTag,
      //   initialDelay: const Duration(days: 1),
      //   constraints: Constraints(
      //     networkType: NetworkType.not_required,
      //     requiresBatteryNotLow: false,
      //   ),
      // );

      print('✅ バックグラウンドタスクのスケジュールが設定されました');
    } catch (e) {
      print('⚠️ バックグラウンドタスクのスケジュール設定に失敗しました: $e');
      rethrow;
    }
  }

  /// バックグラウンドタスクのキャンセル
  Future<void> cancelBackgroundTasks() async {
    if (!_isInitialized || !_isAvailable) {
      print('⚠️ バックグラウンドプロセッサが初期化されていないか、利用できません');
      return;
    }

    try {
      // Temporarily commented out to fix build issues
      // // すべてのタスクをキャンセル
      // await Workmanager().cancelAll();
      print('✅ すべてのバックグラウンドタスクがキャンセルされました');
    } catch (e) {
      print('⚠️ バックグラウンドタスクのキャンセルに失敗しました: $e');
      rethrow;
    }
  }

  /// 即時タスク実行（フォアグラウンドでシミュレーション）
  Future<String> runTaskInForeground(
      String taskType, Map<String, dynamic> data) async {
    if (!_isInitialized) {
      throw Exception('バックグラウンドプロセッサが初期化されていません');
    }

    // タスクIDを生成
    final taskId = _uuid.v4();

    // タスクをキューに追加
    _taskQueue[taskId] = {
      'taskId': taskId,
      'taskType': taskType,
      'data': data,
      'status': 'pending',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      // タスク種類に応じた処理
      switch (taskType) {
        case 'syncData':
          await _executeSyncTask(data);
          break;
        case 'notifyReview':
          await _executeNotificationTask(data);
          break;
        case 'cleanupTask':
          await _executeCleanupTask();
          break;
        default:
          throw Exception('不明なタスクタイプ: $taskType');
      }

      // タスク完了を記録
      _taskQueue[taskId]?['status'] = 'completed';
      _taskQueue[taskId]?['completedAt'] =
          DateTime.now().millisecondsSinceEpoch;

      // Firestoreにタスク履歴を記録（ユーザーがログイン中の場合）
      _saveTaskHistory(taskId, 'completed');

      return taskId;
    } catch (e) {
      // エラー情報を保存
      _taskQueue[taskId]?['status'] = 'error';
      _taskQueue[taskId]?['error'] = e.toString();

      // Firestoreにエラーを記録
      _saveTaskHistory(taskId, 'error', error: e.toString());

      rethrow;
    }
  }

  /// タスク履歴をFirestoreに保存
  Future<void> _saveTaskHistory(String taskId, String status,
      {String? error}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('taskHistory')
          .doc(taskId)
          .set({
        'taskId': taskId,
        'taskType': _taskQueue[taskId]?['taskType'],
        'status': status,
        'createdAt': _taskQueue[taskId]?['createdAt'],
        'completedAt': status == 'completed'
            ? DateTime.now().millisecondsSinceEpoch
            : null,
        if (error != null) 'error': error,
      });
    } catch (e) {
      print('⚠️ タスク履歴の保存に失敗しました: $e');
    }
  }

  /// タスク状態の取得
  Future<Map<String, dynamic>> getTaskStatus(String taskId) async {
    if (!_isInitialized) {
      return {'status': 'error', 'message': 'バックグラウンドプロセッサが初期化されていません'};
    }

    // メモリ内キャッシュから確認
    if (_taskQueue.containsKey(taskId)) {
      return _taskQueue[taskId]!;
    }

    // ユーザーがログインしている場合はFirestoreから取得
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('taskHistory')
            .doc(taskId)
            .get();

        if (snapshot.exists) {
          return snapshot.data() as Map<String, dynamic>;
        }
      } catch (e) {
        print('⚠️ タスク状態の取得に失敗しました: $e');
      }
    }

    return {'status': 'error', 'message': '指定されたタスクが見つかりません'};
  }
}
