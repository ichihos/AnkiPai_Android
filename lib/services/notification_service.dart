import 'dart:io' if (dart.library.html) 'package:anki_pai/utils/web_stub.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';

import '../models/notification_settings_model.dart';
// WebブラウザのUAを取得するための条件付きインポート
import 'dart:html'
    if (dart.library.io) 'package:anki_pai/utils/web_ua_stub.dart' as html;

/// 通知のタイプを定義
enum NotificationType {
  /// 暗記法生成の完了通知（バックグラウンド時）
  techniqueGeneration,

  /// 暗記法の学習リマインダー（忘却曲線ベース）
  techniqueLearning,

  /// フラッシュカードの学習リマインダー（忘却曲線ベース）
  flashcardLearning
}

/// 通知サービス - アプリの通知機能を管理
class NotificationService with WidgetsBindingObserver {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  NotificationSettingsModel? _settings;
  bool _isInitialized = false;
  bool _useSimulationMode = false; // Web環境でのシミュレーションモードフラグ
  
  // アプリがフォアグラウンドにあるか追跡するフラグ
  bool _isAppInForeground = true; // デフォルトとしてアプリは開始時にフォアグラウンドとみなす

  /// 初期化が完了したかどうか
  bool get isInitialized => _isInitialized;

  /// シミュレーションモードかどうか
  bool get isSimulationMode => _useSimulationMode;

  /// 現在の通知設定
  NotificationSettingsModel get settings =>
      _settings ?? NotificationSettingsModel();

  /// 通知サービスを初期化
  Future<void> initialize() async {
    // すでに初期化済みならスキップ
    if (_isInitialized) return;
    
    // ライフサイクルオブザーバーを登録
    WidgetsBinding.instance.addObserver(this);
    print('NotificationService: ライフサイクルオブザーバーを登録しました');

    // Web環境では初期化時にシミュレーションモードの確認
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _useSimulationMode =
            prefs.getBool('notification_simulation_mode') ?? false;
      } catch (e) {
        print('シミュレーションモード設定の読み込み中にエラーが発生しました: $e');
      }
    }

    // ローカル通知の初期化設定
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // FirebaseMessagingの設定
    // Webや各モバイルプラットフォームでのみFirebase Messagingを初期化
    if (!kIsWeb || (kIsWeb && _isBrowserSupportedForFCM())) {
      if (!Platform.isWindows && !Platform.isLinux) {
        await _setupFirebaseMessaging();
      }
    }

    // ユーザーの通知設定を読み込む
    await _loadNotificationSettings();

    _isInitialized = true;
  }

  /// Firebase Cloud Messagingの設定
  Future<void> _setupFirebaseMessaging() async {
    try {
      // Web環境でのService Worker確認
      if (kIsWeb) {
        print('Web環境でのFirebase Messagingを初期化しています');

        // WebブラウザーがFCMをサポートしているか確認
        if (!_isBrowserSupportedForFCM()) {
          print('\u73fe在のブラウザーではFCMがサポートされていません。通知機能をシミュレーションモードに切り替えます。');
          _useSimulationMode = true;
          return;
        }
      }

      // 通知権限の取得
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('ユーザーがプッシュ通知を許可しました: ${settings.authorizationStatus}');

        // 通知トークンを取得して保存
        try {
          // firebase_options.dartからVAPIDキーを取得
          const vapidKey = DefaultFirebaseOptions.webVapidKey;
          print('現在のVAPIDキー: $vapidKey');
          print('キーの長さ: ${vapidKey.length}');

          final token = await _firebaseMessaging.getToken(
            // Web環境では物理デバイス用の設定とVAPIDキーの設定が必要
            vapidKey: kIsWeb ? vapidKey : null,
          );
          print('トークンを取得しました: $token');

          if (token != null && _auth.currentUser != null) {
            await _saveTokenToFirestore(token);
          }
        } catch (e) {
          // FCMトークン取得に失敗した場合
          print('FCMトークンの取得中にエラーが発生しました: $e');
          _useSimulationMode = true;
        }

        // トークンが更新されたときの処理
        FirebaseMessaging.instance.onTokenRefresh.listen(_saveTokenToFirestore);
      } else {
        print('ユーザーがプッシュ通知を許可しませんでした: ${settings.authorizationStatus}');
      }

      // フォアグラウンド通知の設定
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // メッセージハンドラの設定
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      print('Firebase Cloud Messagingの初期化が完了しました');
    } catch (e) {
      print('Firebase Cloud Messagingの初期化中にエラーが発生しました: $e');

      // Web環境の場合、認証エラーが発生した時はシミュレーションモードに切り替える
      if (kIsWeb) {
        if (e.toString().contains('token-subscribe-failed') ||
            e.toString().contains('messaging/permission-blocked') ||
            e
                .toString()
                .contains('missing required authentication credential')) {
          await _handleFirebaseWebError();
        }
      }
    }
  }

  /// バックグラウンドメッセージハンドラ
  static Future<void> _firebaseMessagingBackgroundHandler(
      RemoteMessage message) async {
    // バックグラウンドでの通知処理
    print('バックグラウンド通知を受信: ${message.notification?.title}');
  }

  /// フォアグラウンドメッセージハンドラ
  void _handleForegroundMessage(RemoteMessage message) {
    // フォアグラウンドでの通知処理
    print('フォアグラウンド通知を受信: ${message.notification?.title}');
  }

  /// 通知がタップされたときの処理（開いているアプリの場合）
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('通知がタップされました: ${message.notification?.title}');
    // アプリ内の適切な画面に遷移する処理を追加
  }

  /// Web環境でのFirebase認証エラーを処理
  Future<void> _handleFirebaseWebError() async {
    // シミュレーションモードに設定
    _useSimulationMode = true;

    try {
      // 一部の通知設定をローカルに保存するように変更
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_simulation_mode', true);
      print('Web環境での通知シミュレーションモードを有効化しました');
    } catch (e) {
      print('シミュレーションモードの設定に失敗しました: $e');
    }
  }

  /// 通知がタップされたときの処理（ローカル通知）
  void _onNotificationTap(NotificationResponse response) {
    // 通知のペイロードに基づいて適切な画面に遷移
    if (response.payload != null) {
      // TODO: ペイロードに基づいてナビゲーション処理を追加
    }
  }

  /// FCMトークンをFirestoreに保存
  Future<void> _saveTokenToFirestore(String token) async {
    if (_auth.currentUser == null) return;

    try {
      final os = kIsWeb ? 'web' : Platform.operatingSystem;
      final deviceInfo =
          kIsWeb ? await _getWebBrowserInfo() : await _getDeviceInfo();

      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('fcm')
          .set({
        'token': token,
        'platform': os,
        'deviceInfo': deviceInfo,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('FCMトークンをFirestoreに保存しました');
    } catch (e) {
      print('FCMトークンのFirestore保存に失敗しました: $e');
    }
  }

  /// Webブラウザの情報を取得
  Future<Map<String, dynamic>> _getWebBrowserInfo() async {
    // Web環境ではブラウザ情報が取得できる限られた情報のみ返す
    return {
      'type': 'web',
      'userAgent': 'browser',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// ネイティブ環境でのデバイス情報を取得
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    // ネイティブ環境ではデバイス情報を返す
    // 実際にはdevice_info_plusパッケージなどを使って詳細な情報を取得できる
    return {
      'type': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 現在のブラウザがFirebase Cloud Messagingをサポートしているか確認
  bool _isBrowserSupportedForFCM() {
    if (!kIsWeb) return true;

    try {
      // ブラウザのチェックを実装
      final userAgent = html.window.navigator.userAgent.toLowerCase();

      // FCMを完全にサポートしているブラウザのみチェック
      // Chrome、Edge、Opera、Android WebViewはサポート、Firefox、Safari、IEはサポート外
      return !(userAgent.contains('firefox') ||
          userAgent.contains('safari') && !userAgent.contains('chrome') ||
          userAgent.contains('msie') ||
          userAgent.contains('trident'));
    } catch (e) {
      print('ブラウザチェック中にエラーが発生しました: $e');
      return false; // エラーが発生した場合は安全サイドに倒しシミュレーションモードを使用
    }
  }

  /// ユーザーの通知設定をFirestoreから読み込む
  Future<void> _loadNotificationSettings() async {
    if (_auth.currentUser == null) {
      _settings = NotificationSettingsModel();
      return;
    }

    try {
      final doc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('settings')
          .doc('notifications')
          .get();

      if (doc.exists) {
        _settings = NotificationSettingsModel.fromFirestore(doc);
      } else {
        _settings = NotificationSettingsModel();
        // デフォルト値を保存
        await saveNotificationSettings(_settings!);
      }
    } catch (e) {
      print('通知設定の読み込みに失敗しました: $e');
      _settings = NotificationSettingsModel();
    }
  }

  /// 通知設定を保存
  Future<void> saveNotificationSettings(
      NotificationSettingsModel settings) async {
    if (_auth.currentUser == null) return;

    _settings = settings;

    try {
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('settings')
          .doc('notifications')
          .set(settings.toFirestore());
    } catch (e) {
      print('通知設定の保存に失敗しました: $e');
    }
  }

  /// 通知をスケジュール
  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    int id = 0,
  }) async {
    if (!_isInitialized || !settings.isEnabled) return;

    const androidDetails = AndroidNotificationDetails(
      'learning_reminders_channel',
      '学習リマインダー',
      channelDescription: '忘却曲線に基づく学習リマインダー通知',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  /// 暗記法生成完了通知をスケジュール
  Future<void> scheduleTechniqueGenerationNotification({
    required String title,
    required String body,
    String? techniqueId,
  }) async {
    // アプリがフォアグラウンドにある場合は通知を表示しない
    if (_isAppInForeground) {
      print('アプリがフォアグラウンドにあるため、通知をスキップします: $title');
      return;
    }
    
    if (!_isInitialized ||
        !settings.isEnabled ||
        !settings.enableTechniqueGenerationNotifications) {
      return;
    }

    print('通知をスケジュール: $title (アプリはバックグラウンド)');
    await scheduleNotification(
      title: title,
      body: body,
      scheduledDate: DateTime.now().add(const Duration(seconds: 1)),
      payload: techniqueId != null ? 'technique:$techniqueId' : null,
      id: techniqueId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch % 100000,
    );
  }

  /// 暗記法学習リマインダー通知をスケジュール
  Future<void> scheduleTechniqueLearningReminder({
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? techniqueId,
  }) async {
    if (!_isInitialized ||
        !settings.isEnabled ||
        !settings.enableTechniqueLearningReminders) {
      return;
    }

    await scheduleNotification(
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      payload: techniqueId != null ? 'technique:$techniqueId' : null,
      id: (techniqueId?.hashCode ?? 0) + 100000,
    );
  }

  /// フラッシュカード学習リマインダー通知をスケジュール
  Future<void> scheduleFlashcardLearningReminder({
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? cardSetId,
  }) async {
    if (!_isInitialized ||
        !settings.isEnabled ||
        !settings.enableFlashcardLearningReminders) {
      return;
    }

    await scheduleNotification(
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      payload: cardSetId != null ? 'cardset:$cardSetId' : null,
      id: (cardSetId?.hashCode ?? 0) + 200000,
    );
  }

  /// 特定のIDの通知をキャンセル
  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  /// 特定のタイプの通知をすべてキャンセル
  Future<void> cancelNotificationsByType(NotificationType type) async {
    // Note: 特定の範囲のIDの通知をキャンセルするより効率的な方法がないため
    // 全ての通知をキャンセルしてから必要なものを再スケジュールする方が無難
    await _localNotifications.cancelAll();

    // 他のタイプの通知を再スケジュール
    // TODO: 他の通知タイプの再スケジュール処理を実装
  }

  /// すべての通知をキャンセル
  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  /// アプリのライフサイクル状態が変更されたときに呼び出される
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // アプリがフォアグラウンドに移動
        _isAppInForeground = true;
        print('NotificationService: アプリがフォアグラウンドに移動しました');
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // アプリがバックグラウンドに移動
        _isAppInForeground = false;
        print('NotificationService: アプリがバックグラウンドに移動しました - ${state.toString()}');
        break;
    }
  }
  
  /// リソースの解放
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    print('NotificationService: ライフサイクルオブザーバーを解除しました');
  }
}
