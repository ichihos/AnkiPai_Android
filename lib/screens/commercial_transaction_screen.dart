import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// 特定商取引法に基づく表記画面
class CommercialTransactionScreen extends StatelessWidget {
  const CommercialTransactionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.commercialTransactionAct),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(AppLocalizations.of(context)!.companyName),
              _buildContentText(AppLocalizations.of(context)!.ichihosotsuji),
              _buildSectionTitle(AppLocalizations.of(context)!.representative),
              _buildContentText(AppLocalizations.of(context)!.ichihosotsuji),
              _buildSectionTitle(AppLocalizations.of(context)!.location),
              _buildContentText(AppLocalizations.of(context)!.disclosureUponRequest),
              _buildSectionTitle(AppLocalizations.of(context)!.phoneNumber),
              _buildContentText(AppLocalizations.of(context)!.disclosureUponRequest),
              _buildSectionTitle(AppLocalizations.of(context)!.contact),
              _buildContentText(AppLocalizations.of(context)!.emailAddress('AnkiPai.app@gmail.com')),
              _buildSectionTitle(AppLocalizations.of(context)!.productPrice),
              _buildContentText(AppLocalizations.of(context)!.priceDescription),
              _buildSectionTitle(AppLocalizations.of(context)!.additionalFees),
              _buildContentText(AppLocalizations.of(context)!.additionalFeesDescription),
              _buildSectionTitle(AppLocalizations.of(context)!.deliveryTime),
              _buildContentText(AppLocalizations.of(context)!.deliveryDescription),
              _buildSectionTitle(AppLocalizations.of(context)!.paymentMethod),
              _buildContentText(AppLocalizations.of(context)!.paymentDescription),
              _buildSectionTitle(AppLocalizations.of(context)!.paymentTiming),
              _buildContentText(AppLocalizations.of(context)!.paymentTimingDescription),
              _buildSectionTitle(AppLocalizations.of(context)!.cancellationRefundExchange),
              _buildContentText(AppLocalizations.of(context)!.cancellationRefundExchangeDescription),
              _buildSectionTitle(AppLocalizations.of(context)!.operatingEnvironment),
              _buildContentText(AppLocalizations.of(context)!.operatingEnvironmentDescription),
              _buildSectionTitle(AppLocalizations.of(context)!.serviceSuspension),
              _buildContentText(AppLocalizations.of(context)!.serviceSuspensionDescription),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  AppLocalizations.of(context)!.lastUpdated,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// セクションタイトルを構築
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Color.fromARGB(255, 53, 152, 71),
        ),
      ),
    );
  }

  /// コンテンツテキストを構築
  Widget _buildContentText(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
        ),
      ),
    );
  }
}
