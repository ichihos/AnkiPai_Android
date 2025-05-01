import 'package:anki_pai/models/memory_technique.dart';

class RankedMemoryTechnique {
  final List<MemoryTechnique> techniques;
  int currentIndex;

  RankedMemoryTechnique({
    required this.techniques,
    this.currentIndex = 0,
  });

  MemoryTechnique get current {
    if (techniques.isEmpty) {
      return MemoryTechnique(
        name: '標準学習法',
        description: '暗記法が見つかりませんでした。繰り返し学習を試してみてください。',
      );
    }
    return techniques[currentIndex];
  }

  // 次の暗記法に移動するメソッド
  void nextTechnique() {
    if (techniques.isEmpty) return;
    currentIndex = (currentIndex + 1) % techniques.length;
  }

  // Firestoreに保存するための変換メソッド
  Map<String, dynamic> toMap() {
    return {
      'techniques': techniques.map((t) => t.toMap()).toList(),
      'currentIndex': currentIndex,
    };
  }

  // Firestoreから読み込むための変換メソッド
  factory RankedMemoryTechnique.fromMap(Map<String, dynamic> data) {
    // データに'techniques'が含まれているか確認
    if (!data.containsKey('techniques') || data['techniques'] == null) {
      return RankedMemoryTechnique(techniques: []);
    }

    try {
      final List<dynamic> techniquesData = data['techniques'] as List<dynamic>;
      final List<MemoryTechnique> techniques = techniquesData
          .map((t) => MemoryTechnique.fromMap(t as Map<String, dynamic>))
          .toList();

      return RankedMemoryTechnique(
        techniques: techniques,
        currentIndex: data['currentIndex'] as int? ?? 0,
      );
    } catch (e) {
      return RankedMemoryTechnique(techniques: []);
    }
  }

  // 空のインスタンスを作成するためのファクトリメソッド
  factory RankedMemoryTechnique.empty() {
    return RankedMemoryTechnique(techniques: []);
  }
}
