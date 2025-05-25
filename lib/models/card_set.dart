class CardSet {
  final String id;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime? lastStudiedAt;
  final int cardCount;

  CardSet({
    required this.id,
    required this.title,
    this.description,
    required this.createdAt,
    this.lastStudiedAt,
    this.cardCount = 0,
  });

  // Firestoreから取得したデータからCardSetを作成
  factory CardSet.fromMap(Map<String, dynamic> data, String id) {
    return CardSet(
      id: id,
      title: data['title'] ?? '',
      description: data['description'],
      createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
      lastStudiedAt: data['lastStudiedAt']?.toDate(),
      cardCount: data['cardCount'] ?? 0,
    );
  }

  // CardSetをFirestoreに保存するためのMap
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'createdAt': createdAt,
      'lastStudiedAt': lastStudiedAt,
      'cardCount': cardCount,
    };
  }

  // 既存のCardSetから新しいCardSetを作成（プロパティの一部を変更）
  CardSet copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    DateTime? lastStudiedAt,
    int? cardCount,
  }) {
    return CardSet(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
      cardCount: cardCount ?? this.cardCount,
    );
  }
}
