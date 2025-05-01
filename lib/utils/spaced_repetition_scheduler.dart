import 'package:intl/intl.dart';

/// 忘却曲線に基づいたスケジューリングロジックを提供するクラス
class SpacedRepetitionScheduler {
  /// 次の学習日を計算
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

  /// 次の学習日までの残り日数を取得
  int getDaysUntilNextReview(int reviewCount, DateTime lastReviewDate) {
    final nextReviewDate = calculateNextReviewDate(reviewCount, lastReviewDate);
    final now = DateTime.now();
    final difference = nextReviewDate.difference(now);
    return difference.inDays;
  }

  /// 忘却曲線に基づく学習ステータスを取得
  LearningStatus getLearningStatus(int reviewCount, DateTime lastReviewDate) {
    final now = DateTime.now();
    final nextReviewDate = calculateNextReviewDate(reviewCount, lastReviewDate);

    if (now.isAfter(nextReviewDate.add(const Duration(days: 3)))) {
      // 次の学習日を3日以上過ぎている場合は「遅れている」
      return LearningStatus.overdue;
    } else if (now.isAfter(nextReviewDate)) {
      // 次の学習日が来ている場合は「学習日」
      return LearningStatus.dueToday;
    } else if (now.isAfter(nextReviewDate.subtract(const Duration(days: 1)))) {
      // 次の学習日の1日前の場合は「もうすぐ学習日」
      return LearningStatus.dueSoon;
    } else {
      // それ以外の場合は「学習中」
      return LearningStatus.inProgress;
    }
  }

  /// 次の学習日を人間が読みやすい形式で取得
  String getNextReviewDateFormatted(int reviewCount, DateTime lastReviewDate) {
    final nextReviewDate = calculateNextReviewDate(reviewCount, lastReviewDate);
    return DateFormat('yyyy年MM月dd日').format(nextReviewDate);
  }

  /// 忘却曲線に基づく通知メッセージを取得
  String getNotificationMessage(
      int reviewCount, String itemName, DateTime lastReviewDate) {
    final status = getLearningStatus(reviewCount, lastReviewDate);

    switch (status) {
      case LearningStatus.overdue:
        return '$itemNameの学習日が過ぎています。今すぐ復習しましょう！';
      case LearningStatus.dueToday:
        return '$itemNameの学習日です。今日復習しましょう！';
      case LearningStatus.dueSoon:
        return '$itemNameの学習日が近づいています。明日復習の準備をしましょう！';
      case LearningStatus.inProgress:
        final days = getDaysUntilNextReview(reviewCount, lastReviewDate);
        return '$itemNameの次の学習日まであと$days日です。';
    }
  }
}

/// 学習ステータスを表す列挙型
enum LearningStatus {
  /// 学習中（次の学習日までまだ時間がある）
  inProgress,

  /// もうすぐ学習日（1日以内に学習日が来る）
  dueSoon,

  /// 学習日（今日が学習日）
  dueToday,

  /// 遅れている（学習日を過ぎている）
  overdue,
}
