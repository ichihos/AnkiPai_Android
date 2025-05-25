import 'services/google_vision_service.dart';
import 'services/gpt_ocr_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'l10n/l10n.dart';
import 'providers/language_provider.dart';
import 'services/connectivity_service.dart';
import 'services/language_service.dart';
import 'services/gemini_service.dart';
import 'services/dummy_ai_service.dart';
import 'services/logger_service.dart';
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
import 'screens/payment_cancel_screen.dart';

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
    // ログにエラーを記録
    LoggerService.instance
        .log('❌ Flutter Error: ${details.exception}\n${details.stack}');
  };

  // Capture uncaught async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    // ログに非同期エラーを記録
    LoggerService.instance.log('❌ Uncaught Error: $error\n$stack');
    return true;
  };

  WidgetsFlutterBinding.ensureInitialized();

  // Google Mobile Adsの初期化
  try {
    MobileAds.instance.initialize();
    print('✅ Google Mobile Adsの初期化が成功しました');
  } catch (e) {
    print('❗ Google Mobile Adsの初期化エラー: $e');
  }

  // flutter_background_serviceの初期化
  try {
    if (!kIsWeb) {
      // Webではバックグラウンドサービスを使用しない
      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: (intent) async {
            // バックグラウンドサービスの処理
            return true;
          },
          autoStart: false,
          isForegroundMode: false,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: (intent) async {
            return true;
          },
          onBackground: (intent) async {
            return true;
          },
        ),
      );
    }
  } catch (e) {
    print('❗ Background Serviceの初期化エラー: $e');
  }

  // LoggerServiceの初期化
  try {
    await LoggerService.instance.initialize();
    LoggerService.instance.log('✅ アプリ起動: LoggerServiceが初期化されました');
  } catch (e) {
    print('❌ LoggerServiceの初期化に失敗: $e');
  }

  // 最初にConnectivityServiceを登録して初期化（他のサービスの前に必要）
  if (!GetIt.instance.isRegistered<ConnectivityService>()) {
    final connectivityService = ConnectivityService();
    GetIt.instance.registerSingleton<ConnectivityService>(connectivityService);
    await connectivityService.initialize();
    await LoggerService.instance.log('✅ 最初のステップ: 接続状態監視サービスを初期化しました');
  }

  // オフラインかどうかを確認
  bool isOffline = false;
  try {
    final connectivityService = GetIt.instance<ConnectivityService>();
    isOffline = connectivityService.isOffline;
    await LoggerService.instance
        .log(isOffline ? '📱 オフラインモードで起動します' : '🌐 オンラインモードで起動します');
  } catch (e) {
    await LoggerService.instance.log('⚠️ 接続状態の確認中にエラーが発生: $e');
  }

  // GetItリセットは複数の初期化問題を引き起こすため削除
  // 既存のサービスを尊重し、必要なときだけ登録する

  // App Tracking Transparency サービスの登録を遅延化
  if (!getIt.isRegistered<TrackingService>()) {
    getIt.registerLazySingleton<TrackingService>(() => TrackingService());
  }

  // Firebase初期化とサービス設定を行う

  // Firebase初期化をオフラインモードでも実行するように変更
  try {
    await LoggerService.instance.log('🔥 Firebaseの初期化を開始します');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await LoggerService.instance.log('✅ Firebaseの初期化に成功しました');
  } catch (e) {
    await LoggerService.instance.log('❌ Firebaseの初期化に失敗しました: $e');
    print('⚠️ Firebaseの初期化に失敗しました（オフラインモードで続行します）: $e');
    // Firebase初期化の失敗を無視して続行
    // 初期化失敗の場合でもアプリは続行する
    // isOfflineフラグはすでに接続サービスから設定されているので変更しない
  }

  // サービスの登録 - 非重要サービスをLazySingletonに変更
  if (!getIt.isRegistered<OpenAIService>()) {
    getIt.registerLazySingleton<OpenAIService>(() => OpenAIService());
  }

  // AIServiceInterfaceとしてGeminiServiceを使用
  if (!getIt.isRegistered<GeminiService>() ||
      !getIt.isRegistered<AIServiceInterface>()) {
    try {
      // オフラインモードの場合はエラーをキャッチして処理を続行
      if (GetIt.instance<ConnectivityService>().isOffline) {
        LoggerService.instance.log('📱 オフラインモード: GeminiServiceの初期化をスキップします');
        // オフラインモード用のダミーサービスを登録
        final dummyService = DummyAIService();

        // オフラインモードではGeminiServiceの登録を行わない
        // 代わりにAIServiceInterfaceのみを登録する
        if (!getIt.isRegistered<AIServiceInterface>()) {
          getIt.registerSingleton<AIServiceInterface>(dummyService);
          LoggerService.instance
              .log('✅ オフラインモード用にDummyAIServiceをAIServiceInterfaceとして登録しました');
        }
      } else {
        // オンラインモードの場合は通常の初期化
        final geminiService = GeminiService();
        if (!getIt.isRegistered<GeminiService>()) {
          getIt.registerSingleton<GeminiService>(geminiService);
        }
        if (!getIt.isRegistered<AIServiceInterface>()) {
          getIt.registerSingleton<AIServiceInterface>(geminiService);
        }
      }
    } catch (e) {
      // 何らかのエラーが発生した場合はダミーサービスを登録
      LoggerService.instance.log('❌ GeminiServiceの初期化に失敗しました: $e');
      final dummyService = DummyAIService();

      // GeminiServiceの登録はオフラインモードでは行わない
      // 代わりにAIServiceInterfaceのみを登録する
      if (!getIt.isRegistered<AIServiceInterface>()) {
        getIt.registerSingleton<AIServiceInterface>(dummyService);
        LoggerService.instance
            .log('✅ オフラインモード用にDummyAIServiceをAIServiceInterfaceとして登録しました');
      }
    }
  }

  // MemoryServiceの登録
  if (!getIt.isRegistered<MemoryService>()) {
    try {
      final memoryService = MemoryService();
      getIt.registerSingleton<MemoryService>(memoryService);
      LoggerService.instance.log('✅ MemoryServiceを登録しました');
    } catch (e) {
      // オフラインモードやFirebase初期化失敗時にエラーが発生する可能性がある
      LoggerService.instance.log('❌ MemoryServiceの登録に失敗しました: $e');
      print('⚠️ MemoryServiceの登録に失敗しましたが、アプリは続行します: $e');
      // エラーを無視して続行
    }
  }

  // 認証サービスの登録
  if (!getIt.isRegistered<AuthService>()) {
    getIt.registerSingleton<AuthService>(AuthService());
  }

  // 言語サービスの初期化（オフラインでも必要）
  try {
    await LanguageService.initialize();
    print('✅ 言語サービスを初期化しました');
  } catch (e) {
    print('⚠️ 言語サービスの初期化に失敗しました: $e');
  }

  // フラッシュカード・カードセットサービスの登録
  if (!getIt.isRegistered<FlashCardService>()) {
    final flashCardService = FlashCardService();
    getIt.registerSingleton<FlashCardService>(flashCardService);
    // ログイン後に初期化することで起動時の処理を軽減
    // await flashCardService.initialize();
  }

  if (!getIt.isRegistered<CardSetService>()) {
    final cardSetService = CardSetService();
    getIt.registerSingleton<CardSetService>(cardSetService);
    // ログイン後に初期化することで起動時の処理を軽減
    // await cardSetService.initialize();
  }

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
  // ImageAnalysisServiceの登録
  try {
    if (!getIt.isRegistered<ImageAnalysisService>()) {
      getIt.registerSingleton<ImageAnalysisService>(ImageAnalysisService());
      LoggerService.instance.log('✅ ImageAnalysisServiceを登録しました');
    }
  } catch (e) {
    // オフラインモードや初期化失敗時にエラーが発生する可能性がある
    LoggerService.instance.log('❌ ImageAnalysisServiceの初期化に失敗しました: $e');
    print('⚠️ ImageAnalysisServiceの初期化に失敗しましたが、アプリは続行します: $e');
  }

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

  // オフライン状態は上部で取得済み

  // 確実にVisionServiceを登録する
  VisionService visionService;
  try {
    if (GetIt.instance.isRegistered<VisionService>()) {
      // 既に登録されている場合はそれを使用
      visionService = GetIt.instance<VisionService>();
      print('✔️ 既存のVisionServiceを取得しました');
    } else {
      // 登録されていない場合は新規登録
      visionService = VisionService();
      GetIt.instance.registerSingleton<VisionService>(visionService);
      print('✔️ 新規にVisionServiceを登録しました');
    }
  } catch (e) {
    // エラー発生時は再登録を試みる
    print('⚠️ VisionServiceの取得中にエラー発生: $e');
    try {
      visionService = VisionService();

      // 既存の登録があれば削除
      if (GetIt.instance.isRegistered<VisionService>()) {
        GetIt.instance.unregister<VisionService>();
      }

      GetIt.instance.registerSingleton<VisionService>(visionService);
      print('✔️ VisionServiceを再登録しました');
    } catch (e2) {
      print('❌ VisionServiceの登録失敗: $e2');
      // エラー時はアプリが続行できるように、エラーを無視して続行
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
  if (!getIt.isRegistered<SubscriptionService>()) {
    try {
      final subscriptionService = SubscriptionService();
      await subscriptionService.initialize();
      getIt.registerSingleton<SubscriptionService>(subscriptionService);
      LoggerService.instance.log('✅ サブスクリプションサービスを登録しました');
    } catch (e) {
      // オフラインモードや初期化失敗時にエラーが発生する可能性がある
      LoggerService.instance.log('❌ サブスクリプションサービスの初期化に失敗しました: $e');
      print('⚠️ サブスクリプションサービスの初期化に失敗しましたが、アプリは続行します: $e');

      // エラーが発生してもサービスを登録しておく
      final subscriptionService = SubscriptionService();
      getIt.registerSingleton<SubscriptionService>(subscriptionService);
    }
  }

  // サービスロケーターの初期化
  setupServiceLocator();

  // 通知サービスの登録（重複登録防止付き）
  try {
    if (!GetIt.instance.isRegistered<NotificationService>()) {
      final notificationService = NotificationService();
      await notificationService.initialize();
      GetIt.instance
          .registerSingleton<NotificationService>(notificationService);
      print('✔️ 通知サービスが正常に登録されました');
    } else {
      print('ℹ️ 通知サービスは既に登録されています');
    }
  } catch (e) {
    print('❗ 通知サービス登録エラー: $e');
  }

  // 広告サービスの登録（重複登録防止付き）
  if (!GetIt.instance.isRegistered<AdService>()) {
    final adService = AdService();
    getIt.registerSingleton<AdService>(adService);
    await adService.initialize();
    print('✔️ 広告サービスが正常に登録されました');
  } else {
    print('ℹ️ 広告サービスは既に登録されています');
  }

  // 接続状態監視サービスは既に最初に登録済み

  // 通知関連の初期化
  // タイムゾーンデータの初期化
  tz.initializeTimeZones();
  final notificationHelper = NotificationHelper();
  await notificationHelper.initializeTimeZone();
  await notificationHelper.setupNotificationChannels();

  // バックグラウンドメッセージハンドラの設定
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'MemPie AI',
          locale: languageProvider.currentLocale,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.all,
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
              // 専用のキャンセル画面を使用
              print('Payment Cancel Route');
              return MaterialPageRoute(
                builder: (_) => const PaymentCancelScreen(),
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
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
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
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    LoggerService.instance.log('🔴 AuthWrapperのinitStateが呼ばれました');

    // 即度タイムアウトを設定（スプラッシュ画面が長く表示されるのを防ぐ）
    Future.delayed(const Duration(seconds: 3), () {
      LoggerService.instance.log('🔴 3秒タイムアウトが発生しました');
      if (mounted && !_isInitialized) {
        setState(() {
          _isInitialized = true;
          LoggerService.instance
              .log('🔴 タイムアウトにより強制的に_isInitialized=trueに設定しました');
        });
      }
    });

    // オフラインモードか確認
    bool isOffline = false;
    try {
      final connectivityService = GetIt.instance<ConnectivityService>();
      isOffline = connectivityService.isOffline;
      LoggerService.instance.log('🔴 AuthWrapper初期化時のオフライン状態: $isOffline');

      // オフラインの場合は即座に初期化完了とみなす
      if (isOffline && mounted) {
        setState(() {
          _isInitialized = true;
          LoggerService.instance
              .log('🔴 オフラインモードのため即座に_isInitialized=trueに設定しました');
        });
      }
    } catch (e) {
      LoggerService.instance.log('🔴 接続状態の確認中にエラーが発生: $e');
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    _authFuture = _initAuth(authService);

    // 初期化が完了したことを確認するためのフラグを設定
    _authFuture.then((_) {
      LoggerService.instance.log('🔴 _authFutureが完了しました');
      if (mounted) {
        setState(() {
          _isInitialized = true;
          LoggerService.instance
              .log('🔴 _authFuture完了により_isInitialized=trueに設定しました');
        });
      }
    }).catchError((e) {
      LoggerService.instance.log('🔴 _authFutureのエラー: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true; // エラーが発生しても初期化完了とみなす
          LoggerService.instance
              .log('🔴 _authFutureエラー発生後、_isInitialized=trueに設定しました');
        });
      }
    });

    // ATTダイアログを確実に表示するため、UIが描画された後にスケジュール
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // UIが完全に描画された後に実行
        await Future.delayed(const Duration(seconds: 1));
        await LoggerService.instance.log('🔴 ATT初期化を開始します');

        // TrackingServiceが登録されているか確認
        if (GetIt.instance.isRegistered<TrackingService>()) {
          // ATT (App Tracking Transparency) を初期化
          final trackingService = GetIt.instance<TrackingService>();
          await trackingService.initializeATT();
          await LoggerService.instance.log('💡 ATT初期化完了');
        } else {
          // TrackingServiceが登録されていない場合は、その場で登録して初期化
          await LoggerService.instance.log('⚠️ TrackingServiceを自動登録します');
          final trackingService = TrackingService();
          GetIt.instance.registerSingleton<TrackingService>(trackingService);
          await trackingService.initializeATT();
          await LoggerService.instance.log('💡 ATT初期化完了');
        }
      } catch (e) {
        await LoggerService.instance.log('⚠️ ATT初期化中にエラーが発生: $e');
      }
    });
  }

  Future<void> _initAuth(AuthService authService) async {
    await LoggerService.instance.log('🔴 _initAuth: 認証状態チェック開始');

    // 言語設定を先に初期化しておく（オフラインでも必要）
    try {
      await LoggerService.instance.log('🔴 _initAuth: 言語設定の初期化を開始');
      await LanguageService.initialize();
      await LoggerService.instance.log('🔴 _initAuth: 言語設定の初期化が完了しました');
    } catch (e) {
      await LoggerService.instance
          .log('🔴 _initAuth: 言語設定の初期化中にエラーが発生しました: $e');
    }

    // オフラインモードかどうかを確認
    bool isOffline = false;
    try {
      final connectivityService = GetIt.instance<ConnectivityService>();
      isOffline = connectivityService.isOffline;
      await LoggerService.instance.log('🔴 _initAuth: オフライン状態 = $isOffline');
    } catch (e) {
      await LoggerService.instance.log('🔴 _initAuth: 接続状態の確認中にエラーが発生: $e');
      isOffline = true; // エラーが発生した場合は安全のためオフラインとみなす
    }

    if (isOffline) {
      await LoggerService.instance.log('🔴 _initAuth: オフラインモードのため認証をスキップします');
      return;
    }

    try {
      await LoggerService.instance.log('🔴 _initAuth: オンラインモードで認証を開始');
      // 現在のユーザーを確認
      if (authService.currentUser == null) {
        await LoggerService.instance.log('🔴 _initAuth: ユーザーなし、匿名サインインを実行します');
        await authService.signInAnonymously();
        await LoggerService.instance.log('🔴 _initAuth: 匿名サインインが完了しました');
      } else {
        await LoggerService.instance.log('🔴 _initAuth: 既存のユーザーが存在します');
      }

      await LoggerService.instance.log('🔴 _initAuth: 認証処理が完了しました');
    } catch (e) {
      await LoggerService.instance.log('🔴 _initAuth: 認証エラーが発生しました: $e');

      if (e.toString().contains('オフラインモード')) {
        await LoggerService.instance
            .log('🔴 _initAuth: オフラインモードのエラー、オフラインとして続行します');
      } else {
        await LoggerService.instance.log('🔴 _initAuth: 一般エラーが発生しましたが、続行します');
      }
    }

    await LoggerService.instance.log('🔴 _initAuth: 処理が完了しました');
  }

  @override
  Widget build(BuildContext context) {
    LoggerService.instance
        .log('🔴 AuthWrapper.buildが呼ばれました: _isInitialized=$_isInitialized');

    // オフラインモードか確認
    bool isOffline = false;
    try {
      final connectivityService = GetIt.instance<ConnectivityService>();
      isOffline = connectivityService.isOffline;
      LoggerService.instance.log('🔴 build: オフライン状態 = $isOffline');
    } catch (e) {
      LoggerService.instance.log('🔴 build: 接続状態の確認中にエラーが発生: $e');
      isOffline = true; // エラーが発生した場合は安全のためオフラインとみなす
    }

    // 言語設定が初期化されているか確認（オフラインでも必要）
    try {
      LanguageService.initialize();
    } catch (e) {
      LoggerService.instance.log('🔴 build: 言語設定の初期化中にエラーが発生: $e');
    }

    // オフラインモードまたは初期化完了なら、ホーム画面を表示
    if (isOffline || _isInitialized) {
      LoggerService.instance.log('🔴 build: オフラインまたは初期化完了のためホーム画面を表示します');
      return const HomeScreen();
    }

    // タイムアウトを設定（ここでも設定しておく）
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_isInitialized) {
        LoggerService.instance.log('🔴 build: 2秒タイムアウトが発生しました');
        setState(() {
          _isInitialized = true;
          LoggerService.instance
              .log('🔴 build: タイムアウトにより_isInitialized=trueに設定しました');
        });
      }
    });

    LoggerService.instance.log('🔴 build: FutureBuilderを表示します');
    return FutureBuilder(
      future: _authFuture,
      builder: (context, snapshot) {
        LoggerService.instance.log(
            '🔴 FutureBuilder.builder: connectionState=${snapshot.connectionState}');

        // 完了またはエラーの場合はホーム画面へ
        if (snapshot.connectionState == ConnectionState.done ||
            snapshot.hasError) {
          LoggerService.instance
              .log('🔴 FutureBuilder: 完了またはエラーのためホーム画面を表示します');
          return const HomeScreen();
        }

        // 待機中の場合はスプラッシュ画面を表示
        LoggerService.instance.log('🔴 FutureBuilder: スプラッシュ画面を表示します');
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('アプリを起動しています...'),
              ],
            ),
          ),
        );
      },
    );
  }
}
