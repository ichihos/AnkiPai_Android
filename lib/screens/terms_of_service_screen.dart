import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.termsOfService),
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
              AppLocalizations.of(context)!.termsHeader,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.termsIntro,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              AppLocalizations.of(context)!.termsSection1Title,
              AppLocalizations.of(context)!.termsSection1Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection2Title,
              AppLocalizations.of(context)!.termsSection2Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection3Title,
              AppLocalizations.of(context)!.termsSection3Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection4Title,
              AppLocalizations.of(context)!.termsSection4Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection5Title,
              AppLocalizations.of(context)!.termsSection5Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection6Title,
              AppLocalizations.of(context)!.termsSection6Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection7Title,
              AppLocalizations.of(context)!.termsSection7Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection8Title,
              AppLocalizations.of(context)!.termsSection8Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection9Title,
              AppLocalizations.of(context)!.termsSection9Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection10Title,
              AppLocalizations.of(context)!.termsSection10Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection11Title,
              AppLocalizations.of(context)!.termsSection11Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection12Title,
              AppLocalizations.of(context)!.termsSection12Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection13Title,
              AppLocalizations.of(context)!.termsSection13Content,
            ),
            _buildSection(
              AppLocalizations.of(context)!.termsSection14Title,
              AppLocalizations.of(context)!.termsSection14Content,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                AppLocalizations.of(context)!.termsRevisionDate,
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
