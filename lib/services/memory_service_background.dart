import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'background_processor.dart';

/// メモリーサービス用のバックグラウンド処理拡張
/// このファイルにはバックグラウンド処理関連のメソッドを集約
class MemoryServiceBackgroundExtension {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final BackgroundProcessor _backgroundProcessor = BackgroundProcessor();

  // タスク進行状況キャッシュ
  final Map<String, Map<String, dynamic>> _taskProgressCache = {};

  /// バックグラウンドでの暗記法生成を開始
  Future<String> startBackgroundTechniqueGeneration(String content) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'ユーザーがログインしていません。サービスを利用するには再度ログインしてください。';
    }

    // タスクIDを生成
    final taskId = const Uuid().v4();

    // バックグラウンドタスクのメタデータをFirestoreに保存
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('backgroundTasks')
        .doc(taskId)
        .set({
      'type': 'techniqueGeneration',
      'content': content,
      'status': 'pending',
      'progress': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // バックグラウンドタスクをキューに追加
    final result =
        await _backgroundProcessor.runTaskInForeground('techniqueGeneration', {
      'taskId': taskId,
      'content': content,
    });

    if (result.isEmpty) {
      // バックグラウンドサービスが開始できなかった場合
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('backgroundTasks')
          .doc(taskId)
          .update({
        'status': 'error',
        'error': 'バックグラウンドサービスの開始に失敗しました',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      throw 'バックグラウンド処理の開始に失敗しました';
    }

    print('バックグラウンドタスクを開始しました: $taskId');
    return taskId;
  }

  /// バックグラウンドタスクの進捗状況を取得
  Future<Map<String, dynamic>> getBackgroundTaskProgress(String taskId) async {
    // キャッシュに最近の進捗状況があればそれを返す（頻繁なFirestore読み取りを防ぐ）
    final cachedProgress = _taskProgressCache[taskId];
    final now = DateTime.now().millisecondsSinceEpoch;

    // キャッシュが5秒以内のものであれば、それを返す
    if (cachedProgress != null &&
        cachedProgress['updatedAt'] != null &&
        now - cachedProgress['updatedAt'] < 5000) {
      return cachedProgress;
    }

    // ユーザー認証を確認
    final user = _auth.currentUser;
    if (user == null) {
      throw 'ユーザーがログインしていません。サービスを利用するには再度ログインしてください。';
    }

    try {
      // Firestoreからタスク情報を取得
      final taskDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('backgroundTasks')
          .doc(taskId)
          .get();

      if (!taskDoc.exists) {
        // バックグラウンドプロセッサーから取得を試みる
        return await _backgroundProcessor.getTaskStatus(taskId);
      }

      final taskData = taskDoc.data()!;

      // キャッシュを更新
      taskData['updatedAt'] = now;
      _taskProgressCache[taskId] = taskData;

      return taskData;
    } catch (e) {
      print('タスク進捗の取得に失敗しました: $e');
      // バックグラウンドプロセッサーから取得を試みる
      return await _backgroundProcessor.getTaskStatus(taskId);
    }
  }
}
