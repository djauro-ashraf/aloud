import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/root.dart';
import 'core/platform/native_bridge.dart';
import 'features/listen/audio_handler.dart';
import 'features/lock/vault_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();

  // Speech-oriented audio focus: duck/pause for calls and other media apps.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());

  final audioHandler = await AloudAudioHandler.init();
  final Directory supportDir = await getApplicationSupportDirectory();

  runApp(AloudRoot(
    supportDir: supportDir,
    vaults: VaultService(File(p.join(supportDir.path, 'vault.json'))),
    bridge: NativeBridge(),
    audioHandler: audioHandler,
  ));
}
