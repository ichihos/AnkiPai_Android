import 'dart:io' if (dart.library.html) 'package:anki_pai/utils/web_stub.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// 通知機能の初期化と設定を支援するヘルパークラス
class NotificationHelper {
  static final NotificationHelper _instance = NotificationHelper._internal();
  
  factory NotificationHelper() {
    return _instance;
  }
  
  NotificationHelper._internal();
  
  bool _initialized = false;
  
  /// タイムゾーンの初期化を行う
  Future<void> initializeTimeZone() async {
    if (_initialized) return;
    
    // タイムゾーンデータの初期化
    tz.initializeTimeZones();
    
    // ローカルタイムゾーンの設定
    final String timeZoneName = tz.local.name;
    tz.setLocalLocation(tz.getLocation(timeZoneName));
    
    _initialized = true;
  }
  
  /// 通知チャンネルの設定を初期化（Androidのみ必要）
  Future<void> setupNotificationChannels() async {
    // Webの場合は何もしない
    if (kIsWeb) return;
    
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    
    // Androidの場合のみチャンネル設定
    if (!kIsWeb && Platform.isAndroid) {
    
    // 学習リマインダーチャンネル
    const AndroidNotificationChannel learningChannel = AndroidNotificationChannel(
      'learning_reminders_channel',
      '学習リマインダー',
      description: '忘却曲線に基づく学習リマインダー通知',
      importance: Importance.high,
    );
    
    // 暗記法生成チャンネル
    const AndroidNotificationChannel generationChannel = AndroidNotificationChannel(
      'technique_generation_channel',
      '暗記法生成',
      description: '暗記法生成の完了通知',
      importance: Importance.high,
    );
    
    // チャンネルの作成
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(learningChannel);
    
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(generationChannel);
    }
  }
  
  /// 通知権限を要求する
  Future<bool> requestNotificationPermissions() async {
    // Webの場合は常にtrueを返す
    if (kIsWeb) return true;
    
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    
    // iOSの権限リクエスト
    if (!kIsWeb && Platform.isIOS) {
      final bool? result = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return result ?? false;
    }
    
    // Androidの権限リクエスト（Android 13以上）
    if (!kIsWeb && Platform.isAndroid) {
      // Android 13以上では権限取得が必要だが、flutter_local_notificationsのバージョンによって
      // メソッド名が異なることがあるため、現時点では手動で権限取得を行うことを前提とする
      return true;
    }
    
    return false;
  }
  
  /// 忘却曲線に基づく次の学習日を計算
  DateTime calculateNextReviewDate(int reviewCount, DateTime lastReviewDate) {
    // 忘却曲線に基づいて次の復習日を計算
    switch (reviewCount) {
      case 0: // 初回学習
        return lastReviewDate.add(const Duration(days: 1)); // 1日後
      case 1: // 1回目の復習後
        return lastReviewDate.add(const Duration(days: 3)); // 3日後
      case 2: // 2回目の復習後
        return lastReviewDate.add(const Duration(days: 7)); // 1週間後
      case 3: // 3回目の復習後
        return lastReviewDate.add(const Duration(days: 14)); // 2週間後
      case 4: // 4回目の復習後
        return lastReviewDate.add(const Duration(days: 30)); // 1ヶ月後
      default: // 5回目以降
        return lastReviewDate.add(const Duration(days: 60)); // 2ヶ月後
    }
  }
}
