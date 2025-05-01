import 'package:anki_pai/services/google_vision_service.dart';
import 'package:anki_pai/services/gpt_ocr_service.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/memory_service.dart';
import 'services/openai_service.dart';
import 'services/gemini_service.dart';
import 'services/ai_service_interface.dart';
import 'services/vision_service.dart';
import 'services/image_analysis_service.dart';
import 'services/flash_card_service.dart';
import 'services/card_set_service.dart';
import 'services/image_processing_service.dart';
import 'services/service_locator.dart';
import 'services/subscription_service.dart';
import 'services/notification_service.dart';
import 'services/notification_helper.dart';
import 'services/ad_service.dart';
import 'services/openai_mini_service.dart';
import 'services/tracking_service.dart';
// LoginScreenは現在HomeScreen内から直接使用
import 'screens/home_screen.dart';
import 'screens/payment_success_screen.dart';

// GetItのインスタンスを取得
// 重要: MyAppクラスで参照されているためこの変数は必要
final getIt = GetIt.instance;

// バックグラウンドでFirebaseメッセージを処理するハンドラ
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // バックグラウンドメッセージを処理
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  // Capture Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  // Capture uncaught async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    return true;
  };

  WidgetsFlutterBinding.ensureInitialized();

  // 別の場所でGetItが使われているか確認
  print('すべてのサービスの登録前の状態:');
  print(' - MemoryService: ${GetIt.instance.isRegistered<MemoryService>()}');
  print(
      ' - NotificationService: ${GetIt.instance.isRegistered<NotificationService>()}');
  print(
      ' - OpenAIMiniService: ${GetIt.instance.isRegistered<OpenAIMiniService>()}');

  // 完全なリセットを実行
  try {
    // GetItをリセットして既存の登録をすべてクリアする
    GetIt.instance.reset();
    print('★ GetItの完全リセットを実行しました ★');
  } catch (e) {
    print('❗ GetItリセットエラー: $e');
  }

  // App Tracking Transparency サービスを登録
  try {
    // 既に登録されていない場合のみ登録
    if (!getIt.isRegistered<TrackingService>()) {
      getIt.registerSingleton<TrackingService>(TrackingService());
    }
  } catch (e) {
    print('⚠️ TrackingService登録中にエラーが発生: $e');
    // エラー発生時は強制的に登録を再試行
    try {
      getIt.registerSingleton<TrackingService>(TrackingService());
    } catch (e) {
      // 最終的なエラー処理
    }
  }

  // Firebase初期化とサービス設定を行う

  // Firebase を初期化
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // サービスの登録（すべてGetIt.instanceを直接使用）
  getIt.registerSingleton<OpenAIService>(OpenAIService());

  // AIServiceInterfaceとしてGeminiServiceを使用
  final geminiService = GeminiService();
  getIt.registerSingleton<GeminiService>(geminiService);
  getIt.registerSingleton<AIServiceInterface>(geminiService);
  print('Gemini Service initialized via Firebase Functions');

  // MemoryServiceの登録（単純化した方法）
  try {
    // 単純な登録方法で試す
    final memoryService = MemoryService();
    GetIt.instance.registerSingleton<MemoryService>(memoryService);
    print('✔️ MemoryServiceが正常に登録されました');
  } catch (e) {
    // 失敗した場合は、別のアプローチを試す
    print('❗ MemoryService登録エラー: $e');

    // エラー発生時は既存インスタンスを使用
    try {
      print('⚒️ 既存インスタンスがあればそれをそのまま使用します');
    } catch (e2) {
      print('❗❗ 二次的エラー: $e2');
    }
  }

  // 認証サービスの登録
  getIt.registerSingleton<AuthService>(AuthService());

  // フラッシュカード・カードセットサービスの登録
  final flashCardService = FlashCardService();
  final cardSetService = CardSetService();
  getIt.registerSingleton<FlashCardService>(flashCardService);
  getIt.registerSingleton<CardSetService>(cardSetService);

  // サービスの初期化
  // Firebase初期化後に呼び出す必要がある
  await flashCardService.initialize();
  await cardSetService.initialize();

  // 画像解析サービスの登録
  // 重要: 上下関係を考慮した登録順序
  // OpenAIMiniServiceは二重登録が発生しないように注意し、前に登録
  try {
    // 完全リセットしているのでチェックは不要
    final openAIMiniService = OpenAIMiniService();
    GetIt.instance.registerSingleton<OpenAIMiniService>(openAIMiniService);
    print('✔️ 重要サービス: OpenAIMiniServiceを最初に登録完了');
  } catch (e) {
    print('❗ OpenAIMiniService登録エラー: $e');
  }

  // イメージ関連サービス（OpenAIMiniServiceが登録されていることを前提にコンストラクタが動作）
  // service_locator.dartとの二重登録問題を避けるため、service_locator.dart側の登録をコメントアウトしてここで登録する
  getIt.registerSingleton<ImageProcessingService>(ImageProcessingService());
  getIt.registerSingleton<GoogleVisionService>(GoogleVisionService());
  getIt.registerSingleton<ImageAnalysisService>(ImageAnalysisService());

  // 新しいOCR専用サービスを登録
  try {
    final gptOcrService = GptOcrService();
    GetIt.instance.registerSingleton<GptOcrService>(gptOcrService);
    print('✔️ 新規OCRサービス: GptOcrService登録完了');
  } catch (e) {
    print('❗ GptOcrService登録エラー: $e');
  }

  // VisionServiceはservice_locator.dartですでに登録されているため、ここでは登録しない
  // サービスの二重登録を避けるため、以下のコードはコメントアウト
  // try {
  //   getIt.registerSingleton<VisionService>(VisionService());
  //   print('✔️ VisionService登録完了');
  // } catch (e) {
  //   print('❗ VisionService登録エラー: $e');
  // }

  // 必要不可欠サービスの登録を確実に行う
  // VisionServiceは画像解析に必要なサービス
  print('📷 VisionServiceの登録確認と初期化を行います');

  // 確実にVisionServiceを登録する
  VisionService visionService;
  try {
    if (GetIt.instance.isRegistered<VisionService>()) {
      // 既存のサービスがあれば取得
      visionService = GetIt.instance<VisionService>();
      print('✔️ 既存のVisionServiceを取得しました');
    } else {
      // 登録されていない場合は新規登録
      visionService = VisionService();
      GetIt.instance.registerSingleton<VisionService>(visionService);
      print('✔️ 新規にVisionServiceを登録しました');
    }
  } catch (e) {
    // エラーが発生した場合は、強制的に再登録
    print('⚠️ VisionServiceの取得中にエラー発生: $e');
    try {
      visionService = VisionService();

      // 既存の登録を解除してから再登録
      if (GetIt.instance.isRegistered<VisionService>()) {
        GetIt.instance.unregister<VisionService>();
      }

      GetIt.instance.registerSingleton<VisionService>(visionService);
      print('✔️ VisionServiceを再登録しました');
    } catch (e2) {
      print('❌ VisionServiceの登録失敗: $e2');
    }
  }

  // 確認用: VisionServiceが正しく登録されているか確認
  try {
    final checkService = GetIt.instance<VisionService>();
    print('✅ VisionServiceの登録確認完了: ${checkService.runtimeType}');
  } catch (e) {
    print('⛔ VisionServiceの登録確認失敗: $e');
  }
  // We already have OpenAIService registered above

  // サブスクリプションサービスの登録
  final subscriptionService = SubscriptionService();
  getIt.registerSingleton<SubscriptionService>(subscriptionService);
  await subscriptionService.initialize();

  // サービスロケーターの初期化
  setupServiceLocator();

  // 通知サービスの登録（一時的に初期化をスキップ）
  try {
    if (!GetIt.instance.isRegistered<NotificationService>()) {
      final notificationService = NotificationService();
      // 初期化をスキップ（flutter_local_notificationsの環境の問題で停止する可能性があるため）
      // await notificationService.initialize();
      GetIt.instance
          .registerSingleton<NotificationService>(notificationService);
      print('⚠️ 通知サービスが登録されましたが、初期化はスキップされました');
    } else {
      print('ℹ️ 通知サービスは既に登録されています');
    }
  } catch (e) {
    print('❗ 通知サービス登録エラー: $e');
  }

  // 広告サービスの登録（一時的に初期化部分をスキップ）
  if (!GetIt.instance.isRegistered<AdService>()) {
    final adService = AdService();
    getIt.registerSingleton<AdService>(adService);
    // 初期化はスキップ（Google Mobile Adsが無効化されているため）
    // await adService.initialize();
    print('⚠️ 広告サービスが登録されましたが、初期化はスキップされました（パッケージが一時的に無効化されているため）');
  } else {
    print('ℹ️ 広告サービスは既に登録されています');
  }

  // 通知関連の初期化（一部をスキップ）
  // タイムゾーンデータの初期化
  tz.initializeTimeZones();
  final notificationHelper = NotificationHelper();
  await notificationHelper.initializeTimeZone();
  // チャンネル設定はスキップ
  // await notificationHelper.setupNotificationChannels();

  // バックグラウンドメッセージハンドラの設定をスキップ
  // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  print('⚠️ Firebaseメッセージングのバックグラウンドハンドラ登録をスキップしました');

  // サービスロケーターは既に初期化済み

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => getIt<AuthService>()),
        ChangeNotifierProvider(create: (_) => getIt<MemoryService>()),
        Provider<FlashCardService>(create: (_) => getIt<FlashCardService>()),
        Provider<CardSetService>(create: (_) => getIt<CardSetService>()),
        Provider<SubscriptionService>(
            create: (_) => getIt<SubscriptionService>()),
        Provider<AdService>(create: (_) => getIt<AdService>()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '暗記Pai',
        // ルーティング設定
        initialRoute: '/',
        onGenerateRoute: (settings) {
          print('Route: ${settings.name}');
          print('Arguments: ${settings.arguments}');

          // URLから直接パラメータを取得する処理
          if (kIsWeb) {
            print('Web platform route processing');
            final uri = Uri.parse(Uri.base.toString());
            print('URL base: $uri');
            print('Query params: ${uri.queryParameters}');
          }

          // パスに基づいてルーティング
          if (settings.name == '/') {
            return MaterialPageRoute(builder: (_) => const AuthWrapper());
          } else if (settings.name!.startsWith('/payment_success')) {
            // URLからパラメータを取得
            final uri = Uri.parse(Uri.base.toString());
            final sessionId = uri.queryParameters['session_id'];
            print(
                'Payment Success Route - SessionID: $sessionId, Full URI: ${uri.toString()}');
            return MaterialPageRoute(
                builder: (_) => PaymentSuccessScreen(sessionId: sessionId));
          } else if (settings.name!.startsWith('/payment_cancel')) {
            return MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('支払いキャンセル')),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cancel, size: 80, color: Colors.orange),
                      const SizedBox(height: 20),
                      const Text('支払いがキャンセルされました',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text('ご利用をお待ちしております。',
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pushReplacementNamed(_, '/'),
                        child: const Text('ホームに戻る'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          } else {
            // 不明なルートの場合はホームにリダイレクト
            return MaterialPageRoute(builder: (_) => const AuthWrapper());
          }
        },
        theme: ThemeData(
          primarySwatch: Colors.blue,
          fontFamily: 'Rounded',
          visualDensity: VisualDensity.adaptivePlatformDensity,
          // ボタンスタイル
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            ),
          ),
          // テキストフィールドスタイル
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.blue.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.blue.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
            ),
            fillColor: Colors.blue.shade50,
            filled: true,
          ),
        ),
        // homeは削除（routesで代用）
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late Future<void> _authFuture;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _authFuture = _initAuth(authService);

    // ATTダイアログを確実に表示するため、UIが描画された後にスケジュール
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // UIが完全に描画された後に実行
        await Future.delayed(const Duration(seconds: 1));

        // TrackingServiceが登録されているか確認
        if (GetIt.instance.isRegistered<TrackingService>()) {
          // ATT (App Tracking Transparency) を初期化
          final trackingService = GetIt.instance<TrackingService>();
          await trackingService.initializeATT();
          print('💡 ATT初期化完了');
        } else {
          // TrackingServiceが登録されていない場合は、その場で登録して初期化
          print('⚠️ TrackingServiceを自動登録します');
          final trackingService = TrackingService();
          GetIt.instance.registerSingleton<TrackingService>(trackingService);
          await trackingService.initializeATT();
          print('💡 ATT初期化完了');
        }
      } catch (e) {
        print('⚠️ ATT初期化中にエラーが発生: $e');
      }
    });
  }

  Future<void> _initAuth(AuthService authService) async {
    print('👤 認証状態チェック中...');

    // 現在のユーザーを確認
    if (authService.currentUser == null) {
      print('👤 ユーザーなし: 匿名サインインを実行');
      await authService.signInAnonymously();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 匿名認証の完了を待っている間の表示
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE0F7FA), // 明るい水色
                    Color(0xFFFFF9C4), // 明るい黄色
                  ],
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        // 認証状態に関わらずHomeScreenに遷移
        return const HomeScreen();
      },
    );
  }
}
