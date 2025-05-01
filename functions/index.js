const admin = require('firebase-admin');
const functions = require('firebase-functions');
const cors = require('cors')({ origin: true });

// Stripe初期化は環境変数取得後に行うため、後で定義する
let stripe;
const appleNotifications = require('./apple_notifications');
const apiProxy = require('./api_proxy');
const deepseekV2 = require('./deepseek_v2');
const openaiAlternative = require('./openai_alternative');
const ocrService = require('./ocr_service');
const apiTokenService = require('./api_token_service'); // 新しいAPIトークンサービスを追加

admin.initializeApp();

// Stripe商品情報と価格IDは環境変数またはFirebaseの環境設定から取得
// 環境設定（本番環境かテスト環境か）
const ENVIRONMENT = process.env.NODE_ENV === 'production' || functions.config().environment?.current === 'prod' ? 'prod' : 'test';
console.log(`現在の実行環境: ${ENVIRONMENT}`);

// 環境に応じた設定取得ヘルパー関数
const getEnvironmentConfig = (key) => {
  // 直接環境変数があればそれを使用
  if (process.env[`STRIPE_${key.toUpperCase()}`]) {
    return process.env[`STRIPE_${key.toUpperCase()}`];
  }
  
  // 環境に応じた設定を取得（例: stripe.prod.monthly_price_id または stripe.test.monthly_price_id）
  return functions.config().stripe?.[ENVIRONMENT]?.[key] || functions.config().stripe?.[key];
};

// Stripe secret keyを環境に応じて取得
// 直接設定を表示してデバッグする
const stripeConfig = functions.config().stripe || {};
console.log('Stripe configuration keys:', Object.keys(stripeConfig));
if (stripeConfig[ENVIRONMENT]) {
  console.log(`Environment-specific config found for: ${ENVIRONMENT}`);
  console.log('Available keys:', Object.keys(stripeConfig[ENVIRONMENT]));
}

// 式の異なる取得方法を試す
let stripeSecretKey;
// 方法 1: process.envから直接取得
if (process.env.STRIPE_SECRET_KEY) {
  stripeSecretKey = process.env.STRIPE_SECRET_KEY;
  console.log('Using STRIPE_SECRET_KEY from process.env');
}
// 方法 2: stripe.prod.secret_keyから取得
else if (functions.config().stripe?.[ENVIRONMENT]?.secret_key) {
  stripeSecretKey = functions.config().stripe[ENVIRONMENT].secret_key;
  console.log(`Using secret_key from stripe.${ENVIRONMENT}`);
}
// 方法 3: stripe.secret_keyから直接取得
else if (functions.config().stripe?.secret_key) {
  stripeSecretKey = functions.config().stripe.secret_key;
  console.log('Using secret_key directly from stripe config');
}

if (!stripeSecretKey) {
  console.error(`Stripe secret keyが設定されていません。環境: ${ENVIRONMENT}`);
} else {
  console.log(`Stripeを初期化しました。環境: ${ENVIRONMENT}`);
  // Stripeクライアントを初期化
  stripe = require('stripe')(stripeSecretKey);
}

// 価格ID（Stripeダッシュボードで作成した商品の価格ID）
const PRICE_ID = {
  monthly: getEnvironmentConfig('monthly_price_id'),
  yearly: getEnvironmentConfig('yearly_price_id')
};

// クライアントドメイン（成功・キャンセル時のリダイレクト先）
// 環境ごとに異なるドメインを設定可能
const CLIENT_DOMAIN = functions.config().client?.[ENVIRONMENT]?.domain || 
  functions.config().client?.domain || 
  (ENVIRONMENT === 'prod' ? "https://anki-pai.com" : "https://dev.anki-pai.com");

/**
 * Stripeチェックアウトセッションを作成する
 */
exports.createStripeCheckout = functions
  .region('asia-northeast1') // リージョンを明示的に指定し統一
  .https.onCall(async (data, context) => {
  // 認証確認
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "認証されていません。ログインしてください。"
    );
  }

  const {priceId, plan} = data;
  const uid = context.auth.uid;

  try {
    // カスタマー取得または作成
    const customerSnapshot = await admin
        .firestore()
        .collection("stripe_customers")
        .doc(uid)
        .get();

    let customer;
    if (!customerSnapshot.exists) {
      // ユーザー情報を取得
      const userRecord = await admin.auth().getUser(uid);
      
      // Stripeカスタマーを作成
      customer = await stripe.customers.create({
        email: userRecord.email,
        metadata: {
          firebaseUID: uid,
        },
      });

      // Firestoreに保存
      await admin
          .firestore()
          .collection("stripe_customers")
          .doc(uid)
          .set({
            customer_id: customer.id,
            email: userRecord.email,
          });
    } else {
      customer = {id: customerSnapshot.data().customer_id};
    }

    // すでに有効なサブスクリプションがあるか確認
    const subscriptions = await stripe.subscriptions.list({
      customer: customer.id,
      status: "active",
    });

    if (subscriptions.data.length > 0) {
      throw new functions.https.HttpsError(
          "already-exists",
          "すでに有効なサブスクリプションがあります。"
      );
    }

    // 使用する価格IDの決定
    let targetPriceId = priceId;
    
    if (!targetPriceId) {
      // priceIdが指定されていない場合はプランタイプから取得
      targetPriceId = plan === "yearly" ? PRICE_ID.yearly : PRICE_ID.monthly;
      
      // 価格IDが環境変数または設定から取得できなかった場合はエラー
      if (!targetPriceId) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          `価格IDが設定されていません。管理者にお問い合わせください。プラン: ${plan}`
        );
      }
    }
    
    // チェックアウトセッションを作成
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card"],
      automatic_tax: { enabled: true },
      mode: "subscription",
      customer: customer.id,
      line_items: [
        {
          price: targetPriceId,
          quantity: 1,
        },
      ],
      // 住所情報をStripeに保存 (自動税計算に必要)
      customer_update: {
        address: 'auto',  // 請求先住所を顧客情報に保存
        shipping: 'auto'  // 配送先住所も保存
      },
      // アプリ内からの決済の場合はアプリスキームで戻れるようにする
      success_url: `${CLIENT_DOMAIN}/payment_success?session_id={CHECKOUT_SESSION_ID}&platform=${data.platform || 'web'}`,
      cancel_url: `${CLIENT_DOMAIN}/payment_cancel?platform=${data.platform || 'web'}`,
      // サブスクリプション情報をメタデータに保存
      subscription_data: {
        metadata: {
          firebaseUID: uid,
          plan: plan || "monthly",
        },
      },
    });

    return {sessionId: session.id, url: session.url};
  } catch (error) {
    console.error("Stripe checkout error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Stripeカスタマーポータルセッションを作成する
 */
exports.createStripePortal = functions
  .region('asia-northeast1') // リージョンを明示的に指定し統一
  .https.onCall(async (data, context) => {
  // 認証確認
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "認証されていません。ログインしてください。"
    );
  }

  const uid = context.auth.uid;

  try {
    // カスタマー情報を取得
    const customerSnapshot = await admin
        .firestore()
        .collection("stripe_customers")
        .doc(uid)
        .get();

    if (!customerSnapshot.exists) {
      throw new functions.https.HttpsError(
          "not-found",
          "サブスクリプション情報が見つかりません。"
      );
    }

    // 顧客ポータルセッションを作成
    const session = await stripe.billingPortal.sessions.create({
      customer: customerSnapshot.data().customer_id,
      return_url: CLIENT_DOMAIN,
    });

    return {url: session.url};
  } catch (error) {
    console.error("Stripe customer portal error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Stripeサブスクリプション情報を取得する
 */
exports.getStripeSubscription = functions
  .region('asia-northeast1')
  .https.onCall(async (data, context) => {
  // 認証確認
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "認証されていません。ログインしてください。"
    );
  }

  const uid = context.auth.uid;
  console.log(`getStripeSubscription called for user: ${uid}`);

  try {
    // 1. まずFirestoreからユーザーのStripe顧客IDを取得
    const customerSnapshot = await admin
        .firestore()
        .collection("stripe_customers")
        .doc(uid)
        .get();

    // Stripe顧客情報が存在しない場合
    if (!customerSnapshot.exists) {
      console.log(`No Stripe customer found for user: ${uid}`);
      return {
        active: false,
        plan: "free",
        message: "Stripe顧客情報が存在しません",
      };
    }

    const customerId = customerSnapshot.data().customer_id;
    console.log(`Found Stripe customer ID: ${customerId}`);

    // 2. Stripe APIを使用して顧客のサブスクリプションを直接取得
    const subscriptions = await stripe.subscriptions.list({
      customer: customerId,
      status: "active",
      limit: 1,
    });

    console.log(`Stripe subscriptions found: ${subscriptions.data.length}`);

    // 3. サブスクリプションが存在しない場合
    if (subscriptions.data.length === 0) {
      // 4. Firestoreのデータも確認（ローカルデータのみの場合もあるため）
      const subscriptionSnapshot = await admin
          .firestore()
          .collection("subscriptions")
          .doc(uid)
          .get();

      if (subscriptionSnapshot.exists) {
        const subscriptionData = subscriptionSnapshot.data();
        console.log(`Found subscription in Firestore, but not in Stripe: ${JSON.stringify(subscriptionData)}`);
        
        // サブスクリプションのタイプをチェック
        const type = subscriptionData.type || 'free';
        if (type.includes('premium')) {
          console.log(`Local premium subscription found: ${type}`);
          return {
            active: true,
            plan: subscriptionData.plan || (type.includes('yearly') ? 'yearly' : 'monthly'),
            subscription: subscriptionData,
            source: "firestore_only"
          };
        }
      }
      
      return {
        active: false,
        plan: "free",
        message: "Stripe上にアクティブなサブスクリプションが存在しません",
      };
    }

    // 5. サブスクリプションが存在する場合
    const subscription = subscriptions.data[0];
    console.log(`Active subscription found in Stripe: ${subscription.id}`);
    
    // プラン情報を取得
    const planId = subscription.items.data[0].price.id;
    const planInfo = await stripe.products.retrieve(subscription.items.data[0].price.product);
    const planMetadata = subscription.metadata || {};
    const planType = planMetadata.plan || (planId.includes('yearly') ? 'yearly' : 'monthly');
    
    console.log(`Plan info: ${JSON.stringify(planInfo.name)}, Type: ${planType}`);
    
    // 現在のFirestoreデータも取得
    const subscriptionSnapshot = await admin
        .firestore()
        .collection("subscriptions")
        .doc(uid)
        .get();
    
    let firestoreData = null;
    if (subscriptionSnapshot.exists) {
      firestoreData = subscriptionSnapshot.data();
    }
    
    // 6. Firestoreデータがないか、正しくない場合は自動的に修正
    if (!firestoreData || firestoreData.type === 'free' || !firestoreData.type) {
      // 正しいタイプを設定
      const subscriptionType = planType === 'yearly' ? 'premium_yearly' : 'premium_monthly';
      console.log(`Updating subscription type in Firestore to ${subscriptionType}`);
      
      await admin.firestore().collection("subscriptions").doc(uid).set({
        subscription_id: subscription.id,
        customer_id: customerId,
        plan: planType,
        type: subscriptionType,
        status: subscription.status,
        price_id: planId,
        current_period_start: admin.firestore.Timestamp.fromDate(
            new Date(subscription.current_period_start * 1000)
        ),
        current_period_end: admin.firestore.Timestamp.fromDate(
            new Date(subscription.current_period_end * 1000)
        ),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      
      console.log('Subscription data updated successfully');
      
      // 更新後のデータを取得
      const updatedSnapshot = await admin
          .firestore()
          .collection("subscriptions")
          .doc(uid)
          .get();
      
      if (updatedSnapshot.exists) {
        firestoreData = updatedSnapshot.data();
      }
    }
    
    return {
      active: true,
      plan: planType,
      stripe_subscription: {
        id: subscription.id,
        status: subscription.status,
        current_period_end: subscription.current_period_end,
        plan_name: planInfo.name,
      },
      subscription: firestoreData,
    };
  } catch (error) {
    console.error("Get subscription error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Stripeウェブフックを処理する
 */
exports.processStripeWebhook = functions
  .region('asia-northeast1') // リージョンを明示的に指定し統一
  .https.onRequest(async (req, res) => {
  let event;
  try {
    // Webhook署名を検証
    const signature = req.headers["stripe-signature"];
    // 環境に応じたwebhook secretを取得
    const webhookSecret = getEnvironmentConfig('webhook_secret');
    
    if (!signature && process.env.NODE_ENV !== 'production') {
      // テスト環境では署名がない場合はボディをそのまま解析
      console.log('Testing mode: No signature provided, parsing body directly');
      event = req.body;
    } else if (!webhookSecret) {
      // Webhook secretが設定されていないがシグネチャがある場合
      console.log('Warning: Webhook secret not configured but signature provided');
      // ボディをそのまま解析
      event = req.body;
    } else {
      // 正規の署名検証
      const rawBody = req.rawBody || JSON.stringify(req.body);
      event = stripe.webhooks.constructEvent(
          rawBody,
          signature,
          webhookSecret
      );
    }
  } catch (error) {
    console.error("Webhook signature verification failed:", error.message);
    return res.status(400).send(`Webhook Error: ${error.message}`);
  }

  // イベントタイプに応じた処理
  try {
    if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      
      // サブスクリプション作成時の処理
      if (session.mode === "subscription") {
        await handleSubscriptionCreated(session);
      }
    } else if (event.type === "customer.subscription.updated") {
      // サブスクリプション更新時
      await handleSubscriptionUpdated(event.data.object);
    } else if (event.type === "customer.subscription.deleted") {
      // サブスクリプション削除時
      await handleSubscriptionDeleted(event.data.object);
    }

    res.sendStatus(200);
  } catch (error) {
    console.error("Webhook processing error:", error);
    res.status(500).send(`Webhook handler failed: ${error.message}`);
  }
});

/**
 * サブスクリプション作成時の処理
 */
async function handleSubscriptionCreated(session) {
  console.log('handleSubscriptionCreated called with session:', JSON.stringify(session, null, 2));

  try {
    const subscriptionId = session.subscription;
    console.log('Subscription ID from session:', subscriptionId);
    
    if (!subscriptionId) {
      console.error('No subscription ID found in session');
      return;
    }
    
    const subscription = await stripe.subscriptions.retrieve(subscriptionId);
    console.log('Retrieved subscription details:', JSON.stringify(subscription, null, 2));
    
    const customerId = subscription.customer;
    console.log('Customer ID from subscription:', customerId);

    // customerIdからFirebaseユーザーIDを取得
    const customerSnapshot = await admin
        .firestore()
        .collection("stripe_customers")
        .where("customer_id", "==", customerId)
        .get();

    console.log('Customer snapshot exists:', !customerSnapshot.empty, 'Size:', customerSnapshot.size);

    if (customerSnapshot.empty) {
      console.error("No customer found for subscription:", subscriptionId);
      return;
    }

    const uid = customerSnapshot.docs[0].id;
    console.log('Firebase UID found:', uid);
    
    const plan = subscription.metadata.plan || "monthly";
    console.log('Subscription plan:', plan);

    // サブスクリプション情報をFirestoreに保存
    console.log('Saving subscription data to Firestore for user:', uid);
    
    // プランに基づいて正しいtype値を設定
    const subscriptionType = plan === 'yearly' ? 'premium_yearly' : 'premium_monthly';
    console.log(`Setting subscription type to: ${subscriptionType}`);
    
    await admin
        .firestore()
        .collection("subscriptions")
        .doc(uid)
        .set({
          subscription_id: subscriptionId,
          customer_id: customerId,
          plan: plan,
          status: subscription.status,
          price_id: subscription.items.data[0].price.id,
          // サブスクリプションタイプを追加
          type: subscriptionType,
          current_period_start: admin.firestore.Timestamp.fromDate(
              new Date(subscription.current_period_start * 1000)
          ),
          current_period_end: admin.firestore.Timestamp.fromDate(
              new Date(subscription.current_period_end * 1000)
          ),
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

    console.log('Subscription successfully saved to Firestore for user:', uid);
  } catch (error) {
    console.error('Error in handleSubscriptionCreated:', error);
  }
}

/**
 * サブスクリプション更新時の処理
 */
async function handleSubscriptionUpdated(subscription) {
  const customerId = subscription.customer;

  // customerIdからFirebaseユーザーIDを取得
  const customerSnapshot = await admin
      .firestore()
      .collection("stripe_customers")
      .where("customer_id", "==", customerId)
      .get();

  if (customerSnapshot.empty) {
    console.error("No customer found for subscription:", subscription.id);
    return;
  }

  const uid = customerSnapshot.docs[0].id;

  // サブスクリプション情報を更新
  await admin
      .firestore()
      .collection("subscriptions")
      .doc(uid)
      .update({
        status: subscription.status,
        current_period_start: admin.firestore.Timestamp.fromDate(
            new Date(subscription.current_period_start * 1000)
        ),
        current_period_end: admin.firestore.Timestamp.fromDate(
            new Date(subscription.current_period_end * 1000)
        ),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
}

/**
 * サブスクリプション削除時の処理
 */
async function handleSubscriptionDeleted(subscription) {
  const customerId = subscription.customer;
  const subscriptionId = subscription.id;

  console.log(
      `Delete subscription: ${subscriptionId} from customer: ${customerId}`
  );

  try {
    // customerIdからFirebaseユーザーIDを取得
    const customerSnapshot = await admin
        .firestore()
        .collection("stripe_customers")
        .where("customer_id", "==", customerId)
        .get();
        
    if (customerSnapshot.empty) {
      console.error("No customer found for subscription:", subscription.id);
      return;
    }

    const uid = customerSnapshot.docs[0].id;

    // サブスクリプション情報を更新
    await admin
        .firestore()
        .collection("subscriptions")
        .doc(uid)
        .update({
          status: subscription.status,
          canceled_at: admin.firestore.Timestamp.fromDate(
              new Date(subscription.canceled_at * 1000)
          ),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
  } catch (error) {
    console.error("Error deleting subscription:", error);
  }
}

// Export the App Store notifications handler
// appleNotifications.jsのhandleAppStoreNotifications関数を確認して、そこでregionが設定されているか確認する必要があります
exports.appStoreNotifications = appleNotifications.handleAppStoreNotifications;

// APIトークンサービスの関数をエクスポート
exports.getTemporaryApiToken = apiTokenService.getTemporaryApiToken;
exports.apiProxy = apiTokenService.apiProxy;

/**
 * 決済完了後のサブスクリプション処理をテストするための関数
 * 注意：本番環境では無効化してください
 */
exports.testSubscriptionCreation = functions
  .region('asia-northeast1')
  .https.onCall(async (data, context) => {
  // 認証確認
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "認証されていません。ログインしてください。"
    );
  }

  const uid = context.auth.uid;
  const { sessionId, planType } = data;

  // テスト用にセッションIDを使用
  try {
    // ユーザーのStripe顧客情報を取得
    const customerSnapshot = await admin
        .firestore()
        .collection("stripe_customers")
        .doc(uid)
        .get();

    if (!customerSnapshot.exists) {
      throw new functions.https.HttpsError(
          "not-found",
          "ユーザーのStripe顧客情報が見つかりません。"
      );
    }

    const now = new Date();
    const endDate = planType === 'yearly' 
      ? new Date(now.getFullYear() + 1, now.getMonth(), now.getDate())
      : new Date(now.getFullYear(), now.getMonth() + 1, now.getDate());

    // 直接サブスクリプション情報を作成（テスト用）
    await admin
        .firestore()
        .collection("subscriptions")
        .doc(uid)
        .set({
          subscription_id: `test_sub_${Date.now()}`,
          customer_id: customerSnapshot.data().customer_id,
          plan: planType || 'monthly',
          status: 'active',
          price_id: planType === 'yearly' ? PRICE_ID.yearly : PRICE_ID.monthly,
          current_period_start: admin.firestore.Timestamp.fromDate(now),
          current_period_end: admin.firestore.Timestamp.fromDate(endDate),
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

    return {
      success: true,
      message: "テスト用サブスクリプションが作成されました。",
    };
  } catch (error) {
    console.error("Test subscription creation error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Stripeサブスクリプションを解約する
 */
exports.cancelStripeSubscription = functions
  .region('asia-northeast1')
  .https.onCall(async (data, context) => {
  // 認証確認
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "認証されていません。ログインしてください。"
    );
  }

  const uid = context.auth.uid;
  console.log(`cancelStripeSubscription called for user: ${uid}`);

  try {
    // 1. まずFirestoreからユーザーのStripe顧客IDを取得
    const customerSnapshot = await admin
        .firestore()
        .collection("stripe_customers")
        .doc(uid)
        .get();

    // Stripe顧客情報が存在しない場合
    if (!customerSnapshot.exists) {
      console.log(`No Stripe customer found for user: ${uid}`);
      return {
        success: false,
        error: "Stripe顧客情報が存在しません"
      };
    }

    const customerId = customerSnapshot.data().customer_id;
    console.log(`Found Stripe customer ID: ${customerId}`);

    // 2. Stripe APIを使用して顧客のアクティブなサブスクリプションを取得
    const subscriptions = await stripe.subscriptions.list({
      customer: customerId,
      status: "active",
      limit: 1,
    });

    console.log(`Stripe subscriptions found: ${subscriptions.data.length}`);

    // 3. アクティブなサブスクリプションが存在しない場合
    if (subscriptions.data.length === 0) {
      console.log(`No active subscriptions found for customer: ${customerId}`);
      
      // Firestoreのサブスクリプション状態を更新
      await admin
        .firestore()
        .collection("subscriptions")
        .doc(uid)
        .set({
          status: "canceled",
          type: "free",
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      
      return {
        success: true,
        message: "アクティブなサブスクリプションが見つかりませんでした。ステータスを無料プランに更新しました。"
      };
    }

    // 4. アクティブなサブスクリプションを解約
    const subscription = subscriptions.data[0];
    
    // Stripeのサブスクリプションをキャンセル
    // at_period_end=true を指定すると、現在の請求期間の終了時に解約される
    const canceledSubscription = await stripe.subscriptions.update(
      subscription.id,
      { cancel_at_period_end: true }
    );
    
    console.log(`Subscription ${subscription.id} canceled at period end`);

    // 5. Firestoreのサブスクリプション状態を更新
    await admin
      .firestore()
      .collection("subscriptions")
      .doc(uid)
      .set({
        status: "canceling", // canceling状態は現在のプラン期間が終了したら自動的に無料プランになることを表す
        cancel_at: admin.firestore.Timestamp.fromDate(
          new Date(canceledSubscription.cancel_at * 1000)
        ),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

    return {
      success: true,
      message: "サブスクリプションの解約が完了しました。現在の課金期間が終了するまではプレミアム機能が利用可能です。",
      subscription: {
        id: canceledSubscription.id,
        status: canceledSubscription.status,
        cancel_at: canceledSubscription.cancel_at,
        current_period_end: canceledSubscription.current_period_end
      }
    };
  } catch (error) {
    console.error("Cancel subscription error:", error);
    throw new functions.https.HttpsError("internal", `解約処理中にエラーが発生しました: ${error.message}`);
  }
});

/**
 * Stripeサブスクリプションを再開する
 * キャンセル予定（cancel_at_period_end=true）のサブスクリプションを元に戻す
 */
exports.reactivateStripeSubscription = functions
  .region('asia-northeast1')
  .https.onCall(async (data, context) => {
  // 認証確認
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "認証されていません。ログインしてください。"
    );
  }

  const uid = context.auth.uid;
  console.log(`reactivateStripeSubscription called for user: ${uid}`);

  try {
    // 1. まずFirestoreからユーザーのStripe顧客IDを取得
    const customerSnapshot = await admin
        .firestore()
        .collection("stripe_customers")
        .doc(uid)
        .get();

    // Stripe顧客情報が存在しない場合
    if (!customerSnapshot.exists) {
      console.log(`No Stripe customer found for user: ${uid}`);
      return {
        success: false,
        error: "Stripe顧客情報が存在しません"
      };
    }

    const customerId = customerSnapshot.data().customer_id;
    console.log(`Found Stripe customer ID: ${customerId}`);

    // 2. Stripe APIを使用して顧客のサブスクリプションを取得（キャンセル予定も含む）
    const subscriptions = await stripe.subscriptions.list({
      customer: customerId,
      limit: 10, // 複数のサブスクリプションがある可能性を考慮
    });

    console.log(`Stripe subscriptions found: ${subscriptions.data.length}`);

    // キャンセル予定のサブスクリプションを検索
    const subscriptionToReactivate = subscriptions.data.find(sub => 
      (sub.cancel_at_period_end === true && sub.status === 'active') || 
      sub.status === 'canceled'
    );

    // 再アクティブ化可能なサブスクリプションが存在しない場合
    if (!subscriptionToReactivate) {
      console.log(`No subscription to reactivate found for customer: ${customerId}`);
      return {
        success: false,
        error: "再アクティブ化できるサブスクリプションが見つかりませんでした"
      };
    }

    let updatedSubscription;
    
    // サブスクリプションの状態によって処理を分岐
    if (subscriptionToReactivate.status === 'active' && subscriptionToReactivate.cancel_at_period_end) {
      // キャンセル予定のアクティブなサブスクリプションを再開
      updatedSubscription = await stripe.subscriptions.update(
        subscriptionToReactivate.id,
        { cancel_at_period_end: false }
      );
      console.log(`Subscription ${subscriptionToReactivate.id} reactivated`);
    } else if (subscriptionToReactivate.status === 'canceled') {
      // 既にキャンセルされたサブスクリプションの場合は新しいサブスクリプションを作成
      // 注: この部分は実際のビジネスロジックによって異なる可能性があります
      const items = subscriptionToReactivate.items.data.map(item => ({
        price: item.price.id,
      }));
      
      updatedSubscription = await stripe.subscriptions.create({
        customer: customerId,
        items: items,
      });
      console.log(`New subscription ${updatedSubscription.id} created to replace canceled one`);
    }

    // Firestoreのサブスクリプション状態を更新
    await admin
      .firestore()
      .collection("subscriptions")
      .doc(uid)
      .set({
        status: "active",
        cancel_at: null, // キャンセル日をクリア
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

    return {
      success: true,
      message: "サブスクリプションが正常に再開されました。",
      subscription: {
        id: updatedSubscription.id,
        status: updatedSubscription.status,
        current_period_end: updatedSubscription.current_period_end
      }
    };
  } catch (error) {
    console.error("Reactivate subscription error:", error);
    throw new functions.https.HttpsError("internal", `サブスクリプション再開処理中にエラーが発生しました: ${error.message}`);
  }
});

// External API proxy functions
exports.proxyOpenAI = apiProxy.proxyOpenAI;
exports.proxyDeepSeek = apiProxy.proxyDeepSeek;  // 古い関数（非推奨）
exports.proxyDeepSeekV2 = deepseekV2.proxyDeepSeekV2;  // 新しい最適化版
exports.proxyVision = apiProxy.proxyVision;
exports.proxyMistral = apiProxy.proxyMistral;
exports.proxyImageUpload = apiProxy.proxyImageUpload;
exports.proxyOpenAIV2 = openaiAlternative.proxyOpenAIV2;  // 新しいOpenAI代替関数
exports.performOcr = ocrService.performOcr;  // 新しいOCR専用関数
exports.proxyGemini = require('./gemini_proxy').proxyGemini;  // 新しいGemini代替関数
