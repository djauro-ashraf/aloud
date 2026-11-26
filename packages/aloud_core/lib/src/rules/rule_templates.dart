import 'rule_model.dart';

/// A ready-made rule offered in the template gallery.
final class RuleTemplate {
  const RuleTemplate({
    required this.category,
    required this.title,
    required this.description,
    required this.rule,
    this.defaultOn = false,
  });

  final String category;
  final String title;
  final String description;
  final SpeechRule rule;

  /// Installed (enabled) on first run.
  final bool defaultOn;
}

/// Built-in templates. Ids are stable (`tpl.*`) so a template can be
/// re-installed or reset without creating duplicates.
abstract final class RuleTemplates {
  static const _clean = 'Clean up';
  static const _comfort = 'Listening comfort';
  static const _flow = 'Flow';
  static const _voice = 'Pronunciation';

  static const all = <RuleTemplate>[
    RuleTemplate(
      category: _clean,
      title: "Skip author's notes",
      description: 'Paragraphs that start an author note (A/N, Author\'s Note).',
      defaultOn: true,
      rule: SpeechRule(
        id: 'tpl.skip_author_note',
        name: "Skip author's notes",
        scope: RuleScope.paragraph,
        builtIn: true,
        trigger: RegexTrigger(r"^\s*[\[(]?\s*(?:author'?s?\s+note|a/?n)\s*[:\])]", caseSensitive: false),
        action: SkipAction(),
      ),
    ),
    RuleTemplate(
      category: _clean,
      title: "Skip translator's notes",
      description: 'Paragraphs that start a translator note (T/N, Translator\'s Note).',
      defaultOn: true,
      rule: SpeechRule(
        id: 'tpl.skip_translator_note',
        name: "Skip translator's notes",
        scope: RuleScope.paragraph,
        builtIn: true,
        trigger: RegexTrigger(r"^\s*[\[(]?\s*(?:translator'?s?\s+note|t/?n)\s*[:\])]", caseSensitive: false),
        action: SkipAction(),
      ),
    ),
    RuleTemplate(
      category: _clean,
      title: 'Drop footnote markers',
      description: 'Removes [1], [23] style reference numbers from speech.',
      defaultOn: true,
      rule: SpeechRule(
        id: 'tpl.footnote_markers',
        name: 'Drop footnote markers',
        builtIn: true,
        trigger: RegexTrigger(r'\[\d{1,3}\]'),
        action: ReplaceAction(''),
      ),
    ),
    RuleTemplate(
      category: _clean,
      title: 'Skip links and emails',
      description: 'Sentences that contain a web address or email.',
      defaultOn: true,
      rule: SpeechRule(
        id: 'tpl.skip_urls',
        name: 'Skip links and emails',
        builtIn: true,
        trigger: StructureTrigger(StructureKind.urlOrEmail),
        action: SkipAction(),
      ),
    ),
    RuleTemplate(
      category: _clean,
      title: 'Skip chapter navigation',
      description: '"Next chapter", "Previous chapter", "Table of contents" lines.',
      defaultOn: true,
      rule: SpeechRule(
        id: 'tpl.skip_nav',
        name: 'Skip chapter navigation',
        scope: RuleScope.paragraph,
        builtIn: true,
        trigger: RegexTrigger(r'^\s*(?:<\s*)?(?:previous|prev|next)\s+chapter(?:\s*>)?\s*$|^\s*table of contents\s*$', caseSensitive: false),
        action: SkipAction(),
      ),
    ),
    RuleTemplate(
      category: _clean,
      title: 'Skip support / donation lines',
      description: 'Patreon, Ko-fi, "buy me a coffee" and similar appeals.',
      rule: SpeechRule(
        id: 'tpl.skip_support',
        name: 'Skip support / donation lines',
        scope: RuleScope.paragraph,
        builtIn: true,
        trigger: RegexTrigger(r'patreon|ko-?fi|buy me a coffee|paypal\.me', caseSensitive: false),
        action: SkipAction(),
      ),
    ),
    RuleTemplate(
      category: _clean,
      title: 'Skip bare page numbers',
      description: 'Lines that are only a number, like "42".',
      rule: SpeechRule(
        id: 'tpl.skip_page_numbers',
        name: 'Skip bare page numbers',
        builtIn: true,
        trigger: RegexTrigger(r'^\s*(?:page\s+)?\d{1,4}\s*$', caseSensitive: false),
        action: SkipAction(),
      ),
    ),
    RuleTemplate(
      category: _comfort,
      title: 'Pause at scene breaks',
      description: 'Half a second of silence before and after "***" style dividers.',
      defaultOn: true,
      rule: SpeechRule(
        id: 'tpl.scene_break_pause',
        name: 'Pause at scene breaks',
        builtIn: true,
        trigger: StructureTrigger(StructureKind.sceneBreak),
        action: PauseAfterAction(900),
      ),
    ),
    RuleTemplate(
      category: _comfort,
      title: 'Pause after headings',
      description: 'A short breath after chapter titles and headings.',
      defaultOn: true,
      rule: SpeechRule(
        id: 'tpl.heading_pause',
        name: 'Pause after headings',
        scope: RuleScope.paragraph,
        builtIn: true,
        trigger: FontTrigger(FontKind.larger),
        action: PauseAfterAction(700),
      ),
    ),
    RuleTemplate(
      category: _comfort,
      title: 'Slow down inner thoughts',
      description: '*Text in asterisks* is read a little slower.',
      rule: SpeechRule(
        id: 'tpl.slow_thoughts',
        name: 'Slow down inner thoughts',
        builtIn: true,
        trigger: StructureTrigger(StructureKind.asteriskWrapped),
        action: SpeedShiftAction(-0.1),
      ),
    ),
    RuleTemplate(
      category: _comfort,
      title: 'Slow down italics',
      description: 'Italic text (EPUB/PDF) is read a little slower.',
      rule: SpeechRule(
        id: 'tpl.slow_italics',
        name: 'Slow down italics',
        builtIn: true,
        trigger: FontTrigger(FontKind.italic),
        action: SpeedShiftAction(-0.08),
      ),
    ),
    RuleTemplate(
      category: _comfort,
      title: 'Announce system messages',
      description: 'Bold text in stories (status windows) is introduced with "System".',
      rule: SpeechRule(
        id: 'tpl.system_messages',
        name: 'Announce system messages',
        builtIn: true,
        trigger: FontTrigger(FontKind.bold),
        action: SayBeforeAction('System:'),
      ),
    ),
    RuleTemplate(
      category: _flow,
      title: 'Next chapter at "Thank you for reading"',
      description: 'Jumps ahead when a paragraph is a closing sign-off.',
      rule: SpeechRule(
        id: 'tpl.next_on_signoff',
        name: 'Next chapter at sign-off',
        scope: RuleScope.paragraph,
        builtIn: true,
        trigger: RegexTrigger(r'thanks? (?:you )?for reading|end of chapter', caseSensitive: false),
        action: NextDocumentAction(),
      ),
    ),
    RuleTemplate(
      category: _voice,
      title: 'Pronounce Wi-Fi',
      description: 'Example of a pronunciation fix: "Wi-Fi" → "why fye".',
      rule: SpeechRule(
        id: 'tpl.example_wifi',
        name: 'Pronounce Wi-Fi',
        builtIn: true,
        trigger: LiteralTrigger('Wi-Fi', wholeWord: true),
        action: ReplaceAction('why fye'),
      ),
    ),
  ];

  static RuleTemplate? byId(String id) {
    for (final t in all) {
      if (t.rule.id == id) return t;
    }
    return null;
  }

  /// Rules installed on first launch.
  static List<SpeechRule> defaults() => [
        for (final t in all)
          if (t.defaultOn) t.rule,
      ];
}
