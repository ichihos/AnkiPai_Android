import 'package:cloud_firestore/cloud_firestore.dart';

/// ユーザーの通知設定を管理するモデルクラス
class NotificationSettingsModel {
  /// 通知全体の有効/無効
  final bool isEnabled;
  
  /// 暗記法生成完了通知の有効/無効（アプリがバックグラウンドの場合）
  final bool enableTechniqueGenerationNotifications;
  
  /// 暗記法の学習リマインダー通知の有効/無効（忘却曲線に基づく）
  final bool enableTechniqueLearningReminders;
  
  /// フラッシュカードの学習リマインダー通知の有効/無効（忘却曲線に基づく）
  final bool enableFlashcardLearningReminders;
  
  /// 最終更新日時
  final DateTime lastUpdated;

  NotificationSettingsModel({
    this.isEnabled = true,
    this.enableTechniqueGenerationNotifications = true,
    this.enableTechniqueLearningReminders = true,
    this.enableFlashcardLearningReminders = true,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  /// FirestoreのドキュメントからNotificationSettingsModelを作成
  factory NotificationSettingsModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    
    if (data == null) {
      return NotificationSettingsModel();
    }
    
    return NotificationSettingsModel(
      isEnabled: data['isEnabled'] ?? true,
      enableTechniqueGenerationNotifications: 
          data['enableTechniqueGenerationNotifications'] ?? true,
      enableTechniqueLearningReminders: 
          data['enableTechniqueLearningReminders'] ?? true,
      enableFlashcardLearningReminders: 
          data['enableFlashcardLearningReminders'] ?? true,
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// NotificationSettingsModelをFirestoreに保存するためのマップに変換
  Map<String, dynamic> toFirestore() {
    return {
      'isEnabled': isEnabled,
      'enableTechniqueGenerationNotifications': enableTechniqueGenerationNotifications,
      'enableTechniqueLearningReminders': enableTechniqueLearningReminders,
      'enableFlashcardLearningReminders': enableFlashcardLearningReminders,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }

  /// 設定を更新した新しいインスタンスを作成
  NotificationSettingsModel copyWith({
    bool? isEnabled,
    bool? enableTechniqueGenerationNotifications,
    bool? enableTechniqueLearningReminders,
    bool? enableFlashcardLearningReminders,
  }) {
    return NotificationSettingsModel(
      isEnabled: isEnabled ?? this.isEnabled,
      enableTechniqueGenerationNotifications: 
          enableTechniqueGenerationNotifications ?? 
          this.enableTechniqueGenerationNotifications,
      enableTechniqueLearningReminders: 
          enableTechniqueLearningReminders ?? 
          this.enableTechniqueLearningReminders,
      enableFlashcardLearningReminders: 
          enableFlashcardLearningReminders ?? 
          this.enableFlashcardLearningReminders,
      lastUpdated: DateTime.now(),
    );
  }
}
