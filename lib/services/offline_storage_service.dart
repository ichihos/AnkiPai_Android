import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/card_set.dart';
import '../models/flash_card.dart';
import '../models/memory_technique.dart';

/// Service to handle offline storage of card sets, flash cards and memory techniques
class OfflineStorageService {
  static const String _cardSetsKey = 'offline_card_sets';
  static const String _flashCardsPrefix = 'offline_flash_cards_';
  static const String _memoryTechniquesKey = 'offline_memory_techniques';
  static const String _publicMemoryTechniquesKey = 'offline_public_memory_techniques';
  
  /// Singleton instance
  static final OfflineStorageService _instance = OfflineStorageService._internal();
  
  /// Factory constructor
  factory OfflineStorageService() => _instance;
  
  /// Private constructor
  OfflineStorageService._internal();

  /// Save a card set to offline storage
  Future<void> saveCardSet(CardSet cardSet) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing card sets or initialize empty list
      final List<String> cardSetsJson = prefs.getStringList(_cardSetsKey) ?? [];
      
      // Check if this card set already exists in storage
      final existingIndex = _findCardSetIndex(cardSetsJson, cardSet.id);
      
      // Convert card set to JSON
      final cardSetJson = jsonEncode(cardSet.toMap()..['id'] = cardSet.id);
      
      // Update or add the card set
      if (existingIndex >= 0) {
        cardSetsJson[existingIndex] = cardSetJson;
      } else {
        cardSetsJson.add(cardSetJson);
      }
      
      // Save updated list
      await prefs.setStringList(_cardSetsKey, cardSetsJson);
      print('✅ カードセット「${cardSet.title}」をオフラインストレージに保存しました');
    } catch (e) {
      print('❌ カードセットのオフライン保存エラー: $e');
    }
  }

  /// Find the index of a card set in the JSON list by ID
  int _findCardSetIndex(List<String> cardSetsJson, String cardSetId) {
    for (int i = 0; i < cardSetsJson.length; i++) {
      try {
        final Map<String, dynamic> data = jsonDecode(cardSetsJson[i]);
        if (data['id'] == cardSetId) {
          return i;
        }
      } catch (e) {
        print('❌ カードセットJSONの解析エラー: $e');
      }
    }
    return -1;
  }

  /// Save flash cards for a specific card set
  Future<void> saveFlashCards(String cardSetId, List<FlashCard> cards) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Convert cards to JSON using toJson method to handle DateTime objects
      final List<String> cardsJson = cards.map((card) {
        // toJsonメソッドを使用してDateTimeオブジェクトを文字列に変換
        final json = card.toJson();
        json['id'] = card.id;
        return jsonEncode(json);
      }).toList();
      
      // Save cards with card set ID as part of the key
      await prefs.setStringList('${_flashCardsPrefix}$cardSetId', cardsJson);
      print('✅ カードセット「$cardSetId」の${cards.length}枚のカードをオフラインストレージに保存しました');
    } catch (e) {
      print('❌ フラッシュカードのオフライン保存エラー: $e');
    }
  }

  /// Get all card sets from offline storage
  Future<List<CardSet>> getCardSets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> cardSetsJson = prefs.getStringList(_cardSetsKey) ?? [];
      
      final List<CardSet> cardSets = [];
      
      for (final json in cardSetsJson) {
        try {
          final Map<String, dynamic> data = jsonDecode(json);
          final String id = data['id'] as String;
          cardSets.add(CardSet.fromMap(data, id));
        } catch (e) {
          print('❌ カードセットの解析エラー: $e');
        }
      }
      
      return cardSets;
    } catch (e) {
      print('❌ オフラインカードセットの取得エラー: $e');
      return [];
    }
  }

  /// Get a specific card set by ID
  Future<CardSet?> getCardSetById(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> cardSetsJson = prefs.getStringList(_cardSetsKey) ?? [];
      
      final index = _findCardSetIndex(cardSetsJson, id);
      if (index >= 0) {
        final Map<String, dynamic> data = jsonDecode(cardSetsJson[index]);
        return CardSet.fromMap(data, id);
      }
      
      return null;
    } catch (e) {
      print('❌ オフラインカードセットの取得エラー: $e');
      return null;
    }
  }

  /// Get flash cards for a specific card set
  Future<List<FlashCard>> getFlashCards(String cardSetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> cardsJson = prefs.getStringList('${_flashCardsPrefix}$cardSetId') ?? [];
      
      final List<FlashCard> cards = [];
      
      for (final json in cardsJson) {
        try {
          final Map<String, dynamic> data = jsonDecode(json);
          final String id = data['id'] as String;
          
          // JSONからのDateTime変換を正しく処理
          DateTime createdAt;
          DateTime? lastStudiedAt;
          
          try {
            // createdAtをISO8601形式の文字列からDateTimeに変換
            createdAt = data['createdAt'] != null 
              ? DateTime.parse(data['createdAt'] as String) 
              : DateTime.now();
              
            // lastStudiedAtが存在すれば変換
            lastStudiedAt = data['lastStudiedAt'] != null 
              ? DateTime.parse(data['lastStudiedAt'] as String) 
              : null;
              
            // FlashCardオブジェクトを作成
            cards.add(FlashCard(
              id: id,
              frontText: data['frontText'] ?? '',
              backText: data['backText'] ?? '',
              createdAt: createdAt,
              lastStudiedAt: lastStudiedAt,
              masteryLevel: data['masteryLevel'] ?? 0,
              setId: data['setId'],
            ));
            
            print('✅ カード「${data['frontText']}」をロードしました（setId: ${data['setId']}）');
          } catch (dateError) {
            print('❌ DateTimeの解析エラー: $dateError');
            // エラーが発生した場合は当面の対処としてfromMapを使用
            cards.add(FlashCard.fromMap(data, id));
          }
        } catch (e) {
          print('❌ フラッシュカードの解析エラー: $e');
        }
      }
      
      return cards;
    } catch (e) {
      print('❌ オフラインフラッシュカードの取得エラー: $e');
      return [];
    }
  }

  /// Check if a card set exists in offline storage
  Future<bool> hasCardSet(String cardSetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> cardSetsJson = prefs.getStringList(_cardSetsKey) ?? [];
      
      return _findCardSetIndex(cardSetsJson, cardSetId) >= 0;
    } catch (e) {
      print('❌ オフラインカードセットの確認エラー: $e');
      return false;
    }
  }

  /// Delete a card set and its cards from offline storage
  Future<void> deleteCardSet(String cardSetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Delete cards first
      await prefs.remove('${_flashCardsPrefix}$cardSetId');
      
      // Then delete the card set
      final List<String> cardSetsJson = prefs.getStringList(_cardSetsKey) ?? [];
      final index = _findCardSetIndex(cardSetsJson, cardSetId);
      
      if (index >= 0) {
        cardSetsJson.removeAt(index);
        await prefs.setStringList(_cardSetsKey, cardSetsJson);
        print('✅ カードセット「$cardSetId」をオフラインストレージから削除しました');
      }
    } catch (e) {
      print('❌ カードセットのオフライン削除エラー: $e');
    }
  }
  
  /// Save a memory technique to offline storage
  Future<void> saveMemoryTechnique(MemoryTechnique technique, {bool isPublic = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 公開設定に関わらず、すべての暗記法をユーザーの暗記法として保存
      final String key = _memoryTechniquesKey;
      
      // Get existing memory techniques or initialize empty list
      final List<String> techniquesJson = prefs.getStringList(key) ?? [];
      
      // Check if this technique already exists in storage
      final existingIndex = _findMemoryTechniqueIndex(techniquesJson, technique.id);
      
      // デバッグ用に暗記法の情報を表示
      print('💾 暗記法保存: id=${technique.id}, name=${technique.name}, userId=${technique.userId}, isPublic=${technique.isPublic}');
      
      // Convert technique to JSON
      final techniqueJson = jsonEncode(technique.toMap());
      
      // Update or add the technique
      if (existingIndex >= 0) {
        techniquesJson[existingIndex] = techniqueJson;
        print('🔄 既存の暗記法を更新しました: ${technique.name}');
      } else {
        techniquesJson.add(techniqueJson);
        print('➕ 新しい暗記法を追加しました: ${technique.name}');
      }
      
      // Save updated list
      await prefs.setStringList(key, techniquesJson);
      print('✅ 暗記法「${technique.name}」をオフラインストレージに保存しました (合計: ${techniquesJson.length}個)');
    } catch (e) {
      print('❌ 暗記法のオフライン保存エラー: $e');
    }
  }
  
  /// Get all memory techniques from offline storage
  /// [publicOnly] - 公開暗記法のみを取得する場合はtrue
  /// [userId] - 特定のユーザーの暗記法のみを取得する場合に指定
  Future<List<MemoryTechnique>> getMemoryTechniques({bool publicOnly = false, String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String key = publicOnly ? _publicMemoryTechniquesKey : _memoryTechniquesKey;
      
      final List<String> techniquesJson = prefs.getStringList(key) ?? [];
      final List<MemoryTechnique> techniques = [];
      
      print('🔍 オフラインストレージから暗記法を読み込みます: ${publicOnly ? "公開" : "ユーザー"} 暗記法, ユーザーID: ${userId ?? "指定なし"}');
      print('📊 ストレージ内の暗記法JSON数: ${techniquesJson.length}');
      
      // ユーザーIDが指定されていない場合は、保存されている最後のユーザーIDを試す
      String? effectiveUserId = userId;
      if (effectiveUserId == null) {
        try {
          effectiveUserId = prefs.getString('last_user_id');
          if (effectiveUserId != null) {
            print('📱 保存されていた最後のユーザーID($effectiveUserId)を使用します');
          }
        } catch (e) {
          print('⚠️ 保存されたユーザーIDの取得に失敗: $e');
        }
      }
      
      for (int i = 0; i < techniquesJson.length; i++) {
        final json = techniquesJson[i];
        try {
          final Map<String, dynamic> data = jsonDecode(json);
          
          // デバッグ用に暗記法のデータを表示
          print('🔍 暗記法データ[$i]: id=${data['id']}, name=${data['name']}, userId=${data['userId']}');
          
          final technique = MemoryTechnique.fromMap(data);
          
          // ユーザーIDが指定されている場合は、そのユーザーの暗記法のみをフィルタリング
          if (effectiveUserId != null) {
            final techniqueUserId = technique.userId;
            if (techniqueUserId != null && techniqueUserId == effectiveUserId) {
              techniques.add(technique);
              print('✅ ユーザー($effectiveUserId)の暗記法「${technique.name}」を読み込みました');
            } else if (techniqueUserId == null) {
              // ユーザーIDがない場合は、ユーザーに関係なく追加（古いデータ対応）
              print('⚠️ ユーザーIDのない暗記法「${technique.name}」を読み込みました');
              techniques.add(technique);
            }
          } else {
            // ユーザーIDが指定されていない場合は全て追加
            techniques.add(technique);
            print('✅ すべてのユーザー向け: 暗記法「${technique.name}」を読み込みました');
          }
        } catch (e) {
          print('⚠️ 暗記法のJSONデコードエラー[$i]: $e');
          try {
            // エラーの詳細を確認するために生のJSONを表示
            print('🔍 問題のあるJSON: ${json.substring(0, min(100, json.length))}...');
          } catch (innerError) {
            print('⚠️ JSONの表示にも失敗: $innerError');
          }
        }
      }
      
      print('✅ ${techniques.length}個の暗記法をオフラインストレージから読み込みました');
      return techniques;
    } catch (e) {
      print('❌ 暗記法のオフライン読み込みエラー: $e');
      return [];
    }
  }
  
  /// Get a specific memory technique by ID
  Future<MemoryTechnique?> getMemoryTechniqueById(String id, {bool checkPublic = false}) async {
    try {
      // First check in user techniques
      final techniques = await getMemoryTechniques();
      final technique = techniques.firstWhere((t) => t.id == id, orElse: () => throw 'Not found');
      return technique;
    } catch (e) {
      // If not found and checkPublic is true, check in public techniques
      if (checkPublic) {
        try {
          final publicTechniques = await getMemoryTechniques(publicOnly: true);
          final technique = publicTechniques.firstWhere((t) => t.id == id, orElse: () => throw 'Not found');
          return technique;
        } catch (e) {
          print('⚠️ 暗記法が見つかりません: $id');
          return null;
        }
      }
      print('⚠️ 暗記法が見つかりません: $id');
      return null;
    }
  }
  
  /// Delete a memory technique from offline storage
  Future<void> deleteMemoryTechnique(String id, {bool isPublic = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String key = isPublic ? _publicMemoryTechniquesKey : _memoryTechniquesKey;
      
      final List<String> techniquesJson = prefs.getStringList(key) ?? [];
      final existingIndex = _findMemoryTechniqueIndex(techniquesJson, id);
      
      if (existingIndex >= 0) {
        techniquesJson.removeAt(existingIndex);
        await prefs.setStringList(key, techniquesJson);
        print('✅ 暗記法をオフラインストレージから削除しました: $id');
      } else {
        print('⚠️ 削除対象の暗記法が見つかりません: $id');
      }
    } catch (e) {
      print('❌ 暗記法のオフライン削除エラー: $e');
    }
  }
  
  /// Find the index of a memory technique in the JSON list by ID
  int _findMemoryTechniqueIndex(List<String> techniquesJson, String techniqueId) {
    for (int i = 0; i < techniquesJson.length; i++) {
      try {
        final Map<String, dynamic> data = jsonDecode(techniquesJson[i]);
        if (data['id'] == techniqueId) {
          return i;
        }
      } catch (e) {
        print('⚠️ 暗記法のJSONデコードエラー: $e');
      }
    }
    return -1;
  }
  
  /// Save a single flash card
  Future<void> saveFlashCard(String cardId, FlashCard card) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get the card set ID
      final String? setId = card.setId;
      if (setId == null) {
        print('❌ カードにsetIdがありません');
        return;
      }
      
      // Get existing cards for this set
      final List<String> cardsJson = prefs.getStringList('${_flashCardsPrefix}$setId') ?? [];
      
      // Find if this card already exists
      int existingIndex = -1;
      for (int i = 0; i < cardsJson.length; i++) {
        try {
          final Map<String, dynamic> data = jsonDecode(cardsJson[i]);
          if (data['id'] == cardId) {
            existingIndex = i;
            break;
          }
        } catch (e) {
          print('❌ カードJSONの解析エラー: $e');
        }
      }
      
      // Convert card to JSON using toJson method to handle DateTime objects
      final cardJson = jsonEncode(card.toJson()..['id'] = cardId);
      
      // Update or add the card
      if (existingIndex >= 0) {
        cardsJson[existingIndex] = cardJson;
      } else {
        cardsJson.add(cardJson);
      }
      
      // Save updated list
      await prefs.setStringList('${_flashCardsPrefix}$setId', cardsJson);
      print('✅ カード「$cardId」をオフラインストレージに保存しました');
    } catch (e) {
      print('❌ カードのオフライン保存エラー: $e');
    }
  }
  
  /// Delete a single flash card
  Future<void> deleteFlashCard(String cardId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // We need to search through all card sets to find this card
      final List<String> cardSetsJson = prefs.getStringList(_cardSetsKey) ?? [];
      
      for (final cardSetJson in cardSetsJson) {
        try {
          final Map<String, dynamic> data = jsonDecode(cardSetJson);
          final String setId = data['id'] as String;
          
          // Get cards for this set
          final List<String> cardsJson = prefs.getStringList('${_flashCardsPrefix}$setId') ?? [];
          
          // Find the card
          int cardIndex = -1;
          for (int i = 0; i < cardsJson.length; i++) {
            try {
              final Map<String, dynamic> cardData = jsonDecode(cardsJson[i]);
              if (cardData['id'] == cardId) {
                cardIndex = i;
                break;
              }
            } catch (e) {
              print('❌ カードJSONの解析エラー: $e');
            }
          }
          
          // If found, remove it
          if (cardIndex >= 0) {
            cardsJson.removeAt(cardIndex);
            await prefs.setStringList('${_flashCardsPrefix}$setId', cardsJson);
            print('✅ カード「$cardId」をオフラインストレージから削除しました');
            return;
          }
        } catch (e) {
          print('❌ カードセットJSONの解析エラー: $e');
        }
      }
      
      print('⚠️ カード「$cardId」がオフラインストレージに見つかりませんでした');
    } catch (e) {
      print('❌ カードのオフライン削除エラー: $e');
    }
  }
}
