import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/subscription_constants.dart';

enum SubscriptionType {
  free,
  premium_monthly,
  premium_yearly,
}

class SubscriptionModel {
  final String userId;
  final SubscriptionType type;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? lastUpdated;

  // 利用回数の追跡
  final int thinkingModeUsed;
  final int multiAgentModeUsed;
  final DateTime? usageResetDate; // 利用回数がリセットされる日（月初など）

  // サブスクリプションの状態
  // 'active': 有効なサブスクリプション
  // 'canceling': 解約予定（現在の課金期間が終了したら自動解約）
  // 'canceled': 解約済み
  // null: 状態不明（デフォルトをactiveとみなす）
  final String? status;

  // キャンセル予定日（解約が適用される日付）
  final DateTime? cancelAt;

  const SubscriptionModel({
    required this.userId,
    required this.type,
    this.startDate,
    this.endDate,
    this.lastUpdated,
    this.thinkingModeUsed = 0,
    this.multiAgentModeUsed = 0,
    this.usageResetDate,
    this.currentPeriodEnd,
    this.status,
    this.cancelAt,
  });

  // コピーコンストラクタ - 特定のフィールドを変更して新しいインスタンスを作成

  // フリープランの制限値
  static const int maxCardSets = 5;
  static const int maxCardsPerSet = 20;
  static const int maxThinkingModeUsage = 3;
  static const int maxMultiAgentModeUsage = 3;

  // Stripeから取得したデータに含まれるかもしれない追加フィールド
  final DateTime? currentPeriodEnd;

  // サブスクリプションが有効かどうかを確認
  bool get isActive {
    // フリープランは常に有効
    if (type == SubscriptionType.free) return true;

    // premium_*プランでtypeが設定されている場合は有効とみなす
    // Stripeからデータを強制満了した場合でも動作するようにする
    if (type == SubscriptionType.premium_monthly ||
        type == SubscriptionType.premium_yearly) {
      // 日付情報が存在する場合は日付で判定
      final now = DateTime.now();

      // 1. 通常の終了日チェック
      if (endDate != null && endDate!.isAfter(now)) {
        return true;
      }

      // 2. Stripe APIから取得した現在の期間チェック
      if (currentPeriodEnd != null && currentPeriodEnd!.isAfter(now)) {
        return true;
      }

      // 3. 日付情報がない場合、タイプのpremium_*判定のみで有効とみなす
      // Stripeから強制更新された場合はここで動作する
      return true;
    }

    return false;
  }

  // プレミアムプランかどうか
  bool get isPremium =>
      (type == SubscriptionType.premium_monthly ||
          type == SubscriptionType.premium_yearly) &&
      isActive;

  // カードセット数の制限を確認
  bool get hasReachedCardSetLimit => !isPremium && true; // 実装は後で行います

  // カード数の制限を確認
  bool hasReachedCardLimit(int currentCount) {
    return !isPremium && currentCount >= maxCardsPerSet;
  }

  // 思考モードの利用可能回数を確認
  int get remainingThinkingModeUses {
    if (isPremium) return -1; // 無制限を示す-1
    return maxThinkingModeUsage - thinkingModeUsed;
  }

  // マルチエージェントモードの利用可能回数を確認
  int get remainingMultiAgentModeUses {
    if (isPremium) return -1; // 無制限を示す-1
    return maxMultiAgentModeUsage - multiAgentModeUsed;
  }

  // 次回の利用回数リセット日を計算
  DateTime calculateNextResetDate() {
    final now = DateTime.now();
    // 翌月の1日を計算
    return DateTime(now.year, now.month + 1, 1);
  }

  // FirestoreからSubscriptionModelを生成
  factory SubscriptionModel.fromMap(Map<String, dynamic> data) {
    SubscriptionType type;
    final typeStr = data['type'] as String? ?? 'free';

    // サブスクリプションタイプをマッピング
    switch (typeStr) {
      case 'premium_monthly':
        type = SubscriptionType.premium_monthly;
        break;
      case 'premium_yearly':
        type = SubscriptionType.premium_yearly;
        break;
      case 'premium': // 旧データとの互換性のため
        type = SubscriptionType.premium_monthly;
        break;
      default:
        type = SubscriptionType.free;
    }

    // Stripe APIで使用されるフィールドをチェック
    DateTime? currentPeriodEnd;
    if (data['current_period_end'] != null) {
      try {
        currentPeriodEnd = (data['current_period_end'] as Timestamp).toDate();
      } catch (e) {}
    }

    // サブスクリプションの状態を取得
    String? status = data['status'] as String?;

    // 解約予定日を取得
    DateTime? cancelAt;
    if (data['cancel_at'] != null) {
      try {
        cancelAt = (data['cancel_at'] as Timestamp).toDate();
      } catch (e) {
        print('解約予定日のパースエラー: $e');
      }
    }

    return SubscriptionModel(
      userId: data['userId'],
      type: type,
      startDate: data['startDate'] != null
          ? (data['startDate'] as Timestamp).toDate()
          : null,
      endDate: data['endDate'] != null
          ? (data['endDate'] as Timestamp).toDate()
          : null,
      lastUpdated: data['lastUpdated'] != null
          ? (data['lastUpdated'] as Timestamp).toDate()
          : null,
      thinkingModeUsed: data['thinkingModeUsed'] ?? 0,
      multiAgentModeUsed: data['multiAgentModeUsed'] ?? 0,
      usageResetDate: data['usageResetDate'] != null
          ? (data['usageResetDate'] as Timestamp).toDate()
          : null,
      currentPeriodEnd: currentPeriodEnd,
      status: status,
      cancelAt: cancelAt,
    );
  }

  // FirestoreにデータをMapとして返す
  Map<String, dynamic> toMap() {
    String typeStr;

    switch (type) {
      case SubscriptionType.premium_monthly:
        typeStr = 'premium_monthly';
        break;
      case SubscriptionType.premium_yearly:
        typeStr = 'premium_yearly';
        break;
      default:
        typeStr = 'free';
    }

    return {
      'userId': userId,
      'type': typeStr,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'lastUpdated': Timestamp.fromDate(DateTime.now()),
      'thinkingModeUsed': thinkingModeUsed,
      'multiAgentModeUsed': multiAgentModeUsed,
      'usageResetDate':
          usageResetDate != null ? Timestamp.fromDate(usageResetDate!) : null,
      'currentPeriodEnd': currentPeriodEnd != null
          ? Timestamp.fromDate(currentPeriodEnd!)
          : null,
      'status': status,
      'cancel_at': cancelAt != null ? Timestamp.fromDate(cancelAt!) : null,
    };
  }

  // サブスクリプションプランの表示名を取得
  String get subscriptionName {
    switch (type) {
      case SubscriptionType.premium_monthly:
        return '月額プレミアム';
      case SubscriptionType.premium_yearly:
        return '年間プレミアム';
      default:
        return '無料プラン';
    }
  }

  // サブスクリプションの価格を取得
  String get subscriptionPrice {
    switch (type) {
      case SubscriptionType.premium_monthly:
        return SubscriptionConstants.monthlyPriceDisplay;
      case SubscriptionType.premium_yearly:
        return SubscriptionConstants.yearlyPriceDisplay;
      default:
        return '無料';
    }
  }

  // 新しいインスタンスを作成（コピーと更新）
  SubscriptionModel copyWith({
    String? userId,
    SubscriptionType? type,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? lastUpdated,
    int? thinkingModeUsed,
    int? multiAgentModeUsed,
    DateTime? usageResetDate,
    DateTime? currentPeriodEnd,
    String? status,
    DateTime? cancelAt,
  }) {
    return SubscriptionModel(
      userId: userId ?? this.userId,
      type: type ?? this.type,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      thinkingModeUsed: thinkingModeUsed ?? this.thinkingModeUsed,
      multiAgentModeUsed: multiAgentModeUsed ?? this.multiAgentModeUsed,
      usageResetDate: usageResetDate ?? this.usageResetDate,
    );
  }

  // 思考モードの使用回数をインクリメント
  SubscriptionModel incrementThinkingModeUsage() {
    return copyWith(thinkingModeUsed: thinkingModeUsed + 1);
  }

  // マルチエージェントモードの使用回数をインクリメント
  SubscriptionModel incrementMultiAgentModeUsage() {
    return copyWith(multiAgentModeUsed: multiAgentModeUsed + 1);
  }

  // デフォルトの無料プラン設定を作成
  factory SubscriptionModel.defaultFree(String userId) {
    final now = DateTime.now();
    final resetDate = DateTime(now.year, now.month + 1, 1); // 翌月1日

    return SubscriptionModel(
      userId: userId,
      type: SubscriptionType.free,
      lastUpdated: now,
      thinkingModeUsed: 0,
      multiAgentModeUsed: 0,
      usageResetDate: resetDate,
    );
  }
}
