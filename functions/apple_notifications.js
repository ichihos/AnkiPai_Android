const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');

// App Store通知処理用のFirebase Function
exports.handleAppStoreNotifications = functions
  .region('asia-northeast1') // リージョンを明示的に指定し統一
  .https.onRequest(async (req, res) => {
  try {
    // メソッドチェック
    if (req.method !== 'POST') {
      console.error('Invalid request method', req.method);
      return res.status(405).send('Method Not Allowed');
    }

    console.log('Received App Store notification');
    
    // リクエストボディから通知データを取得
    const notification = req.body;
    
    // 通知データのログ (開発中のみ使用し、本番環境ではセキュリティのため削除することを推奨)
    console.log('Notification payload:', JSON.stringify(notification));

    // JWSシグネチャの検証 (本番環境では必ず実装すべき)
    // if (!verifySignature(notification)) {
    //   console.error('Invalid notification signature');
    //   return res.status(400).send('Invalid signature');
    // }

    // 通知タイプの確認
    const notificationType = notification?.notificationType || 
                            notification?.notification_type;
    
    // 環境の確認（本番環境かSandboxか）
    const environment = notification?.environment || 'PROD';
    console.log(`Notification type: ${notificationType}, Environment: ${environment}`);

    // サブスクリプション情報を処理
    if (notificationType) {
      await processSubscriptionNotification(notification);
    }

    // Apple Serverに200 OKを返して通知の受信を確認
    // 通知が正しく処理されなくても200を返すことが推奨されている（Appleが再試行するため）
    return res.status(200).send('OK');
  } catch (error) {
    console.error('Error processing App Store notification:', error);
    // エラーがあっても通常は200を返す（エラーログは記録する）
    return res.status(200).send('Error processing notification');
  }
});

/**
 * サブスクリプション通知を処理する
 * @param {Object} notification 通知オブジェクト
 */
async function processSubscriptionNotification(notification) {
  try {
    // 通知タイプ
    const notificationType = notification?.notificationType || 
                            notification?.notification_type;
    
    // 通知タイプに基づいて処理
    switch (notificationType) {
      case 'INITIAL_BUY':
      case 'DID_RENEW':
        await handleSubscriptionActive(notification);
        break;
      case 'CANCEL':
      case 'DID_FAIL_TO_RENEW':
        await handleSubscriptionFailed(notification);
        break;
      case 'EXPIRED':
        await handleSubscriptionExpired(notification);
        break;
      case 'REFUND':
        await handleSubscriptionRefunded(notification);
        break;
      case 'PRICE_INCREASE':
        // 価格変更通知の処理
        console.log('Price increase notification received');
        break;
      case 'REVOKE':
        // 払い戻し通知の処理
        await handleSubscriptionRevoked(notification);
        break;
      default:
        console.log(`Unhandled notification type: ${notificationType}`);
    }
  } catch (error) {
    console.error('Error processing subscription notification:', error);
  }
}

/**
 * 新規購入またはリニューアル時の処理
 * @param {Object} notification 通知オブジェクト
 */
async function handleSubscriptionActive(notification) {
  try {
    // レシート情報を取得
    const latestReceiptInfo = getLatestReceiptInfo(notification);
    if (!latestReceiptInfo) {
      console.error('No receipt info found in notification');
      return;
    }
    
    // 必要な情報を抽出
    const { 
      original_transaction_id,
      product_id,
      expires_date_ms,
      transaction_id,
      purchase_date_ms
    } = latestReceiptInfo;
    
    // アプリ内で使用しているユーザーIDを取得
    const userId = await getUserIdFromTransaction(original_transaction_id);
    if (!userId) {
      console.error('User ID not found for transaction:', original_transaction_id);
      return;
    }
    
    // サブスクリプションタイプを判定 (product_idに基づく)
    const subscriptionType = product_id.includes('yearly') 
      ? 'premium_yearly' 
      : 'premium_monthly';
    
    // 有効期限を計算
    const expiresDate = new Date(parseInt(expires_date_ms));
    const purchaseDate = new Date(parseInt(purchase_date_ms));
    
    console.log(`Updating subscription for user ${userId}: Type=${subscriptionType}, Expires=${expiresDate.toISOString()}`);
    
    // Firestoreでサブスクリプション情報を更新
    await admin.firestore().collection('subscriptions').doc(userId).set({
      type: subscriptionType,
      startDate: admin.firestore.Timestamp.fromDate(purchaseDate),
      endDate: admin.firestore.Timestamp.fromDate(expiresDate),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      originalTransactionId: original_transaction_id,
      transactionId: transaction_id,
      productId: product_id,
      status: 'active'
    }, { merge: true });
    
    console.log(`Subscription activated for user ${userId}`);
  } catch (error) {
    console.error('Error handling subscription activation:', error);
  }
}

/**
 * サブスクリプション更新失敗時の処理
 * @param {Object} notification 通知オブジェクト
 */
async function handleSubscriptionFailed(notification) {
  try {
    const latestReceiptInfo = getLatestReceiptInfo(notification);
    if (!latestReceiptInfo) return;
    
    const { original_transaction_id } = latestReceiptInfo;
    const userId = await getUserIdFromTransaction(original_transaction_id);
    if (!userId) return;
    
    // 猶予期間などの情報を更新
    await admin.firestore().collection('subscriptions').doc(userId).update({
      status: 'grace_period',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`Subscription renewal failed for user ${userId}`);
  } catch (error) {
    console.error('Error handling subscription failure:', error);
  }
}

/**
 * サブスクリプション期限切れ時の処理
 * @param {Object} notification 通知オブジェクト
 */
async function handleSubscriptionExpired(notification) {
  try {
    const latestReceiptInfo = getLatestReceiptInfo(notification);
    if (!latestReceiptInfo) return;
    
    const { original_transaction_id } = latestReceiptInfo;
    const userId = await getUserIdFromTransaction(original_transaction_id);
    if (!userId) return;
    
    // サブスクリプション情報を更新
    await admin.firestore().collection('subscriptions').doc(userId).update({
      type: 'free',
      status: 'expired',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`Subscription expired for user ${userId}`);
  } catch (error) {
    console.error('Error handling subscription expiration:', error);
  }
}

/**
 * サブスクリプションの払い戻し時の処理
 * @param {Object} notification 通知オブジェクト
 */
async function handleSubscriptionRefunded(notification) {
  try {
    const latestReceiptInfo = getLatestReceiptInfo(notification);
    if (!latestReceiptInfo) return;
    
    const { original_transaction_id } = latestReceiptInfo;
    const userId = await getUserIdFromTransaction(original_transaction_id);
    if (!userId) return;
    
    // サブスクリプション情報を更新
    await admin.firestore().collection('subscriptions').doc(userId).update({
      type: 'free',
      status: 'refunded',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`Subscription refunded for user ${userId}`);
  } catch (error) {
    console.error('Error handling subscription refund:', error);
  }
}

/**
 * サブスクリプションの取り消し時の処理
 * @param {Object} notification 通知オブジェクト
 */
async function handleSubscriptionRevoked(notification) {
  try {
    const latestReceiptInfo = getLatestReceiptInfo(notification);
    if (!latestReceiptInfo) return;
    
    const { original_transaction_id } = latestReceiptInfo;
    const userId = await getUserIdFromTransaction(original_transaction_id);
    if (!userId) return;
    
    // サブスクリプション情報を更新
    await admin.firestore().collection('subscriptions').doc(userId).update({
      type: 'free',
      status: 'revoked',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`Subscription revoked for user ${userId}`);
  } catch (error) {
    console.error('Error handling subscription revocation:', error);
  }
}

/**
 * 通知からレシート情報を取得する
 * @param {Object} notification 通知オブジェクト
 * @returns {Object|null} 最新のレシート情報
 */
function getLatestReceiptInfo(notification) {
  // App Store Server Notifications v2
  if (notification.data && notification.data.signedTransactionInfo) {
    try {
      // JWSデコード (実際の実装ではJWSの検証が必要)
      const transactionInfo = JSON.parse(
        Buffer.from(notification.data.signedTransactionInfo.split('.')[1], 'base64').toString()
      );
      return transactionInfo;
    } catch (e) {
      console.error('Error parsing signedTransactionInfo:', e);
    }
  }
  
  // App Store Server Notifications v1
  if (notification.unified_receipt && notification.unified_receipt.latest_receipt_info) {
    return notification.unified_receipt.latest_receipt_info[0];
  }
  
  // その他のフォーマット
  if (notification.latest_receipt_info) {
    return Array.isArray(notification.latest_receipt_info) 
      ? notification.latest_receipt_info[0] 
      : notification.latest_receipt_info;
  }
  
  return null;
}

/**
 * トランザクションIDからユーザーIDを取得する
 * 実際の実装ではデータベースクエリが必要
 * @param {string} transactionId 取引ID
 * @returns {Promise<string|null>} ユーザーID
 */
async function getUserIdFromTransaction(transactionId) {
  try {
    // transactionIdからユーザーIDを取得
    const querySnapshot = await admin.firestore()
      .collection('subscriptions')
      .where('originalTransactionId', '==', transactionId)
      .limit(1)
      .get();
    
    if (!querySnapshot.empty) {
      return querySnapshot.docs[0].id;
    }
    
    // 見つからない場合はpurchase_recordsコレクションも確認
    const purchaseRecords = await admin.firestore()
      .collection('purchase_records')
      .where('originalTransactionId', '==', transactionId)
      .limit(1)
      .get();
    
    if (!purchaseRecords.empty) {
      return purchaseRecords.docs[0].data().userId;
    }
    
    return null;
  } catch (error) {
    console.error('Error getting user ID from transaction:', error);
    return null;
  }
}

/**
 * 署名を検証する関数（実際の実装が必要）
 * @param {Object} notification 通知オブジェクト
 * @returns {boolean} 検証結果
 */
function verifySignature(notification) {
  // App Store通知のJWS署名検証を実装（本番では必須）
  // Apple公開鍵の取得、JWSの検証など
  return true; // 開発用に一時的にtrueを返す
}
