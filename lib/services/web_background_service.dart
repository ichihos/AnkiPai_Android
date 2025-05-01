import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web環境向けバックグラウンド処理実装
/// 
/// WebではバックグラウンドサービスはService Workerを使用するが、
/// FlutterでのWeb対応は限定的なため、WebStorageとシミュレーションを組み合わせて実装
Future<void> initializeWebBackgroundService() async {
  if (!kIsWeb) return;
  
  print('Web向けバックグラウンドサービスを初期化しています');
  
  try {
    // IndexedDBやLocalStorageが使用可能か確認
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_service_initialized', true);
    
    // サービスワーカーが登録されているか確認
    if (html.window.navigator.serviceWorker != null) {
      print('サービスワーカーを確認しています');
      _registerServiceWorker();
    }
    
    print('Web向けバックグラウンドサービス初期化完了');
  } catch (e) {
    print('Web向けバックグラウンドサービスの初期化に失敗しました: $e');
  }
}

// Web用のServiceWorker登録
void _registerServiceWorker() {
  // Service Workerのサポート確認
  if (html.window.navigator.serviceWorker == null) {
    print('このブラウザではService Workerがサポートされていません');
    return;
  }

  try {
    // null安全チェックを行ってからregister呼び出し
    final serviceWorker = html.window.navigator.serviceWorker;
    if (serviceWorker != null) {
      serviceWorker.register('/background_service_worker.js')
          .then((registration) {
        print('Service Worker登録成功: ${registration.scope}');
      }).catchError((error) {
        print('Service Worker登録失敗: $error');
      });
    }
  } catch (e) {
    print('Service Worker登録中にエラーが発生しました: $e');
  }
}

// Webバックグラウンドサービス開始（シミュレーション）
Future<bool> startWebBackgroundService() async {
  try {
    // SharedPreferencesにサービス稼働状態を記録
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('web_background_service_running', true);
    
    // 定期的なタスクチェック処理を開始
    _startWebTaskProcessor();
    return true;
  } catch (e) {
    print('Webバックグラウンドサービスの開始に失敗しました: $e');
    return false;
  }
}

// Webバックグラウンドサービス停止（シミュレーション）
Future<bool> stopWebBackgroundService() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('web_background_service_running', false);
    return true;
  } catch (e) {
    print('Webバックグラウンドサービスの停止に失敗しました: $e');
    return false;
  }
}

// Webバックグラウンドタスクの追加（LocalStorageベース）
Future<bool> queueWebBackgroundTask(Map<String, dynamic> taskData) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // 現在のタスクキューを取得
    final queueJson = prefs.getString('web_background_task_queue') ?? '[]';
    final queue = json.decode(queueJson) as List;
    
    // 新しいタスクを追加
    queue.add(taskData);
    
    // 更新されたキューを保存
    await prefs.setString('web_background_task_queue', json.encode(queue));
    
    // サービスが実行中でなければ開始
    if (!(prefs.getBool('web_background_service_running') ?? false)) {
      await startWebBackgroundService();
    } else {
      // すでに実行中の場合は、タスク処理を促すメッセージをポスト
      _notifyTaskProcessor();
    }
    
    return true;
  } catch (e) {
    print('Webバックグラウンドタスクのキューイングに失敗しました: $e');
    return false;
  }
}

// Webタスクの進捗を取得
Future<Map<String, dynamic>> getWebTaskProgress(String taskId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final progressJson = prefs.getString('web_task_progress_$taskId');
    
    if (progressJson != null) {
      return json.decode(progressJson) as Map<String, dynamic>;
    }
    
    return {
      'taskId': taskId,
      'status': 'queued',
      'progress': 0.0,
      'error': null,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  } catch (e) {
    print('Webタスク進捗の取得に失敗しました: $e');
    return {
      'taskId': taskId,
      'status': 'error',
      'progress': 0.0,
      'error': e.toString(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

// Webタスク処理を開始するシミュレーション
void _startWebTaskProcessor() {
  // 定期的なタスク処理（10秒ごと）
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    
    // サービスが停止されていれば処理停止
    if (!(prefs.getBool('web_background_service_running') ?? false)) {
      timer.cancel();
      return;
    }
    
    await _processWebTasks();
  });
  
  // 初回実行
  _processWebTasks();
}

// タスク処理イベントを発行
void _notifyTaskProcessor() {
  // タスク処理を促すCustomEventを発火（Service Workerへの通知用）
  try {
    final event = html.CustomEvent('ankipai_task_available', detail: {
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });
    html.window.dispatchEvent(event);
  } catch (e) {
    print('タスク通知イベントの発行に失敗しました: $e');
  }
}

// Web環境でのタスク処理シミュレーション
Future<void> _processWebTasks() async {
  final prefs = await SharedPreferences.getInstance();
  
  // タスクキューを取得
  final queueJson = prefs.getString('web_background_task_queue') ?? '[]';
  final queue = json.decode(queueJson) as List;
  
  if (queue.isEmpty) return;
  
  // 最初のタスクを取得
  final task = queue.first as Map<String, dynamic>;
  final taskId = task['taskId'] as String?;
  
  if (taskId == null) {
    // 不正なタスクは削除
    queue.removeAt(0);
    await prefs.setString('web_background_task_queue', json.encode(queue));
    return;
  }
  
  try {
    // タスク処理開始
    await _updateTaskProgress(taskId, 0.1, 'processing');
    
    // タスクの種類に応じて処理
    final action = task['action'] as String? ?? 'unknown';
    
    if (action == 'generateTechnique') {
      await _simulateWebTechniqueGeneration(taskId, task);
    } else {
      await _updateTaskProgress(taskId, 0.0, 'error', 'Unknown task type: $action');
    }
    
    // 処理済みタスクを削除
    queue.removeAt(0);
    await prefs.setString('web_background_task_queue', json.encode(queue));
    
  } catch (e) {
    // エラー状態を記録
    await _updateTaskProgress(taskId, 0.0, 'error', e.toString());
    
    // エラーがあっても処理済みとする
    queue.removeAt(0);
    await prefs.setString('web_background_task_queue', json.encode(queue));
  }
}

// Web環境での暗記法生成シミュレーション
Future<void> _simulateWebTechniqueGeneration(String taskId, Map<String, dynamic> task) async {
  // 段階的に進捗を更新しながら、タスク処理をシミュレート
  await _updateTaskProgress(taskId, 0.2, 'processing');
  await Future.delayed(const Duration(seconds: 2));
  
  await _updateTaskProgress(taskId, 0.5, 'processing');
  await Future.delayed(const Duration(seconds: 2));
  
  await _updateTaskProgress(taskId, 0.8, 'processing');
  await Future.delayed(const Duration(seconds: 2));
  
  // 処理完了
  await _updateTaskProgress(taskId, 1.0, 'completed');
  
  // 通知を表示（Web APIを使用）
  _showWebNotification('暗記法生成完了', '「${_getPreviewText(task['content'] as String? ?? '')}」の暗記法が生成されました');
}

// タスクの進捗状況更新
Future<void> _updateTaskProgress(String taskId, double progress, String status, [String? error]) async {
  final prefs = await SharedPreferences.getInstance();
  
  final progressData = {
    'taskId': taskId,
    'status': status,
    'progress': progress,
    'error': error,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };
  
  await prefs.setString('web_task_progress_$taskId', json.encode(progressData));
}

// Web通知APIを使用した通知表示
void _showWebNotification(String title, String body) {
  try {
    // 通知許可の確認
    if (html.Notification.permission == 'granted') {
      html.Notification(title, body: body);
    } else if (html.Notification.permission != 'denied') {
      // 許可を要求
      html.Notification.requestPermission().then((permission) {
        if (permission == 'granted') {
          html.Notification(title, body: body);
        }
      });
    }
  } catch (e) {
    print('Web通知の表示に失敗しました: $e');
  }
}

// プレビューテキストを取得（長すぎる場合は切り詰め）
String _getPreviewText(String text) {
  if (text.length <= 20) return text;
  return '${text.substring(0, 17)}...';
}
