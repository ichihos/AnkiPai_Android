import 'package:flutter/material.dart';
import '../models/subscription_model.dart';

class SubscriptionStatusWidget extends StatelessWidget {
  final SubscriptionModel? subscription;
  final bool isLoading;
  final String mode;
  final Function(String) getRemainingUsesText;

  const SubscriptionStatusWidget({
    super.key,
    required this.subscription,
    required this.isLoading,
    required this.mode,
    required this.getRemainingUsesText,
  });

  @override
  Widget build(BuildContext context) {
    String usageText = '読み込み中...';
    if (!isLoading && subscription != null) {
      usageText = getRemainingUsesText(mode);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isLoading ? Icons.pending_outlined : Icons.info_outline,
            color: Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            '現在の利用状況: $usageText',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
