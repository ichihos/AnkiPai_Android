import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';

class PaymentSuccessScreen extends StatefulWidget {
  final String? sessionId;

  const PaymentSuccessScreen({super.key, this.sessionId});

  @override
  _PaymentSuccessScreenState createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _refreshSubscription();
  }

  Future<void> _refreshSubscription() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      print(
          'Payment Success Screen - Refreshing subscription with session ID: ${widget.sessionId}');

      // 最初にキャッシュをクリア
      final subscriptionService =
          Provider.of<SubscriptionService>(context, listen: false);
      subscriptionService.clearCache();

      // サブスクリプション情報を更新（強制的に再読み込み）
      try {
        await subscriptionService.refreshSubscription();
        print('Subscription refreshed successfully');
      } catch (refreshError) {
        print('Error refreshing subscription: $refreshError');
        // エラーが発生しても処理を続行
      }

      // 3秒待機してから再度取得を試みる
      await Future.delayed(const Duration(seconds: 3));
      try {
        await subscriptionService.refreshSubscription();
        print('Second subscription refresh attempt completed');
      } catch (secondError) {
        print('Error on second refresh attempt: $secondError');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Critical error in _refreshSubscription: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'サブスクリプション情報の更新に失敗しました: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('決済完了'),
        backgroundColor: const Color.fromARGB(255, 53, 152, 71),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(24),
              child: Icon(
                Icons.check_circle,
                size: 72,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'お支払いが完了しました！',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'プレミアム機能をご利用いただけるようになりました。\nご利用ありがとうございます。',
              style: TextStyle(
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 53, 152, 71),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'ホームに戻る',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
