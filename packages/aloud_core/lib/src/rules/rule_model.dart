/// Where a rule is evaluated.
enum RuleScope {
  /// Each sentence is tested on its own. Supports every action.
  sentence,

  /// The whole paragraph is tested once. Supports skip / stop / next-document
  /// / pauses (text replacement is sentence-scope only so that display and
  /// speech stay aligned).
  paragraph,
}

/// Typographic context a reader can attach to a sentence (EPUB/PDF).
final class SentenceContext {
  const SentenceContext({
    this.italic = false,
    this.bold = false,
    this.larger = false,
    this.smaller = false,
  });

  static const none = SentenceContext();

  final bool italic;
  final bool bold;
  final bool larger;
  final bool smaller;

  bool get different => italic || bold || larger || smaller;
}

// ── Triggers ──────────────────────────────────────────────────────────────

enum StructureKind {
  quotedSpeech,
  allCapsWord,
  headingLike,
  asteriskWrapped,
  urlOrEmail,
  onlySymbols,
  sceneBreak,
  startsWithMarker,
}

enum FontKind { italic, bold, larger, smaller, different }

enum ConditionType {
  containsWord,
  containsAny,
  doesNotContain,
  startsWith,
  endsWith,
  isAllCaps,
  veryShort,
  veryLong,
  containsNumber,
  containsUrlOrEmail,
  onlySymbols,
  startsWithMarker,
}

/// One clause of the no-regex "builder" trigger.
final class RuleCondition {
  const RuleCondition(
    this.type, {
    this.value = '',
    this.or = false,
    this.negated = false,
  });

  final ConditionType type;

  /// Word / comma-list / threshold depending on [type].
  final String value;

  /// Combine with the previous clause using OR instead of AND.
  final bool or;
  final bool negated;

  Map<String, Object?> toJson() =>
      {'type': type.name, 'value': value, 'or': or, 'negated': negated};

  static RuleCondition fromJson(Map<String, Object?> j) => RuleCondition(
        ConditionType.values.asNameMap()[j['type']] ?? ConditionType.containsWord,
        value: (j['value'] as String?) ?? '',
        or: (j['or'] as bool?) ?? false,
        negated: (j['negated'] as bool?) ?? false,
      );
}

/// How a rule recognises text.
sealed class RuleTrigger {
  const RuleTrigger();

  Map<String, Object?> toJson();

  static RuleTrigger fromJson(Map<String, Object?> j) {
    switch (j['kind']) {
      case 'regex':
        return RegexTrigger(
          (j['pattern'] as String?) ?? '',
          caseSensitive: (j['caseSensitive'] as bool?) ?? false,
        );
      case 'structure':
        return StructureTrigger(
          StructureKind.values.asNameMap()[j['structure']] ?? StructureKind.quotedSpeech,
        );
      case 'font':
        return FontTrigger(FontKind.values.asNameMap()[j['font']] ?? FontKind.different);
      case 'conditions':
        return ConditionsTrigger([
          for (final c in (j['conditions'] as List<Object?>? ?? const []))
            RuleCondition.fromJson((c! as Map).cast<String, Object?>()),
        ]);
      default:
        return LiteralTrigger(
          (j['text'] as String?) ?? '',
          wholeWord: (j['wholeWord'] as bool?) ?? false,
          caseSensitive: (j['caseSensitive'] as bool?) ?? false,
        );
    }
  }
}

final class LiteralTrigger extends RuleTrigger {
  const LiteralTrigger(this.text, {this.wholeWord = false, this.caseSensitive = false});
  final String text;
  final bool wholeWord;
  final bool caseSensitive;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'literal',
        'text': text,
        'wholeWord': wholeWord,
        'caseSensitive': caseSensitive,
      };
}

final class RegexTrigger extends RuleTrigger {
  const RegexTrigger(this.pattern, {this.caseSensitive = false});
  final String pattern;
  final bool caseSensitive;

  @override
  Map<String, Object?> toJson() =>
      {'kind': 'regex', 'pattern': pattern, 'caseSensitive': caseSensitive};
}

final class StructureTrigger extends RuleTrigger {
  const StructureTrigger(this.structure);
  final StructureKind structure;

  @override
  Map<String, Object?> toJson() => {'kind': 'structure', 'structure': structure.name};
}

final class FontTrigger extends RuleTrigger {
  const FontTrigger(this.font);
  final FontKind font;

  @override
  Map<String, Object?> toJson() => {'kind': 'font', 'font': font.name};
}

final class ConditionsTrigger extends RuleTrigger {
  const ConditionsTrigger(this.conditions);
  final List<RuleCondition> conditions;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'conditions',
        'conditions': [for (final c in conditions) c.toJson()],
      };
}

// ── Actions ───────────────────────────────────────────────────────────────

/// What a matching rule does.
sealed class RuleAction {
  const RuleAction();

  Map<String, Object?> toJson();

  static RuleAction fromJson(Map<String, Object?> j) {
    switch (j['action']) {
      case 'replace':
        return ReplaceAction((j['with'] as String?) ?? '');
      case 'sayBefore':
        return SayBeforeAction((j['phrase'] as String?) ?? '');
      case 'sayAfter':
        return SayAfterAction((j['phrase'] as String?) ?? '');
      case 'pauseBefore':
        return PauseBeforeAction(((j['ms'] as num?) ?? 0).toInt());
      case 'pauseAfter':
        return PauseAfterAction(((j['ms'] as num?) ?? 0).toInt());
      case 'speedShift':
        return SpeedShiftAction(
          ((j['delta'] as num?) ?? 0).toDouble(),
          restore: (j['restore'] as bool?) ?? true,
        );
      case 'stop':
        return const StopAction();
      case 'nextDocument':
        return const NextDocumentAction();
      default:
        return const SkipAction();
    }
  }
}

/// Don't speak the text. It stays visible on screen.
final class SkipAction extends RuleAction {
  const SkipAction();
  @override
  Map<String, Object?> toJson() => {'action': 'skip'};
}

/// Replace matches (literal/regex triggers) or the whole text (other triggers)
/// with [replacement] before speaking. Empty ⇒ delete; nothing left ⇒ skip.
final class ReplaceAction extends RuleAction {
  const ReplaceAction(this.replacement);
  final String replacement;
  @override
  Map<String, Object?> toJson() => {'action': 'replace', 'with': replacement};
}

final class SayBeforeAction extends RuleAction {
  const SayBeforeAction(this.phrase);
  final String phrase;
  @override
  Map<String, Object?> toJson() => {'action': 'sayBefore', 'phrase': phrase};
}

final class SayAfterAction extends RuleAction {
  const SayAfterAction(this.phrase);
  final String phrase;
  @override
  Map<String, Object?> toJson() => {'action': 'sayAfter', 'phrase': phrase};
}

final class PauseBeforeAction extends RuleAction {
  const PauseBeforeAction(this.ms);
  final int ms;
  @override
  Map<String, Object?> toJson() => {'action': 'pauseBefore', 'ms': ms};
}

final class PauseAfterAction extends RuleAction {
  const PauseAfterAction(this.ms);
  final int ms;
  @override
  Map<String, Object?> toJson() => {'action': 'pauseAfter', 'ms': ms};
}

/// Temporarily change playback speed by [delta] (e.g. `+0.2`).
final class SpeedShiftAction extends RuleAction {
  const SpeedShiftAction(this.delta, {this.restore = true});
  final double delta;

  /// Return to the base speed after this sentence.
  final bool restore;
  @override
  Map<String, Object?> toJson() =>
      {'action': 'speedShift', 'delta': delta, 'restore': restore};
}

/// Stop playback at this point.
final class StopAction extends RuleAction {
  const StopAction();
  @override
  Map<String, Object?> toJson() => {'action': 'stop'};
}

/// Jump to the next chapter/document.
final class NextDocumentAction extends RuleAction {
  const NextDocumentAction();
  @override
  Map<String, Object?> toJson() => {'action': 'nextDocument'};
}

// ── Rule ──────────────────────────────────────────────────────────────────

/// A single user (or built-in) listening rule.
final class SpeechRule {
  const SpeechRule({
    required this.id,
    required this.name,
    required this.trigger,
    required this.action,
    this.scope = RuleScope.sentence,
    this.enabled = true,
    this.priority = 0,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final RuleTrigger trigger;
  final RuleAction action;
  final RuleScope scope;
  final bool enabled;

  /// Lower runs first.
  final int priority;

  /// Seeded from a template (can be reset, not edited in place).
  final bool builtIn;

  SpeechRule copyWith({
    String? name,
    RuleTrigger? trigger,
    RuleAction? action,
    RuleScope? scope,
    bool? enabled,
    int? priority,
  }) =>
      SpeechRule(
        id: id,
        name: name ?? this.name,
        trigger: trigger ?? this.trigger,
        action: action ?? this.action,
        scope: scope ?? this.scope,
        enabled: enabled ?? this.enabled,
        priority: priority ?? this.priority,
        builtIn: builtIn,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'scope': scope.name,
        'enabled': enabled,
        'priority': priority,
        'builtIn': builtIn,
        'trigger': trigger.toJson(),
        'action': action.toJson(),
      };

  static SpeechRule fromJson(Map<String, Object?> j) => SpeechRule(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        scope: RuleScope.values.asNameMap()[j['scope']] ?? RuleScope.sentence,
        enabled: (j['enabled'] as bool?) ?? true,
        priority: ((j['priority'] as num?) ?? 0).toInt(),
        builtIn: (j['builtIn'] as bool?) ?? false,
        trigger: RuleTrigger.fromJson((j['trigger']! as Map).cast<String, Object?>()),
        action: RuleAction.fromJson((j['action']! as Map).cast<String, Object?>()),
      );
}
