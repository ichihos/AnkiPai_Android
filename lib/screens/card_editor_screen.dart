import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/flash_card_service.dart';
import '../services/card_set_service.dart';

class CardEditorScreen extends StatefulWidget {
  final String? cardId;
  final String? initialFrontText;
  final String? initialBackText;
  final String? setId;

  const CardEditorScreen({
    super.key,
    this.cardId,
    this.initialFrontText,
    this.initialBackText,
    this.setId,
  });

  @override
  _CardEditorScreenState createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _frontTextController = TextEditingController();
  final TextEditingController _backTextController = TextEditingController();
  bool _isLoading = false;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.cardId != null;
    _frontTextController.text = widget.initialFrontText ?? '';
    _backTextController.text = widget.initialBackText ?? '';
  }

  @override
  void dispose() {
    _frontTextController.dispose();
    _backTextController.dispose();
    super.dispose();
  }

  // カードの保存
  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final frontText = _frontTextController.text;
      final backText = _backTextController.text;
      final flashCardService =
          Provider.of<FlashCardService>(context, listen: false);
      final cardSetService =
          Provider.of<CardSetService>(context, listen: false);

      if (_isEditMode && widget.cardId != null) {
        // 既存のカードを更新
        await flashCardService.updateFlashCard(
            widget.cardId!, frontText, backText);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.cardUpdated)),
          );
        }
      } else {
        // 新しいカードを追加
        if (widget.setId != null) {
          // カードセットに紐づいたカードを追加する場合
          await cardSetService.addCardToSet(widget.setId!, frontText, backText);
        } else {
          // 紐づかないカードを追加する場合
          await flashCardService.addFlashCard(frontText, backText);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.newCardAdded)),
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context)!.failedToSaveCard(e.toString())),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode
            ? AppLocalizations.of(context)!.editCard
            : AppLocalizations.of(context)!.createNewCard),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveCard,
              tooltip: AppLocalizations.of(context)!.saveCard,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 表面（質問側）テキストフィールド
                    Card(
                      elevation: 2.0,
                      margin: const EdgeInsets.only(bottom: 16.0),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.frontQuestion,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(height: 8.0),
                            TextFormField(
                              controller: _frontTextController,
                              maxLines: 5,
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!
                                    .enterQuestionOrWord,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return AppLocalizations.of(context)!
                                      .frontTextRequired;
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 裏面（回答側）テキストフィールド
                    Card(
                      elevation: 2.0,
                      margin: const EdgeInsets.only(bottom: 16.0),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.backAnswer,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(height: 8.0),
                            TextFormField(
                              controller: _backTextController,
                              maxLines: 5,
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!
                                    .enterAnswerOrDefinition,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return AppLocalizations.of(context)!
                                      .backTextRequired;
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 保存ボタン
                    ElevatedButton(
                      onPressed: _saveCard,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                      ),
                      child: Text(
                        _isEditMode
                            ? AppLocalizations.of(context)!.updateCard
                            : AppLocalizations.of(context)!.createCard,
                        style: const TextStyle(fontSize: 16.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
