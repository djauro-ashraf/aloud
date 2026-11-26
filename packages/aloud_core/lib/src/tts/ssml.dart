/// Builds SSML for the Edge neural endpoint.
abstract final class SsmlBuilder {
  /// `en-US-JennyNeural` → `en-US`.
  static String localeOfVoice(String voice) {
    final m = RegExp(r'^([a-z]{2,3}-[A-Za-z0-9]{2,4})-').firstMatch(voice);
    return m?.group(1) ?? 'en-US';
  }

  static String escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Edge rejects control characters; strip them before escaping.
  static String _clean(String s) => s.replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), ' ');

  static String _signed(int v, String unit) => '${v >= 0 ? '+' : ''}$v$unit';

  /// [ratePercent]/[pitchHz]/[volumePercent] are offsets from the voice's
  /// baseline. Playback *speed* is applied by the audio player, not here, so
  /// that cached audio is reusable at every speed.
  static String build({
    required String text,
    required String voice,
    int ratePercent = 0,
    int pitchHz = 0,
    int volumePercent = 0,
  }) {
    final lang = localeOfVoice(voice);
    final body = escapeXml(_clean(text));
    return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
        "xml:lang='$lang'><voice name='$voice'>"
        "<prosody pitch='${_signed(pitchHz, 'Hz')}' rate='${_signed(ratePercent, '%')}' "
        "volume='${_signed(volumePercent, '%')}'>$body</prosody></voice></speak>";
  }
}
