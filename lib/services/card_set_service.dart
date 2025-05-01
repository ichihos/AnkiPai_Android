import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../models/card_set.dart';
import '../models/flash_card.dart';
import '../models/subscription_model.dart';
import 'subscription_service.dart';
import 'package:get_it/get_it.dart';

class CardSetService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ストリームコントローラーのマップ（複数のリスナーをサポート）
  final Map<String, StreamController<List<CardSet>>> _cardSetControllers = {};

  // 認証状態変更時などにすべてのリスナーをクリーンアップ
  void cleanupAllListeners() {
    print('すべてのCardSetServiceリスナーをクリーンアップしています...');
    // すべてのストリームコントローラーを閉じて削除
    _cardSetControllers.forEach((key, controller) {
      if (!controller.isClosed) {
        controller.close();
      }
    });
    _cardSetControllers.clear();
    print('CardSetServiceリスナーのクリーンアップが完了しました');
  }

  // サービスの初期化 - アプリ起動時やユーザーログイン時に呼び出す
  Future<void> initialize() async {
    final user = _auth.currentUser;
    if (user == null) {
      print('ユーザーがログインしていません。ログイン後に初期化を再試行します。');
      return;
    }

    try {
      // まず既存のリスナーをクリーンアップ（認証状態が変わった可能性があるため）
      cleanupAllListeners();

      // Firebase Authトークンを更新
      await user.getIdToken(true);

      // cardSetsコレクションの存在確認と初期化
      await ensureCardSetCollectionExists();

      print('CardSetService初期化完了: ユーザーID ${user.uid}');
    } catch (e) {
      print('CardSetService初期化エラー: $e');
      throw Exception('カードセットサービスの初期化に失敗しました: $e');
    }
  }

  // cardSetsコレクションの存在を確認し、必要に応じて作成
  Future<void> ensureCardSetCollectionExists() async {
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

      // cardSetsコレクションが存在するか確認（最大1件を取得してみる）
      final cardSetsRef = userDocRef.collection('cardSets');
      final query = await cardSetsRef.limit(1).get();

      // コレクションにデータがなければ、初期データを追加
      if (query.docs.isEmpty) {
        print('cardSetsコレクションが空のため、初期化します');
        // 最初のカードセットは追加しない - ユーザーが必要に応じて追加します
      }
    } catch (e) {
      print('cardSetsコレクション初期化エラー: $e');
      throw Exception('カードセットコレクションの初期化に失敗しました: $e');
    }
  }

  // ユーザーのCardSetコレクションの参照を取得
  Future<CollectionReference<Map<String, dynamic>>>
      get _cardSetsCollection async {
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

    return _firestore.collection('users').doc(user.uid).collection('cardSets');
  }

  // ユーザーのFlashCardコレクションの参照を取得（特定のカードセット内のカード）
  Future<CollectionReference<Map<String, dynamic>>> _flashCardsCollection(
      String cardSetId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません。サービスを利用するには再度ログインしてください。');
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('flashCards');
  }

  // Firestoreのパスを取得（ストリームID生成用）
  Future<String> get _cardSetsPath async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません。');
    }
    return 'users/${user.uid}/cardSets';
  }

  // エラーメッセージをユーザーフレンドリーな形に変換
  String _getAuthErrorMessage(dynamic error) {
    if (error.toString().contains('permission-denied')) {
      return 'アクセス権限がありません。再度ログインして試してください。';
    }
    return error.toString();
  }

  // すべてのカードセットを取得
  Future<List<CardSet>> getCardSets() async {
    try {
      // 先にコレクションの存在を確認
      await ensureCardSetCollectionExists();

      // 認証確認とトークンの更新が行われる
      final cardSetsRef = await _cardSetsCollection;

      final querySnapshot =
          await cardSetsRef.orderBy('createdAt', descending: true).get();

      return querySnapshot.docs
          .map((doc) => CardSet.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('カードセットの取得エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードセットの読み込みに失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // ユーザーのカードセットを取得する (サブスクリプション確認用)
  Future<List<CardSet>> getUserCardSets() async {
    return await getCardSets();
  }

  // 特定のカードセットを取得
  Future<CardSet?> getCardSetById(String id) async {
    try {
      // 認証確認とトークンの更新が行われる
      final cardSetsRef = await _cardSetsCollection;

      final docSnapshot = await cardSetsRef.doc(id).get();
      if (docSnapshot.exists) {
        return CardSet.fromMap(docSnapshot.data()!, docSnapshot.id);
      }
      return null;
    } catch (e) {
      print('カードセットの取得エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードセットの読み込みに失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // 新しいカードセットを追加
  Future<DocumentReference> addCardSet(String title,
      {String? description}) async {
    // サブスクリプションサービスからプランを取得
    final subscriptionService = GetIt.instance<SubscriptionService>();
    final subscription = await subscriptionService.getUserSubscription();

    // フリープランの場合、カードセット数を確認
    if (!subscription.isPremium) {
      final cardSets = await getCardSets();
      if (cardSets.length >= SubscriptionModel.maxCardSets) {
        throw Exception(
            'フリープランでは最大${SubscriptionModel.maxCardSets}つまでのカードセットしか作成できません。プレミアムプランにアップグレードすると、無制限に作成できます。');
      }
    }
    try {
      // 先にコレクションの存在を確認
      await ensureCardSetCollectionExists();

      // 認証確認とトークンの更新が行われる
      final cardSetsRef = await _cardSetsCollection;

      final newCardSet = {
        'title': title,
        'description': description,
        'createdAt': FieldValue.serverTimestamp(),
        'lastStudiedAt': null,
        'cardCount': 0,
      };

      return await cardSetsRef.add(newCardSet);
    } catch (e) {
      print('カードセットの追加エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードセットの追加に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // カードセットを更新
  Future<void> updateCardSet(String id,
      {String? title, String? description}) async {
    try {
      // 認証確認とトークンの更新が行われる
      final cardSetsRef = await _cardSetsCollection;

      Map<String, dynamic> updateData = {};
      if (title != null) updateData['title'] = title;
      if (description != null) updateData['description'] = description;

      await cardSetsRef.doc(id).update(updateData);
    } catch (e) {
      print('カードセットの更新エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードセットの更新に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // カードセットを削除（関連するカードも削除）
  Future<void> deleteCardSet(String setId) async {
    try {
      final cardSetsRef = await _cardSetsCollection;
      final flashCardsRef = await _flashCardsCollection(setId);

      // バッチ処理の作成（トランザクションより効率的）
      final batch = _firestore.batch();

      // 特定のセットに属するカードを取得
      final querySnapshot =
          await flashCardsRef.where('setId', isEqualTo: setId).get();

      // カード数が多い場合はログに記録
      if (querySnapshot.docs.length > 50) {
        print('多数のカード(${querySnapshot.docs.length}枚)を削除します - カードセットID: $setId');
      }

      // バッチにカード削除操作を追加
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      // カードセット自体を削除
      batch.delete(cardSetsRef.doc(setId));

      // バッチ処理を実行
      await batch.commit();

      print(
          'カードセットの削除が完了しました - ID: $setId, 削除されたカード: ${querySnapshot.docs.length}枚');
    } catch (e) {
      print('カードセットの削除エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードセットの削除に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // カードセット内のカードを取得
  Future<List<FlashCard>> getCardsInSet(String setId) async {
    try {
      final flashCardsRef = await _flashCardsCollection(setId);

      final querySnapshot = await flashCardsRef
          .where('setId', isEqualTo: setId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => FlashCard.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('セット内のカード取得エラー: ${_getAuthErrorMessage(e)}');
      throw 'セット内のカードの読み込みに失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // カードセットにカードを追加
  Future<DocumentReference> addCardToSet(
      String setId, String frontText, String backText) async {
    try {
      final cardSetsRef = await _cardSetsCollection;
      final flashCardsRef = await _flashCardsCollection(setId);

      // トランザクションを使用してカードを追加し、カードセットのカウントを更新
      return await _firestore
          .runTransaction<DocumentReference>((transaction) async {
        // カードセット情報を取得
        final setDoc = await transaction.get(cardSetsRef.doc(setId));
        if (!setDoc.exists) {
          throw 'カードセットが見つかりません';
        }

        // 新しいカードのリファレンスを作成
        final newCardRef = flashCardsRef.doc();

        // カードを作成
        transaction.set(newCardRef, {
          'frontText': frontText,
          'backText': backText,
          'createdAt': FieldValue.serverTimestamp(),
          'lastStudiedAt': null,
          'masteryLevel': 0,
          'setId': setId,
        });

        // カードセットのカード数を更新
        int currentCount = (setDoc.data()?['cardCount'] ?? 0) as int;
        transaction
            .update(cardSetsRef.doc(setId), {'cardCount': currentCount + 1});

        return newCardRef;
      });
    } catch (e) {
      print('カードの追加エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードの追加に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // セットからカードを削除
  Future<void> removeCardFromSet(String setId, String cardId) async {
    try {
      final cardSetsRef = await _cardSetsCollection;
      final flashCardsRef = await _flashCardsCollection(setId);

      // トランザクションを使用してカードを削除し、カードセットのカウントを更新
      await _firestore.runTransaction((transaction) async {
        // カードセット情報を取得
        final setDoc = await transaction.get(cardSetsRef.doc(setId));
        if (!setDoc.exists) {
          throw 'カードセットが見つかりません';
        }

        // カードの存在を確認
        final cardDoc = await transaction.get(flashCardsRef.doc(cardId));
        if (!cardDoc.exists) {
          throw 'カードが見つかりません';
        }

        // カードを削除
        transaction.delete(flashCardsRef.doc(cardId));

        // カードセットのカード数を更新
        int currentCount = (setDoc.data()?['cardCount'] ?? 0) as int;
        transaction.update(cardSetsRef.doc(setId),
            {'cardCount': currentCount > 0 ? currentCount - 1 : 0});
      });
    } catch (e) {
      print('カードの削除エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードの削除に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // カードセットの最終学習日を更新
  Future<void> updateCardSetLastStudied(String setId) async {
    try {
      final cardSetsRef = await _cardSetsCollection;
      await cardSetsRef.doc(setId).update({
        'lastStudiedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('カードセットの学習日更新エラー: ${_getAuthErrorMessage(e)}');
      throw 'カードセットの学習日更新に失敗しました: ${_getAuthErrorMessage(e)}';
    }
  }

  // ストリームIDの生成（リスナーの識別用）
  Future<String> _generateStreamId(String prefix) async {
    final path = await _cardSetsPath;
    return '$prefix-$path';
  }

  // リアルタイムでカードセットを監視するStream
  Future<Stream<List<CardSet>>> watchCardSets() async {
    // 先にコレクションの存在を確認
    await ensureCardSetCollectionExists();

    final streamId = await _generateStreamId('all-sets');

    // 型安全性のため、適切なStreamControllerの取得
    if (_cardSetControllers.containsKey(streamId)) {
      final controller = _cardSetControllers[streamId];
      if (controller is StreamController<List<CardSet>>) {
        return controller.stream;
      }
    }

    // 新しいコントローラーの作成
    final controller = StreamController<List<CardSet>>.broadcast();

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
      _cardSetControllers.remove(streamId);
      // 既に閉じられていない場合のみ閉じる
      if (!controller.isClosed) {
        controller.close();
      }
    };

    _cardSetControllers[streamId] = controller;

    try {
      final cardSetsRef = await _cardSetsCollection;
      cardSetsRef.orderBy('createdAt', descending: true).snapshots().listen(
        (snapshot) {
          // isClosed チェックを追加
          if (!controller.isClosed) {
            final sets = snapshot.docs
                .map((doc) => CardSet.fromMap(doc.data(), doc.id))
                .toList();
            controller.add(sets);
          }
        },
        onError: (error) {
          // 指定のエラーはサイレントにして表示しない
          if (error.toString().contains('permission-denied')) {
            // ログアウト時の権限エラーは非表示
            print('カードセットの権限エラーを無視しました');
          } else {
            print('カードセットのリスニングエラー: $error');
            safeAddError(controller, 'カードセットのリスニングに失敗しました: $error');
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            _cardSetControllers.remove(streamId);
            controller.close();
          }
        },
      );
    } catch (e) {
      String errorMessage = _getAuthErrorMessage(e);
      print('カードセットの監視エラー: $errorMessage');
      safeAddError(controller, 'カードセットのリスニングに失敗しました: $errorMessage');

      // エラーが発生した場合はマップから削除
      _cardSetControllers.remove(streamId);

      // 既に閉じられていない場合のみ閉じる
      if (!controller.isClosed) {
        controller.close();
      }
    }

    return controller.stream;
  }

  // リアルタイムで特定のカードセットを監視するStream
  Future<Stream<CardSet?>> watchCardSet(String id) async {
    try {
      // 新しいコントローラーの作成
      final controller = StreamController<CardSet?>.broadcast();

      // クリーンアップ用のコールバックを設定
      controller.onCancel = () {
        if (!controller.isClosed) {
          controller.close();
        }
      };

      final cardSetsRef = await _cardSetsCollection;
      cardSetsRef.doc(id).snapshots().listen(
        (snapshot) {
          if (!controller.isClosed) {
            if (snapshot.exists && snapshot.data() != null) {
              controller.add(CardSet.fromMap(snapshot.data()!, snapshot.id));
            } else {
              controller.add(null); // ドキュメントが存在しない場合はnullを発行
            }
          }
        },
        onError: (error) {
          print('カードセットのリスニングエラー: $error');
          if (!controller.isClosed) {
            controller.addError('カードセットのリスニングに失敗しました: $error');
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );

      return controller.stream;
    } catch (e) {
      String errorMessage = _getAuthErrorMessage(e);
      print('カードセットの監視エラー: $errorMessage');
      throw 'カードセットの監視に失敗しました: $errorMessage';
    }
  }

  // リアルタイムでカードセット内のカードを監視するStream
  Future<Stream<List<FlashCard>>> watchCardsInSet(String setId) async {
    // 新しいコントローラーの作成
    final controller = StreamController<List<FlashCard>>.broadcast();

    // エラーを安全に追加するためのヘルパー関数
    void safeAddError(StreamController controller, String errorMessage) {
      if (!controller.isClosed) {
        controller.addError(errorMessage);
      } else {
        print('Warning: エラーの追加がスキップされました (コントローラーは既に閉じられています): $errorMessage');
      }
    }

    // クリーンアップ用のコールバックを設定
    controller.onCancel = () {
      if (!controller.isClosed) {
        controller.close();
      }
    };

    try {
      final flashCardsRef = await _flashCardsCollection(setId);
      flashCardsRef
          .where('setId', isEqualTo: setId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen(
        (snapshot) {
          if (!controller.isClosed) {
            final cards = snapshot.docs
                .map((doc) => FlashCard.fromMap(doc.data(), doc.id))
                .toList();
            controller.add(cards);
          }
        },
        onError: (error) {
          print('カードのリスニングエラー: $error');
          safeAddError(controller, 'カードのリスニングに失敗しました: $error');
        },
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );
    } catch (e) {
      String errorMessage = _getAuthErrorMessage(e);
      print('カードの監視エラー: $errorMessage');
      safeAddError(controller, 'カードのリスニングに失敗しました: $errorMessage');

      if (!controller.isClosed) {
        controller.close();
      }
    }

    return controller.stream;
  }
}
