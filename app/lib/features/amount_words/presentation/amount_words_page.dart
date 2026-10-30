import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/region.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../domain/amount_words.dart';

String _defaultCurrency() {
  final country = (Region.country ?? '').toUpperCase();
  switch (Region.toolRegion) {
    case ToolRegion.india:
      return 'INR';
    case ToolRegion.gulf:
      return country == 'SA' ? 'SAR' : 'AED';
    case ToolRegion.europe:
      return country == 'GB' ? 'GBP' : 'EUR';
    default:
      return 'USD';
  }
}

WordsLanguage _defaultLanguage() {
  if (Strings.code == 'de') return WordsLanguage.de;
  if (Strings.code == 'ar') return WordsLanguage.ar;
  return Region.toolRegion == ToolRegion.india ? WordsLanguage.enIn : WordsLanguage.en;
}

/// Writes an amount in words for a cheque, an invoice or a receipt. Everything is worked out on the phone.
class AmountWordsPage extends StatefulWidget {
  const AmountWordsPage({super.key});

  @override
  State<AmountWordsPage> createState() => _AmountWordsPageState();
}

class _AmountWordsPageState extends State<AmountWordsPage> {
  final _amount = TextEditingController();
  final _focus = FocusNode();
  late String _currency = _defaultCurrency();
  late WordsLanguage _language = _defaultLanguage();
  late bool _only = _language == WordsLanguage.enIn;
  WordsCase _case = WordsCase.title;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && mounted) setState(() => _touched = true);
    });
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final c = p.getString('words_currency');
      if (c != null && (c == 'none' || wordsCurrency(c) != null)) _currency = c;
      final l = p.getString('words_language');
      _language = WordsLanguage.values.where((v) => v.name == l).firstOrNull ?? _language;
      _only = p.getBool('words_only') ?? (_language == WordsLanguage.enIn);
      _case = WordsCase.values.where((v) => v.name == p.getString('words_case')).firstOrNull ?? _case;
    });
  }

  Future<void> _remember() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('words_currency', _currency);
    await p.setString('words_language', _language.name);
    await p.setBool('words_only', _only);
    await p.setString('words_case', _case.name);
  }

  void _set(VoidCallback change) {
    setState(change);
    _remember();
  }

  String? get _problem => wordsAmountProblem(_amount.text, currency: _currency);

  String? get _words => _amount.text.trim().isEmpty || _problem != null
      ? null
      : amountInWords(_amount.text, language: _language, currency: _currency, only: _only, letters: _case);

  bool get _hasCase => _language != WordsLanguage.ar;

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showMessage(context, 'Copied');
  }

  Future<void> _share(String text) async {
    final r = await sl<ShareService>().shareText(text: text, subject: tr('Amount in words'));
    if (mounted && r.failureOrNull != null) showFailure(context, r.failureOrNull!);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final parsed = parseWordsAmount(_amount.text);
    final problem = _problem;
    final words = _words;
    final rtl = _language == WordsLanguage.ar;
    final figures = parsed == null || problem != null ? null : wordsFigures(parsed, indian: _language == WordsLanguage.enIn);
    // A wrong amount is called out once the field is left, or at once when the problem is the currency.
    final error = problem != null && (_touched || parsed != null) ? tr(problem) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Amount in words')),
      body: SingleChildScrollView(
        padding: contentPadding(context),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.',
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('words-amount'),
              controller: _amount,
              focusNode: _focus,
              maxLength: 20,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]'))],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Amount'),
                hintText: _language == WordsLanguage.enIn ? '1,23,456.50' : '123,456.50',
                helperText: figures == null ? null : '${tr('In figures')}: $figures',
                errorText: error,
                errorMaxLines: 3,
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              key: const ValueKey('words-currency'),
              initialValue: _currency,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Currency')),
              items: [
                for (final c in wordsCurrencies) DropdownMenuItem(value: c.code, child: Text(c.name)),
                const DropdownMenuItem(value: 'none', child: Text('No currency (number only)')),
              ],
              onChanged: (v) => _set(() => _currency = v ?? _currency),
            ),
            const SizedBox(height: AppSpacing.md),
            _label(tr('Language')),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final l in WordsLanguage.values)
                  ChoiceChip(
                    key: ValueKey('words-lang-${l.name}'),
                    selected: _language == l,
                    showCheckmark: false,
                    label: Text(l.label),
                    onSelected: (_) => _set(() => _language = l),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_language != WordsLanguage.de) ...[
              SwitchListTile(
                key: const ValueKey('words-only'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Add the word "Only"'),
                subtitle: const Text('Stops anyone from adding more words after the amount.'),
                value: _only,
                onChanged: (v) => _set(() => _only = v),
              ),
            ],
            if (_hasCase) ...[
              _label(tr('Letters')),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final (c, label) in [(WordsCase.title, 'Capitalised'), (WordsCase.upper, 'UPPERCASE'), (WordsCase.lower, 'lowercase')])
                    ChoiceChip(
                      key: ValueKey('words-case-${c.name}'),
                      selected: _case == c,
                      showCheckmark: false,
                      label: Text(label),
                      onSelected: (_) => _set(() => _case = c),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (words == null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: const Text('Enter an amount to see it in words.', style: TextStyle(color: AppColors.inkMuted)),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label(tr('In words')),
                      SelectableText(
                        words,
                        key: const ValueKey('words-result'),
                        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('words-copy'),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                            onPressed: () => _copy(words),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copy'),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('words-share'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                            onPressed: () => _share(words),
                            icon: const Icon(Icons.ios_share, size: 18),
                            label: const Text('Share'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (rtl) ...[
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Check the Arabic wording with a native speaker before you use it on a legal document.',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
