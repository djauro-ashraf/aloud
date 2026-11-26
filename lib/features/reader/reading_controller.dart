import 'dart:async';
import 'dart:math';

import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/core_providers.dart';
import '../../app/services.dart';
import '../../core/prefs.dart';
import '../../core/util/ids.dart';
import '../../data/models/models.dart';
import '../listen/audio_handler.dart';
import '../listen/backend_factory.dart';
import '../listen/engines/speech_backend.dart';
import '../listen/narrator.dart';
import '../translate/translation_providers.dart';
import '../web_import/web_import_service.dart';

const _keep = Object();

/// Everything the reader and player UI need to know.
final class ReadingState {
  const ReadingState({
    this.doc,
    this.toc = const [],
    this.section = 0,
    this.content,
    this.index,
    this.cursor = 0,
    this.status = NarratorStatus.idle,
    this.loading = false,
    this.error,
    this.notice,
    this.translated = false,
    this.translating = false,
    this.sleepEnd,
    this.sleepAtChapterEnd = false,
    this.prepareProgress,
  });

  final Doc? doc;
  final List<String> toc;
  final int section;
  final ReaderSection? content;
  final SectionIndex? index;

  /// Flat sentence index within [content] currently read/highlighted.
  final int cursor;
  final NarratorStatus status;
  final bool loading;

  /// Last playback error (shown once, then cleared).
  final String? error;

  /// Informational message to show once (snackbar).
  final String? notice;
  final bool translated;
  final bool translating;
  final DateTime? sleepEnd;
  final bool sleepAtChapterEnd;

  /// 0‥1 while the chapter's audio is being prepared for offline use.
  final double? prepareProgress;

  bool get isPlaying => status == NarratorStatus.playing;
  bool get hasDoc => doc != null;
  int get sectionCount => max(toc.length, doc?.sectionCount ?? 0);

  /// Block containing the cursor (for scrolling/highlighting).
  int? get cursorBlock {
    final i = index;
    if (i == null || i.isEmpty) return null;
    return i.sentences[cursor.clamp(0, i.length - 1)].block;
  }

  String get sectionTitle {
    if (section >= 0 && section < toc.length && toc[section].isNotEmpty) return toc[section];
    return content?.title ?? '';
  }

  ReadingState copyWith({
    Doc? doc,
    List<String>? toc,
    int? section,
    ReaderSection? content,
    SectionIndex? index,
    int? cursor,
    NarratorStatus? status,
    bool? loading,
    Object? error = _keep,
    Object? notice = _keep,
    bool? translated,
    bool? translating,
    Object? sleepEnd = _keep,
    bool? sleepAtChapterEnd,
    Object? prepareProgress = _keep,
  }) =>
      ReadingState(
        doc: doc ?? this.doc,
        toc: toc ?? this.toc,
        section: section ?? this.section,
        content: content ?? this.content,
        index: index ?? this.index,
        cursor: cursor ?? this.cursor,
        status: status ?? this.status,
        loading: loading ?? this.loading,
        error: identical(error, _keep) ? this.error : error as String?,
        notice: identical(notice, _keep) ? this.notice : notice as String?,
        translated: translated ?? this.translated,
        translating: translating ?? this.translating,
        sleepEnd: identical(sleepEnd, _keep) ? this.sleepEnd : sleepEnd as DateTime?,
        sleepAtChapterEnd: sleepAtChapterEnd ?? this.sleepAtChapterEnd,
        prepareProgress: identical(prepareProgress, _keep) ? this.prepareProgress : prepareProgress as double?,
      );
}

final readingProvider = NotifierProvider<ReadingController, ReadingState>(ReadingController.new);

/// Owns the open document and its [Narrator].
///
/// It is app-scoped on purpose: playback continues when the reader screen is
/// closed, and the library shows a mini-player bound to the same state.
class ReadingController extends Notifier<ReadingState> {
  late final Narrator _narrator;
  late final BackendFactory _factory;
  late final AloudAudioHandler _handler;
  StreamSubscription<NarratorEvent>? _sub;
  Timer? _sleepTimer;
  final _saver = Debouncer(const Duration(milliseconds: 900));

  RuleEngine _engine = RuleEngine.empty();
  String? _language;
  SectionIndex? _originalIndex;
  int _openToken = 0;
  String? _openingId;
  bool _wantAutoplay = false;

  AppServices get _s => ref.read(servicesProvider);
  Map<String, Object?> get _prefs => ref.read(settingsProvider);

  @override
  ReadingState build() {
    _factory = ref.read(backendFactoryProvider);
    _handler = _s.audioHandler;
    _narrator = Narrator(
      backend: () => _factory.current,
      rules: () => _engine,
      voice: () => VoiceResolver.resolve(_prefs, language: _language),
      settings: () => NarratorSettings(
        speed: Prefs.speed.read(_prefs),
        paragraphPauseMs: Prefs.paragraphPauseMs.read(_prefs),
        sentencePauseMs: Prefs.sentencePauseMs.read(_prefs),
        prefetch: Prefs.prefetch.read(_prefs),
      ),
    );
    _sub = _narrator.events.listen(_onEvent);

    _handler
      ..onPlay = play
      ..onPause = pause
      ..onNext = nextParagraph
      ..onPrevious = previousParagraph
      ..onStop = close;

    ref.listen(rulesListProvider, (_, _) => _rebuildEngine());
    ref.listen(settingsProvider, (prev, next) => _onSettingsChanged(prev ?? next, next));
    ref.listen(fallbackNoticeProvider, (_, reason) {
      if (reason == null) return;
      state = state.copyWith(notice: 'Using the device voice for now ($reason)');
      ref.read(fallbackNoticeProvider.notifier).clear();
    });
    ref.onDispose(() {
      _sleepTimer?.cancel();
      _saver.dispose();
      _sub?.cancel();
      _handler
        ..onPlay = null
        ..onPause = null
        ..onNext = null
        ..onPrevious = null
        ..onStop = null;
      _handler.publish(title: '', subtitle: '', playing: false, active: false);
      unawaited(_narrator.dispose());
    });
    return const ReadingState();
  }

  // ── Settings reactions ─────────────────────────────────────────────────

  void _onSettingsChanged(Map<String, Object?> prev, Map<String, Object?> next) {
    if (Prefs.speed.read(prev) != Prefs.speed.read(next)) unawaited(_narrator.speedChanged());

    final normalizerChanged = [Prefs.normalizeText, Prefs.expandAbbreviations, Prefs.spellAcronyms]
        .any((p) => p.read(prev) != p.read(next));
    if (normalizerChanged) _rebuildEngine();

    String sig(Map<String, Object?> m) => [
          Prefs.engine, Prefs.edgeVoice, Prefs.systemVoice, Prefs.sherpaVoice, Prefs.pcVoice,
          Prefs.pcUrl, Prefs.fallbackToSystem, Prefs.sherpaThreads,
        ].map((p) => '${p.read(m)}').join('|');
    if (sig(prev) != sig(next) && state.hasDoc) unawaited(_restartCurrentSentence());
  }

  Future<void> _restartCurrentSentence() async {
    final wasPlaying = state.isPlaying;
    await _factory.prepare();
    if (wasPlaying) await _narrator.jumpTo(state.cursor);
  }

  void _rebuildEngine() {
    final rules = ref.read(rulesListProvider).value ?? const <SpeechRule>[];
    _engine = RuleEngine(
      rules,
      normalizer: NormalizerOptions(
        language: _language ?? 'en',
        expandAbbreviations: Prefs.expandAbbreviations.read(_prefs),
        spellAcronyms: Prefs.spellAcronyms.read(_prefs),
      ),
      normalize: Prefs.normalizeText.read(_prefs),
    );
  }

  // ── Opening ────────────────────────────────────────────────────────────

  /// Opens [docId], resuming where the reader left off.
  Future<void> open(String docId, {bool autoplay = false}) async {
    // The library and the reader screen both call this; the second call must
    // not cancel the first (and must not lose its "start playing" intent).
    if (_openingId == docId) {
      if (autoplay) {
        if (state.content != null && !state.loading) {
          if (!state.isPlaying) await play();
        } else {
          _wantAutoplay = true;
        }
      }
      return;
    }
    _openingId = docId;
    _wantAutoplay = autoplay;
    final token = ++_openToken;
    await _closeCurrent();
    state = const ReadingState(loading: true);

    final doc = await _s.library.getDoc(docId);
    if (doc == null || token != _openToken) {
      if (token == _openToken) _openingId = null;
      state = const ReadingState();
      return;
    }
    if (!doc.kind.isSpeakable) {
      state = ReadingState(doc: doc);
      await _s.library.touch(docId);
      return;
    }
    await ref.read(rulesListProvider.future);
    final toc = await _s.content.readToc(docId);
    if (token != _openToken) return;
    await _s.library.touch(docId);

    _language = doc.language;
    _rebuildEngine();
    state = ReadingState(doc: doc, toc: toc, loading: true);
    final pos = doc.completed ? ReadingPosition.start : doc.position;
    await _loadSection(min(pos.section, max(0, (toc.isEmpty ? doc.sectionCount : toc.length) - 1)),
        sentence: pos.sentence);
  }

  Future<void> _closeCurrent() async {
    _saver.flush(() {});
    if (state.hasDoc && state.index != null) await _savePosition();
    _sleepTimer?.cancel();
    await _narrator.stop();
    _originalIndex = null;
  }

  Future<void> close() async {
    _openToken++;
    _openingId = null;
    _wantAutoplay = false;
    await _closeCurrent();
    state = const ReadingState();
    _handler.publish(title: '', subtitle: '', playing: false, active: false);
  }

  // ── Sections ───────────────────────────────────────────────────────────

  Future<void> goToSection(int i, {bool play = false}) async {
    if (i < 0 || i >= state.sectionCount || !state.hasDoc) return;
    final wasPlaying = state.isPlaying;
    await _loadSection(i, play: play || wasPlaying);
  }

  Future<void> _loadSection(int i, {int sentence = 0, int? block, bool play = false}) async {
    final doc = state.doc;
    if (doc == null) return;
    final token = _openToken;
    state = state.copyWith(loading: true);

    final original = await _s.content.readSection(doc.id, i);
    var shown = original;
    var translated = state.translated;
    if (translated) {
      state = state.copyWith(translating: true);
      try {
        shown = await ref.read(translationServiceProvider).translate(doc, i, original);
      } on TranslationException catch (e) {
        translated = false;
        state = state.copyWith(notice: e.message);
      }
      state = state.copyWith(translating: false);
    }
    if (token != _openToken) return;

    _language = translated ? Prefs.translateTarget.read(_prefs) : doc.language;
    _rebuildEngine();

    final index = SectionIndex.build(shown);
    _originalIndex = translated ? SectionIndex.build(original) : index;

    var start = sentence;
    if (block != null) start = index.firstSentenceAtOrAfterBlock(block) ?? 0;
    // Positions saved against the untranslated text map through its blocks.
    if (block == null && translated && _originalIndex!.length > sentence) {
      start = index.firstSentenceAtOrAfterBlock(_originalIndex!.sentences[sentence].block) ?? 0;
    }
    start = index.isEmpty ? 0 : start.clamp(0, index.length - 1);

    state = state.copyWith(
      section: i,
      content: shown,
      index: index,
      cursor: start,
      translated: translated,
    );
    // `loading` stays true until the narrator has the new section, so the
    // media notification is never dropped between chapters.
    await _narrator.load(shown, index, startAt: start);
    if (token != _openToken) return;
    state = state.copyWith(loading: false);
    _publishMedia();
    final autoplay = play || _wantAutoplay;
    _wantAutoplay = false;
    if (autoplay) await this.play();
  }

  // ── Transport ──────────────────────────────────────────────────────────

  Future<void> play() async {
    if (state.index == null) return;
    state = state.copyWith(error: null);
    await _factory.prepare();
    await _narrator.play();
  }

  Future<void> pause() async {
    await _narrator.pause();
    await _savePosition();
  }

  Future<void> toggle() => state.isPlaying ? pause() : play();

  Future<void> seekToSentence(int i, {bool play = false}) async {
    await _factory.prepare();
    await _narrator.jumpTo(i);
    if (play && !state.isPlaying) await _narrator.play();
  }

  /// Tap-to-read: start speaking from the sentence containing [offset] in [block].
  Future<void> playFromBlock(int block, {int offset = 0}) async {
    final i = state.index?.sentenceAt(block, offset);
    if (i == null) return;
    await seekToSentence(i, play: true);
  }

  Future<void> nextSentence() => _narrator.nextSentence();
  Future<void> previousSentence() => _narrator.previousSentence();
  Future<void> nextParagraph() => _narrator.nextParagraph();
  Future<void> previousParagraph() => _narrator.previousParagraph();

  Future<void> setSpeed(double speed) => ref.read(settingsProvider.notifier).set(Prefs.speed, speed.clamp(0.5, 3.0));

  // ── Offline preparation ───────────────────────────────────────────────

  bool _cancelPrepare = false;

  /// Synthesises every sentence of the current chapter into the audio cache
  /// so it can be heard later without a network (or without waiting for the
  /// neural voice). Safe to run while listening.
  Future<void> prepareChapterOffline() async {
    if (state.index == null || state.prepareProgress != null) return;
    final engine = VoiceResolver.engineOf(_prefs);
    if (engine == EngineKind.system) {
      state = state.copyWith(notice: 'The device voice speaks instantly; there is nothing to prepare.');
      return;
    }
    await _factory.prepare();
    final items = _narrator.itemsFrom(0, count: 1 << 20);
    if (items.isEmpty) return;
    _cancelPrepare = false;
    state = state.copyWith(prepareProgress: 0);
    try {
      await _factory.current.renderAhead(
        items,
        isCancelled: () => _cancelPrepare,
        onProgress: (done) => state = state.copyWith(prepareProgress: done / items.length),
      );
      if (!_cancelPrepare) state = state.copyWith(notice: 'Chapter ready for offline listening.');
    } on SpeechException catch (e) {
      state = state.copyWith(notice: 'Preparation stopped: ${e.message}');
    } finally {
      state = state.copyWith(prepareProgress: null);
    }
  }

  void cancelPrepare() => _cancelPrepare = true;

  // ── Sleep timer ────────────────────────────────────────────────────────

  void setSleepTimer(Duration? d) {
    _sleepTimer?.cancel();
    if (d == null) {
      state = state.copyWith(sleepEnd: null, sleepAtChapterEnd: false);
      return;
    }
    state = state.copyWith(sleepEnd: DateTime.now().add(d), sleepAtChapterEnd: false);
    _sleepTimer = Timer(d, () async {
      state = state.copyWith(sleepEnd: null, notice: 'Sleep timer finished — paused.');
      await pause();
    });
  }

  void setSleepAtChapterEnd(bool on) {
    _sleepTimer?.cancel();
    state = state.copyWith(sleepAtChapterEnd: on, sleepEnd: null);
  }

  // ── Translation ────────────────────────────────────────────────────────

  Future<void> setTranslated(bool on) async {
    if (on == state.translated || !state.hasDoc) return;
    final wasPlaying = state.isPlaying;
    final block = state.cursorBlock;
    state = state.copyWith(translated: on);
    await _loadSection(state.section, block: block ?? 0, play: wasPlaying);
  }

  // ── Events ─────────────────────────────────────────────────────────────

  void _onEvent(NarratorEvent e) {
    switch (e) {
      case CursorEvent(:final index):
        state = state.copyWith(cursor: index);
        _saver.run(() => unawaited(_savePosition()));
      case StatusEvent(:final status):
        state = state.copyWith(status: status);
        _publishMedia();
        if (status != NarratorStatus.playing) _saver.flush(() => unawaited(_savePosition()));
      case SectionEndEvent(:final flow):
        unawaited(_onSectionEnd(flow));
      case ErrorEvent(:final message):
        state = state.copyWith(error: message);
    }
  }

  Future<void> _onSectionEnd(FlowDirective flow) async {
    final doc = state.doc;
    if (doc == null) return;
    if (state.sleepAtChapterEnd) {
      state = state.copyWith(sleepAtChapterEnd: false, notice: 'Sleep timer: chapter finished.');
      final hasNext = state.section + 1 < state.sectionCount;
      if (hasNext) await _loadSection(state.section + 1);
      return;
    }
    final advance = flow == FlowDirective.nextDocument || Prefs.autoNextSection.read(_prefs);
    if (!advance) return;
    await _advance();
  }

  Future<void> _advance() async {
    final doc = state.doc;
    if (doc == null) return;
    final count = state.sectionCount;
    if (state.section + 1 < count) {
      await _loadSection(state.section + 1, play: true);
      return;
    }

    // Last chapter. Web novels may have more online.
    if (doc.kind == DocKind.web && doc.nextUrl != null) {
      try {
        final updated = await ref.read(webImportServiceProvider).appendNext(doc);
        if (updated != null && updated.sectionCount > count) {
          final toc = await _s.content.readToc(doc.id);
          state = state.copyWith(doc: updated, toc: toc);
          await _loadSection(count, play: true);
          return;
        }
      } on Object catch (e) {
        state = state.copyWith(notice: 'Could not fetch the next chapter: $e');
      }
    }

    // Finished the document.
    await _s.library.savePosition(
      doc.id,
      position: ReadingPosition(section: max(0, count - 1), sentence: max(0, (state.index?.length ?? 1) - 1)),
      progress: 1,
      completed: true,
    );
    if (Prefs.autoNextDocument.read(_prefs)) {
      final next = await _s.library.nextAfter(doc);
      if (next != null) {
        await open(next.id, autoplay: true);
        return;
      }
    }
    state = state.copyWith(notice: 'Finished “${doc.title}”.');
  }

  // ── Persistence & media session ────────────────────────────────────────

  int _originalCursor() {
    final idx = state.index;
    if (idx == null || idx.isEmpty) return 0;
    if (!state.translated) return state.cursor;
    final block = idx.sentences[state.cursor.clamp(0, idx.length - 1)].block;
    return _originalIndex?.firstSentenceAtOrAfterBlock(block) ?? 0;
  }

  Future<void> _savePosition() async {
    final doc = state.doc;
    final idx = state.index;
    if (doc == null || idx == null || !doc.kind.isSpeakable) return;
    final fraction = ReadingProgress.fraction(
      section: state.section,
      sectionCount: state.sectionCount,
      sentence: _originalCursor(),
      sentenceCount: _originalIndex?.length ?? idx.length,
    );
    await _s.library.savePosition(
      doc.id,
      position: ReadingPosition(section: state.section, sentence: _originalCursor()),
      progress: fraction,
    );
  }

  void _publishMedia() {
    final doc = state.doc;
    _handler.publish(
      title: doc?.title ?? '',
      subtitle: state.sectionTitle,
      playing: state.isPlaying,
      active: doc != null && (state.status != NarratorStatus.idle || state.loading),
    );
  }

  /// Re-reads the document record and chapter list (after chapters were added).
  Future<void> reloadDocMeta() async {
    final id = state.doc?.id;
    if (id == null) return;
    final doc = await _s.library.getDoc(id);
    final toc = await _s.content.readToc(id);
    if (doc != null) state = state.copyWith(doc: doc, toc: toc);
  }

  void clearNotice() => state = state.copyWith(notice: null);
  void clearError() => state = state.copyWith(error: null);
}
