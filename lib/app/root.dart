import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/platform/native_bridge.dart';
import '../core/theme/app_theme.dart';
import '../features/listen/audio_handler.dart';
import '../features/lock/lock_screen.dart';
import '../features/lock/lock_settings.dart';
import '../features/lock/vault_service.dart';
import 'app.dart';
import 'core_providers.dart';
import 'services.dart';

/// Decides what to show at launch: splash → (lock screen →) app.
///
/// Opening a vault creates one [AppServices] and hands it to a fresh
/// [ProviderScope]. Locking disposes that scope, so every controller (and any
/// playback) is torn down cleanly — nothing from the private library lingers.
class AloudRoot extends StatefulWidget {
  const AloudRoot({
    super.key,
    required this.supportDir,
    required this.vaults,
    required this.bridge,
    required this.audioHandler,
  });

  final Directory supportDir;
  final VaultService vaults;
  final NativeBridge bridge;
  final AloudAudioHandler audioHandler;

  @override
  State<AloudRoot> createState() => _AloudRootState();
}

enum _Phase { booting, locked, open, failed }

class _AloudRootState extends State<AloudRoot> {
  _Phase _phase = _Phase.booting;
  AppServices? _services;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final cfg = await widget.vaults.load();
    if (cfg.locked) {
      setState(() => _phase = _Phase.locked);
    } else {
      await _open(VaultId.main);
    }
  }

  Future<void> _open(VaultId vault) async {
    try {
      final s = await AppServices.open(
        supportDir: widget.supportDir,
        vault: vault,
        bridge: widget.bridge,
        audioHandler: widget.audioHandler,
      );
      if (!mounted) {
        await s.close();
        return;
      }
      setState(() {
        _services = s;
        _phase = _Phase.open;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _phase = _Phase.failed;
        });
      }
    }
  }

  void _lock() {
    final s = _services;
    setState(() {
      _services = null;
      _phase = _Phase.locked;
    });
    // Let the old provider scope dispose (and save positions) first.
    if (s != null) Future<void>.delayed(const Duration(milliseconds: 600), s.close);
  }

  Future<bool> _unlock(String passphrase) async {
    final vault = await widget.vaults.unlock(passphrase);
    if (vault == null) return false;
    await _open(vault);
    return true;
  }

  @override
  void dispose() {
    unawaited(_services?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.open:
        final s = _services!;
        return ProviderScope(
          key: ObjectKey(s),
          overrides: [
            servicesProvider.overrideWithValue(s),
            vaultServiceProvider.overrideWithValue(widget.vaults),
            lockCallbackProvider.overrideWithValue(_lock),
          ],
          child: const AloudApp(),
        );
      case _Phase.locked:
        return _plain(LockScreen(onSubmit: _unlock));
      case _Phase.failed:
        return _plain(Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Aloud could not open its library.\n\n$_error', textAlign: TextAlign.center),
            ),
          ),
        ));
      case _Phase.booting:
        return _plain(const Scaffold(body: Center(child: CircularProgressIndicator())));
    }
  }

  Widget _plain(Widget home) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(Color(AppTheme.accents.first), Brightness.light),
        darkTheme: AppTheme.build(Color(AppTheme.accents.first), Brightness.dark),
        home: home,
      );
}
