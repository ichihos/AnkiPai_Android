/**
 * Stripeサブスクリプションを解約するための関数
 * index.jsに追加する必要があります
 */

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
