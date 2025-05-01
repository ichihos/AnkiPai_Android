import 'package:get_it/get_it.dart';
// import 'package:anki_pai/services/image_processing_service.dart'; // コメントアウト：main.dartでの登録に変更したため
// import 'package:anki_pai/services/vision_service.dart'; // コメントアウト：main.dartでの登録に変更したため
import 'package:anki_pai/services/google_vision_service.dart';
import 'package:anki_pai/services/subscription_service.dart';
import 'package:anki_pai/services/api_token_service.dart';
import 'package:anki_pai/services/notification_service.dart';
import 'package:anki_pai/services/ad_service.dart';
// import 'package:anki_pai/services/openai_mini_service.dart'; // コメントアウト：main.dartでの登録に変更したため

/// サービスロケーターの初期化を行う
/// アプリ起動時に呼び出す
/// 重複呼び出し問題を回避するため、グローバル変数で初期化ステータスを追跡
bool _serviceLocatorInitialized = false;

void setupServiceLocator() {
  // 重複実行防止
  if (_serviceLocatorInitialized) {
    print('※※※ service_locatorはすでに初期化されています。重複呼び出しをスキップします ※※※');
    return;
  }
  
  print('※※※ service_locatorのsetupServiceLocatorが呼び出されました ※※※');
  final GetIt locator = GetIt.instance;

  // 各サービスがすでに登録されていないか確認してから登録する

  // Google Vision サービスの登録
  if (!locator.isRegistered<GoogleVisionService>()) {
    locator.registerLazySingleton<GoogleVisionService>(() => GoogleVisionService());
    print('✔️ GoogleVisionServiceを登録しました');
  }

  // サブスクリプションサービスの登録
  if (!locator.isRegistered<SubscriptionService>()) {
    locator.registerLazySingleton<SubscriptionService>(() => SubscriptionService());
    print('✔️ SubscriptionServiceを登録しました');
  }
      
  // APIトークンサービスの登録
  if (!locator.isRegistered<ApiTokenService>()) {
    locator.registerLazySingleton<ApiTokenService>(() => ApiTokenService());
    print('✔️ ApiTokenServiceを登録しました');
  }
  
  // 通知サービスの登録
  if (!locator.isRegistered<NotificationService>()) {
    // 注意: NotificationServiceは初期化が必要なため、ここでは登録しない
    // main.dartで初期化され登録される
    print('ℹ️ NotificationServiceは初期化が必要なためmain.dartで登録されます');
  }
  
  // 広告サービスの登録
  if (!locator.isRegistered<AdService>()) {
    // 注意: AdServiceは初期化が必要なため、ここでは登録しない
    // main.dartで初期化され登録される
    print('ℹ️ AdServiceは初期化が必要なためmain.dartで登録されます');
  }

  // 初期化完了をマーク
  _serviceLocatorInitialized = true;
}
