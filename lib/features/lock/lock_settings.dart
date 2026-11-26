import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/ui/widgets.dart';
import 'vault_service.dart';

/// The vault service of the running app (overridden by `AloudRoot`).
final vaultServiceProvider = Provider<VaultService>((ref) {
  throw StateError('vaultServiceProvider must be overridden.');
});

/// Current lock configuration, refreshed after changes.
final vaultConfigProvider = FutureProvider<VaultConfig>((ref) => ref.watch(vaultServiceProvider).load());

/// "Privacy" block of the settings page: passphrase lock and decoy library.
class LockSettingsSection extends ConsumerWidget {
  const LockSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(vaultConfigProvider).value ?? const VaultConfig();
    final vault = ref.read(vaultServiceProvider);

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: const Text('Passphrase lock'),
          subtitle: const Text('Ask for a passphrase every time the app starts'),
          value: cfg.locked,
          onChanged: (on) async {
            if (on) {
              final res = await _askNewPassphrase(context);
              if (res == null) return;
              await vault.enable(res, decoy: false);
            } else {
              final ok = await _verify(context, vault, 'Turn off the lock');
              if (!ok) return;
              await vault.disable();
            }
            ref.invalidate(vaultConfigProvider);
          },
        ),
        if (cfg.locked) ...[
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Decoy library'),
            subtitle: const Text(
              'A wrong passphrase opens an empty, separate library instead of an error, '
              'so nobody can tell yours is hidden.',
            ),
            value: cfg.decoy,
            onChanged: (v) async {
              await vault.setDecoy(v);
              ref.invalidate(vaultConfigProvider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Change passphrase'),
            onTap: () async {
              if (!await _verify(context, vault, 'Enter your current passphrase')) return;
              if (!context.mounted) return;
              final res = await _askNewPassphrase(context);
              if (res == null) return;
              await vault.enable(res, decoy: cfg.decoy);
              ref.invalidate(vaultConfigProvider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('Lock now'),
            onTap: () => ref.read(lockCallbackProvider)(),
          ),
        ],
      ],
    );
  }

  Future<bool> _verify(BuildContext context, VaultService vault, String title) async {
    final pass = await promptText(context, title: title, hint: 'Passphrase', obscure: true);
    if (pass == null) return false;
    final ok = await vault.verify(pass);
    if (!ok && context.mounted) context.snack('That passphrase is not correct.');
    return ok;
  }

  Future<String?> _askNewPassphrase(BuildContext context) async {
    final a = TextEditingController();
    final b = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set a passphrase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: a, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Passphrase')),
            const SizedBox(height: 12),
            TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat passphrase')),
            const SizedBox(height: 12),
            const Text('There is no recovery. If you forget it, clear the app’s data to reset.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (a.text.length < 4) {
                ctx.snack('Use at least 4 characters.');
              } else if (a.text != b.text) {
                ctx.snack('The two entries don’t match.');
              } else {
                Navigator.pop(ctx, a.text);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    a.dispose();
    b.dispose();
    return result;
  }
}
