const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');
const { GoogleAuth } = require('google-auth-library');

/**
 * Google Vertex AI Gemini API へのプロキシリクエスト
 * クライアントからのリクエストを Vertex AI Gemini API に転送し、結果を返す
 */
exports.proxyGemini = functions
  .region('asia-northeast1')
  .runWith({
    memory: '1GB',
    timeoutSeconds: 120
  })
  .https.onCall(async (data, context) => {
    // 認証チェック
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'ユーザー認証が必要です'
      );
    }

    try {
      // リクエストデータを取得
      const requestData = data.data || {};
      const model = requestData.model || 'gemini-2.5-flash-preview-04-17';
      const contents = requestData.contents || [];
      const generationConfig = requestData.generation_config || {
        temperature: 0.7,
        max_output_tokens: 1000
      };
      
      if (!contents || contents.length === 0) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'contents は必須フィールドです'
        );
      }

      console.log(`Vertex AI Geminiリクエスト: モデル=${model}, 温度=${generationConfig.temperature}, 最大トークン=${generationConfig.max_output_tokens}`);
      const requestStartTime = Date.now();

      // ユーザーID確認とクォータチェック
      const userId = context.auth.uid;
      await checkUserQuota(userId, 'gemini');

      // Google Cloud認証
      const auth = new GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/cloud-platform']
      });
      const client = await auth.getClient();
      const token = await client.getAccessToken();

      // Vertex AI向けのリクエストを作成
      const location = 'us-central1'; // または適切なリージョン
      const project = process.env.GCLOUD_PROJECT;
      const publisher = 'google';
      
      // Vertex AIのエンドポイント
      const apiEndpoint = `https://${location}-aiplatform.googleapis.com/v1/projects/${project}/locations/${location}/publishers/${publisher}/models/${model}:generateContent`;
      
      // Vertex AI APIにリクエストを送信
      const response = await axios.post(apiEndpoint, {
        contents: contents,
        generationConfig: generationConfig
      }, {
        headers: {
          'Authorization': `Bearer ${token.token}`,
          'Content-Type': 'application/json'
        },
        timeout: 90000 // 90秒のタイムアウト設定
      });

      const elapsedTime = Date.now() - requestStartTime;
      console.log(`Vertex AI Geminiレスポンス受信時間: ${elapsedTime}ms`);

      // レスポンスを解析
      if (response.data && response.data.candidates && response.data.candidates.length > 0) {
        const candidate = response.data.candidates[0];
        
        if (candidate.content && candidate.content.parts && candidate.content.parts.length > 0) {
          const text = candidate.content.parts[0].text || '';
          
          // 使用量を記録
          await recordAPIUsage(userId, 'gemini', {
            model: model,
            promptTokens: estimateTokenCount(JSON.stringify(contents)),
            completionTokens: estimateTokenCount(text),
            totalTokens: estimateTokenCount(JSON.stringify(contents) + text)
          });

          return {
            text: text,
            model: model,
            usage: {
              prompt_tokens: estimateTokenCount(JSON.stringify(contents)),
              completion_tokens: estimateTokenCount(text),
              total_tokens: estimateTokenCount(JSON.stringify(contents) + text)
            }
          };
        }
      }

      // エラーの場合
      throw new functions.https.HttpsError(
        'internal',
        'Vertex AI Geminiからの応答を処理できませんでした',
        { apiResponse: response.data }
      );
    } catch (error) {
      console.error('Vertex AI Gemini エラー:', error.message);
      
      if (error.response) {
        console.error('エラーステータス:', error.response.status);
        console.error('エラーデータ:', JSON.stringify(error.response.data));
      }
      
      throw new functions.https.HttpsError(
        'internal',
        `Vertex AI Gemini処理エラー: ${error.message}`,
        { originalError: error.toString() }
      );
    }
  });

/**
 * ユーザーの API 使用量をチェックする
 * @param {string} userId - ユーザーID
 * @param {string} apiType - API種別 (gemini)
 */
async function checkUserQuota(userId, apiType) {
  try {
    // 今日の開始時刻のTimestampを取得
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    // 今日の使用回数をカウントのみ実施(制限は適用しない)
    // Firestoreの正しいパターンを使用: collection -> document -> collection -> ...
    const usageRef = admin.firestore()
      .collection('users')
      .doc(userId)
      .collection(`api_usage_${apiType}`) // 正しいパターン: apiTypeをコレクション名の一部として使用
      .where('timestamp', '>=', today)
      .orderBy('timestamp', 'desc');
    
    const usageSnapshot = await usageRef.get();
    // 制限チェックは無効化されました
    // 利用制限を設ける場合は以下のコードを復活させてください
    /*
    const dailyLimit = 15;
    if (usageSnapshot.size >= dailyLimit) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        `無料ユーザーの1日あたりの${apiType.toUpperCase()}利用制限(${dailyLimit}回)に達しました。サブスクリプションにアップグレードしてください。`
      );
    }
    */
    console.log('利用制限チェックが無効化されています。使用回数: ' + usageSnapshot.size);
    
    return true;
  } catch (error) {
    console.error('クォータチェックエラー:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
      'internal',
      'API使用量の確認中にエラーが発生しました'
    );
  }
}

/**
 * API使用量を記録する
 * @param {string} userId - ユーザーID
 * @param {string} apiType - API種別 (gemini)
 * @param {Object} usage - 使用量情報
 */
async function recordAPIUsage(userId, apiType, usage) {
  try {
    // 新しいデータ機造で記録: users/{userId}/api_usage_${apiType}/doc_id
    await admin.firestore()
      .collection('users')
      .doc(userId)
      .collection(`api_usage_${apiType}`) // apiTypeをコレクション名の一部として使用
      .add({
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        model: usage.model,
        prompt_tokens: usage.promptTokens,
        completion_tokens: usage.completionTokens,
        total_tokens: usage.totalTokens
      });
    
    return true;
  } catch (error) {
    console.error('API使用量記録エラー:', error);
    // 記録失敗してもユーザー体験に影響しないよう、エラーはスローしない
    return false;
  }
}

/**
 * テキストのトークン数を概算する簡易関数
 * 英語テキストでは約4文字で1トークンと概算
 * @param {string} text - 推定対象テキスト
 * @returns {number} - 概算トークン数
 */
function estimateTokenCount(text) {
  if (!text) return 0;
  // 英語は約4文字/トークン、日本語は約1.5文字/トークンで概算
  // 日本語判定（ざっくり）
  const hasJapanese = /[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF\u3400-\u4DBF]/.test(text);
  
  if (hasJapanese) {
    return Math.ceil(text.length / 1.5);
  } else {
    return Math.ceil(text.length / 4);
  }
}
