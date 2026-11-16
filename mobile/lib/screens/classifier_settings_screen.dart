import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/ai_settings.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';

/// The classifier's settings, grouped as on the web, in the order of
/// `Family::BayesSettings::DEFAULTS`. Keys the server adds later land in
/// "Other" under their own name.
const List<(String group, List<String> keys)> classifierSettingGroups = [
  ('training', [
    'skip_self_labels',
    'self_label_grace_days',
    'exclude_transfers',
    'max_training_transactions',
  ]),
  ('words', [
    'include_notes',
    'word_split',
    'drop_numbers',
    'keep_single_chars',
    'drop_codes',
    'spread_filter',
    'spread_margin',
    'bigrams',
    'binary',
    'merchant_name_words',
  ]),
  ('amount', ['amount_field', 'amount_by_direction']),
  ('account_merchant', ['account_field', 'merchant_field']),
  ('matcher', [
    'lock_similar_merchants',
    'similar_threshold',
    'similar_min_neighbours',
    'similar_common_share',
    'similar_skip_self',
    'similar_self_grace_days',
  ]),
  ('scoring', ['complement', 'smoothing', 'prior', 'separate_fields']),
  ('classifier', ['threshold', 'lock_results']),
];

String _groupLabel(AppLocalizations l, String group) => switch (group) {
      'training' => l.s4sClsTraining,
      'words' => l.s4sClsWords,
      'amount' => l.s4sClsAmount,
      'account_merchant' => l.s4sClsAccountMerchant,
      'matcher' => l.s4sClsMatcher,
      'scoring' => l.s4sClsScoring,
      'classifier' => l.s4sClsClassifier,
      _ => l.s4sClsOther,
    };

/// The plain label of a setting; an unknown key reads as its words.
String classifierSettingLabel(AppLocalizations l, String key) => switch (key) {
      'skip_self_labels' => l.s4sClsSkipSelfLabels,
      'self_label_grace_days' => l.s4sClsSelfLabelGraceDays,
      'exclude_transfers' => l.s4sClsExcludeTransfers,
      'max_training_transactions' => l.s4sClsMaxTraining,
      'include_notes' => l.s4sClsIncludeNotes,
      'word_split' => l.s4sClsWordSplit,
      'drop_numbers' => l.s4sClsDropNumbers,
      'keep_single_chars' => l.s4sClsKeepSingleChars,
      'drop_codes' => l.s4sClsDropCodes,
      'spread_filter' => l.s4sClsSpreadFilter,
      'spread_margin' => l.s4sClsSpreadMargin,
      'bigrams' => l.s4sClsBigrams,
      'merchant_name_words' => l.s4sClsMerchantNameWords,
      'amount_field' => l.s4sClsAmountField,
      'amount_by_direction' => l.s4sClsAmountByDirection,
      'account_field' => l.s4sClsAccountField,
      'merchant_field' => l.s4sClsMerchantField,
      'lock_similar_merchants' => l.s4sClsLockSimilarMerchants,
      'similar_threshold' => l.s4sClsSimilarThreshold,
      'similar_min_neighbours' => l.s4sClsSimilarMinNeighbours,
      'similar_common_share' => l.s4sClsSimilarCommonShare,
      'similar_skip_self' => l.s4sClsSimilarSkipSelf,
      'similar_self_grace_days' => l.s4sClsSimilarSelfGraceDays,
      'complement' => l.s4sClsComplement,
      'smoothing' => l.s4sClsSmoothing,
      'prior' => l.s4sClsPrior,
      'binary' => l.s4sClsBinary,
      'separate_fields' => l.s4sClsSeparateFields,
      'threshold' => l.s4sClsThreshold,
      'lock_results' => l.s4sClsLockResults,
      _ => key.isEmpty
          ? key
          : '${key[0].toUpperCase()}${key.substring(1).replaceAll('_', ' ')}',
    };

String _choiceLabel(AppLocalizations l, String key, String choice) =>
    switch ((key, choice)) {
      ('word_split', 'ascii') => l.s4sClsWordSplitAscii,
      ('word_split', 'unicode') => l.s4sClsWordSplitUnicode,
      ('word_split', 'symbols') => l.s4sClsWordSplitSymbols,
      _ => choice,
    };

/// How a numeric setting is edited: a slider for fractions (span up to 1),
/// else a stepper. [step] is the slider's or stepper's increment.
@visibleForTesting
({bool slider, num step}) classifierNumberControl(
    SettingRange range, bool integer) {
  final span = range.max - range.min;
  if (!integer && span <= 1) return (slider: true, step: 0.01);
  if (!integer) return (slider: false, step: 0.1);
  if (span <= 20) return (slider: false, step: 1);
  // Roughly a hundredth of the range, rounded to a familiar number.
  const steps = [5, 10, 30, 100, 500, 1000];
  num step = 1;
  for (final s in steps) {
    if (s <= span / 100) step = s;
  }
  return (slider: false, step: step);
}

/// Classifier settings built from the server's `settings`, `ranges` and
/// `choices`: switches for true/false, a picker for choices, sliders and
/// steppers for numbers. Each change is saved through [onSave], which
/// returns the saved settings or null on failure (the caller says why);
/// a failure puts the old value back.
class ClassifierSettingsScreen extends StatefulWidget {
  const ClassifierSettingsScreen({
    super.key,
    required this.initial,
    required this.onSave,
    this.saveDelay = const Duration(milliseconds: 600),
  });

  final ClassifierSettings initial;
  final Future<ClassifierSettings?> Function(Map<String, dynamic> settings)
      onSave;

  /// How long a stepper waits for more taps before saving.
  final Duration saveDelay;

  @override
  State<ClassifierSettingsScreen> createState() =>
      _ClassifierSettingsScreenState();
}

class _ClassifierSettingsScreenState extends State<ClassifierSettingsScreen> {
  late ClassifierSettings _saved;
  late Map<String, dynamic> _values;
  final Map<String, Timer> _pending = {};

  @override
  void initState() {
    super.initState();
    _saved = widget.initial;
    _values = Map.of(widget.initial.settings);
  }

  @override
  void dispose() {
    // Save what a stepper was still waiting on.
    for (final entry in _pending.entries) {
      entry.value.cancel();
      widget.onSave({entry.key: _values[entry.key]});
    }
    super.dispose();
  }

  Future<void> _save(String key, dynamic value) async {
    final result = await widget.onSave({key: value});
    if (!mounted) return;
    setState(() {
      if (result != null) {
        _saved = result;
        _values[key] = result.settings[key];
      } else {
        _values[key] = _saved.settings[key];
      }
    });
  }

  void _set(String key, dynamic value, {bool debounce = false}) {
    setState(() => _values[key] = value);
    _pending.remove(key)?.cancel();
    if (!debounce) {
      _save(key, value);
      return;
    }
    _pending[key] = Timer(widget.saveDelay, () {
      _pending.remove(key);
      _save(key, _values[key]);
    });
  }

  Widget? _row(BuildContext context, String key) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final value = _values[key];
    final label = classifierSettingLabel(l, key);
    final choices = _saved.choices[key];
    final range = _saved.ranges[key];

    if (value is bool) {
      return SureListRow(
        key: ValueKey('cls-$key'),
        title: label,
        trailing: Switch.adaptive(
          value: value,
          activeTrackColor: palette.success,
          onChanged: (v) => _set(key, v),
        ),
      );
    }
    if (choices != null && value is String) {
      return SureListRow(
        key: ValueKey('cls-$key'),
        title: label,
        value: _choiceLabel(l, key, value),
        showChevron: true,
        onTap: () async {
          final picked = await showManageOptionSheet<String>(
            context,
            title: label,
            options: [for (final c in choices) (c, _choiceLabel(l, key, c))],
            selected: value,
          );
          if (picked != null && picked.value != value && mounted) {
            _set(key, picked.value);
          }
        },
      );
    }
    if (value is num && range != null) {
      final defaultValue = _saved.defaults[key];
      final integer = value is int && (defaultValue == null || defaultValue is int);
      final control = classifierNumberControl(range, integer);
      return _NumberRow(
        key: ValueKey('cls-$key'),
        label: label,
        value: value,
        range: range,
        integer: integer,
        slider: control.slider,
        step: control.step,
        onChanged: control.slider
            ? (v) => setState(() => _values[key] = v)
            : (v) => _set(key, v, debounce: true),
        onChangeEnd: control.slider ? (v) => _set(key, v) : null,
      );
    }
    // Lists (excluded categories) and anything unexpected stay on the web.
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final known = {for (final (_, keys) in classifierSettingGroups) ...keys};
    final other = [
      for (final key in _values.keys)
        if (!known.contains(key)) key,
    ];
    final groups = [
      ...classifierSettingGroups,
      if (other.isNotEmpty) ('other', other),
    ];

    return SureLargeTitleScaffold(
      title: l.s4sClsTitle,
      leading: SureBackButton(label: l.s4sAiTitle),
      slivers: [
        SliverList.list(
          children: [
            for (final (group, keys) in groups)
              ...() {
                final rows = [
                  for (final key in keys)
                    if (_values.containsKey(key)) _row(context, key),
                ].whereType<Widget>().toList();
                if (rows.isEmpty) return const <Widget>[];
                return [
                  SureSectionHeader(label: _groupLabel(l, group)),
                  SurePanel.rows(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    children: rows,
                  ),
                ];
              }(),
            const SizedBox(height: SureSpacing.lg),
          ],
        ),
      ],
    );
  }
}

/// A numeric setting: the label and value on one line, then a slider or a
/// −/+ stepper, and the allowed range.
class _NumberRow extends StatelessWidget {
  const _NumberRow({
    super.key,
    required this.label,
    required this.value,
    required this.range,
    required this.integer,
    required this.slider,
    required this.step,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final num value;
  final SettingRange range;
  final bool integer;
  final bool slider;
  final num step;
  final ValueChanged<num> onChanged;
  final ValueChanged<num>? onChangeEnd;

  int get _decimals {
    if (integer) return 0;
    var d = 0;
    for (final n in [step, range.min, range.max]) {
      final text = n.toString();
      final dot = text.indexOf('.');
      if (dot >= 0) {
        final trimmed = text.substring(dot + 1).replaceAll(RegExp(r'0+$'), '');
        if (trimmed.length > d) d = trimmed.length;
      }
    }
    return d.clamp(1, 3);
  }

  num _clamp(num v) {
    final clamped = v.clamp(range.min, range.max);
    if (integer) return clamped.round();
    const factor = 1000;
    return (clamped * factor).round() / factor;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final format = NumberFormat.decimalPatternDigits(
        locale: locale, decimalDigits: _decimals);
    final mono = SureMoney.tabular(TextStyle(
      fontFamily: SureTokens.fontMono,
      fontFamilyFallback: const <String>['Menlo', 'monospace'],
      fontSize: 15,
      color: palette.textSecondary,
    ));

    Widget stepButton(String icon, String semantic, num next, bool enabled) =>
        IconButton(
          tooltip: semantic,
          onPressed: enabled ? () => onChanged(_clamp(next)) : null,
          icon: SureIcon(icon,
              size: 18,
              color: enabled ? palette.link : palette.textSubdued),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (slider) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(format.format(value), style: mono),
                ),
              ] else ...[
                stepButton(SureIcons.minus, l.s4sClsDecrease, value - step,
                    value > range.min),
                Text(format.format(value), style: mono),
                stepButton(SureIcons.plus, l.s4sClsIncrease, value + step,
                    value < range.max),
              ],
            ],
          ),
          if (slider)
            Slider.adaptive(
              value: value.toDouble().clamp(
                  range.min.toDouble(), range.max.toDouble()),
              min: range.min.toDouble(),
              max: range.max.toDouble(),
              divisions:
                  ((range.max - range.min) / step).round().clamp(1, 1000),
              activeColor: palette.link,
              onChanged: (v) => onChanged(_clamp(v)),
              onChangeEnd:
                  onChangeEnd == null ? null : (v) => onChangeEnd!(_clamp(v)),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Text(
              l.s4sClsRange(format.format(range.min), format.format(range.max)),
              style: TextStyle(fontSize: 12, color: palette.textSubdued),
            ),
          ),
        ],
      ),
    );
  }
}
