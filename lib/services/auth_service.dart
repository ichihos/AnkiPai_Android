import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'subscription_service.dart';
import 'connectivity_service.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // Webプラットフォームでは固定のクライアントIDを使用
    clientId: kIsWeb ? '1019104165530-2d7q6sfj83873t4ngbu2ut8hd7me9oqt.apps.googleusercontent.com' : null,
    scopes: ['email', 'profile'],
  );

  User? get currentUser => _auth.currentUser;
  Stream<User?> get userStream => _auth.authStateChanges();

  // ユーザーが認証されているかチェック
  bool isAuthenticated() {
    // オフラインモードの場合は別の方法で確認
    try {
      final connectivityService = GetIt.instance<ConnectivityService>();
      if (connectivityService.isOffline) {
        // オフラインモードでは常に認証済みとみなす
        return true;
      }
    } catch (e) {
      print('接続状態の確認中にエラーが発生: $e');
    }
    
    return _auth.currentUser != null;
  }
  
  // ローカルストレージからユーザー情報を取得
  Future<Map<String, dynamic>?> getOfflineUserInfo() async {
    try {
      print('💾 ローカルストレージからユーザー情報を取得します');
      final prefs = await SharedPreferences.getInstance();
      
      // ユーザーIDを先に確認
      final userId = prefs.getString('offline_user_id');
      if (userId == null || userId.isEmpty) {
        print('⚠️ ローカルストレージにユーザーIDがありません');
      } else {
        print('🔑 ローカルストレージからユーザーIDを取得: $userId');
      }
      
      // ユーザー情報を取得
      final userInfoJson = prefs.getString('offline_user_info');
      
      if (userInfoJson == null || userInfoJson.isEmpty) {
        print('⚠️ ローカルストレージにユーザー情報がありません');
        return null;
      }
      
      // JSONをデコード
      try {
        final userInfo = jsonDecode(userInfoJson) as Map<String, dynamic>;
        
        // データの検証
        if (!userInfo.containsKey('uid') || userInfo['uid'] == null) {
          print('⚠️ ユーザー情報にユーザーIDがありません');
          return null;
        }
        
        // ユーザー情報の最終更新日時を確認
        if (userInfo.containsKey('lastUpdated')) {
          try {
            final lastUpdated = DateTime.parse(userInfo['lastUpdated'] as String);
            final now = DateTime.now();
            final difference = now.difference(lastUpdated);
            
            // 最終更新からの経過時間を表示
            print('💾 ユーザー情報の最終更新: ${difference.inDays}日前');
          } catch (dateError) {
            print('⚠️ 最終更新日時の解析エラー: $dateError');
          }
        }
        
        print('✅ ローカルストレージからユーザー情報を取得しました: ${userInfo['displayName'] ?? userInfo['email'] ?? userInfo['uid']}');
        return userInfo;
      } catch (jsonError) {
        print('❌ JSONデコードエラー: $jsonError');
        return null;
      }
    } catch (e) {
      print('❌ オフラインユーザー情報の取得エラー: $e');
      return null;
    }
  }
  
  // ユーザー情報をローカルストレージに保存
  Future<void> saveUserInfoToLocalStorage() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('⚠️ ユーザーがログインしていないため、ユーザー情報の保存をスキップします');
        return;
      }
      
      print('💾 ユーザー情報の保存を開始: ${user.uid}');
      
      // プロフィール画像のURLがあれば取得する
      String? profileImageData;
      if (user.photoURL != null && user.photoURL!.isNotEmpty) {
        try {
          // プロフィール画像のURLを保存
          profileImageData = user.photoURL;
          print('✅ プロフィール画像のURLを保存しました');
        } catch (imageError) {
          print('⚠️ プロフィール画像の取得エラー: $imageError');
          // エラーが発生しても処理を続行
        }
      }
      
      // ユーザーの詳細情報を取得
      Map<String, dynamic> additionalUserInfo = {};
      try {
        // 詳細情報を取得する処理を追加することも可能
        // 例: Firestoreからユーザーの詳細情報を取得するなど
      } catch (userInfoError) {
        print('⚠️ 追加ユーザー情報の取得エラー: $userInfoError');
      }
      
      // ユーザー情報をマップにまとめる
      final userInfo = {
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': profileImageData,
        'emailVerified': user.emailVerified,
        'isAnonymous': user.isAnonymous,
        'creationTime': user.metadata.creationTime?.toIso8601String(),
        'lastSignInTime': user.metadata.lastSignInTime?.toIso8601String(),
        'lastUpdated': DateTime.now().toIso8601String(),
        'additionalInfo': additionalUserInfo,
      };
      
      // ローカルストレージに保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_user_info', jsonEncode(userInfo));
      
      // ユーザーIDを別に保存（クイックアクセス用）
      await prefs.setString('offline_user_id', user.uid);
      
      print('✅ ユーザー情報をローカルストレージに保存しました: ${user.displayName ?? user.email}');
    } catch (e) {
      print('❌ ユーザー情報のローカル保存エラー: $e');
    }
  }
  
  // オフラインモードでもユーザー情報を取得できるようにする
  Future<Map<String, dynamic>?> getUserInfo() async {
    try {
      // オフライン状態を確認
      final connectivityService = GetIt.instance<ConnectivityService>();
      final isOffline = connectivityService.isOffline;
      
      if (isOffline) {
        // オフラインモードではローカルストレージから取得
        print('📱 オフラインモード: ローカルストレージからユーザー情報を取得します');
        return await getOfflineUserInfo();
      }
      
      // オンラインモードの場合は通常の処理
      final user = _auth.currentUser;
      if (user == null) {
        print('⚠️ ユーザーがログインしていません');
        return null;
      }
      
      // ユーザー情報をローカルストレージに保存（オフラインモード用）
      saveUserInfoToLocalStorage();
      
      return {
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'emailVerified': user.emailVerified,
        'isAnonymous': user.isAnonymous,
        'creationTime': user.metadata.creationTime?.toIso8601String(),
        'lastSignInTime': user.metadata.lastSignInTime?.toIso8601String(),
      };
    } catch (e) {
      print('❌ ユーザー情報取得エラー: $e');
      return null;
    }
  }

  // ユーザーの認証状態を再検証
  Future<bool> validateAuthentication() async {
    try {
      // オフライン状態を確認
      try {
        final connectivityService = GetIt.instance<ConnectivityService>();
        if (connectivityService.isOffline) {
          print('📱 オフラインモード: 認証チェックをスキップします');
          // オフラインモードでは常にtrueを返す
          return true;
        }
      } catch (connectivityError) {
        print('接続状態の確認中にエラーが発生: $connectivityError');
        // 接続状態の確認に失敗した場合は、オフラインとみなしてtrueを返す
        return true;
      }
      
      // オンラインモードの場合は通常の認証チェックを行う
      final user = _auth.currentUser;
      if (user == null) {
        print('認証: ユーザーが見つかりません、即座に匿名ログインを試みます');
        try {
          // ユーザーがいない場合は自動的に匿名ログインを試みる
          await _auth.signInAnonymously();
          print('認証: 匿名ログインに成功しました');
          return true;
        } catch (anonError) {
          print('認証: 匿名ログインに失敗しました: $anonError');
          // 失敗してもアプリは使用可能としてtrueを返す
          return true;
        }
      }

      // トークンの再取得を試みる（期限切れの場合に更新される）
      try {
        await user.getIdToken(true);
        print('認証: トークン再取得成功');
        return true;
      } catch (tokenError) {
        print('認証: トークンの再取得に失敗しましたが、アプリは継続します: $tokenError');
        return true; // トークンの再取得に失敗しても、アプリは使用可能とみなす
      }
    } catch (e) {
      print('認証状態の検証中に予期しないエラーが発生しました: $e');
      // 予期しないエラーの場合も、アプリは使用可能とみなす
      return true;
    }
  }

  // 匿名アカウントを正規アカウントにアップグレード
  Future<UserCredential> upgradeAnonymousAccount(String email, String password) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null || !currentUser.isAnonymous) {
        throw '匿名アカウントがありません';
      }
      
      print('匿名アカウントを正規アカウントにアップグレードします');
      
      // 認証情報を作成
      AuthCredential credential = EmailAuthProvider.credential(
        email: email,
        password: password
      );
        
      // 匿名アカウントを正規アカウントにリンク
      final result = await currentUser.linkWithCredential(credential);
      
      // Firestoreのユーザー情報を更新
      await _firestore.collection('users').doc(result.user!.uid).update({
        'email': email,
        'isAnonymous': false,
        'lastLogin': FieldValue.serverTimestamp(),
      });
      
      notifyListeners();
      return result;
    } catch (e) {
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'email-already-in-use':
            throw 'このメールアドレスは既に使用されています';
          case 'invalid-email':
            throw 'メールアドレスの形式が正しくありません';
          case 'weak-password':
            throw 'パスワードが弱すぎます。より強力なパスワードを設定してください';
          case 'requires-recent-login':
            throw '再度ログインし直してから操作してください';
          default:
            throw 'アカウントのアップグレードに失敗しました: ${e.message}';
        }
      }
      throw 'アカウントのアップグレードに失敗しました: $e';
    }
  }
  
  // メール・パスワードでサインイン
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      // 現在匿名ユーザーならアップグレードを試みる
      if (_auth.currentUser != null && _auth.currentUser!.isAnonymous) {
        try {
          return await upgradeAnonymousAccount(email, password);
        } catch (upgradeError) {
          print('アップグレードできませんでした: $upgradeError - 通常ログインを試みます');
          // アップグレードに失敗した場合はログアウトしてから通常ログイン
          await signOut();
        }
      }
      
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // ユーザーの最終ログイン日時を更新
      await _createUserInFirestoreIfNeeded(result.user!);
      
      // ローカルストレージにユーザー情報を保存
      await saveUserInfoToLocalStorage();

      notifyListeners();
      return result;
    } catch (e) {
      // エラーメッセージを日本語化
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            throw 'メールアドレスが登録されていません';
          case 'wrong-password':
            throw 'パスワードが間違っています';
          case 'invalid-email':
            throw 'メールアドレスの形式が正しくありません';
          case 'user-disabled':
            throw 'このアカウントは無効化されています';
          default:
            throw 'ログインに失敗しました: ${e.message}';
        }
      }
      throw 'ログインに失敗しました: $e';
    }
  }

  // メール・パスワードで登録
  Future<UserCredential> registerWithEmailAndPassword(
      String email, String password) async {
    try {
      // 現在匿名ユーザーならアップグレードを試みる
      if (_auth.currentUser != null && _auth.currentUser!.isAnonymous) {
        try {
          return await upgradeAnonymousAccount(email, password);
        } catch (upgradeError) {
          print('アップグレードできませんでした: $upgradeError - 新規登録を試みます');
          // アップグレードに失敗した場合はログアウトしてから新規登録
          await signOut();
        }
      }
      
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Firestore にユーザー情報を登録
      await _createUserInFirestoreIfNeeded(result.user!);

      notifyListeners();
      return result;
    } catch (e) {
      // エラーメッセセージを日本語化
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'email-already-in-use':
            throw 'このメールアドレスは既に使用されています';
          case 'invalid-email':
            throw 'メールアドレスの形式が正しくありません';
          case 'weak-password':
            throw 'パスワードが弱すぎます。より強力なパスワードを設定してください';
          case 'operation-not-allowed':
            throw 'この操作は許可されていません';
          default:
            throw '登録に失敗しました: ${e.message}';
        }
      }
      throw '登録に失敗しました: $e';
    }
  }

  // Googleでサインイン
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Web環境の場合は別の方法でサインイン
      if (kIsWeb) {
        return await _signInWithGoogleWeb();
      }

      // モバイル環境の場合
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        throw 'Googleサインインがキャンセルされました';
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final result = await _auth.signInWithCredential(credential);

      // Firestoreにユーザー情報を保存
      await _createUserInFirestoreIfNeeded(result.user!);

      notifyListeners();
      return result;
    } catch (e) {
      print('Googleサインインエラー: $e');
      throw 'Googleサインインに失敗しました: $e';
    }
  }

  // Web環境専用のGoogleサインイン
  Future<UserCredential> _signInWithGoogleWeb() async {
    try {
      // GoogleAuthProviderを使用してFirebaseAuthから直接サインイン
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.addScope('profile');

      // Firebase Hostingのドメインを適切に設定
      googleProvider.setCustomParameters(
          {'login_hint': 'user@example.com', 'prompt': 'select_account'});

      // Firebase Auth直接のリダイレクトサインインを使用
      final result = await _auth.signInWithPopup(googleProvider);

      // Firestoreにユーザー情報を保存
      await _createUserInFirestoreIfNeeded(result.user!);

      notifyListeners();
      return result;
    } catch (e) {
      print('Webサインインエラー: $e');
      throw 'Webサインインに失敗しました: $e';
    }
  }

  // 匿名サインイン
  Future<UserCredential> signInAnonymously() async {
    try {
      // オフラインかどうか確認
      final connectivityService = GetIt.instance<ConnectivityService>();
      final isOffline = connectivityService.isOffline;
      
      if (isOffline) {
        print('📱 オフラインモード: 匿名サインインをスキップします');
        // オフラインモードでは疑似的なUserCredentialを返す
        final prefs = await SharedPreferences.getInstance();
        final offlineUserId = prefs.getString('offline_user_id');
        
        if (offlineUserId != null) {
          print('📱 オフラインモード: 以前のユーザーIDを使用します: $offlineUserId');
          // 疑似的なUserCredentialを作成して返す（実際には使用されない）
          throw '📱 オフラインモードではサインインをスキップします';
        } else {
          print('⚠️ オフラインモード: 以前のユーザーIDが見つかりません');
          throw 'オフラインモードで初めて起動しました。一度オンラインに接続してください';
        }
      }
      
      final result = await _auth.signInAnonymously();

      // Firestore にユーザー情報を登録
      await _createUserInFirestoreIfNeeded(result.user!);
      
      // オフライン用にユーザーIDを保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_user_id', result.user!.uid);

      notifyListeners();
      return result;
    } catch (e) {
      print('匿名サインインエラー: $e');
      // オフラインモードのエラーは特別に処理
      if (e.toString().contains('オフラインモード')) {
        rethrow; // そのまま再スロー
      }
      throw '匿名サインインに失敗しました: $e';
    }
  }

  // サインアウト
  Future<void> signOut() async {
    try {
      // サブスクリプションサービスのキャッシュをクリア
      try {
        final subscriptionService = GetIt.instance<SubscriptionService>();
        subscriptionService.clearCache();
      } catch (cacheError) {
        print('サブスクリプションキャッシュのクリアに失敗しました: $cacheError');
      }

      // 各種サインアウト処理
      await _googleSignIn.signOut();
      await _auth.signOut();
      notifyListeners();
    } catch (e) {
      throw 'サインアウトに失敗しました: $e';
    }
  }
  
  /// アカウントの完全削除
  /// 
  /// ユーザーアカウントと関連するデータを完全に削除します。
  /// この操作は取り消すことができません。
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ログインしていません');
      }
      
      // 1. ユーザーのプロフィール画像をStorageから削除
      try {
        final profileImagesRef = _storage.ref().child('profile_images').child('${user.uid}.jpg');
        await profileImagesRef.delete();
        print('✅ プロフィール画像を削除しました');
      } catch (e) {
        // 画像が存在しない場合は無視する
        print('画像削除のスキップまたはエラー: $e');
      }

      // 2. Firestoreからユーザーのデータを削除
      try {
        // ユーザーの書き込みを削除
        await _firestore.collection('users').doc(user.uid).delete();
        print('✅ Firestoreからユーザーデータを削除しました');
        
        // 公開した暦記法やカードセットなども削除する
        final batch = _firestore.batch();
        
        // メモリーテクニックの削除
        final memoryTechniques = await _firestore
            .collection('memoryTechniques')
            .where('userId', isEqualTo: user.uid)
            .get();
            
        for (var doc in memoryTechniques.docs) {
          batch.delete(doc.reference);
        }
        
        // カードセットの削除
        final cardSets = await _firestore
            .collection('cardSets')
            .where('userId', isEqualTo: user.uid)
            .get();
            
        for (var doc in cardSets.docs) {
          batch.delete(doc.reference);
        }
        
        // 一括commit
        await batch.commit();
        print('✅ ユーザーのコンテンツを削除しました');
      } catch (e) {
        print('⛔ Firestoreデータの削除中にエラーが発生しました: $e');
        // エラーをスローしないで継続処理する
      }
      
      // 3. Firebase Authからアカウントを削除
      await user.delete();
      print('✅ Firebase Authからアカウントを削除しました');
      
      // 完了時に通知
      notifyListeners();
      
    } catch (e) {
      print('⚠️ アカウント削除に失敗しました: $e');
      throw 'アカウントの削除に失敗しました: $e';
    }
  }
  
  // リフレッシュ用に認証情報を再取得
  Future<User?> refreshUserData() async {
    await _auth.currentUser?.reload();
    notifyListeners();
    return _auth.currentUser;
  }
  
  // プロフィール画像をアップロード
  Future<String?> uploadProfileImage({required XFile imageFile}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // ファイル名を生成 (UUID + 拡張子)
      final String fileName = '${const Uuid().v4()}${path.extension(imageFile.path)}';
      final String storagePath = 'profile_images/${user.uid}/$fileName';

      // アップロードタスクを作成
      UploadTask uploadTask;
      if (kIsWeb) {
        // Web環境の場合
        final bytes = await imageFile.readAsBytes();
        final ref = _storage.ref().child(storagePath);
        uploadTask = ref.putData(bytes);
      } else {
        // モバイル環境の場合
        final file = File(imageFile.path);
        final ref = _storage.ref().child(storagePath);
        uploadTask = ref.putFile(file);
      }

      // アップロードを完了し、ダウンロードURLを取得
      final snapshot = await uploadTask.whenComplete(() => null);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Firestoreとユーザープロファイルを更新
      await updateProfilePhotoURL(downloadUrl);

      return downloadUrl;
    } catch (e) {
      print('プロフィール画像のアップロードに失敗しました: $e');
      throw Exception('プロフィール画像のアップロードに失敗しました: $e');
    }
  }

  // プロフィール画像URLを更新
  Future<void> updateProfilePhotoURL(String photoURL) async {
    try {
      // オフライン状態を確認
      final connectivityService = GetIt.instance<ConnectivityService>();
      final isOffline = connectivityService.isOffline;
      
      if (isOffline) {
        print('📱 オフラインモード: プロフィール画像の更新はキューに保存されます');
        
        // ローカルストレージからユーザー情報を取得
        final userInfo = await getOfflineUserInfo();
        if (userInfo == null) {
          throw Exception('オフラインモードでユーザー情報が見つかりません');
        }
        
        // ユーザー情報を更新
        final prefs = await SharedPreferences.getInstance();
        final updatedUserInfo = Map<String, dynamic>.from(userInfo);
        updatedUserInfo['photoURL'] = photoURL;
        updatedUserInfo['lastUpdated'] = DateTime.now().toIso8601String();
        
        // 更新した情報を保存
        await prefs.setString('offline_user_info', jsonEncode(updatedUserInfo));
        print('✅ オフラインモード: プロフィール画像URLをローカルに保存しました');
        
        // オフラインモードではここで処理を終了
        notifyListeners();
        return;
      }
      
      // オンラインモードの場合は通常の処理
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // Firebaseユーザープロファイルを更新
      await user.updatePhotoURL(photoURL);
      print('✅ Firebase Authのプロフィール画像URLを更新しました');

      // Firestoreユーザードキュメントを更新
      await _firestore.collection('users').doc(user.uid).update({
        'photoURL': photoURL,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('✅ Firestoreのプロフィール画像URLを更新しました');
      
      // ローカルストレージにも保存（オフラインモード用）
      await saveUserInfoToLocalStorage();

      notifyListeners();
    } catch (e) {
      print('❌ プロフィール画像URLの更新に失敗しました: $e');
      throw Exception('プロフィール画像URLの更新に失敗しました: $e');
    }
  }

  // プロフィール画像のURLを取得
  Future<String?> getProfilePhotoURL() async {
    try {
      // オフライン状態を確認
      final connectivityService = GetIt.instance<ConnectivityService>();
      final isOffline = connectivityService.isOffline;
      
      if (isOffline) {
        // オフラインモードではローカルストレージから取得
        print('📱 オフラインモード: ローカルストレージからプロフィール画像URLを取得します');
        final userInfo = await getOfflineUserInfo();
        if (userInfo != null && userInfo.containsKey('photoURL')) {
          final photoURL = userInfo['photoURL'];
          if (photoURL != null && photoURL.isNotEmpty) {
            print('✅ ローカルストレージからプロフィール画像URLを取得しました');
            return photoURL;
          }
        }
        print('⚠️ ローカルストレージにプロフィール画像URLがありません');
        return null;
      }
      
      // オンラインモードの場合は通常の処理
      final user = _auth.currentUser;
      if (user == null) {
        print('⚠️ ユーザーがログインしていません');
        return null;
      }

      // Firebase Authからphoto URLを取得
      if (user.photoURL != null && user.photoURL!.isNotEmpty) {
        print('✅ Firebase Authからプロフィール画像URLを取得しました');
        return user.photoURL;
      }

      // Firestoreからphoto URLを取得
      final docSnapshot = await _firestore.collection('users').doc(user.uid).get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        final photoURL = data?['photoURL'];
        if (photoURL != null && photoURL.isNotEmpty) {
          // Firebase Authのプロファイルも更新しておく
          await user.updatePhotoURL(photoURL);
          print('✅ Firestoreからプロフィール画像URLを取得しました');
          
          // ローカルストレージにも保存
          await saveUserInfoToLocalStorage();
          
          return photoURL;
        }
      }

      print('⚠️ プロフィール画像URLが見つかりませんでした');
      return null;
    } catch (e) {
      print('❌ プロフィール画像URLの取得に失敗しました: $e');
      return null;
    }
  }
  
  // 表示名を更新
  Future<void> updateDisplayName(String displayName) async {
    try {
      // オフライン状態を確認
      final connectivityService = GetIt.instance<ConnectivityService>();
      final isOffline = connectivityService.isOffline;
      
      if (isOffline) {
        print('📱 オフラインモード: 表示名の更新はローカルに保存されます');
        
        // ローカルストレージからユーザー情報を取得
        final userInfo = await getOfflineUserInfo();
        if (userInfo == null) {
          throw Exception('オフラインモードでユーザー情報が見つかりません');
        }
        
        // ユーザー情報を更新
        final prefs = await SharedPreferences.getInstance();
        final updatedUserInfo = Map<String, dynamic>.from(userInfo);
        updatedUserInfo['displayName'] = displayName;
        updatedUserInfo['lastUpdated'] = DateTime.now().toIso8601String();
        
        // 更新した情報を保存
        await prefs.setString('offline_user_info', jsonEncode(updatedUserInfo));
        print('✅ オフラインモード: 表示名をローカルに保存しました: $displayName');
        
        // オフラインモードではここで処理を終了
        notifyListeners();
        return;
      }
      
      // オンラインモードの場合は通常の処理
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // Firebase Authのプロファイルを更新
      await user.updateDisplayName(displayName);
      print('✅ Firebase Authの表示名を更新しました: $displayName');

      // Firestoreユーザードキュメントも更新
      await _firestore.collection('users').doc(user.uid).update({
        'displayName': displayName,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('✅ Firestoreの表示名を更新しました');
      
      // ローカルストレージにも保存（オフラインモード用）
      await saveUserInfoToLocalStorage();

      notifyListeners();
    } catch (e) {
      print('❌ 表示名の更新に失敗しました: $e');
      throw Exception('表示名の更新に失敗しました: $e');
    }
  }
  
  // 画像ピッカーを開いてプロフィール画像を選択
  Future<XFile?> pickProfileImage({required ImageSource source}) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      return pickedFile;
    } catch (e) {
      print('画像の選択に失敗しました: $e');
      throw Exception('画像の選択に失敗しました: $e');
    }
  }

  // すべての登録方法で使えるFirestoreユーザー作成メソッド
  Future<void> _createUserInFirestoreIfNeeded(User user) async {
    // users コレクションのユーザーのドキュメントへの参照を取得
    final userDoc = _firestore.collection('users').doc(user.uid);

    // ドキュメントが存在するか確認
    final docSnapshot = await userDoc.get();

    // ドキュメントが存在しない場合、新しく作成
    if (!docSnapshot.exists) {
      await userDoc.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } else {
      // 既存ユーザーの場合は最終ログイン日時を更新
      await userDoc.update({
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Apple Sign In用の安全なランダムnonce生成
  Future<String> _generateNonce() async {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    final result = List.generate(32, (_) => charset[random.nextInt(charset.length)]).join();
    
    // 生成したnonceを返す
    return result;
  }
  
  /// 入力文字列のSHA256ハッシュを生成
  String sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
