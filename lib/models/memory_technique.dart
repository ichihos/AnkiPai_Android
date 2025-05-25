class Flashcard {
  final String question;
  final String answer;

  Flashcard({
    required this.question,
    required this.answer,
  });

  factory Flashcard.fromMap(Map<String, dynamic> data) {
    return Flashcard(
      question: data['question'] ?? '',
      answer: data['answer'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'answer': answer,
    };
  }
}

class MemoryTechnique {
  final String id; // 暗記法のID
  final String name;
  final String description;
  final String type; // "mnemonic", "relationship", "concept", or "unknown"
  final List<String> tags; // タグリスト（検索用）
  final List<String> contentKeywords; // コンテンツのキーワード（検索用）
  final bool isPublic; // 公開するか否か
  final String itemContent; // 複数項目の場合の元の項目内容
  final String itemDescription; // 項目の説明や補足情報
  final List<Flashcard> flashcards; // フラッシュカード
  final String image; // 暗記法に関連する画像の説明
  final String content; // 暗記法の対象となる内容
  final String taskId; // バックグラウンドタスクのID
  final String? userId; // 暗記法を作成したユーザーID

  MemoryTechnique({
    this.id = '',
    required this.name,
    required this.description,
    this.type = 'unknown',
    this.tags = const [],
    this.contentKeywords = const [],
    this.isPublic = false,
    this.itemContent = '',
    this.itemDescription = '',
    this.flashcards = const [],
    this.image = '',
    this.content = '',
    this.taskId = '',
    this.userId,
  });

  factory MemoryTechnique.fromMap(Map<String, dynamic> data) {
    // Extract tags with proper type checking
    List<String> extractTags(dynamic tagsData) {
      if (tagsData == null) return [];
      if (tagsData is List) {
        return tagsData.map((item) => item.toString()).toList();
      }
      return [];
    }

    return MemoryTechnique(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      type: data['type'] ?? 'unknown',
      tags: extractTags(data['tags']),
      contentKeywords: extractTags(data['contentKeywords']),
      isPublic: data['isPublic'] ?? false,
      itemContent: data['itemContent'] ?? '',
      itemDescription: data['itemDescription'] ?? '',
      image: data['image'] ?? '',
      content: data['content'] ?? '',
      taskId: data['taskId'] ?? '',
      userId: data['userId'],
      flashcards: () {
        // Handle both old single flashcard format and new multiple flashcards format
        if (data['flashcards'] != null && data['flashcards'] is List) {
          return (data['flashcards'] as List)
              .map((item) =>
                  item is Map<String, dynamic> ? Flashcard.fromMap(item) : null)
              .where((item) => item != null)
              .cast<Flashcard>()
              .toList();
        } else if (data['flashcard'] != null) {
          // Legacy format - single flashcard
          if (data['flashcard'] is Map<String, dynamic>) {
            final flashcardData = data['flashcard'] as Map<String, dynamic>;
            if (flashcardData['question'] != null ||
                flashcardData['answer'] != null) {
              return [Flashcard.fromMap(flashcardData)];
            }
          } else if (data['flashcard'] is List) {
            // Handle case where flashcard is a list in the old format
            return (data['flashcard'] as List)
                .map((item) => item is Map<String, dynamic>
                    ? Flashcard.fromMap(item)
                    : null)
                .where((item) => item != null)
                .cast<Flashcard>()
                .toList();
          }
        }
        return <Flashcard>[];
      }(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'type': type,
      'tags': tags,
      'contentKeywords': contentKeywords,
      'isPublic': isPublic,
      'itemContent': itemContent,
      'itemDescription': itemDescription,
      'image': image,
      'createdAt': DateTime.now().millisecondsSinceEpoch, // 作成日時を追加
      'userId': userId, // ユーザーIDを追加
      'flashcards': flashcards.map((card) => card.toMap()).toList(),
    };
  }
}
