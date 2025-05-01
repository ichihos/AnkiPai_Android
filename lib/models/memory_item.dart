import 'memory_technique.dart';

class MemoryItem {
  final String id;
  final String title;
  final String content;
  final String contentType; // 'text' or 'image'
  final String? imageUrl;
  final int mastery; // 習得度 (0-100%)
  final DateTime createdAt;
  final DateTime? lastStudiedAt;
  final List<MemoryTechnique> memoryTechniques;

  MemoryItem({
    required this.id,
    required this.title,
    required this.content,
    required this.contentType,
    this.imageUrl,
    this.mastery = 0,
    required this.createdAt,
    this.lastStudiedAt,
    required this.memoryTechniques,
  });

  // Firestoreから取得したデータからMemoryItemを作成
  factory MemoryItem.fromMap(Map<String, dynamic> data, String id) {
    return MemoryItem(
      id: id,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      contentType: data['contentType'] ?? 'text',
      imageUrl: data['imageUrl'],
      mastery: data['mastery'] ?? 0,
      createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
      lastStudiedAt: data['lastStudiedAt']?.toDate(),
      memoryTechniques: (data['memoryTechniques'] as List?)
              ?.map((technique) => MemoryTechnique.fromMap(technique))
              .toList() ??
          [],
    );
  }

  // MemoryItemをFirestoreに保存するためのMap
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'contentType': contentType,
      'imageUrl': imageUrl,
      'mastery': mastery,
      'createdAt': createdAt,
      'lastStudiedAt': lastStudiedAt,
      'memoryTechniques':
          memoryTechniques.map((technique) => technique.toMap()).toList(),
    };
  }

  // 既存のMemoryItemから新しいMemoryItemを作成（プロパティの一部を変更）
  MemoryItem copyWith({
    String? id,
    String? title,
    String? content,
    String? contentType,
    String? imageUrl,
    int? mastery,
    DateTime? createdAt,
    DateTime? lastStudiedAt,
    List<MemoryTechnique>? memoryTechniques,
  }) {
    return MemoryItem(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      imageUrl: imageUrl ?? this.imageUrl,
      mastery: mastery ?? this.mastery,
      createdAt: createdAt ?? this.createdAt,
      lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
      memoryTechniques: memoryTechniques ?? this.memoryTechniques,
    );
  }
}
