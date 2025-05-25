import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.privacyPolicy),
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromARGB(255, 53, 152, 71),
                Color.fromARGB(255, 40, 130, 60),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.privacyPolicyHeader,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.privacyPolicyIntro,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              AppLocalizations.of(context)!.privacyPolicySection1Title,
              AppLocalizations.of(context)!.privacyPolicySection1Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.privacyPolicySection2Title,
              AppLocalizations.of(context)!.privacyPolicySection2Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.privacyPolicySection3Title,
              AppLocalizations.of(context)!.privacyPolicySection3Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.privacyPolicySection4Title,
              AppLocalizations.of(context)!.privacyPolicySection4Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.privacyPolicySection5Title,
              AppLocalizations.of(context)!.privacyPolicySection5Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.privacyPolicySection6Title,
              AppLocalizations.of(context)!.privacyPolicySection6Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.privacyPolicySection7Title,
              AppLocalizations.of(context)!.privacyPolicySection7Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.privacyPolicySection8Title,
              AppLocalizations.of(context)!.privacyPolicySection8Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.privacyPolicySection9Title,
              AppLocalizations.of(context)!.privacyPolicySection9Content,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                AppLocalizations.of(context)!.policyRevisionDate,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade800,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
