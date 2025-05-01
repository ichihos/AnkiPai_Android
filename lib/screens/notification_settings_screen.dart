import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

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

    await _notificationService.saveNotificationSettings(_settings);

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知設定を保存しました'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知設定'),
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
                      title: '通知',
                      description: '通知を受け取るかどうかを設定します。オフにすると、すべての通知が無効になります。',
                      child: SwitchListTile(
                        title: const Text('通知を有効にする'),
                        subtitle: Text(
                          _settings.isEnabled ? '通知はオンです' : '通知はオフです',
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
                        title: '暗記法生成完了通知',
                        description: 'バックグラウンドで暗記法の生成が完了したときに通知します。',
                        child: SwitchListTile(
                          title: const Text('暗記法生成完了通知'),
                          subtitle: const Text('バックグラウンドで生成が完了したら通知'),
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
                        title: '暗記法学習リマインダー',
                        description: '忘却曲線に基づいて、作成した暗記法の復習時期を通知します。',
                        child: SwitchListTile(
                          title: const Text('暗記法学習リマインダー'),
                          subtitle: const Text('忘却曲線に基づく学習タイミングを通知'),
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
                        title: 'フラッシュカード学習リマインダー',
                        description: '忘却曲線に基づいて、作成したフラッシュカードの復習時期を通知します。',
                        child: SwitchListTile(
                          title: const Text('フラッシュカード学習リマインダー'),
                          subtitle: const Text('忘却曲線に基づく学習タイミングを通知'),
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
                        child: const Text('設定を保存'),
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
              const Text(
                '忘却曲線について',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '忘却曲線は、人間の記憶がどのように減衰するかを示す曲線です。'
            '効果的な学習のためには、適切なタイミングで復習することが重要です。',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            '通常、以下のタイミングで復習することが推奨されています：',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          _buildTimelineItem('1回目の復習：学習した日の1日後'),
          _buildTimelineItem('2回目の復習：前回の復習から3日後'),
          _buildTimelineItem('3回目の復習：前回の復習から1週間後'),
          _buildTimelineItem('4回目の復習：前回の復習から2週間後'),
          _buildTimelineItem('5回目の復習：前回の復習から1ヶ月後'),
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
