/// Pure-Dart domain logic for Aloud: text segmentation, speech
/// normalisation, listening rules, PDF clean-up and reading models.
///
/// This package has no Flutter or platform dependency, so everything in it
/// can be unit-tested on any machine.
library;

export 'src/audio/wav_codec.dart';
export 'src/library/library_logic.dart';
export 'src/pdf/pdf_cleanup.dart';
export 'src/reading/block_classifier.dart';
export 'src/reading/reading_model.dart';
export 'src/rules/rule_engine.dart';
export 'src/rules/rule_model.dart';
export 'src/rules/rule_templates.dart';
export 'src/text/hashing.dart';
export 'src/text/number_words.dart';
export 'src/text/paragraphs.dart';
export 'src/text/sentence_splitter.dart';
export 'src/text/text_normalizer.dart';
export 'src/translate/batching.dart';
export 'src/translate/languages.dart';
export 'src/tts/sherpa_catalog.dart';
export 'src/tts/ssml.dart';
export 'src/tts/voice.dart';
export 'src/web/web_text_polisher.dart';
