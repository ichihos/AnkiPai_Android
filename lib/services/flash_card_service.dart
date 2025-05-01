import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get_it/get_it.dart';
import 'subscription_service.dart';
import 'dart:async';
import '../models/flash_card.dart';
import '../models/subscription_model.dart';
// 重複インポートを削除しました

class FlashCardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ストリームコントローラーのマップ（複数のリスナーをサポート）
  final Map<String, StreamController<List<FlashCard>>> _flashCardControllers =
      {};

  // サービスの初期化 - アプリ起動時やユーザーログイン時に呼び出す
  Future<void> initialize() async {
    final user = _auth.currentUser;
    if (user == null) {
      print('ユーザーがログインしていません。ログイン後に初期化を再試行します。');
      return;
    }

    try {
      // Firebase Authトークンを更新
      await user.getIdToken(true);

      // flashCardsコレクションの存在確認と初期化
      await ensureFlashCardCollectionExists();

      print('FlashCardService初期化完了: ユーザーID ${user.uid}');
    } catch (e) {
      print('FlashCardService初期化エラー: $e');
      throw Exception('フラッシュカードサービスの初期化に失敗しました: $e');
    }
  }

  // flashCardsコレクションの存在を確認し、必要に応じて作成
  Future<void> ensureFlashCardCollectionExists() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません。サービスを利用するには再度ログインしてください。');
    }

    try {
      // ユーザードキュメントを取得
      final userDocRef = _firestore.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();

      // ユーザードキュメントが存在しない場合は作成
      if (!userDoc.exists) {
        await userDocRef.set({
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });
        print('新規ユーザードキュメント作成: ${user.uid}');
      }

      // flashCardsコレクションが存在するか確認（最大1件を取得してみる）
      final flashCardsRef = userDocRef.collection('flashCards');
      final query = await flashCardsRef.limit(1).get();

      // コレクションにデータがなければ、初期データを追加
      if (query.docs.isEmpty) {
        print('flashCardsコレクションが空のため、初期化します');
        // 最初の空のフラッシュカードは追加しない - ユーザーが必要に応じて追加します
        // ただしコレクションが存在することを確認しました
      }
    } catch (e) {
      print('flashCardsコレクション初期化エラー: $e');
      throw Exception('フラッシュカードコレクションの初期化に失敗しました: $e');
    }
  }

  // ユーザーのFlashCardコレクションの参照を取得
  Future<CollectionReference<Map<String, dynamic>>>
      get _flashCardsCollection async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません。サービスを利用するには再度ログインしてください。');
    }

    // 毎回トークンを確認する
    try {
      // Firebase Authトークンを更新
      await user.getIdToken(true);
    } catch (e) {
      print('トークンのリフレッシュエラー: $e');
      throw Exception('認証トークンのリフレッシュに失敗しました。再度ログインしてください。');
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('flashCards');
  }

  // Firestoreのパスを取得（ストリームID生成用）
  Future<String> get _flashCardsPath async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません。');
    }
    return 'users/${user.uid}/flashCards';
  }

  // エラーメッセージをユーザーフレンドリーな形に変換
  String _getAuthErrorMessage(dynamic error) {
    if (error.toString().contains('permission-denied')) {
      return 'アクセス権限がありません。再度ログインして試してください。';
    }
    return error.toString();
  }

  // すべてのフラッシュカードを取得
  Future<List<FlashCard>> getFlashCards() async {
    try {
      // 先にコレクションの存在を確認
      await ensureFlashCardCollectionExists();

      // 認証確認とトークンの更新が行われる
      final flashCardsRef = await _flashCardsCollection;

      final querySnapshot =
          await flashCardsRef.orderBy('createdAt', descending: true).get();

      return querySnapshot.docs
          .map((doc) => FlashCard.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('フラッシュカードの取得エラー: ${_getAuthErrorMessage(e)}');
      throw 'フラッシュカードの読み込みに失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // 特定のフラッシュカードを取得
  Future<FlashCard?> getFlashCardById(String id) async {
    try {
      // 認証確認とトークンの更新が行われる
      final flashCardsRef = await _flashCardsCollection;

      final docSnapshot = await flashCardsRef.doc(id).get();
      if (docSnapshot.exists) {
        return FlashCard.fromMap(docSnapshot.data()!, docSnapshot.id);
      }
      return null;
    } catch (e) {
      print('フラッシュカードの取得エラー: ${_getAuthErrorMessage(e)}');
      throw 'フラッシュカードの読み込みに失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // 新しいフラッシュカードを追加
  Future<DocumentReference> addFlashCard(String frontText, String backText,
      {String? setId}) async {
    // サブスクリプションサービスからプランを取得
    final subscriptionService = GetIt.instance<SubscriptionService>();
    final subscription = await subscriptionService.getUserSubscription();

    // フリープランの場合、セット内のカード数を確認
    if (!subscription.isPremium && setId != null) {
      final cards = await getFlashCardsBySet(setId);
      if (cards.length >= SubscriptionModel.maxCardsPerSet) {
        throw Exception(
            'フリープランでは各カードセットに最大${SubscriptionModel.maxCardsPerSet}枚までのカードしか作成できません。プレミアムプランにアップグレードすると、無制限に作成できます。');
      }
    }
    try {
      // 先にコレクションの存在を確認
      await ensureFlashCardCollectionExists();

      // 認証確認とトークンの更新が行われる
      final flashCardsRef = await _flashCardsCollection;

      final newFlashCard = {
        'frontText': frontText,
        'backText': backText,
        'createdAt': FieldValue.serverTimestamp(),
        'lastStudiedAt': null,
        'masteryLevel': 0,
        'setId': setId,
      };

      final docRef = await flashCardsRef.add(newFlashCard);

      // カードセットのカード数を更新（セットIDが指定されている場合のみ）
      if (setId != null) {
        await _updateCardSetCount(setId, 1);
      }

      return docRef;
    } catch (e) {
      print('フラッシュカードの追加エラー: ${_getAuthErrorMessage(e)}');
      throw 'フラッシュカードの追加に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // フラッシュカードを更新
  Future<void> updateFlashCard(
      String id, String frontText, String backText) async {
    try {
      // 認証確認とトークンの更新が行われる
      final flashCardsRef = await _flashCardsCollection;

      await flashCardsRef.doc(id).update({
        'frontText': frontText,
        'backText': backText,
      });
    } catch (e) {
      print('フラッシュカードの更新エラー: ${_getAuthErrorMessage(e)}');
      throw 'フラッシュカードの更新に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // フラッシュカードを削除
  Future<void> deleteFlashCard(String id) async {
    try {
      final flashCardsRef = await _flashCardsCollection;

      // カードを取得して、セットIDを取得
      final cardDoc = await flashCardsRef.doc(id).get();
      final data = cardDoc.data();
      final String? setId = data != null ? data['setId'] as String? : null;

      // カードを削除
      await flashCardsRef.doc(id).delete();

      // セットIDが存在する場合、カードセットのカード数を更新
      if (setId != null) {
        await _updateCardSetCount(setId, -1);
      }
    } catch (e) {
      print('フラッシュカードの削除エラー: ${_getAuthErrorMessage(e)}');
      throw 'フラッシュカードの削除に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // フラッシュカードの学習状態を更新
  Future<void> updateFlashCardStudyStatus(String id, int masteryLevel) async {
    try {
      final flashCardsRef = await _flashCardsCollection;
      await flashCardsRef.doc(id).update({
        'lastStudiedAt': FieldValue.serverTimestamp(),
        'masteryLevel': masteryLevel,
      });
    } catch (e) {
      print('フラッシュカードの学習状態更新エラー: ${_getAuthErrorMessage(e)}');
      throw 'フラッシュカードの学習状態更新に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // バッチ処理で複数のフラッシュカードを一度に追加
  Future<void> addFlashCardsBatch(List<Map<String, String>> cards,
      {String? setId}) async {
    // サブスクリプションサービスからプランを取得
    final subscriptionService = GetIt.instance<SubscriptionService>();
    final subscription = await subscriptionService.getUserSubscription();

    // フリープランの場合、セット内のカード数を確認
    if (!subscription.isPremium && setId != null) {
      final existingCards = await getFlashCardsBySet(setId);
      final totalCardsAfterAdd = existingCards.length + cards.length;

      if (totalCardsAfterAdd > SubscriptionModel.maxCardsPerSet) {
        final remainingSlots =
            SubscriptionModel.maxCardsPerSet - existingCards.length;
        throw Exception(
            'フリープランでは各カードセットに最大${SubscriptionModel.maxCardsPerSet}枚までのカードしか作成できません。現在のカード数: ${existingCards.length}枚、追加可能なカード数: $remainingSlots枚、プレミアムプランにアップグレードすると無制限に作成できます。');
      }
    }
    if (cards.isEmpty) return;

    try {
      // 先にコレクションの存在を確認
      await ensureFlashCardCollectionExists();

      final flashCardsRef = await _flashCardsCollection;
      final WriteBatch batch = _firestore.batch();

      for (final card in cards) {
        final newDoc = flashCardsRef.doc();
        final newFlashCard = {
          'frontText': card['frontText'] ?? '',
          'backText': card['backText'] ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'lastStudiedAt': null,
          'masteryLevel': 0,
          'setId': setId,
        };

        batch.set(newDoc, newFlashCard);
      }

      await batch.commit();

      // カードセットのカード数を更新（セットIDが指定されている場合のみ）
      if (setId != null) {
        await _updateCardSetCount(setId, cards.length);
      }
    } catch (e) {
      print('複数フラッシュカードの追加エラー: ${_getAuthErrorMessage(e)}');
      throw '複数のフラッシュカードの追加に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // バッチ処理で複数のフラッシュカードを一度に更新
  Future<void> updateFlashCardsBatch(
      Map<String, Map<String, dynamic>> updates) async {
    if (updates.isEmpty) return;

    try {
      final flashCardsRef = await _flashCardsCollection;
      final WriteBatch batch = _firestore.batch();

      updates.forEach((id, data) {
        batch.update(flashCardsRef.doc(id), data);
      });

      await batch.commit();
    } catch (e) {
      print('複数フラッシュカードの更新エラー: ${_getAuthErrorMessage(e)}');
      throw '複数のフラッシュカードの更新に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // バッチ処理で複数のフラッシュカードを一度に削除
  Future<void> deleteFlashCardsBatch(List<String> ids) async {
    if (ids.isEmpty) return;

    try {
      final flashCardsRef = await _flashCardsCollection;

      // カードセットの更新のためにカードの情報を先に取得
      final Map<String, int> setCountUpdates = {};

      // カードを一括で取得
      final List<Future<DocumentSnapshot>> cardFutures =
          ids.map((id) => flashCardsRef.doc(id).get()).toList();

      final cardDocs = await Future.wait(cardFutures);

      // セットIDごとに削除するカードの数をカウント
      for (final doc in cardDocs) {
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          final String? setId = data != null ? data['setId'] as String? : null;
          if (setId != null) {
            setCountUpdates[setId] = (setCountUpdates[setId] ?? 0) + 1;
          }
        }
      }

      // カードを一括削除
      final WriteBatch batch = _firestore.batch();
      for (final id in ids) {
        batch.delete(flashCardsRef.doc(id));
      }
      await batch.commit();

      // カードセットのカード数を更新
      for (final entry in setCountUpdates.entries) {
        await _updateCardSetCount(entry.key, -entry.value);
      }
    } catch (e) {
      print('複数フラッシュカードの削除エラー: ${_getAuthErrorMessage(e)}');
      throw '複数のフラッシュカードの削除に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // 特定の条件に基づいてフラッシュカードをクエリ
  Future<List<FlashCard>> queryFlashCards({
    int? minMasteryLevel,
    int? maxMasteryLevel,
    DateTime? studiedBefore,
    DateTime? studiedAfter,
    int limit = 20,
  }) async {
    try {
      final flashCardsRef = await _flashCardsCollection;
      Query query = flashCardsRef;

      if (minMasteryLevel != null) {
        query = query.where('masteryLevel',
            isGreaterThanOrEqualTo: minMasteryLevel);
      }

      if (maxMasteryLevel != null) {
        query =
            query.where('masteryLevel', isLessThanOrEqualTo: maxMasteryLevel);
      }

      if (studiedBefore != null) {
        query =
            query.where('lastStudiedAt', isLessThanOrEqualTo: studiedBefore);
      }

      if (studiedAfter != null) {
        query =
            query.where('lastStudiedAt', isGreaterThanOrEqualTo: studiedAfter);
      }

      query = query.limit(limit);

      final querySnapshot = await query.get();

      return querySnapshot.docs
          .map((doc) =>
              FlashCard.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      print('フラッシュカードのクエリエラー: ${_getAuthErrorMessage(e)}');
      throw 'フラッシュカードのクエリに失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // ストリームIDの生成（リスナーの識別用）
  Future<String> _generateStreamId(String prefix) async {
    final path = await _flashCardsPath;
    return '$prefix-$path';
  }

  // カードセットのカード数を更新するヘルパーメソッド
  Future<void> _updateCardSetCount(String setId, int delta) async {
    try {
      // カードセットコレクションの参照を取得
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません。');
      }

      final cardSetRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cardSets')
          .doc(setId);

      // カードセットドキュメントを取得
      final cardSetDoc = await cardSetRef.get();
      if (!cardSetDoc.exists) {
        print('警告：カードセット $setId が見つかりません。カウントを更新できません。');
        return;
      }

      // 現在のカード数を取得し、更新
      final data = cardSetDoc.data();
      int currentCount = data != null ? (data['cardCount'] as int? ?? 0) : 0;
      int newCount = currentCount + delta;
      if (newCount < 0) newCount = 0; // 負の値にならないようにする

      await cardSetRef.update({'cardCount': newCount});
    } catch (e) {
      print('カードセットのカウント更新エラー： $e');
    }
  }

  // カードセットに基づいてフラッシュカードを取得
  Future<List<FlashCard>> getFlashCardsBySet(String setId) async {
    try {
      // 認証確認とトークンの更新が行われる
      final flashCardsRef = await _flashCardsCollection;

      final querySnapshot = await flashCardsRef
          .where('setId', isEqualTo: setId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => FlashCard.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('セットのフラッシュカード取得エラー: ${_getAuthErrorMessage(e)}');
      throw 'セットのフラッシュカード取得に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // カードセットのカード数を取得
  Future<int> getCardCountForSet(String cardSetId) async {
    try {
      // 認証確認とトークンの更新が行われる
      final flashCardsRef = await _flashCardsCollection;

      final querySnapshot =
          await flashCardsRef.where('setId', isEqualTo: cardSetId).get();

      return querySnapshot.docs.length;
    } catch (e) {
      print('カードセットのカード数取得エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードセットのカード数取得に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // カードセットに追加可能な残りのカード枚数をチェック
  Future<Map<String, dynamic>> checkAvailableCardSlots(String cardSetId) async {
    try {
      // サブスクリプションサービスからプランを取得
      final subscriptionService = GetIt.instance<SubscriptionService>();
      final subscription = await subscriptionService.getUserSubscription();

      // プレミアムプランの場合は無制限
      if (subscription.isPremium) {
        return {
          'hasLimit': false,
          'availableSlots': -1, // -1は無制限を示す
          'totalLimit': -1,
          'isPremium': true,
        };
      }

      // 現在のカード数を取得
      final currentCount = await getCardCountForSet(cardSetId);

      // フリープランの場合の制限を計算
      const int maxCards = SubscriptionModel.maxCardsPerSet;
      final int availableSlots = maxCards - currentCount;

      return {
        'hasLimit': true,
        'availableSlots': availableSlots > 0 ? availableSlots : 0,
        'totalLimit': maxCards,
        'currentCount': currentCount,
        'isPremium': false,
      };
    } catch (e) {
      print('利用可能スロットチェックエラー: ${_getAuthErrorMessage(e)}');
      throw '利用可能なカード数のチェックに失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // カードをあるセットから別のセットに移動
  Future<void> moveCardToSet(String cardId, String? newSetId) async {
    try {
      final flashCardsRef = await _flashCardsCollection;

      // カードを取得して、現在のセットIDを確認
      final cardDoc = await flashCardsRef.doc(cardId).get();
      final String? currentSetId = cardDoc.data()?['setId'];

      // 同じセットなら何もしない
      if (currentSetId == newSetId) return;

      // カードのセットIDを更新
      await flashCardsRef.doc(cardId).update({'setId': newSetId});

      // 元のセットのカード数を減らす
      if (currentSetId != null) {
        await _updateCardSetCount(currentSetId, -1);
      }

      // 新しいセットのカード数を増やす
      if (newSetId != null) {
        await _updateCardSetCount(newSetId, 1);
      }
    } catch (e) {
      print('カードのセット移動エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードのセット移動に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // リアルタイムでフラッシュカードを監視するStream
  Future<Stream<List<FlashCard>>> watchFlashCards(
      {String? tag, String? setId}) async {
    // 先にコレクションの存在を確認
    await ensureFlashCardCollectionExists();

    final streamId =
        await _generateStreamId(tag ?? (setId != null ? 'set-$setId' : 'all'));

    // 型安全性のため、適切なStreamControllerの取得
    if (_flashCardControllers.containsKey(streamId)) {
      final controller = _flashCardControllers[streamId];
      if (controller is StreamController<List<FlashCard>>) {
        return controller.stream;
      }
    }

    // 新しいコントローラーの作成
    final controller = StreamController<List<FlashCard>>.broadcast();

    // エラーを安全に追加するためのヘルパー関数
    void safeAddError(StreamController controller, String errorMessage) {
      // コントローラーが閉じられていない場合のみエラーを追加
      if (!controller.isClosed) {
        controller.addError(errorMessage);
      } else {
        print('Warning: エラーの追加がスキップされました (コントローラーは既に閉じられています): $errorMessage');
      }
    }

    // クリーンアップ用のコールバックを設定
    controller.onCancel = () {
      _flashCardControllers.remove(streamId);
      // 既に閉じられていない場合のみ閉じる
      if (!controller.isClosed) {
        controller.close();
      }
    };

    _flashCardControllers[streamId] = controller;

    try {
      final flashCardsRef = await _flashCardsCollection;
      Query query = flashCardsRef.orderBy('createdAt', descending: true);

      // セットIDが指定されている場合はクエリに条件を追加
      if (setId != null) {
        query = query.where('setId', isEqualTo: setId);
      }

      query.snapshots().listen(
        (snapshot) {
          // isClosed チェックを追加
          if (!controller.isClosed) {
            final cards = snapshot.docs
                .map((doc) => FlashCard.fromMap(
                    doc.data() as Map<String, dynamic>, doc.id))
                .toList();
            controller.add(cards);
          }
        },
        onError: (error) {
          print('フラッシュカードのリスニングエラー: $error');
          safeAddError(controller, 'フラッシュカードのリスニングに失敗しました: $error');
        },
        // キャンセル時の処理を追加
        onDone: () {
          if (!controller.isClosed) {
            _flashCardControllers.remove(streamId);
            controller.close();
          }
        },
      );
    } catch (e) {
      String errorMessage = _getAuthErrorMessage(e);
      print('フラッシュカードの監視エラー: $errorMessage');
      safeAddError(controller, 'フラッシュカードのリスニングに失敗しました: $errorMessage');

      // エラーが発生した場合はマップから削除
      _flashCardControllers.remove(streamId);

      // 既に閉じられていない場合のみ閉じる
      if (!controller.isClosed) {
        controller.close();
      }
    }

    return controller.stream;
  }

  // 特定のフラッシュカードの変更を監視
  Future<Stream<FlashCard?>> watchFlashCardById(String id) async {
    // 新しいストリームコントローラーを作成
    // 最初に定義しておくことで、onCancelやこの後の参照で問題が発生しないようにする
    final StreamController<FlashCard?> cardController =
        StreamController<FlashCard?>.broadcast();

    // エラーを安全に追加するためのヘルパー関数
    void safeAddError(StreamController controller, String errorMessage) {
      // コントローラーが閉じられていない場合のみエラーを追加
      if (!controller.isClosed) {
        controller.addError(errorMessage);
      } else {
        print('Warning: エラーの追加がスキップされました (コントローラーは既に閉じられています): $errorMessage');
      }
    }

    // onCancelのコールバック設定
    cardController.onCancel = () {
      // 既に閉じられていない場合のみ閉じる
      if (!cardController.isClosed) {
        cardController.close();
      }
    };

    try {
      final flashCardsRef = await _flashCardsCollection;
      flashCardsRef.doc(id).snapshots().listen(
        (snapshot) {
          // isClosed チェックを追加
          if (!cardController.isClosed) {
            if (snapshot.exists && snapshot.data() != null) {
              final Map<String, dynamic> data = snapshot.data()!;
              cardController.add(FlashCard.fromMap(data, snapshot.id));
            } else {
              cardController.add(null);
            }
          }
        },
        onError: (error) {
          print('フラッシュカードのリスニングエラー: $error');
          safeAddError(cardController, 'フラッシュカードのリスニングに失敗しました: $error');
        },
        // キャンセル時の処理を追加
        onDone: () {
          if (!cardController.isClosed) {
            cardController.close();
          }
        },
      );
    } catch (e) {
      String errorMessage = _getAuthErrorMessage(e);
      print('フラッシュカードの監視エラー: $errorMessage');
      safeAddError(cardController, 'フラッシュカードのリスニングに失敗しました: $errorMessage');

      // エラーが発生した場合は、将来のリスナー追加のためにストリームを閉じる前に適切なエラーを返す
      if (!cardController.isClosed) {
        cardController.close();
      }
    }

    return cardController.stream;
  }
}
