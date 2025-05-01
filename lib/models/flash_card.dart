class FlashCard {
  final String id;
  final String frontText;
  final String backText;
  final DateTime createdAt;
  final DateTime? lastStudiedAt;
  final int masteryLevel; // 習得度 (0-100%)
  final String? setId; // カードセットID

  FlashCard({
    required this.id,
    required this.frontText,
    required this.backText,
    required this.createdAt,
    this.lastStudiedAt,
    this.masteryLevel = 0,
    this.setId,
  });

  // Firestoreから取得したデータからFlashCardを作成
  factory FlashCard.fromMap(Map<String, dynamic> data, String id) {
    return FlashCard(
      id: id,
      frontText: data['frontText'] ?? '',
      backText: data['backText'] ?? '',
      createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
      lastStudiedAt: data['lastStudiedAt']?.toDate(),
      masteryLevel: data['masteryLevel'] ?? 0,
      setId: data['setId'],
    );
  }

  // FlashCardをFirestoreに保存するためのMap
  Map<String, dynamic> toMap() {
    return {
      'frontText': frontText,
      'backText': backText,
      'createdAt': createdAt,
      'lastStudiedAt': lastStudiedAt,
      'masteryLevel': masteryLevel,
      'setId': setId,
    };
  }

  // 既存のFlashCardから新しいFlashCardを作成（プロパティの一部を変更）
  FlashCard copyWith({
    String? id,
    String? frontText,
    String? backText,
    DateTime? createdAt,
    DateTime? lastStudiedAt,
    int? masteryLevel,
    String? setId,
  }) {
    return FlashCard(
      id: id ?? this.id,
      frontText: frontText ?? this.frontText,
      backText: backText ?? this.backText,
      createdAt: createdAt ?? this.createdAt,
      lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
      masteryLevel: masteryLevel ?? this.masteryLevel,
      setId: setId ?? this.setId,
    );
  }
}
