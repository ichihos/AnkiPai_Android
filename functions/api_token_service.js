/**
 * 一時的なAPIトークン生成サービス
 * このモジュールはAI APIへのアクセス用の一時トークンを生成します
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');

// JWT署名用のシークレット（環境変数から取得）
let JWT_SECRET;

// 環境設定関連
const ENVIRONMENT = process.env.NODE_ENV === 'production' || 
                   functions.config().environment?.current === 'prod' ? 'prod' : 'test';

/**
 * 環境設定値を取得するヘルパー関数
 */
const getEnvironmentConfig = (key) => {
  // 環境変数がある場合はそちらを優先
  if (process.env[key]) {
    return process.env[key];
  }
  
  // Firebaseの設定から取得を試みる
  try {
    const configs = functions.config();
    const parts = key.split('_').map(p => p.toLowerCase());
    
    // 設定オブジェクトをドリルダウンして値を取得
    let value = configs;
    for (const part of parts) {
      if (value[part] === undefined) return null;
      value = value[part];
    }
    
    return value;
  } catch (error) {
    console.error(`[${ENVIRONMENT}] 設定キー ${key} の取得に失敗: ${error}`);
    return null;
  }
};

// 初期化時に必要な設定を取得
const initConfig = () => {
  try {
    JWT_SECRET = getEnvironmentConfig('API_TOKEN_SECRET') || 
                crypto.randomBytes(32).toString('hex'); // フォールバックとして一時的なシークレットを生成
    
    console.log(`[${ENVIRONMENT}] API Token Serviceを初期化しました`);
    return true;
  } catch (error) {
    console.error(`[${ENVIRONMENT}] API Token Service初期化エラー: ${error}`);
    return false;
  }
};

// サービス初期化
initConfig();

/**
 * JWT形式の一時トークンを生成
 * @param {string} uid ユーザーID
 * @param {Object} payload 追加データ
 * @param {number} expiresIn 有効期限（秒）
 * @returns {string} JWTトークン
 */
const generateToken = (uid, payload = {}, expiresIn = 3600) => {
  if (!JWT_SECRET) {
    throw new Error('API Token Secret is not configured');
  }
  
  const now = Math.floor(Date.now() / 1000);
  const exp = now + expiresIn;
  
  const tokenData = {
    iss: 'anki-pai-api-service',
    sub: uid,
    iat: now,
    exp,
    ...payload
  };
  
  // JWTのヘッダー
  const header = {
    alg: 'HS256',
    typ: 'JWT'
  };
  
  // Base64エンコードされたヘッダーとペイロード
  const encodedHeader = Buffer.from(JSON.stringify(header)).toString('base64')
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  
  const encodedPayload = Buffer.from(JSON.stringify(tokenData)).toString('base64')
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  
  // 署名部分の生成
  const signature = crypto
    .createHmac('sha256', JWT_SECRET)
    .update(`${encodedHeader}.${encodedPayload}`)
    .digest('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
  
  // JWTの組み立て
  return `${encodedHeader}.${encodedPayload}.${signature}`;
};

/**
 * トークンの検証
 * @param {string} token JWTトークン
 * @returns {Object|null} トークンが有効な場合はデコードされたペイロード、無効な場合はnull
 */
const verifyToken = (token) => {
  if (!JWT_SECRET) {
    throw new Error('API Token Secret is not configured');
  }
  
  try {
    const [encodedHeader, encodedPayload, signature] = token.split('.');
    
    // 署名の検証
    const expectedSignature = crypto
      .createHmac('sha256', JWT_SECRET)
      .update(`${encodedHeader}.${encodedPayload}`)
      .digest('base64')
      .replace(/=/g, '')
      .replace(/\+/g, '-')
      .replace(/\//g, '_');
    
    if (signature !== expectedSignature) {
      return null;
    }
    
    // ペイロードのデコード
    const payload = JSON.parse(
      Buffer.from(encodedPayload, 'base64').toString('utf8')
    );
    
    // 有効期限チェック
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp < now) {
      return null;
    }
    
    return payload;
  } catch (error) {
    console.error('トークン検証エラー:', error);
    return null;
  }
};

/**
 * AI APIキーへのアクセス用の一時トークンを発行するCloud Function
 */
exports.getTemporaryApiToken = functions.region('asia-northeast1').https.onCall(async (data, context) => {
  // 認証確認
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'このリクエストにはログインが必要です。'
    );
  }
  
  try {
    const uid = context.auth.uid;
    
    // ユーザーのサブスクリプション状態を確認（オプション）
    // ここでプレミアムユーザーかどうかなどの確認を行うことも可能
    
    // 一時トークンにAPIアクセスに必要な情報だけを含める
    // 実際のAPIキーはサーバーサイドに保持し、トークンには含めない
    const tokenPayload = {
      // アクセス権限の定義
      permissions: {
        deepseek: true,
        openai: true,
        mistral: true
      },
      // レート制限などの設定
      limits: {
        requestsPerMinute: 10,
      }
    };
    
    // トークンの有効期限（秒）
    // 本番環境では適切な値に調整する（例: 15分～1時間）
    const tokenExpiry = 60 * 15; // 15分
    
    // トークン生成
    const token = generateToken(uid, tokenPayload, tokenExpiry);
    
    return {
      success: true,
      token,
      expiresIn: tokenExpiry
    };
  } catch (error) {
    console.error('一時APIトークン発行エラー:', error);
    throw new functions.https.HttpsError(
      'internal',
      '一時トークンの発行中にエラーが発生しました',
      { message: error.message }
    );
  }
});

/**
 * API呼び出しを中継するプロキシ関数
 * クライアントはAPIキーの代わりに一時トークンを使用
 */
exports.apiProxy = functions.region('asia-northeast1').https.onCall(async (data, context) => {
  // リクエストデータ検証
  if (!data.token || !data.endpoint || !data.method) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      '必要なパラメータが不足しています（token, endpoint, method）'
    );
  }
  
  // トークン検証
  const tokenData = verifyToken(data.token);
  if (!tokenData) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'トークンが無効か期限切れです'
    );
  }
  
  try {
    // APIエンドポイントに基づいて適切なAPIキーを選択
    const apiType = data.apiType || 'deepseek'; // デフォルトはDeepSeek
    
    // トークンの権限チェック
    if (!tokenData.permissions[apiType]) {
      throw new functions.https.HttpsError(
        'permission-denied',
        `このトークンには ${apiType} APIへのアクセス権限がありません`
      );
    }
    
    // 現在はトークン認証のみ実装しています
    // 実際のAPI呼び出しプロキシ処理は既存の`api_proxy.js`などの機能を活用するか
    // または新たに実装する必要があります
    
    return {
      success: true,
      message: 'API機能は現在準備中です'
    };
    
    // 実際のAPI呼び出し部分は別途実装が必要です
  } catch (error) {
    console.error('APIプロキシエラー:', error);
    throw new functions.https.HttpsError(
      'internal',
      'APIリクエスト処理中にエラーが発生しました',
      { message: error.message }
    );
  }
});

// トークン関連の内部ユーティリティをエクスポート
exports.utils = {
  generateToken,
  verifyToken
};
