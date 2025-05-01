import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/memory_item.dart';
import '../models/memory_technique.dart';
import '../models/ranked_memory_technique.dart';
import 'gemini_service.dart';
import 'ai_service_interface.dart';
import 'ai_agent_service.dart';
import 'notification_service.dart';
import 'background_processor.dart';
import '../utils/spaced_repetition_scheduler.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

class MemoryService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // GeminiServiceをメインのAIサービスとして使用
  final AIServiceInterface _aiService = GetIt.instance<GeminiService>();
  // 後方互換性のため一時的に保持
  // final OpenAiService _openAIService = OpenAiService();
  late final AIAgentService _aiAgentService;
  late final NotificationService _notificationService;
  final SpacedRepetitionScheduler _scheduler = SpacedRepetitionScheduler();
  // バックグラウンド処理用のプロセッサー
  final BackgroundProcessor _backgroundProcessor = BackgroundProcessor();

  // ストリームコントローラーのマップ（複数のリスナーをサポート）
  final Map<String, StreamController<List<MemoryItem>>> _memoryItemControllers =
      {};

  // バックグラウンドタスクの進行状況キャッシュ
  final Map<String, Map<String, dynamic>> _taskProgressCache = {};

  MemoryService() {
    // AIAgentServiceを初期化
    _aiAgentService = AIAgentService(_aiService);

    // 自己登録処理は完全に無効化
    // main.dartで一元管理されるように改修
    print('MemoryService.initialize()が実行されました（自己登録は行わない）');

    // NotificationServiceを遅延取得（メモリサービス初期化後に通知サービスが登録される可能性があるため）
    _setupNotificationService();

    // バックグラウンドプロセッサーを初期化
    _initializeBackgroundProcessor();

    // 定期的な学習リマインダーのチェックを開始
    _scheduleStudyReminderCheck();
  }

  /// 通知サービスの遅延セットアップ
  Future<void> _setupNotificationService() async {
    // 遅延実行して通知サービスが登録される時間を確保
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // GetItから通知サービスの取得を試みる
      if (GetIt.instance.isRegistered<NotificationService>()) {
        _notificationService = GetIt.instance<NotificationService>();
        print('MemoryService: 通知サービスをGetItから正常に取得しました');
      } else {
        // 登録されていない場合は新規作成
        _notificationService = NotificationService();
        await _notificationService.initialize();

        // main.dartで通知サービスが登録済みのはずなので、ここでは登録しない
        // if (!GetIt.instance.isRegistered<NotificationService>()) {
        //   GetIt.instance.registerSingleton<NotificationService>(_notificationService);
        //   print('MemoryService: 通知サービスをGetItに登録しました');
        // }
        print('MemoryService: 通知サービスを取得しました（GetItには登録しません）');
      }
    } catch (e) {
      print('MemoryService: 通知サービスの取得に失敗: $e');
      _notificationService = NotificationService();
      await _notificationService.initialize();
    }
  }

  /// バックグラウンドプロセッサーを初期化
  // バックグラウンドプロセッサーの初期化
  Future<void> _initializeBackgroundProcessor() async {
    try {
      await _backgroundProcessor.initialize();
      print('バックグラウンドプロセッサーが初期化されました');
    } catch (e) {
      print('バックグラウンドプロセッサーの初期化に失敗しました: $e');
    }
  }

  /// 定期的に学習リマインダーをチェックする
  void _scheduleStudyReminderCheck() {
    // アプリ起動時に一度チェック
    _checkAndScheduleLearningReminders();

    // 毎日24時間ごとにチェック（デバッグ時は短い間隔でも可）
    Timer.periodic(const Duration(hours: 24), (_) {
      _checkAndScheduleLearningReminders();
    });
  }

  /// 学習提出物のリマインダーをチェックしスケジュール
  Future<void> _checkAndScheduleLearningReminders() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      print('学習リマインダーのチェックを開始します');

      // ユーザーの全ての学習アイテムを取得
      final snapshot = await _userItems
          .where('lastStudiedAt', isNull: false)
          .orderBy('lastStudiedAt', descending: true)
          .get();

      final items = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return MemoryItem.fromMap(data, doc.id);
      }).toList();

      print('リマインダー対象となる学習アイテム数: ${items.length}');

      // 各アイテムについて学習リマインダーをスケジュール
      for (var item in items) {
        // アイテムの学習状況を確認
        final mastery = item.mastery;

        // masteryを復習回数として扱う
        final status = _scheduler.getLearningStatus(
            mastery, item.lastStudiedAt ?? DateTime.now());

        // 学習日が近づいている予定の場合、リマインダーを送信
        if (status == LearningStatus.dueSoon ||
            status == LearningStatus.dueToday) {
          _sendLearningReminderNotification(item, mastery);
        }
      }
    } catch (e) {
      print('学習リマインダーのチェック中にエラーが発生しました: $e');
    }
  }

  // 認証状態変更時などにすべてのリスナーをクリーンアップ
  void cleanupAllListeners() {
    print('すべてのMemoryServiceリスナーをクリーンアップしています...');
    // すべてのストリームコントローラーを閉じて削除
    _memoryItemControllers.forEach((key, controller) {
      if (!controller.isClosed) {
        controller.close();
      }
    });
    _memoryItemControllers.clear();
    print('MemoryServiceリスナーのクリーンアップが完了しました');
  }

  /// 暗記法生成完了の通知を送信
  void _sendTechniqueGenerationCompletedNotification(String content) {
    try {
      // コンテンツの一部を通知に表示
      final contentPreview =
          content.length > 30 ? '${content.substring(0, 30)}...' : content;

      _notificationService.scheduleTechniqueGenerationNotification(
        title: '暗記法生成完了',
        body: '「$contentPreview」の暗記法が生成されました。タップして確認しましょう。',
      );

      print('暗記法生成完了通知を送信しました');
    } catch (e) {
      print('通知送信に失敗しました: $e');
    }
  }

  /// バックグラウンドでの暗記法生成を開始
  Future<String> _startBackgroundTechniqueGeneration(String content) async {
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
    final result = await _backgroundProcessor.startTask({
      'taskId': taskId,
      'type': 'techniqueGeneration',
      'content': content,
      'userId': user.uid,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
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

  /// バックグラウンドでのフラッシュカード作成タスクを開始
  Future<Map<String, dynamic>> startBackgroundFlashcardCreation({
    required List<Map<String, dynamic>> flashcardDataList,
    required String cardSetId,
    required String cardSetName,
    String? techniqueId,
    String? techniqueName,
  }) async {
    // ユーザー認証を確認
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
      'type': 'flashcardCreation',
      'cardSetId': cardSetId,
      'cardSetName': cardSetName,
      'techniqueId': techniqueId ?? '',
      'techniqueName': techniqueName ?? '',
      'flashcardsCount': flashcardDataList.length,
      'status': 'pending',
      'progress': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // バックグラウンドタスクをキューに追加
    final result = await _backgroundProcessor.startTask({
      'taskId': taskId,
      'type': 'flashcardCreation',
      'cardSetId': cardSetId,
      'cardSetName': cardSetName,
      'flashcardsData': flashcardDataList,
      'techniqueId': techniqueId ?? '',
      'techniqueName': techniqueName ?? '',
      'userId': user.uid,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
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

    print('フラッシュカード作成のバックグラウンドタスクを開始しました: $taskId');
    return {
      'taskId': taskId,
      'status': 'pending',
      'progress': 0.0,
    };
  }

  /// バックグラウンドプロセッサーが初期化されているかどうかを確認
  bool get isBackgroundProcessorInitialized =>
      _backgroundProcessor.isInitialized;

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
        return await _backgroundProcessor.getTaskProgress(taskId);
      }

      final taskData = taskDoc.data()!;

      // キャッシュを更新
      taskData['updatedAt'] = now;
      _taskProgressCache[taskId] = taskData;

      return taskData;
    } catch (e) {
      print('タスク進捗の取得に失敗しました: $e');
      // バックグラウンドプロセッサーから取得を試みる
      return await _backgroundProcessor.getTaskProgress(taskId);
    }
  }

  /// 学習リマインダーの通知を送信
  void _sendLearningReminderNotification(MemoryItem item, int reviewCount) {
    try {
      // 忘却曲線に基づくメッセージの生成
      final nextReviewDate = _scheduler.calculateNextReviewDate(
        reviewCount,
        item.lastStudiedAt ?? DateTime.now(),
      );

      // 日付フォーマット
      final formattedDate = '${nextReviewDate.month}月${nextReviewDate.day}日';
      final message = '「${item.title}」の学習日が近づいています。$formattedDate に復習しましょう。';

      // 暗記法の学習リマインダー通知をスケジュール
      _notificationService.scheduleTechniqueLearningReminder(
        title: '学習リマインダー',
        body: message,
        scheduledDate: nextReviewDate,
        techniqueId: item.id,
      );

      print('学習リマインダー通知をスケジュールしました: ${item.title}');
    } catch (e) {
      print('通知送信に失敗しました: $e');
    }
  }

  // ユーザーのコレクションへの参照
  CollectionReference get _userItems {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'ユーザーがログインしていません。サービスを利用するには再度ログインしてください。';
    }
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('memoryItems');
  }

  // 認証状態を確認するヘルパーメソッド
  Future<bool> _isUserAuthenticated() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      // トークンの有効性を確認するためにトークンをリフレッシュ
      await user.getIdToken(true);
      return true;
    } catch (e) {
      print('認証トークンの更新に失敗しました: $e');
      return false;
    }
  }

  // 認証エラーをよりユーザーフレンドリーなメッセージに変換
  String _getAuthErrorMessage(dynamic error) {
    if (error.toString().contains('permission-denied')) {
      return 'アクセス権限がありません。再度ログインして試してください。';
    }
    return error.toString();
  }

  // 覚え方(MemoryTechnique)のコレクションへの参照
  CollectionReference get _memoryTechniquesCollection {
    return _firestore.collection('memoryTechniques');
  }

  // 最近公開された暗記法を1件取得
  Future<MemoryTechnique?> getRecentPublicTechnique() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'ユーザーがログインしていません';
      }

      // 最新の暗記法を取得（作成日時の降順で並べ替え）
      final snapshot = await _memoryTechniquesCollection
          .where('isPublic', isEqualTo: true) // 公開された暗記法のみ取得
          .where('userId', isNotEqualTo: user.uid) // 他のユーザーの暗記法のみ取得
          .orderBy('userId')
          .orderBy('createdAt', descending: true)
          .limit(10) // 最新の10件を取得
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      // ランダムに1件選択（最新10件の中から）
      final random = Random();
      final randomIndex = random.nextInt(snapshot.docs.length);
      final doc = snapshot.docs[randomIndex];
      final data = doc.data() as Map<String, dynamic>;

      return MemoryTechnique.fromMap(data);
    } catch (e) {
      print('最近の暗記法の取得に失敗しました: $e');
      throw '最近の暗記法の取得に失敗しました: $e';
    }
  }

  // ユーザーの暗記法を取得
  Future<List<MemoryTechnique>> getUserMemoryTechniques() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'ユーザーがログインしていません';
      }

      final snapshot = await _memoryTechniquesCollection
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) =>
              MemoryTechnique.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('ユーザーの暗記法の取得に失敗しました: $e');
      throw 'ユーザーの暗記法の取得に失敗しました: $e';
    }
  }

  // ユーザーが公開した暗記法を取得
  Future<List<MemoryTechnique>> getUserPublishedTechniques() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'ユーザーがログインしていません';
      }

      final snapshot = await _memoryTechniquesCollection
          .where('userId', isEqualTo: user.uid)
          .where('isPublic', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) =>
              MemoryTechnique.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('ユーザーの公開暗記法の取得に失敗しました: $e');
      throw 'ユーザーの公開暗記法の取得に失敗しました: $e';
    }
  }

  // 公開された暗記法から検索
  Future<List<MemoryTechnique>> searchPublicTechniques(String query) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'ユーザーがログインしていません';
      }

      // queryを小文字に変換して比較
      final lowercaseQuery = query.toLowerCase();

      // 公開された暗記法を取得
      final snapshot = await _memoryTechniquesCollection
          .where('isPublic', isEqualTo: true)
          .where('userId', isNotEqualTo: user.uid) // 自分以外のユーザーの暗記法
          .orderBy('userId')
          .orderBy('createdAt', descending: true)
          .limit(50) // 最大50件取得
          .get();

      // クライアントサイドでフィルタリング
      return snapshot.docs
          .map((doc) =>
              MemoryTechnique.fromMap(doc.data() as Map<String, dynamic>))
          .where((technique) {
        return technique.name.toLowerCase().contains(lowercaseQuery) ||
            technique.description.toLowerCase().contains(lowercaseQuery) ||
            technique.tags
                .any((tag) => tag.toLowerCase().contains(lowercaseQuery));
      }).toList();
    } catch (e) {
      print('公開暗記法の検索に失敗しました: $e');
      throw '公開暗記法の検索に失敗しました: $e';
    }
  }

  // 暗記法を公開する
  Future<void> publishMemoryTechnique(MemoryTechnique technique) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'ユーザーがログインしていません';
      }

      // 同じ名前の暗記法が既に公開されているか確認
      final existingSnapshot = await _memoryTechniquesCollection
          .where('userId', isEqualTo: user.uid)
          .where('name', isEqualTo: technique.name)
          .where('isPublic', isEqualTo: true)
          .get();

      // 既に公開されている場合は新たに追加しない
      if (existingSnapshot.docs.isNotEmpty) {
        print('同じ名前の暗記法が既に公開されています。新たに追加せず既存の暗記法を更新します。');
        return;
      }

      // 暗記法にユーザーIDとユーザー名を追加
      final techniqueData = technique.toMap();
      techniqueData['userId'] = user.uid;
      techniqueData['userName'] = user.displayName ?? '匿名ユーザー';
      techniqueData['isPublic'] = true; // 確実に公開設定をtrueにする
      techniqueData['createdAt'] = FieldValue.serverTimestamp(); // 作成日時を追加

      // Firestoreに追加
      await _memoryTechniquesCollection.add(techniqueData);
    } catch (e) {
      print('暗記法の公開に失敗しました: $e');
      throw '暗記法の公開に失敗しました: $e';
    }
  }

  // 暗記法の公開を取り消す（Firestoreから完全に削除）
  Future<void> unpublishMemoryTechnique(MemoryTechnique technique) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'ユーザーがログインしていません';
      }

      print('暗記法の公開取り消しを開始: ${technique.name}');

      // ユーザーIDと名前が一致する公開暗記法を検索
      final snapshot = await _memoryTechniquesCollection
          .where('userId', isEqualTo: user.uid)
          .where('isPublic', isEqualTo: true)
          .where('name', isEqualTo: technique.name)
          .get();

      // 一致するドキュメントがない場合
      if (snapshot.docs.isEmpty) {
        print('公開済みの暗記法が見つかりません: ${technique.name}');
        throw '公開済みの暗記法が見つかりません';
      }

      print('削除対象の暗記法数: ${snapshot.docs.length}');

      // 各ドキュメントをFirestoreから完全に削除
      for (var doc in snapshot.docs) {
        await doc.reference.delete();
        print('公開暗記法をFirestoreから削除しました: ${technique.name} (ID: ${doc.id})');
      }

      return;
    } catch (e) {
      print('暗記法の公開取り消しに失敗しました: $e');
      throw '暗記法の公開取り消しに失敗しました: $e';
    }
  }

  // テキスト暗記アイテムを追加
  Future<DocumentReference> addTextMemoryItem(
      String title, String content, List<MemoryTechnique> techniques) async {
    final item = {
      'title': title,
      'content': content,
      'contentType': 'text',
      'mastery': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'memoryTechniques': techniques.map((t) => t.toMap()).toList(),
    };

    final docRef = await _userItems.add(item);
    notifyListeners();
    return docRef;
  }

  // 画像暗記アイテムを追加
  Future<DocumentReference> addImageMemoryItemWithUrl(
      String title, String imageUrl) async {
    final item = {
      'title': title,
      'content': '',
      'contentType': 'image',
      'imageUrl': imageUrl,
      'mastery': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'memoryTechniques': [], // 空の暗記法配列を初期化
    };

    final docRef = await _userItems.add(item);
    notifyListeners();
    return docRef;
  }

  // AI解析した画像暗記アイテムを追加
  Future<DocumentReference> addImageMemoryItemWithContent(String title,
      String content, String imageUrl, List<MemoryTechnique> techniques) async {
    final item = {
      'title': title,
      'content': content,
      'contentType': 'image',
      'imageUrl': imageUrl,
      'mastery': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'memoryTechniques': techniques.map((t) => t.toMap()).toList(),
    };

    final docRef = await _userItems.add(item);
    notifyListeners();
    return docRef;
  }

  // ストリームIDの生成（リスナーの識別用）
  Future<String> _generateStreamId(String prefix) async {
    final user = _auth.currentUser;
    if (user == null) {
      return '$prefix-anonymous';
    }
    return '$prefix-${user.uid}';
  }

  // エラーを安全に追加するためのヘルパー関数
  void _safeAddError(StreamController controller, String errorMessage) {
    // コントローラーが閉じられていない場合のみエラーを追加
    if (!controller.isClosed) {
      controller.addError(errorMessage);
    } else {
      print('Warning: エラーの追加がスキップされました (コントローラーは既に閉じられています): $errorMessage');
    }
  }

  // リアルタイムで暗記アイテムを監視するStream
  Future<Stream<List<MemoryItem>>> watchMemoryItems({String? tag}) async {
    final streamId = await _generateStreamId(tag ?? 'all');

    // 型安全性のため、適切なStreamControllerの取得
    if (_memoryItemControllers.containsKey(streamId)) {
      final controller = _memoryItemControllers[streamId];
      if (controller is StreamController<List<MemoryItem>>) {
        return controller.stream;
      }
    }

    // 新しいコントローラーの作成
    final controller = StreamController<List<MemoryItem>>.broadcast();

    // クリーンアップ用のコールバックを設定
    controller.onCancel = () {
      _memoryItemControllers.remove(streamId);
      // 既に閉じられていない場合のみ閉じる
      if (!controller.isClosed) {
        controller.close();
      }
    };

    _memoryItemControllers[streamId] = controller;

    try {
      if (!await _isUserAuthenticated()) {
        _safeAddError(controller, 'ユーザーがログインしていません。サービスを利用するには再度ログインしてください。');
        return controller.stream;
      }

      // Firestoreのリスナーを設定
      _userItems.orderBy('createdAt', descending: true).snapshots().listen(
        (snapshot) {
          // isClosed チェックを追加
          if (!controller.isClosed) {
            final items = snapshot.docs
                .map((doc) => MemoryItem.fromMap(
                    doc.data() as Map<String, dynamic>, doc.id))
                .toList();
            controller.add(items);
          }
        },
        onError: (error) {
          // 指定のエラーはサイレントにして表示しない
          if (error.toString().contains('permission-denied')) {
            // ログアウト時の権限エラーは非表示
            print('暗記アイテムの権限エラーを無視しました');
          } else {
            print('暗記アイテムのリスニングエラー: $error');
            _safeAddError(controller, '暗記アイテムのリスニングに失敗しました: $error');
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            _memoryItemControllers.remove(streamId);
            controller.close();
          }
        },
      );
    } catch (e) {
      String errorMessage = _getAuthErrorMessage(e);
      print('暗記アイテムの監視エラー: $errorMessage');
      _safeAddError(controller, '暗記アイテムのリスニングに失敗しました: $errorMessage');

      // エラーが発生した場合はマップから削除
      _memoryItemControllers.remove(streamId);

      // 既に閉じられていない場合のみ閉じる
      if (!controller.isClosed) {
        controller.close();
      }
    }

    return controller.stream;
  }

  // すべての暗記アイテムを取得
  Future<List<MemoryItem>> getAllMemoryItems() async {
    try {
      if (!await _isUserAuthenticated()) {
        throw 'ユーザーがログインしていません。サービスを利用するには再度ログインしてください。';
      }

      final snapshot =
          await _userItems.orderBy('createdAt', descending: true).get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return MemoryItem.fromMap(data, doc.id);
      }).toList();
    } catch (e) {
      print('暗記アイテム取得エラー: ${_getAuthErrorMessage(e)}');
      throw '暗記アイテムの読み込みに失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // 暗記アイテムをIDで取得
  Future<MemoryItem?> getMemoryItemById(String id) async {
    try {
      if (!await _isUserAuthenticated()) {
        throw 'ユーザーがログインしていません。サービスを利用するには再度ログインしてください。';
      }

      final doc = await _userItems.doc(id).get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;
      return MemoryItem.fromMap(data, doc.id);
    } catch (e) {
      print('フラッシュカード取得エラー: ${_getAuthErrorMessage(e)}');
      throw 'フラッシュカードの読み込みに失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // 推奨される学習アイテムを取得（復習が必要なアイテム）
  Future<List<MemoryItem>> getRecommendedStudyItems(int limit) async {
    final snapshot = await _userItems
        .where('mastery', isLessThan: 80) // 習得度が80%未満のアイテム
        .orderBy('mastery', descending: false) // 習得度の低い順
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return MemoryItem.fromMap(data, doc.id);
    }).toList();
  }

  // 暗記アイテムを更新
  Future<void> updateMemoryItem(MemoryItem item) async {
    await _userItems.doc(item.id).update(item.toMap());
    notifyListeners();
  }

  // 暗記アイテムを削除
  Future<void> deleteMemoryItem(String id) async {
    try {
      // 削除前にアイテムの情報を取得する
      final itemSnapshot = await _userItems.doc(id).get();
      if (!itemSnapshot.exists) {
        throw '削除するアイテムが見つかりません';
      }

      // MemoryItemオブジェクトに変換
      final itemData = itemSnapshot.data() as Map<String, dynamic>;
      final memoryItem = MemoryItem.fromMap(itemData, id);

      // 関連する公開された覚え方（メモリーテクニック）を削除
      if (memoryItem.memoryTechniques.isNotEmpty) {
        final user = _auth.currentUser;
        if (user != null) {
          for (var technique in memoryItem.memoryTechniques) {
            // 公開されている覚え方を検索
            final techniqueSnapshot = await _memoryTechniquesCollection
                .where('userId', isEqualTo: user.uid)
                .where('name', isEqualTo: technique.name)
                .where('isPublic', isEqualTo: true)
                .get();

            // 見つかった覚え方を削除
            for (var doc in techniqueSnapshot.docs) {
              await doc.reference.delete();
              print('公開された覚え方を削除しました: ${technique.name}');
            }
          }
        }
      }

      // メモリーアイテム自体を削除
      await _userItems.doc(id).delete();
      notifyListeners();
    } catch (e) {
      print('アイテムの削除中にエラーが発生しました: $e');
      throw 'アイテムの削除に失敗しました: $e';
    }
  }

  // 学習後のアイテム更新（習得度の増加）
  Future<void> updateMasteryAfterStudy(String id, int newMastery) async {
    // ドキュメントを更新
    await _userItems.doc(id).update({
      'mastery': newMastery,
      'lastStudiedAt': FieldValue.serverTimestamp(),
    });

    // ドキュメントを再取得して、最新の値を元に通知をスケジュール
    final docSnapshot = await _userItems.doc(id).get();
    if (docSnapshot.exists) {
      final item =
          MemoryItem.fromMap(docSnapshot.data() as Map<String, dynamic>, id);
      // 次回の学習リマインダーをスケジュール
      _sendLearningReminderNotification(item, newMastery);
    }

    notifyListeners();
  }

  // AI支援による暗記法提案（フォアグラウンドまたはバックグラウンドで実行可能）
  Future<List<MemoryTechnique>> suggestMemoryTechniques(
    String content, {
    Function(double progress, int processedItems, int totalItems,
            bool isMultipleItems)?
        progressCallback,
    bool runInBackground = false,
    bool isThinkingMode = false,
    bool isMultiAgentMode = false,
    Map<String, dynamic>? multipleItemsDetection,
    int? itemCount,
  }) async {
    try {
      // バックグラウンド実行が指定され、プロセッサーが初期化されている場合
      if (runInBackground && _backgroundProcessor.isInitialized) {
        print('バックグラウンドで暗記法生成を開始します');
        final taskId = await _startBackgroundTechniqueGeneration(content);

        // 処理中であることを示す特殊なMemoryTechniqueオブジェクトを返す
        // クライアントコードはtaskIdを使って進捗を確認できる
        return [
          MemoryTechnique(
            id: 'background_task_$taskId',
            name: 'バックグラウンド処理中',
            type: 'background_task',
            description: '暗記法をバックグラウンドで生成しています',
            content: content,
            taskId: taskId,
          )
        ];
      }

      // 既存の暗記法が見つからない場合は新しく生成
      print('GeminiServiceを使用して暗記法を生成します');

      List<MemoryTechnique> newTechniques = [];

      // 検測中のプログレスコールバック
      progressCallback?.call(0.05, 0, 1, false);

      // バックグラウンド実行が選択された場合
      if (runInBackground) {
        _startBackgroundTechniqueGeneration(content);
        return [];
      }

      // 複数項目処理を行う条件を確認
      bool isMultipleItems = false;

      if (multipleItemsDetection != null) {
        // multipleItemsDetectionが存在し、itemsフィールドを持つか、itemCountが1より大きい場合
        isMultipleItems = multipleItemsDetection.containsKey('items') ||
            (multipleItemsDetection.containsKey('itemCount') &&
                multipleItemsDetection['itemCount'] > 1);
      }

      // itemCountが指定され、1より大きい場合も複数項目とみなす
      if (itemCount != null && itemCount > 1) {
        isMultipleItems = true;
      }

      print('複数項目処理判定: $isMultipleItems (itemCount: $itemCount)');

      if (isMultipleItems && multipleItemsDetection != null) {
        // 複数項目の場合は個別に暗記法を生成
        final items = multipleItemsDetection.containsKey('items')
            ? multipleItemsDetection['items']
            : [];
        print('複数項目が検出されました。項目数: ${items?.length ?? 0}');

        // 複数項目の処理を開始することを通知
        progressCallback?.call(0.1, 0, items.length, true);

        // 高速検知情報があるか確認（GeminiServiceの高速検出では'message'フィールドに「高速検出」が含まれる）
        final bool isQuickDetection =
            multipleItemsDetection.containsKey('message') &&
                multipleItemsDetection['message'].toString().contains('高速検出');

        // 高速検知の場合は生のOCRデータも渡す
        if (isQuickDetection &&
            multipleItemsDetection.containsKey('rawContent')) {
          final rawContent = multipleItemsDetection['rawContent'];
          final itemCount = multipleItemsDetection.containsKey('itemCount')
              ? multipleItemsDetection['itemCount']
              : items.length;

          print('高速検知された複数項目に対して生データを使用した暗記法を生成します。項目数: $itemCount');

          newTechniques = await generateTechniquesForMultipleItems(
            items,
            progressCallback: (progress, processed, total) {
              progressCallback?.call(progress, processed, total, true);
              if (progress >= 0.98 && processed >= total - 1) {
                _sendTechniqueGenerationCompletedNotification('複数項目の暗記法');
              }
            },
            rawContent: rawContent, // 生データを渡す
            isQuickDetection: true,
            itemCount: itemCount,
            isThinkingMode: isThinkingMode,
            isMultiAgentMode: isMultiAgentMode,
          );
        } else {
          // 通常の処理
          print('標準検出による複数項目の暗記法を生成します');
          newTechniques = await generateTechniquesForMultipleItems(items,
              progressCallback: (progress, processed, total) {
            progressCallback?.call(progress, processed, total, true);
            if (progress >= 0.98 && processed >= total - 1) {
              _sendTechniqueGenerationCompletedNotification('複数項目の暗記法');
            }
          });
        }
      } else {
        // 単一項目の場合
        try {
          // 進行状況を報告
          progressCallback?.call(0.1, 0, 1, false);

          // 考え方モードの場合は特別な処理
          if (isThinkingMode) {
            // 考え方モードの暗記法を生成
            print('考え方モード: 暗記法と考え方を並行で生成します');

            // 単一項目用の暗記法と考え方を同時生成
            try {
              // 1. 通常の暗記法生成と考え方生成を並行で実行
              final memoryTechniqueFuture =
                  _aiService.generateMemoryTechniquesForMultipleItems(
                [
                  {'content': content, 'description': ''}
                ],
                progressCallback: (progress, processed, total) {
                  // 進捗状況を上位コールバックに転送
                  progressCallback?.call(
                      progress * 0.5, processed, total, false);
                },
                itemCount: 1,
              );

              // 考え方モードの説明生成を並行で実行
              final geminiService = _aiService as GeminiService;
              final thinkingFuture = geminiService
                  .generateThinkingModeExplanation(
                content: content,
              )
                  .catchError((e) {
                print('考え方モードの生成中にエラーが発生しました: $e');
                return '生成中にエラーが発生しました。別の方法で考えてみましょう。';
              });

              // 両方の結果を待ち受ける
              final results =
                  await Future.wait([memoryTechniqueFuture, thinkingFuture]);
              progressCallback?.call(0.9, 1, 1, false); // 進捗状況の更新

              // 通常の暗記法生成結果
              final rawTechniques = results[0] as List<Map<String, dynamic>>;
              // 考え方モードの結果
              final thinkingExplanation = results[1] as String;

              // デバッグ情報
              print(
                  '暗記法数: ${rawTechniques.length}, 考え方: ${thinkingExplanation.substring(0, min(50, thinkingExplanation.length))}...');

              // 2. 通常の暗記法生成結果をMemoryTechniqueに変換
              final memoryTechniques = rawTechniques.map((item) {
                // フラッシュカードの作成
                final flashcards =
                    _extractFlashcards(item['flashcards'], content);

                return MemoryTechnique(
                  id: const Uuid().v4(),
                  name: item['name'] ?? '標準学習法',
                  description: item['description'] ?? '繰り返し練習で覚えよう',
                  type: item['type'] ?? 'concept',
                  tags: item['tags'] != null
                      ? List<String>.from(item['tags'])
                      : <String>[],
                  contentKeywords: item['contentKeywords'] != null
                      ? List<String>.from(item['contentKeywords'])
                      : [content],
                  content: content,
                  itemContent: content,
                  flashcards: flashcards,
                  image: item['image'] ?? '',
                );
              }).toList();

              progressCallback?.call(1.0, 1, 1, true); // 完了通知
              _sendTechniqueGenerationCompletedNotification(content); // 生成完了を通知

              return memoryTechniques;
            } catch (e) {
              print('考え方モードの並行処理中にエラーが発生しました: $e');
              // エラー時は通常の考え方モードだけで対応
              if (_aiService is GeminiService) {
                final geminiService = _aiService as GeminiService;
                final explanation =
                    await geminiService.generateThinkingModeExplanation(
                  content: content,
                );

                // 生成された考え方を暗記法形式に変換して返却
                return [
                  MemoryTechnique(
                    id: const Uuid().v4(),
                    name: '考え方モード',
                    description: '内容の本質を単純な考え方で理解しよう',
                    type: 'concept',
                    tags: ['thinking', '考え方'],
                    contentKeywords: [content],
                    content: content,
                    itemContent: content,
                    flashcards: [
                      Flashcard(
                        question: content,
                        answer: explanation,
                      )
                    ],
                    image: '',
                  )
                ];
              }
            }

            return newTechniques;
          } else {
            // 複数項目検出情報とitemCountが両方渡されている場合は、それを優先的に使用
            bool isMultipleItemDetection = false;
            String? rawContentForItems;
            int actualItemCount = itemCount ?? 1;

            // 複数項目検出情報があり、itemCountが指定されている場合
            if (multipleItemsDetection != null &&
                itemCount != null &&
                itemCount > 1) {
              isMultipleItemDetection = true;
              if (multipleItemsDetection.containsKey('rawContent')) {
                rawContentForItems = multipleItemsDetection['rawContent'];
              }
              actualItemCount = itemCount;
              print(
                  '複数項目として処理します: itemCount=$actualItemCount, rawContent=${rawContentForItems != null}');
            }

            final rawTechniques = await _aiService
                .generateMemoryTechniquesForMultipleItems([
              {'content': content, 'description': ''}
            ], progressCallback: (progress, processed, total) {
              // 進捗状況を上位コールバックに転送
              progressCallback?.call(progress, processed, total, false);
              print('itemCount: $actualItemCount');

              // 進行状況が完了に近い場合、生成完了通知を送信
              if (progress >= 0.98) {
                _sendTechniqueGenerationCompletedNotification(content);
              }
            },
                    isThinkingMode: isThinkingMode,
                    isMultiAgentMode: isMultiAgentMode,
                    itemCount: actualItemCount,
                    isQuickDetection: isMultipleItemDetection,
                    rawContent: rawContentForItems);

            // レスポンスから共通タイトルを取得
            String title = '';
            if (rawTechniques.isNotEmpty &&
                rawTechniques[0].containsKey('commonTitle')) {
              title = rawTechniques[0]['commonTitle'] ?? '';
            }

            // Map<String, dynamic>のリストからMemoryTechniqueのリストに変換
            newTechniques = rawTechniques.map((item) {
              return MemoryTechnique(
                name: title.isNotEmpty ? title : (item['name'] ?? '標準学習法'),
                description: item['description'] ?? '繰り返し練習で覚えよう',
                type: item['type'] ?? 'concept',
                tags: item['tags'] != null
                    ? List<String>.from(item['tags'])
                    : <String>[],
                contentKeywords: item['contentKeywords'] != null
                    ? List<String>.from(item['contentKeywords'])
                    : [item['itemContent'] ?? ''],
                itemContent: item['itemContent'] ?? content,
                flashcards: _extractFlashcards(item['flashcards'], content),
                image: item['image'] ?? '',
              );
            }).toList();
          }
        } catch (e) {
          print('Geminiでの暗記法生成に失敗したため、OpenAIにフォールバック: $e');
        }
      }

      // 生成した暗記法をFirestoreに保存
      if (newTechniques.isNotEmpty) {
        await storeMemoryTechniques(content, newTechniques);
      }

      return newTechniques;
    } catch (e) {
      print('暗記法の提案に失敗しました: $e');
      return [
        MemoryTechnique(
          name: '標準学習法',
          description: 'API応答で暗記法を取得できませんでした。繰り返し学習を試してみてください。',
          type: 'concept',
        ),
      ];
    }
  }

  // フラッシュカードを抽出するヘルパーメソッド
  List<Flashcard> _extractFlashcards(
      dynamic flashcardsData, String defaultContent) {
    if (flashcardsData == null) {
      // デフォルトのフラッシュカードを返す
      return [Flashcard(question: defaultContent, answer: '繰り返し確認してください')];
    }

    if (flashcardsData is List) {
      return flashcardsData.map((flashcard) {
        if (flashcard is Map<String, dynamic>) {
          return Flashcard(
            question: flashcard['question']?.toString() ?? '',
            answer: flashcard['answer']?.toString() ?? '',
          );
        }
        return Flashcard(question: '', answer: '');
      }).toList();
    }

    if (flashcardsData is Map<String, dynamic>) {
      return [
        Flashcard(
          question: flashcardsData['question']?.toString() ?? '',
          answer: flashcardsData['answer']?.toString() ?? '',
        )
      ];
    }

    return [Flashcard(question: '', answer: '')];
  }

  // 入力内容に複数の項目が含まれているかチェックする
  Future<Map<String, dynamic>> detectMultipleItems(String content) async {
    try {
      var result = await _aiService.detectMultipleItems(content);
      return result;
    } catch (e) {
      print('Geminiでの複数項目検出に失敗したため、OpenAIにフォールバック: $e');
      // エラー時はOpenAIにフォールバック
      // return await _openAIService.detectMultipleItems(content);
      return {'isMultipleItems': false, 'items': [], 'format': 'text'};
    }
  }

  // 複数の項目に対して個別に暗記法を生成する
  /// 特殊モード（考え方モードやマルチエージェントモード）の結果を処理するヘルパーメソッド
  List<MemoryTechnique> _processSpecialModeResults(
      List<Map<String, dynamic>> results) {
    print('特殊モードの結果を処理します: ${results.length}件');

    // Map<String, dynamic>のリストからMemoryTechniqueのリストに変換
    final techniques = results.map((item) {
      // フラッシュカードの処理
      List<Flashcard> flashcards = [];

      // フラッシュカードデータの処理（新旧形式に対応）
      if (item['flashcards'] != null && item['flashcards'] is List) {
        // 新形式の複数フラッシュカード
        final List flashcardsData = item['flashcards'] as List;
        flashcards = flashcardsData.map((cardData) {
          if (cardData is Map<String, dynamic>) {
            return Flashcard(
              question: cardData['question'] ?? '',
              answer: cardData['answer'] ?? '',
            );
          }
          return Flashcard(question: '', answer: '');
        }).toList();
      } else if (item['flashcard'] != null && item['flashcard'] is Map) {
        // 旧形式の単一フラッシュカード
        final cardData = item['flashcard'] as Map<String, dynamic>;
        flashcards = [
          Flashcard(
            question: cardData['question'] ?? '',
            answer: cardData['answer'] ?? '',
          )
        ];
      }

      // 暗記法インスタンスを生成
      return MemoryTechnique(
        id: const Uuid().v4(),
        name: item['name'] ?? '無名の暗記法',
        description: item['description'] ?? '',
        type: item['type'] ?? 'unknown',
        content: item['content'] ?? '',
        itemContent: item['content'] ?? '', // 内容を項目内容にも設定
        flashcards: flashcards,
        tags: item['tags'] == null
            ? []
            : (item['tags'] as List<dynamic>).map((e) => e.toString()).toList(),
      );
    }).toList();

    return techniques;
  }

  Future<List<MemoryTechnique>> generateTechniquesForMultipleItems(
    List<dynamic> items, {
    Function(double progress, int processedItems, int totalItems)?
        progressCallback,
    String? rawContent, // 高速検知時の生データ
    bool isQuickDetection = false, // 高速検知フラグ
    int? itemCount,
    bool isThinkingMode = false, // 考え方モードフラグ
    bool isMultiAgentMode = false, // マルチエージェントモードフラグ
  }) async {
    List<Map<String, dynamic>> results;
    try {
      // 特殊モード（考え方モードやマルチエージェントモード）の場合は分割処理しない
      if (isThinkingMode || isMultiAgentMode) {
        print('特殊モード（考え方モードまたはマルチエージェントモード）が指定されているため、単一項目として処理します');
        results =
            await _aiService.generateMemoryTechniquesForMultipleItems(items,
                progressCallback: progressCallback,
                isQuickDetection: false, // 特殊モードでは高速検出無効
                rawContent: rawContent,
                itemCount: 1); // 項目数を1に固定

        return _processSpecialModeResults(results);
      }

      // 通常の暗記法生成フローに進む
      // まずGeminiで試みる

      // 項目数を確認
      print('項目数: ${itemCount ?? items.length}');
      // 指定された項目数またはitemsの長さのうち、大きい方を使用
      final int totalItems =
          itemCount != null ? max(itemCount, items.length) : items.length;

      print(
          '使用する項目数: $totalItems (itemCount: $itemCount, items.length: ${items.length})');

      // 項目数が多い場合はバッチ処理を使用
      if ((totalItems > 10 || (itemCount != null && itemCount > 10)) &&
          _aiService is GeminiService) {
        print('項目数が$totalItems個あるため、バッチ処理を使用します');
        final geminiService = _aiService as GeminiService;
        results = await geminiService.generateMemoryTechniquesWithBatching(
            items,
            progressCallback: progressCallback,
            isQuickDetection: isQuickDetection,
            rawContent: rawContent,
            itemCount: itemCount);
      } else {
        // 少ない項目数の場合は通常の処理
        results = await _aiService.generateMemoryTechniquesForMultipleItems(
            items,
            progressCallback: progressCallback,
            isQuickDetection: isQuickDetection,
            rawContent: rawContent,
            itemCount: itemCount);
      }
    } catch (e) {
      print('Geminiでの暗記法生成に失敗したため、OpenAIにフォールバック: $e');
      // エラー時はOpenAIにフォールバック
      // results =
      //     await _openAIService.generateMemoryTechniquesForMultipleItems(items);
      results = [];
    }

    // Map<String, dynamic>のリストからMemoryTechniqueのリストに変換
    final techniques = results.map((item) {
      // フラッシュカードの処理
      List<Flashcard> extractFlashcards(dynamic flashcardsData) {
        if (flashcardsData == null) {
          // 古い形式の'flashcard'があれば使用
          if (item['flashcard'] != null) {
            final flashcard = item['flashcard'];
            if (flashcard is Map<String, dynamic>) {
              return [
                Flashcard(
                  question: flashcard['question']?.toString() ?? '',
                  answer: flashcard['answer']?.toString() ?? '',
                )
              ];
            }
          }

          // デフォルトのフラッシュカードを返す
          return [
            Flashcard(
              question: item['itemContent']?.toString() ?? '',
              answer: item['itemDescription']?.toString() ?? '',
            )
          ];
        }

        if (flashcardsData is List) {
          return flashcardsData.map((flashcard) {
            if (flashcard is Map<String, dynamic>) {
              return Flashcard(
                question: flashcard['question']?.toString() ?? '',
                answer: flashcard['answer']?.toString() ?? '',
              );
            }
            return Flashcard(question: '', answer: '');
          }).toList();
        }

        if (flashcardsData is Map<String, dynamic>) {
          return [
            Flashcard(
              question: flashcardsData['question']?.toString() ?? '',
              answer: flashcardsData['answer']?.toString() ?? '',
            )
          ];
        }

        return [];
      }

      return MemoryTechnique(
        name: item['name'] ?? '標準学習法',
        description: item['description'] ?? '繰り返し練習で覚えよう',
        type: item['type'] ?? 'concept',
        tags:
            item['tags'] != null ? List<String>.from(item['tags']) : <String>[],
        contentKeywords: item['contentKeywords'] != null
            ? List<String>.from(item['contentKeywords'])
            : [item['itemContent'] ?? ''],
        itemContent: item['itemContent'] ?? '',
        flashcards: extractFlashcards(item['flashcards']),
        image: item['image'] ?? '',
      );
    }).toList();

    return techniques;
  }

  // マルチエージェントによる暗記法提案（評価・ランク付け機能付き）
  Future<RankedMemoryTechnique> suggestRankedMemoryTechniques(
      String content) async {
    try {
      // まず、既存のランク付け暗記法を検索
      final existingRankedTechniques =
          await searchExistingRankedTechniques(content);
      if (existingRankedTechniques != null) {
        print('既存のランク付け暗記法が見つかりました');
        return existingRankedTechniques;
      }

      // 既存の暗記法が見つからない場合は、マルチエージェントで新しく生成
      print('マルチエージェントによる暗記法の生成を開始します');
      final rankedTechniques =
          await _aiAgentService.generateRankedMemoryTechniques(content);

      // 生成した暗記法がある場合のみ保存
      if (rankedTechniques.techniques.isNotEmpty) {
        await storeRankedMemoryTechniques(content, rankedTechniques);
        print('ランク付けされた暗記法を生成・保存しました: ${rankedTechniques.techniques.length}件');
      } else {
        print('暗記法の生成結果が空でした');
      }

      return rankedTechniques;
    } catch (e) {
      print('ランク付け暗記法の提案に失敗しました: $e');
      // デフォルトの暗記法を返す
      return RankedMemoryTechnique(
        techniques: [
          MemoryTechnique(
            name: '標準学習法',
            description: '$contentは繰り返し練習で覚えよう',
            type: 'concept',
          ),
        ],
      );
    }
  }

  // 既存のランク付け暗記法を検索する
  Future<RankedMemoryTechnique?> searchExistingRankedTechniques(
      String content) async {
    try {
      final contentHash = content.hashCode.toString();
      final user = _auth.currentUser;
      if (user == null) throw 'ユーザーがログインしていません';

      // コンテンツハッシュで完全一致検索
      final snapshot = await _memoryTechniquesCollection
          .where('contentHash', isEqualTo: contentHash)
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      final doc = snapshot.docs.first;
      final data = doc.data() as Map<String, dynamic>;

      // techniques配列が存在するか確認
      if (!data.containsKey('techniques') || data['techniques'] == null) {
        return null;
      }

      try {
        // techniquesデータからMemoryTechniqueのリストを作成
        final List<dynamic> techniquesData =
            data['techniques'] as List<dynamic>;
        final List<MemoryTechnique> techniques = techniquesData
            .map((t) => MemoryTechnique.fromMap(t as Map<String, dynamic>))
            .toList();

        if (techniques.isEmpty) return null;

        final currentIndex = data['currentIndex'] as int? ?? 0;
        return RankedMemoryTechnique(
          techniques: techniques,
          currentIndex: currentIndex,
        );
      } catch (e) {
        print('RankedMemoryTechnique変換エラー: $e');
        return null;
      }
    } catch (e) {
      print('既存ランク付け暗記法の検索に失敗しました: $e');
      return null;
    }
  }

  // 暗記法の表示順序を更新（次の暗記法に切り替え）
  Future<RankedMemoryTechnique> rotateMemoryTechnique(String content) async {
    try {
      final contentHash = content.hashCode.toString();
      final user = _auth.currentUser;
      if (user == null) throw 'ユーザーがログインしていません';

      // まずは既存の暗記法を取得
      final existingTechniques = await searchExistingRankedTechniques(content);
      if (existingTechniques == null || existingTechniques.techniques.isEmpty) {
        // 既存のものがなければ新規生成
        return await suggestRankedMemoryTechniques(content);
      }

      // インデックスを更新
      existingTechniques.nextTechnique();

      // Firestoreの該当ドキュメントを検索
      final snapshot = await _memoryTechniquesCollection
          .where('contentHash', isEqualTo: contentHash)
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // ドキュメントが見つかった場合はインデックスを更新
        final docRef = snapshot.docs.first.reference;
        await docRef.update({
          'currentIndex': existingTechniques.currentIndex,
        });
        print('暗記法の表示順序を更新しました: インデックス ${existingTechniques.currentIndex}');
      }

      return existingTechniques;
    } catch (e) {
      print('暗記法のローテーションに失敗しました: $e');
      throw '暗記法のローテーションに失敗しました: $e';
    }
  }

  // AIを使用して新しい暗記法を生成
  // 注意: このメソッドは削除されました。すべての暗記法生成はGeminiServiceのAPI統一メソッドに置き換えられました。

  // 生成した暗記法をメモリに保持するのみ（Firestoreには保存しない）
  // 暗記法は公開するとした場合のみ、publishMemoryTechniqueメソッドでFirestoreに保存される
  // MemoryTechniqueクラスのtoMapメソッドがスキーマほど（imageフィールドを含む）を処理する
  Future<void> storeMemoryTechniques(
      String content, List<MemoryTechnique> techniques) async {
    try {
      // コンテンツのハッシュ値を計算（同じ内容の重複を避けるため）
      final contentHash = content.hashCode.toString();
      print('コンテンツハッシュ値: $contentHash');

      // 日本語と英語のキーワードを抽出（検索用）
      final keywordsList = _extractSimpleKeywords(content);
      // 確実にString型のリストに変換する
      final List<String> keywords =
          keywordsList.map((k) => k.toString()).toList();
      print('抽出したキーワード: $keywords');

      // 暗記法はメモリに保持するのみで、Firestoreには保存しない
      // 公開する場合は別途publishMemoryTechniqueメソッドで処理される
      print('${techniques.length}件の暗記法をメモリに保持しました（Firestoreには保存されません）');
    } catch (e) {
      print('暗記法のメモリ保持に失敗しました: $e');
    }
  }

  // ランク付けされた暗記法をメモリに保持するのみ（Firestoreには保存しない）
  Future<void> storeRankedMemoryTechniques(
      String content, RankedMemoryTechnique rankedTechniques) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'ユーザーがログインしていません';
      }

      // コンテンツのハッシュ値を計算
      final contentHash = content.hashCode.toString();
      print('コンテンツハッシュ値: $contentHash');

      // 日本語と英語のキーワードを抽出（検索用）
      final keywordsList = _extractSimpleKeywords(content);
      final List<String> keywords =
          keywordsList.map((k) => k.toString()).toList();
      print('抽出したキーワード: $keywords');

      // 暗記法はメモリに保持するのみで、Firestoreには保存しない
      // 公開する場合は別途publishMemoryTechniqueメソッドで処理される
      print('ランク付けされた暗記法をメモリに保持しました（Firestoreには保存されません）');
      return;
    } catch (e) {
      print('ランク付け暗記法のメモリ保持に失敗しました: $e');
      throw 'ランク付け暗記法のメモリ保持に失敗しました: $e';
    }
  }

  // 類似の内容に関する暗記法を取得（MemoryMethodScreen用）
  Future<List<MemoryTechnique>> getSimilarTechniques(String content) async {
    try {
      // AIを使わず、簡易的なキーワード抽出を実行
      final List<String> keywords = _extractSimpleKeywords(content);

      if (keywords.isEmpty) {
        return [];
      }

      // キーワードを使用してFirestoreを検索
      final List<MemoryTechnique> results = [];
      final Map<String, int> techniqueScores = {}; // 技術ごとの関連スコア

      // まず完全一致を検索（自分のコンテンツと同じものは除外）
      final contentHash = content.hashCode.toString();

      // キーワードの重要度
      final keywordWeights = <String, double>{};
      for (int i = 0; i < keywords.length; i++) {
        // 最初のキーワードほど重要度が高い
        keywordWeights[keywords[i]] = 1.0 - (i * 0.15);
      }

      // キーワード検索（個別にクエリを実行して結果を統合）
      for (final keyword in keywords) {
        try {
          // 各キーワードに対して個別にクエリを実行
          final keywordMatches = await _memoryTechniquesCollection
              .where('contentKeywords', arrayContains: keyword)
              .limit(10) // 検索数を増やす
              .get();

          for (final doc in keywordMatches.docs) {
            final data = doc.data() as Map<String, dynamic>;
            // 自分のコンテンツは除外（contentHashを後でチェック）
            if (data['contentHash'] == contentHash) {
              continue;
            }

            final technique = MemoryTechnique.fromMap(data);
            final techniqueId = '${technique.name}:${technique.description}';

            // 重複を避けつつスコアを加算
            if (!techniqueScores.containsKey(techniqueId)) {
              techniqueScores[techniqueId] = 0;
              results.add(technique);
            }

            // このキーワードの重要度に基づいてスコアを加算
            techniqueScores[techniqueId] = techniqueScores[techniqueId]! +
                (keywordWeights[keyword] != null
                    ? (keywordWeights[keyword]! * 100).round()
                    : 50);

            // キーワードの共通数でスコアを加算
            if (data['contentKeywords'] != null) {
              final techniqueKeywords =
                  List<String>.from(data['contentKeywords']);
              for (final kw in techniqueKeywords) {
                if (keywords.contains(kw)) {
                  techniqueScores[techniqueId] =
                      techniqueScores[techniqueId]! + 10;
                }
              }
            }

            // タイプに基づいてスコアを調整（ユーザーの学習パターンなどに基づく）
            if (technique.type == 'mnemonic') {
              techniqueScores[techniqueId] = techniqueScores[techniqueId]! + 5;
            } else if (technique.type == 'relationship') {
              techniqueScores[techniqueId] = techniqueScores[techniqueId]! + 3;
            }
          }
        } catch (e) {
          print('キーワード "$keyword" の検索中にエラーが発生しました: $e');
          // エラーが発生しても続行
        }
      }

      // 人気のある暗記法も追加する（直近で多く使われているもの）
      try {
        final popularTechniques = await _memoryTechniquesCollection
            .orderBy('usageCount', descending: true)
            .limit(5)
            .get();

        for (final doc in popularTechniques.docs) {
          final data = doc.data() as Map<String, dynamic>;
          // 自分のコンテンツは除外
          if (data['contentHash'] == contentHash) {
            continue;
          }

          final technique = MemoryTechnique.fromMap(data);
          final techniqueId = '${technique.name}:${technique.description}';

          // 重複を避けつつスコアを加算
          if (!techniqueScores.containsKey(techniqueId)) {
            techniqueScores[techniqueId] = 20; // 人気のあるものにはデフォルトスコア
            results.add(technique);
          }
        }
      } catch (e) {
        print('人気の暗記法の取得中にエラーが発生しました: $e');
        // エラーが発生しても続行
      }

      // スコアに基づいて結果をソート
      results.sort((a, b) {
        final aId = '${a.name}:${a.description}';
        final bId = '${b.name}:${b.description}';
        return (techniqueScores[bId] ?? 0).compareTo(techniqueScores[aId] ?? 0);
      });

      // 最大10件まで返す
      return results.take(10).toList();
    } catch (e) {
      print('類似の暗記法の取得に失敗しました: $e');
      return [];
    }
  }

  // 暗記法を提案（履歴を考慮して重複を避ける）
  Future<List<MemoryTechnique>> suggestMemoryTechniquesWithHistory(
    String content,
    List<MemoryTechnique> previousTechniques, {
    bool isThinkingMode = false,
    bool isMultiAgentMode = false,
    int itemCount = 1,
    String? customTitle,
  }) async {
    List<Map<String, dynamic>> rawTechniques = [];

    try {
      // モードに基づいて処理判断
      if (isMultiAgentMode || isThinkingMode) {
        // マルチエージェントモードと考え方モードはバックグラウンド処理を使用
        print('バックグラウンドプロセッサーを使用して暗記法生成');

        // バックグラウンドプロセッサーのインスタンスを取得
        final backgroundProcessor = BackgroundProcessor();

        // モードに応じたタスクタイプと通知メッセージを設定
        String taskType;
        String notificationTitle;
        String notificationBody;

        if (isMultiAgentMode) {
          // マルチエージェントモード
          taskType = 'multiAgentMode';
          notificationTitle = 'マルチエージェント処理中';
          notificationBody = '暗記法を複数のAIで生成しています...';
        } else {
          // 考え方モード
          taskType = 'thinkingMode';
          notificationTitle = '考え方モード処理中';
          notificationBody = '内容の本質を分析しています...';
        }

        // タスクIDを生成（モードと現在時分に基づくユニークなID）
        final taskId = '${taskType}_${DateTime.now().millisecondsSinceEpoch}';

        // タスクデータを作成
        final taskData = {
          'type': taskType,
          'content': content,
          'itemCount': itemCount,
        };

        // タイトルがあれば追加（考え方モード用）
        if (isThinkingMode && customTitle != null && customTitle.isNotEmpty) {
          taskData['title'] = customTitle;
        }

        // タスクIDを含めてデータを中心化
        taskData['taskId'] = taskId;
        // 通知の設定を追加
        taskData['showNotification'] = 'true'; // 文字列型に変換
        taskData['notificationTitle'] = notificationTitle;
        taskData['notificationBody'] = notificationBody;

        // バックグラウンドタスクを開始
        final result = await backgroundProcessor.startTask(taskData);

        if (result.isEmpty) {
          // タスクの完了を待機
          bool isCompleted = false;
          int retryCount = 0;
          const maxRetries = 60; // 最大3分間待機（60回 * 3秒 = 180秒）

          // バックグラウンド処理が完了するまでポーリング
          while (!isCompleted && retryCount < maxRetries) {
            // 3秒待機
            await Future.delayed(const Duration(seconds: 3));
            retryCount++;

            // タスクの状態を確認
            final taskProgress =
                await backgroundProcessor.getTaskProgress(taskId);
            final status = taskProgress['status'] as String? ?? 'unknown';

            print('バックグラウンドタスク状態: $status');

            if (status == 'completed') {
              isCompleted = true;
              final result =
                  taskProgress['result'] as Map<String, dynamic>? ?? {};
              final techniques = result['techniques'] as List? ?? [];

              if (techniques.isNotEmpty) {
                // 結果をrawTechniquesに変換
                rawTechniques = List<Map<String, dynamic>>.from(techniques);
                print('バックグラウンドタスクが${rawTechniques.length}個の暗記法を生成しました');
              }
            } else if (status == 'error') {
              isCompleted = true;
              print('バックグラウンドタスクエラー: ${taskProgress['error']}');
              // エラーがあった場合はフォールバック処理へ
              rawTechniques = await _generateFallbackTechniques(
                  content, isThinkingMode, itemCount);
            }
          }

          // タイムアウト時のフォールバック
          if (!isCompleted) {
            print('バックグラウンドタスクがタイムアウトしました。通常モードにフォールバックします。');
            // 通常のモードで生成
            rawTechniques = await _generateFallbackTechniques(
                content, isThinkingMode, itemCount);
          }
        } else {
          // タスク開始失敗時のフォールバック
          print('バックグラウンドタスクの開始に失敗しました。通常モードにフォールバックします。');
          // 通常のモードで生成
          rawTechniques = await _generateFallbackTechniques(
              content, isThinkingMode, itemCount);
        }
      } else {
        // 既存の通常モード処理を維持
        print('AIサービスを使用して新しい暗記法を生成します');

        // 単一項目として暗記法を生成
        rawTechniques =
            await _aiService.generateMemoryTechniquesForMultipleItems(
          [
            {'content': content, 'description': '', 'itemCount': itemCount}
          ],
          isThinkingMode: false,
          isMultiAgentMode: false,
        );
      }

      // ここから下は既存の処理をそのまま維持
      // Map<String, dynamic>のリストからMemoryTechniqueのリストに変換
      final techniques = rawTechniques.map((item) {
        return MemoryTechnique(
          name: item['name'] ?? '標準学習法',
          description: item['description'] ?? '繰り返し練習で覚えよう',
          type: item['type'] ?? 'concept',
          tags: item['tags'] != null
              ? List<String>.from(item['tags'])
              : <String>[],
          contentKeywords: item['contentKeywords'] != null
              ? List<String>.from(item['contentKeywords'])
              : [item['itemContent'] ?? ''],
          itemContent: item['itemContent'] ?? content,
          flashcards: _extractFlashcards(item['flashcards'], content),
          image: item['image'] ?? '',
        );
      }).toList();

      // 生成した暗記法をFirestoreに保存
      await storeMemoryTechniques(content, techniques);

      // 過去に表示したものとの重複を確認
      final nonDuplicateTechniques = techniques.where((technique) {
        return !previousTechniques.any((prev) =>
            prev.name.toLowerCase() == technique.name.toLowerCase() &&
            prev.description.toLowerCase() ==
                technique.description.toLowerCase());
      }).toList();

      if (nonDuplicateTechniques.isEmpty) {
        // それでも重複する場合は、強制的に名前を変更
        return techniques.map((t) {
          return MemoryTechnique(
            name: '新・${t.name}',
            description: '${t.description}\n\n(新しいアプローチで取り組んでみましょう)',
            type: t.type,
            tags: t.tags,
            contentKeywords: t.contentKeywords,
            itemContent: t.itemContent,
            flashcards: t.flashcards,
            image: t.image,
          );
        }).toList();
      }

      return nonDuplicateTechniques;
    } catch (e) {
      print('暗記法の提案に失敗しました: $e');
      // エラー発生時は最低限の暗記法を返す
      return [
        MemoryTechnique(
          name: '標準学習法',
          description: 'API応答で暗記法を取得できませんでした。繰り返し学習を試してみてください。',
          type: 'unknown',
        )
      ];
    }
  }

  // キーワードキャッシュ（APIコール削減のため）
  final Map<String, List<String>> _keywordCache = {};
  final int _maxKeywordCacheSize = 50;

  // フォールバック用の暗記法生成メソッド
  Future<List<Map<String, dynamic>>> _generateFallbackTechniques(
    String content,
    bool isThinkingMode,
    int itemCount,
  ) async {
    if (isThinkingMode) {
      // 考え方モードの場合
      print('考え方モード: GeminiServiceの生成機能を使用（フォールバック）');
      try {
        if (_aiService is GeminiService) {
          final geminiService = _aiService as GeminiService;
          final explanation =
              await geminiService.generateThinkingModeExplanation(
            content: content,
          );

          // 生成された考え方を暗記法形式に変換
          return [
            {
              'name': '考え方',
              'description': explanation,
              'type': 'thinking',
              'tags': ['thinking', '考え方'],
              'itemContent': content,
              'flashcards': [
                {'question': content, 'answer': explanation}
              ]
            }
          ];
        }
      } catch (e) {
        print('考え方モードの生成エラー: $e');
      }
    }

    // 標準モードまたは考え方モードのエラー時
    print('AIサービスを使用して新しい暗記法を生成します');

    // 単一項目として暗記法を生成
    return await _aiService.generateMemoryTechniquesForMultipleItems(
      [
        {'content': content, 'description': '', 'itemCount': itemCount}
      ],
      isThinkingMode: isThinkingMode,
      isMultiAgentMode: false,
    );
  }

  // テキストからキーワードを簡易的に抽出する（AIを使わないシンプルな方法）
  List<String> _extractSimpleKeywords(String content) {
    if (content.isEmpty) {
      return [];
    }

    // キャッシュをチェック
    final contentKey = content.hashCode.toString();
    if (_keywordCache.containsKey(contentKey)) {
      return _keywordCache[contentKey]!;
    }

    // 単語分割と前処理
    final text = content
        .toLowerCase()
        .replaceAll(RegExp(r'[\r\n\t.,;:!?(){}\[\]<>"\\/@#$%^&*=+~`|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // ストップワード（無視する一般的な単語）
    final stopWords = {
      'a', 'an', 'the', 'and', 'or', 'but', 'if', 'because', 'as', 'what',
      'when', 'where', 'how', 'who', 'which', 'this', 'that', 'these', 'those',
      'then', 'just', 'so', 'than', 'such', 'both', 'through', 'about', 'for',
      'is', 'of', 'while', 'during', 'to', 'from', 'in', 'on', 'by', 'with',
      // 日本語のストップワード
      'は', 'が', 'の', 'に', 'を', 'で', 'と', 'も', 'や', 'から', 'まで', 'へ',
      'より', 'など', 'だ', 'です', 'ます', 'ない', 'ある', 'いる', 'する',
      'れる', 'られる', 'なる', 'という', 'あり', 'これ', 'それ', 'あの', 'この'
    };

    // 単語リストを作成し、頻度をカウント
    final Map<String, int> wordFreq = {};
    final words = text.split(' ');
    for (final word in words) {
      if (word.length < 2 || stopWords.contains(word)) continue;
      wordFreq[word] = (wordFreq[word] ?? 0) + 1;
    }

    // 頻度順にソートしてトップのキーワードを抽出
    final sortedWords = wordFreq.keys.toList()
      ..sort((a, b) => wordFreq[b]!.compareTo(wordFreq[a]!));

    // 最大10つのキーワードを選択
    final extractedKeywords = sortedWords.take(10).toList();

    // キャッシュに保存
    if (_keywordCache.length >= _maxKeywordCacheSize) {
      // キャッシュがいっぱいの場合、最初のエントリを削除
      final firstKey = _keywordCache.keys.first;
      _keywordCache.remove(firstKey);
    }
    _keywordCache[contentKey] = extractedKeywords;

    return extractedKeywords;
  }
}
