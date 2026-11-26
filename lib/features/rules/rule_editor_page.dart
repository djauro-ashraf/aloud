import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/ui/widgets.dart';
import '../../core/util/ids.dart';
import 'rules_page.dart';
import 'rules_text.dart';

enum _TriggerKind {
  literal('Text'),
  regex('Pattern'),
  structure('Shape'),
  font('Formatting'),
  conditions('Conditions');

  const _TriggerKind(this.label);
  final String label;
}

enum _ActionKind {
  skip('Skip it'),
  replace('Say something else'),
  sayBefore('Say a phrase before'),
  sayAfter('Say a phrase after'),
  pauseBefore('Pause before'),
  pauseAfter('Pause after'),
  speed('Change speed'),
  stop('Stop playback'),
  next('Jump to next chapter');

  const _ActionKind(this.label);
  final String label;
}

/// Create or edit one rule. Rules read as sentences: "When a sentence
/// [contains “patreon”], then [skip it]."
class RuleEditorPage extends ConsumerStatefulWidget {
  const RuleEditorPage({super.key, this.ruleId});

  final String? ruleId;

  @override
  ConsumerState<RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends ConsumerState<RuleEditorPage> {
  SpeechRule? _existing;
  bool _loaded = false;

  final _name = TextEditingController();
  final _text = TextEditingController();
  final _pattern = TextEditingController();
  final _phrase = TextEditingController();
  RuleScope _scope = RuleScope.sentence;
  _TriggerKind _tKind = _TriggerKind.literal;
  bool _whole = false;
  bool _case = false;
  StructureKind _structure = StructureKind.quotedSpeech;
  FontKind _font = FontKind.italic;
  List<RuleCondition> _conds = [const RuleCondition(ConditionType.containsWord)];
  _ActionKind _aKind = _ActionKind.skip;
  double _ms = 500;
  double _delta = -0.1;
  bool _restore = true;

  @override
  void initState() {
    super.initState();
    if (widget.ruleId == null) {
      _loaded = true;
    } else {
      ref.read(servicesProvider).rules.all().then((all) {
        final r = all.where((x) => x.id == widget.ruleId).firstOrNull;
        if (!mounted) return;
        setState(() {
          _loaded = true;
          if (r != null) _fill(r);
        });
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    _pattern.dispose();
    _phrase.dispose();
    super.dispose();
  }

  void _fill(SpeechRule r) {
    _existing = r;
    _name.text = r.name;
    _scope = r.scope;
    switch (r.trigger) {
      case LiteralTrigger(:final text, :final wholeWord, :final caseSensitive):
        _tKind = _TriggerKind.literal;
        _text.text = text;
        _whole = wholeWord;
        _case = caseSensitive;
      case RegexTrigger(:final pattern, :final caseSensitive):
        _tKind = _TriggerKind.regex;
        _pattern.text = pattern;
        _case = caseSensitive;
      case StructureTrigger(:final structure):
        _tKind = _TriggerKind.structure;
        _structure = structure;
      case FontTrigger(:final font):
        _tKind = _TriggerKind.font;
        _font = font;
      case ConditionsTrigger(:final conditions):
        _tKind = _TriggerKind.conditions;
        _conds = [...conditions];
    }
    switch (r.action) {
      case SkipAction():
        _aKind = _ActionKind.skip;
      case ReplaceAction(:final replacement):
        _aKind = _ActionKind.replace;
        _phrase.text = replacement;
      case SayBeforeAction(:final phrase):
        _aKind = _ActionKind.sayBefore;
        _phrase.text = phrase;
      case SayAfterAction(:final phrase):
        _aKind = _ActionKind.sayAfter;
        _phrase.text = phrase;
      case PauseBeforeAction(:final ms):
        _aKind = _ActionKind.pauseBefore;
        _ms = ms.toDouble();
      case PauseAfterAction(:final ms):
        _aKind = _ActionKind.pauseAfter;
        _ms = ms.toDouble();
      case SpeedShiftAction(:final delta, :final restore):
        _aKind = _ActionKind.speed;
        _delta = delta;
        _restore = restore;
      case StopAction():
        _aKind = _ActionKind.stop;
      case NextDocumentAction():
        _aKind = _ActionKind.next;
    }
  }

  RuleTrigger _trigger() => switch (_tKind) {
        _TriggerKind.literal => LiteralTrigger(_text.text, wholeWord: _whole, caseSensitive: _case),
        _TriggerKind.regex => RegexTrigger(_pattern.text, caseSensitive: _case),
        _TriggerKind.structure => StructureTrigger(_structure),
        _TriggerKind.font => FontTrigger(_font),
        _TriggerKind.conditions => ConditionsTrigger(_conds),
      };

  RuleAction _action() => switch (_aKind) {
        _ActionKind.skip => const SkipAction(),
        _ActionKind.replace => ReplaceAction(_phrase.text),
        _ActionKind.sayBefore => SayBeforeAction(_phrase.text),
        _ActionKind.sayAfter => SayAfterAction(_phrase.text),
        _ActionKind.pauseBefore => PauseBeforeAction(_ms.round()),
        _ActionKind.pauseAfter => PauseAfterAction(_ms.round()),
        _ActionKind.speed => SpeedShiftAction(_delta, restore: _restore),
        _ActionKind.stop => const StopAction(),
        _ActionKind.next => const NextDocumentAction(),
      };

  String? _validate() {
    switch (_tKind) {
      case _TriggerKind.literal:
        if (_text.text.isEmpty) return 'Enter the text to look for.';
      case _TriggerKind.regex:
        final e = RuleEngine.validateRegex(_pattern.text);
        if (e != null) return 'Pattern problem: $e';
      case _TriggerKind.conditions:
        if (_conds.isEmpty) return 'Add at least one condition.';
      case _TriggerKind.structure || _TriggerKind.font:
        break;
    }
    if ((_aKind == _ActionKind.sayBefore || _aKind == _ActionKind.sayAfter) && _phrase.text.trim().isEmpty) {
      return 'Enter the phrase to say.';
    }
    if (_scope == RuleScope.paragraph && _aKind == _ActionKind.replace) {
      return 'Replacing text works on sentences. Switch the scope to “Sentence”.';
    }
    return null;
  }

  SpeechRule _build() {
    final base = _existing;
    final auto = '${_aKind.label}: ${RulesText.trigger(_trigger())}';
    return SpeechRule(
      id: base?.id ?? newId(),
      name: _name.text.trim().isEmpty ? auto : _name.text.trim(),
      scope: _scope,
      trigger: _trigger(),
      action: _action(),
      enabled: base?.enabled ?? true,
      priority: base?.priority ?? 1000,
      builtIn: base?.builtIn ?? false,
    );
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      context.snack(err);
      return;
    }
    await ref.read(servicesProvider).rules.upsert(_build());
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final regexError = _tKind == _TriggerKind.regex && _pattern.text.isNotEmpty ? RuleEngine.validateRegex(_pattern.text) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'New rule' : 'Edit rule'),
        actions: [
          TextButton(
            onPressed: () {
              final err = _validate();
              if (err != null) return context.snack(err);
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => RuleTester(extraRule: _build()),
              );
            },
            child: const Text('Test'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (optional)')),
          const SectionLabel('When'),
          SegmentedButton<RuleScope>(
            segments: const [
              ButtonSegment(value: RuleScope.sentence, label: Text('A sentence')),
              ButtonSegment(value: RuleScope.paragraph, label: Text('A paragraph')),
            ],
            selected: {_scope},
            onSelectionChanged: (v) => setState(() => _scope = v.first),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<_TriggerKind>(
            initialValue: _tKind,
            decoration: const InputDecoration(labelText: 'matches by'),
            items: [for (final k in _TriggerKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
            onChanged: (v) => setState(() => _tKind = v ?? _tKind),
          ),
          const SizedBox(height: 12),
          ..._triggerFields(regexError),
          const SectionLabel('Then'),
          DropdownButtonFormField<_ActionKind>(
            initialValue: _aKind,
            decoration: const InputDecoration(labelText: 'Action'),
            items: [for (final k in _ActionKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
            onChanged: (v) => setState(() => _aKind = v ?? _aKind),
          ),
          const SizedBox(height: 12),
          ..._actionFields(),
        ],
      ),
    );
  }

  List<Widget> _triggerFields(String? regexError) {
    switch (_tKind) {
      case _TriggerKind.literal:
        return [
          TextField(controller: _text, decoration: const InputDecoration(labelText: 'Contains this text')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Whole word only'), value: _whole, onChanged: (v) => setState(() => _whole = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Match case'), value: _case, onChanged: (v) => setState(() => _case = v)),
        ];
      case _TriggerKind.regex:
        return [
          TextField(
            controller: _pattern,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Regular expression', errorText: regexError, helperText: r'Example: \[\d+\]'),
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Match case'), value: _case, onChanged: (v) => setState(() => _case = v)),
        ];
      case _TriggerKind.structure:
        return [
          DropdownButtonFormField<StructureKind>(
            initialValue: _structure,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Shape'),
            items: [for (final e in RulesText.structureLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _structure = v ?? _structure),
          ),
        ];
      case _TriggerKind.font:
        return [
          DropdownButtonFormField<FontKind>(
            initialValue: _font,
            decoration: const InputDecoration(labelText: 'Formatting'),
            items: [for (final e in RulesText.fontLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _font = v ?? _font),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Available for EPUB and web pages, which keep formatting.'),
          ),
        ];
      case _TriggerKind.conditions:
        return [
          for (var i = 0; i < _conds.length; i++) _conditionRow(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _conds = [..._conds, const RuleCondition(ConditionType.containsWord)]),
              icon: const Icon(Icons.add),
              label: const Text('Add condition'),
            ),
          ),
        ];
    }
  }

  Widget _conditionRow(int i) {
    final c = _conds[i];
    void update(RuleCondition next) => setState(() => _conds = [..._conds]..[i] = next);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (i > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('AND')),
                    ButtonSegment(value: true, label: Text('OR')),
                  ],
                  selected: {c.or},
                  onSelectionChanged: (v) => update(RuleCondition(c.type, value: c.value, or: v.first, negated: c.negated)),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ConditionType>(
                    initialValue: c.type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'The text'),
                    items: [for (final e in RulesText.conditionLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => update(RuleCondition(v ?? c.type, value: c.value, or: c.or, negated: c.negated)),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: _conds.length <= 1 ? null : () => setState(() => _conds = [..._conds]..removeAt(i)),
                ),
              ],
            ),
            if (RulesText.needsValue.contains(c.type))
              TextFormField(
                initialValue: c.value,
                decoration: const InputDecoration(labelText: 'Value'),
                onChanged: (v) => _conds[i] = RuleCondition(c.type, value: v, or: c.or, negated: c.negated),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Invert (NOT)'),
              value: c.negated,
              onChanged: (v) => update(RuleCondition(c.type, value: c.value, or: c.or, negated: v)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actionFields() {
    switch (_aKind) {
      case _ActionKind.replace:
        return [
          TextField(
            controller: _phrase,
            decoration: const InputDecoration(
              labelText: 'Say this instead',
              helperText: 'Leave empty to remove the matched text. Text/Pattern rules replace only the match.',
            ),
          ),
        ];
      case _ActionKind.sayBefore || _ActionKind.sayAfter:
        return [TextField(controller: _phrase, decoration: const InputDecoration(labelText: 'Phrase'))];
      case _ActionKind.pauseBefore || _ActionKind.pauseAfter:
        return [
          SliderTile(
            title: 'Pause length',
            value: _ms,
            min: 100,
            max: 3000,
            divisions: 29,
            label: '${_ms.round()} ms',
            onChanged: (v) => setState(() => _ms = v),
          ),
        ];
      case _ActionKind.speed:
        return [
          SliderTile(
            title: 'Speed change',
            value: _delta,
            min: -0.5,
            max: 0.5,
            divisions: 20,
            label: '${_delta >= 0 ? '+' : ''}${(_delta * 100).round()}%',
            onChanged: (v) => setState(() => _delta = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Return to normal after this sentence'),
            value: _restore,
            onChanged: (v) => setState(() => _restore = v),
          ),
        ];
      case _ActionKind.skip || _ActionKind.stop || _ActionKind.next:
        return const [];
    }
  }
}
