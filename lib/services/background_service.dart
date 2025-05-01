import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// バックグラウンドタスクサービス - スタブ実装
/// 注意: これはスタブ実装です。flutter_background_serviceパッケージがAndroid SDK 35で
/// 動作しないため一時的に無効化されています。
class BackgroundTaskService {
  static final BackgroundTaskService _instance = BackgroundTaskService._internal();
  factory BackgroundTaskService() => _instance;
  BackgroundTaskService._internal();

  // 初期化フラグ
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // 初期化
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('⚠️ バックグラウンドサービスは無効化されています（スタブ実装）');
    _isInitialized = true;
    return;
  }

  // バックグラウンドサービスの開始
  Future<void> startService() async {
    if (!_isInitialized) {
      print('⚠️ バックグラウンドサービスが初期化されていません');
      return;
    }
    
    print('⚠️ バックグラウンドサービスは無効化されています（スタブ実装）');
    return;
  }

  // バックグラウンドサービスの停止
  Future<void> stopService() async {
    if (!_isInitialized) {
      print('⚠️ バックグラウンドサービスが初期化されていません');
      return;
    }
    
    print('⚠️ バックグラウンドサービスは無効化されています（スタブ実装）');
    return;
  }

  // バックグラウンドタスクのキュー追加
  Future<String> queueTask(String taskType, Map<String, dynamic> data) async {
    if (!_isInitialized) {
      print('⚠️ バックグラウンドサービスが初期化されていません');
      return '';
    }
    
    // タスクIDを生成（実際には処理は行わない）
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    print('⚠️ バックグラウンドタスクは無効化されています（スタブ実装）: $taskType, ID: $taskId');
    
    // ダミーの進捗情報を保存
    final prefs = await SharedPreferences.getInstance();
    final progressData = {
      'taskId': taskId,
      'status': 'completed', // 即時完了とする
      'progress': 1.0,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString('task_progress_$taskId', json.encode(progressData));
    
    return taskId;
  }

  // タスク進捗の取得
  Future<Map<String, dynamic>> getTaskProgress(String taskId) async {
    if (!_isInitialized) {
      return {
        'status': 'error',
        'message': 'バックグラウンドサービスが初期化されていません',
      };
    }
    
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
}
