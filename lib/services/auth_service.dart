import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
// Temporarily commented out: import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:get_it/get_it.dart';
import 'subscription_service.dart';

// Temporary stub classes for sign_in_with_apple package
// These will be removed when the actual package is restored
class AppleIDAuthorizationScopes {
  static const email = 'email';
  static const fullName = 'fullName';
}

class WebAuthenticationOptions {
  final String clientId;
  final Uri redirectUri;
  
  WebAuthenticationOptions({required this.clientId, required this.redirectUri});
}

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
    return _auth.currentUser != null;
  }

  // ユーザーの認証状態を再検証
  Future<bool> validateAuthentication() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return false;
      }

      // トークンの再取得を試みる（期限切れの場合に更新される）
      await user.getIdToken(true);
      return true;
    } catch (e) {
      print('認証状態の検証に失敗しました: $e');
      return false;
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
      final result = await _auth.signInAnonymously();

      // Firestore にユーザー情報を登録
      await _createUserInFirestoreIfNeeded(result.user!);

      notifyListeners();
      return result;
    } catch (e) {
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

  // プロフィール画像のURLを更新
  Future<void> updateProfilePhotoURL(String photoURL) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // Firebaseユーザープロファイルを更新
      await user.updatePhotoURL(photoURL);

      // Firestoreユーザードキュメントを更新
      await _firestore.collection('users').doc(user.uid).update({
        'photoURL': photoURL,
      });

      notifyListeners();
    } catch (e) {
      print('プロフィール画像URLの更新に失敗しました: $e');
      throw Exception('プロフィール画像URLの更新に失敗しました: $e');
    }
  }

  // プロフィール画像のURLを取得
  Future<String?> getProfilePhotoURL() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return null;
      }

      // Firebase Authからphoto URLを取得
      if (user.photoURL != null && user.photoURL!.isNotEmpty) {
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
          return photoURL;
        }
      }

      return null;
    } catch (e) {
      print('プロフィール画像URLの取得に失敗しました: $e');
      return null;
    }
  }
  
  // 表示名を更新
  Future<void> updateDisplayName(String displayName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // Firebase Authのプロファイルを更新
      await user.updateDisplayName(displayName);

      // Firestoreユーザードキュメントも更新
      await _firestore.collection('users').doc(user.uid).update({
        'displayName': displayName,
      });

      notifyListeners();
    } catch (e) {
      print('表示名の更新に失敗しました: $e');
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

  // Sign in with Apple
  // Temporary stub implementation of signInWithApple
  // This will be replaced when the sign_in_with_apple package is restored
  Future<UserCredential?> signInWithApple() async {
    try {
      // デバッグ: 現在のプラットフォーム情報を記録
      print('✨ Apple Sign In開始 - Platform: ${kIsWeb ? "Web" : Platform.operatingSystem}');
      print('⚠️ Apple Sign In is temporarily disabled');
      
      // Webプラットフォーム用の実装のみを保持
      if (kIsWeb) {
        // Webプラットフォーム用の実装
        print('✨ Web用Apple Sign Inを実行します');
        
        // Webではプロバイダ対象のサインインを直接使う
        final provider = OAuthProvider('apple.com');
        
        // 必要なスコープを指定
        provider.addScope('email');
        provider.addScope('name');
        
        // Firebase AuthのSignInWithPopupを使用
        print('✨ FirebaseのOAuthポップアップを開きます');
        return await _auth.signInWithPopup(provider);
      } else {
        // ネイティブプラットフォーム用の実装は一時的に無効化
        throw Exception('Apple Sign Inは現在、このアプリでは利用できません。他のサインイン方法をお試しください。');
      }
      
      // Note: The code below will never be reached in the native implementation
      // but is left as a placeholder for when the actual implementation is restored
      return null;
    } catch (e) {
      print('Apple Sign Inに失敗しました: $e');
      return null;
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
