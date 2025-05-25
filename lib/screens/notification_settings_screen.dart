import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/notification_settings_model.dart';
import '../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _notificationService =
      GetIt.instance<NotificationService>();
  bool _isLoading = true;
  late NotificationSettingsModel _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 通知設定を読み込む
  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    // 通知サービスが初期化されていなければ初期化
    if (!_notificationService.isInitialized) {
      await _notificationService.initialize();
    }

    setState(() {
      _settings = _notificationService.settings;
      _isLoading = false;
    });
  }

  /// 通知設定を保存する
  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    await _notificationService.updateNotificationSettings(_settings);

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.notificationSettingsSaved),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.notificationSettings),
        backgroundColor: const Color.fromARGB(255, 53, 152, 71),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 通知の全体設定
                    _buildSettingsSection(
                      title: AppLocalizations.of(context)!.notificationSectionTitle,
                      description: AppLocalizations.of(context)!.notificationSectionDescription,
                      child: SwitchListTile(
                        title: Text(AppLocalizations.of(context)!.enableNotifications),
                        subtitle: Text(
                          _settings.isEnabled ? AppLocalizations.of(context)!.notificationsOn : AppLocalizations.of(context)!.notificationsOff,
                          style: TextStyle(
                            color: _settings.isEnabled
                                ? Colors.green
                                : Colors.grey,
                          ),
                        ),
                        value: _settings.isEnabled,
                        activeColor: Colors.green,
                        onChanged: (value) {
                          setState(() {
                            _settings = _settings.copyWith(isEnabled: value);
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 通知種類別の設定
                    if (_settings.isEnabled) ...[
                      _buildSettingsSection(
                        title: AppLocalizations.of(context)!.techniqueGenerationNotificationTitle,
                        description: AppLocalizations.of(context)!.techniqueGenerationNotificationDescription,
                        child: SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.memorizationCompletedNotification),
                          subtitle: Text(AppLocalizations.of(context)!.notifyWhenGenerationCompletes),
                          value:
                              _settings.enableTechniqueGenerationNotifications,
                          activeColor: Colors.green,
                          onChanged: (value) {
                            setState(() {
                              _settings = _settings.copyWith(
                                enableTechniqueGenerationNotifications: value,
                              );
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSettingsSection(
                        title: AppLocalizations.of(context)!.memoryMethodReminderTitle,
                        description: AppLocalizations.of(context)!.memoryMethodReminderDescription,
                        child: SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.memorizationMethodReminder),
                          subtitle: Text(AppLocalizations.of(context)!.notifyOptimalTimingForgeeting),
                          value: _settings.enableTechniqueLearningReminders,
                          activeColor: Colors.green,
                          onChanged: (value) {
                            setState(() {
                              _settings = _settings.copyWith(
                                enableTechniqueLearningReminders: value,
                              );
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSettingsSection(
                        title: AppLocalizations.of(context)!.flashcardReminderTitle,
                        description: AppLocalizations.of(context)!.flashcardReminderDescription,
                        child: SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.flashcardLearningReminder),
                          subtitle: Text(AppLocalizations.of(context)!.notifyOptimalTimingForgeeting),
                          value: _settings.enableFlashcardLearningReminders,
                          activeColor: Colors.green,
                          onChanged: (value) {
                            setState(() {
                              _settings = _settings.copyWith(
                                enableFlashcardLearningReminders: value,
                              );
                            });
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // 保存ボタン
                    Center(
                      child: ElevatedButton(
                        onPressed: _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                        ),
                        child: Text(AppLocalizations.of(context)!.saveSettings),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 忘却曲線の説明
                    if (_settings.isEnabled &&
                        (_settings.enableTechniqueLearningReminders ||
                            _settings.enableFlashcardLearningReminders))
                      _buildInfoCard(),
                  ],
                ),
              ),
            ),
    );
  }

  /// 設定セクションのウィジェットを構築
  Widget _buildSettingsSection({
    required String title,
    required String description,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
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
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  /// 忘却曲線についての説明カード
  Widget _buildInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.aboutForgettingCurve,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.forgettingCurveDescription,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.reviewRecommendation,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          _buildTimelineItem(AppLocalizations.of(context)!.firstReview),
          _buildTimelineItem(AppLocalizations.of(context)!.secondReview),
          _buildTimelineItem(AppLocalizations.of(context)!.thirdReview),
          _buildTimelineItem(AppLocalizations.of(context)!.fourthReview),
          _buildTimelineItem(AppLocalizations.of(context)!.fifthReview),
        ],
      ),
    );
  }

  /// タイムラインアイテムを構築
  Widget _buildTimelineItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
