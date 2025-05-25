import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'; // WidgetsFlutterBindingのために追加
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Web環境用のシミュレーション実装
import 'package:anki_pai/services/web_background_service.dart'
    if (dart.library.io) 'package:anki_pai/services/native_background_service.dart';

class BackgroundTaskService {
  static final BackgroundTaskService _instance =
      BackgroundTaskService._internal();
  factory BackgroundTaskService() => _instance;
  BackgroundTaskService._internal();

  // バックグラウンドサービス
  late FlutterBackgroundService _backgroundService;

  // ネイティブ通知チャンネル設定
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'background_service_channel',
    'バックグラウンド処理',
    description: 'バックグラウンドでの処理状況を通知',
    importance: Importance.high,
  );

  static const String _taskChannelId = 'com.ankipai.background.task';

  // 初期化フラグ
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // 初期化
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Web環境での実装は異なる
    if (kIsWeb) {
      await initializeWebBackgroundService();
      _isInitialized = true;
      return;
    }

    try {
      // 通知チャンネル作成
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // バックグラウンドサービス初期化
      _backgroundService = FlutterBackgroundService();
      await _backgroundService.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: _taskChannelId,
          initialNotificationTitle: 'Anki Pai',
          initialNotificationContent: 'バックグラウンド処理を初期化しています',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onStart,
          onBackground: _onIosBackground,
        ),
      );

      // 初期化完了
      _isInitialized = true;
      print('バックグラウンドサービスが初期化されました');
    } catch (e) {
      print('バックグラウンドサービスの初期化に失敗しました: $e');
    }
  }

  // バックグラウンドサービスを開始
  Future<bool> startService() async {
    if (!_isInitialized) await initialize();

    if (kIsWeb) {
      return startWebBackgroundService();
    }

    try {
      return await _backgroundService.startService();
    } catch (e) {
      print('バックグラウンドサービスの開始に失敗しました: $e');
      return false;
    }
  }

  // バックグラウンドサービスを停止
  Future<bool> stopService() async {
    if (!_isInitialized) return false;

    if (kIsWeb) {
      return stopWebBackgroundService();
    }

    try {
      return await _backgroundService.isRunning().then((isRunning) {
        if (isRunning) {
          _backgroundService.invoke('stopService', {'action': 'stopService'});
          return true;
        }
        return false;
      });
    } catch (e) {
      print('バックグラウンドサービスの停止に失敗しました: $e');
      return false;
    }
  }

  // 暗記法生成タスクを追加
  Future<bool> queueTechniqueGenerationTask(
      String content, String userId, String taskId) async {
    if (!_isInitialized) await initialize();

    final taskData = {
      'action': 'generateTechnique',
      'content': content,
      'userId': userId,
      'taskId': taskId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // タスクをキューに追加
    if (kIsWeb) {
      return await queueWebBackgroundTask(taskData);
    } else {
      if (await _backgroundService.isRunning()) {
        // 最新バージョンではinvokeMethodを使用
        _backgroundService.invoke('taskData', taskData);
        return true;
      } else {
        // サービスが実行されていなければ開始
        final started = await startService();
        if (started) {
          _backgroundService.invoke('taskData', taskData);
          return true;
        }
      }
    }
    return false;
  }

  // タスクの進捗状況を取得
  Future<Map<String, dynamic>> getTaskProgress(String taskId) async {
    if (kIsWeb) {
      return await getWebTaskProgress(taskId);
    }

    // モバイル環境ではSharedPreferencesを利用
    final prefs = await SharedPreferences.getInstance();
    final progressJson = prefs.getString('task_progress_$taskId');
    if (progressJson != null) {
      return json.decode(progressJson);
    }
    return {'status': 'unknown', 'progress': 0.0};
  }
}

// iOSのバックグラウンド処理ハンドラ（必須）
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// バックグラウンド処理のメイン関数
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  // Android向けの設定
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // サービス停止リクエスト処理
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 暗記法生成タスク処理
  service.on('generateTechnique').listen((event) async {
    if (event == null) return;

    final taskId = event['taskId'] as String?;
    final content = event['content'] as String?;
    final userId = event['userId'] as String?;

    if (taskId == null || content == null || userId == null) return;

    try {
      // プログレス保存用の処理
      Future<void> saveProgress(double progress, String status) async {
        final prefs = await SharedPreferences.getInstance();
        final progressData = {
          'taskId': taskId,
          'status': status,
          'progress': progress,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        };
        await prefs.setString(
            'task_progress_$taskId', json.encode(progressData));

        // 通知を更新（Androidのみ）
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: '暗記法を生成中',
            content: '進捗: ${(progress * 100).toInt()}%',
          );
        }
      }

      // タスク開始
      await saveProgress(0.1, 'processing');

      // TODO: ここで実際の暗記法生成処理を実行
      // これは独自実装が必要なため、現状ではダミー実装

      // タスク成功として記録
      await saveProgress(1.0, 'completed');

      // Firestoreに結果を保存（実際の実装では生成結果を保存）
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('backgroundTasks')
          .doc(taskId)
          .set({
        'status': 'completed',
        'progress': 1.0,
        'completedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('バックグラウンドタスク実行中にエラーが発生しました: $e');
      // エラー状態を保存
      final prefs = await SharedPreferences.getInstance();
      final errorData = {
        'taskId': taskId,
        'status': 'error',
        'error': e.toString(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('task_progress_$taskId', json.encode(errorData));
    }
  });
}
