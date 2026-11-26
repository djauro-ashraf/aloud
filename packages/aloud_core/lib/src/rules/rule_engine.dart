import '../text/hashing.dart';
import '../text/text_normalizer.dart';
import 'rule_model.dart';

/// Playback-flow instruction produced by a rule.
enum FlowDirective { none, stop, nextDocument }

/// Everything a player needs to speak (or not speak) one sentence.
final class SpeechPlan {
  const SpeechPlan({
    required this.original,
    required this.spoken,
    this.skip = false,
    this.before = const [],
    this.after = const [],
    this.pauseBeforeMs = 0,
    this.pauseAfterMs = 0,
    this.speedDelta = 0,
    this.restoreSpeed = true,
    this.flow = FlowDirective.none,
    this.appliedRuleIds = const [],
  });

  /// Text exactly as shown on screen.
  final String original;

  /// Text after rules and normalisation — what the voice receives.
  final String spoken;

  /// Nothing is spoken. Pauses still apply (e.g. silence at a scene break).
  final bool skip;

  /// Extra phrases spoken before/after the sentence.
  final List<String> before;
  final List<String> after;

  final int pauseBeforeMs;
  final int pauseAfterMs;

  /// Added to the base speed for this sentence.
  final double speedDelta;
  final bool restoreSpeed;
  final FlowDirective flow;
  final List<String> appliedRuleIds;

  /// Full text to synthesise in one go: before + spoken + after.
  String get fullSpeech => [...before, if (!skip) spoken, ...after]
      .where((s) => s.trim().isNotEmpty)
      .join(' ');

  bool get hasSpeech => fullSpeech.trim().isNotEmpty;
}

/// Result of testing a whole paragraph.
final class ParagraphVerdict {
  const ParagraphVerdict({
    this.skip = false,
    this.flow = FlowDirective.none,
    this.pauseBeforeMs = 0,
    this.pauseAfterMs = 0,
  });

  static const pass = ParagraphVerdict();

  final bool skip;
  final FlowDirective flow;
  final int pauseBeforeMs;
  final int pauseAfterMs;
}

/// Evaluates [SpeechRule]s and turns display sentences into [SpeechPlan]s.
///
/// One engine instance is cheap to build; regexes are compiled once in the
/// constructor. Invalid user regexes never throw — they simply never match
/// (use [validateRegex] in the editor to show the error).
final class RuleEngine {
  RuleEngine(
    Iterable<SpeechRule> rules, {
    this.normalizer = const NormalizerOptions(),
    this.normalize = true,
  }) : _rules = _compile(rules);

  /// An engine with no rules (normaliser only).
  RuleEngine.empty({
    this.normalizer = const NormalizerOptions(),
    this.normalize = true,
  }) : _rules = const [];

  final NormalizerOptions normalizer;
  final bool normalize;
  final List<_Compiled> _rules;

  /// Stable identity of everything that changes the spoken output. Part of
  /// every audio-cache key.
  String get fingerprint => fingerprintOf(
        [for (final c in _rules) c.rule],
        normalizer: normalizer,
        normalize: normalize,
      );

  static String fingerprintOf(
    Iterable<SpeechRule> rules, {
    NormalizerOptions normalizer = const NormalizerOptions(),
    bool normalize = true,
  }) {
    final active = rules.where((r) => r.enabled).toList()
      ..sort(_byPriority);
    final b = StringBuffer(TextNormalizer.version)
      ..write('|${normalize ? normalizer.fingerprint : 'raw'}');
    for (final r in active) {
      b
        ..write('|')
        ..write(r.scope.name)
        ..write(r.trigger.toJson())
        ..write(r.action.toJson());
    }
    return Hashing.hex64(b.toString());
  }

  /// Returns an error message for an invalid regex, or `null` if it compiles.
  static String? validateRegex(String pattern) {
    if (pattern.isEmpty) return 'Pattern is empty';
    try {
      RegExp(pattern);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  // ── Paragraph level ────────────────────────────────────────────────────

  ParagraphVerdict checkParagraph(String paragraph, {SentenceContext context = SentenceContext.none}) {
    var skip = false;
    var flow = FlowDirective.none;
    var before = 0;
    var after = 0;
    for (final c in _rules) {
      if (c.rule.scope != RuleScope.paragraph) continue;
      if (!c.matches(paragraph, context)) continue;
      switch (c.rule.action) {
        case SkipAction():
          skip = true;
        case StopAction():
          if (flow == FlowDirective.none) flow = FlowDirective.stop;
        case NextDocumentAction():
          if (flow == FlowDirective.none) flow = FlowDirective.nextDocument;
        case PauseBeforeAction(:final ms):
          if (ms > before) before = ms;
        case PauseAfterAction(:final ms):
          if (ms > after) after = ms;
        default:
          break;
      }
    }
    if (!skip && flow == FlowDirective.none && before == 0 && after == 0) {
      return ParagraphVerdict.pass;
    }
    return ParagraphVerdict(skip: skip, flow: flow, pauseBeforeMs: before, pauseAfterMs: after);
  }

  // ── Sentence level ─────────────────────────────────────────────────────

  SpeechPlan plan(String sentence, {SentenceContext context = SentenceContext.none}) {
    final original = sentence.trim();
    if (original.isEmpty) {
      return const SpeechPlan(original: '', spoken: '', skip: true);
    }

    var current = original;
    var skip = false;
    var replaced = false;
    final before = <String>[];
    final after = <String>[];
    var pauseBefore = 0;
    var pauseAfter = 0;
    var speed = 0.0;
    var restore = true;
    var flow = FlowDirective.none;
    final applied = <String>[];

    for (final c in _rules) {
      if (c.rule.scope != RuleScope.sentence) continue;
      if (!c.matches(current, context)) continue;
      applied.add(c.rule.id);
      switch (c.rule.action) {
        case SkipAction():
          skip = true;
        case ReplaceAction(:final replacement):
          current = c.replace(current, replacement);
          replaced = true;
        case SayBeforeAction(:final phrase):
          if (phrase.trim().isNotEmpty && !before.contains(phrase)) before.add(phrase);
        case SayAfterAction(:final phrase):
          if (phrase.trim().isNotEmpty && !after.contains(phrase)) after.add(phrase);
        case PauseBeforeAction(:final ms):
          if (ms > pauseBefore) pauseBefore = ms;
        case PauseAfterAction(:final ms):
          if (ms > pauseAfter) pauseAfter = ms;
        case SpeedShiftAction(:final delta, restore: final r):
          speed += delta;
          restore = restore && r;
        case StopAction():
          if (flow == FlowDirective.none) flow = FlowDirective.stop;
        case NextDocumentAction():
          if (flow == FlowDirective.none) flow = FlowDirective.nextDocument;
      }
    }

    var spoken = current.trim();
    if (replaced && spoken.isEmpty) skip = true;
    if (!skip && normalize) {
      spoken = TextNormalizer.normalize(spoken, options: normalizer);
    }
    // Nothing pronounceable (e.g. "***", "—") is never sent to a voice.
    if (!_hasSpeakable(spoken)) skip = true;

    return SpeechPlan(
      original: original,
      spoken: skip ? '' : spoken,
      skip: skip,
      before: List.unmodifiable(before),
      after: List.unmodifiable(after),
      pauseBeforeMs: pauseBefore,
      pauseAfterMs: pauseAfter,
      speedDelta: speed,
      restoreSpeed: restore,
      flow: flow,
      appliedRuleIds: List.unmodifiable(applied),
    );
  }

  static final _speakable = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static bool _hasSpeakable(String s) => _speakable.hasMatch(s);

  static int _byPriority(SpeechRule a, SpeechRule b) {
    final p = a.priority.compareTo(b.priority);
    return p != 0 ? p : a.id.compareTo(b.id);
  }

  static List<_Compiled> _compile(Iterable<SpeechRule> rules) {
    final list = [
      for (final r in rules)
        if (r.enabled) r,
    ];
    // Stable by priority, keeping insertion order for equal priorities.
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])]
      ..sort((a, b) {
        final p = a.$2.priority.compareTo(b.$2.priority);
        return p != 0 ? p : a.$1.compareTo(b.$1);
      });
    return [for (final (_, r) in indexed) _Compiled(r)];
  }
}

// ── Compiled matcher ──────────────────────────────────────────────────────

final class _Compiled {
  _Compiled(this.rule) : _rx = _regexFor(rule.trigger);

  final SpeechRule rule;
  final RegExp? _rx;

  static final _quoted = RegExp('["“”][^"“”]+["“”]');
  static final _allCaps = RegExp(r'\b[A-Z]{2,}\b');
  static final _asterisk = RegExp(r'\*[^*\n]+\*');
  static final _urlEmail = RegExp(
    r'(?:https?://|www\.)\S+|[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );
  static final _wordSplit = RegExp(r'\s+');
  static const _markerStarts = {'[', '(', '{', '*', '-', '—', '–', '•', '※', '#', '~'};
  static const _breakChars = '*-_~#=•·◆◇◊—–';

  static RegExp? _regexFor(RuleTrigger t) {
    try {
      switch (t) {
        case LiteralTrigger(:final text, :final wholeWord, :final caseSensitive):
          if (text.isEmpty) return null;
          if (!wholeWord) return RegExp(RegExp.escape(text), caseSensitive: caseSensitive);
          return RegExp(
            '(?<![\\p{L}\\p{N}_])${RegExp.escape(text)}(?![\\p{L}\\p{N}_])',
            caseSensitive: caseSensitive,
            unicode: true,
          );
        case RegexTrigger(:final pattern, :final caseSensitive):
          if (pattern.isEmpty) return null;
          return RegExp(pattern, caseSensitive: caseSensitive, unicode: true);
        default:
          return null;
      }
    } on FormatException {
      return null;
    }
  }

  bool matches(String text, SentenceContext ctx) {
    switch (rule.trigger) {
      case LiteralTrigger() || RegexTrigger():
        return _rx?.hasMatch(text) ?? false;
      case StructureTrigger(:final structure):
        return _structure(structure, text);
      case FontTrigger(:final font):
        return switch (font) {
          FontKind.italic => ctx.italic,
          FontKind.bold => ctx.bold,
          FontKind.larger => ctx.larger,
          FontKind.smaller => ctx.smaller,
          FontKind.different => ctx.different,
        };
      case ConditionsTrigger(:final conditions):
        return _conditions(text, conditions);
    }
  }

  /// Applies a replacement: regex/literal triggers replace each match, every
  /// other trigger replaces the whole text.
  String replace(String text, String replacement) {
    final rx = _rx;
    if (rx != null) return text.replaceAll(rx, replacement);
    return replacement;
  }

  bool _structure(StructureKind kind, String text) {
    final t = text.trim();
    switch (kind) {
      case StructureKind.quotedSpeech:
        return _quoted.hasMatch(t);
      case StructureKind.allCapsWord:
        return _allCaps.hasMatch(t);
      case StructureKind.headingLike:
        if (t.length < 2 || t.length > 60) return false;
        final first = t[0];
        if (first == first.toLowerCase() && first != first.toUpperCase()) return false;
        return !'.!?,;:"”'.contains(t[t.length - 1]);
      case StructureKind.asteriskWrapped:
        return _asterisk.hasMatch(t);
      case StructureKind.urlOrEmail:
        return _urlEmail.hasMatch(t);
      case StructureKind.onlySymbols:
        return _onlySymbols(t);
      case StructureKind.sceneBreak:
        final s = t.replaceAll(RegExp(r'\s'), '');
        if (s.length < 3) return false;
        return s.split('').every(_breakChars.contains);
      case StructureKind.startsWithMarker:
        return t.isNotEmpty && _markerStarts.contains(t[0]);
    }
  }

  static bool _onlySymbols(String t) {
    final s = t.replaceAll(RegExp(r'\s'), '');
    return s.isNotEmpty && !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s);
  }

  bool _conditions(String text, List<RuleCondition> conditions) {
    bool? acc;
    for (final c in conditions) {
      var v = _condition(text, c);
      if (c.negated) v = !v;
      acc = acc == null ? v : (c.or ? (acc || v) : (acc && v));
    }
    return acc ?? false;
  }

  bool _condition(String text, RuleCondition c) {
    final v = c.value.trim();
    final t = text.trim();
    final lower = t.toLowerCase();
    switch (c.type) {
      case ConditionType.containsWord:
        if (v.isEmpty) return false;
        return RegExp(
          '(?<![\\p{L}\\p{N}_])${RegExp.escape(v)}(?![\\p{L}\\p{N}_])',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(t);
      case ConditionType.containsAny:
        return v
            .split(',')
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .any(lower.contains);
      case ConditionType.doesNotContain:
        return v.isNotEmpty && !lower.contains(v.toLowerCase());
      case ConditionType.startsWith:
        return v.isNotEmpty && lower.startsWith(v.toLowerCase());
      case ConditionType.endsWith:
        return v.isNotEmpty && lower.endsWith(v.toLowerCase());
      case ConditionType.isAllCaps:
        final letters = t.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
        return letters.isNotEmpty && letters == letters.toUpperCase() && letters != letters.toLowerCase();
      case ConditionType.veryShort:
        return _words(t) < (int.tryParse(v) ?? 6);
      case ConditionType.veryLong:
        return _words(t) > (int.tryParse(v) ?? 80);
      case ConditionType.containsNumber:
        return RegExp(r'\d').hasMatch(t);
      case ConditionType.containsUrlOrEmail:
        return _urlEmail.hasMatch(t);
      case ConditionType.onlySymbols:
        return _onlySymbols(t);
      case ConditionType.startsWithMarker:
        return t.isNotEmpty && _markerStarts.contains(t[0]);
    }
  }

  static int _words(String t) =>
      t.trim().split(_wordSplit).where((w) => w.isNotEmpty).length;
}
