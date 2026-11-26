import 'package:material_ui/material_ui.dart';

/// Passphrase prompt shown before any library is opened.
///
/// Repeated wrong entries add a short delay, which makes guessing from the
/// keyboard impractical without ever locking the owner out.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onSubmit});

  /// Returns `true` if a vault was opened.
  final Future<bool> Function(String passphrase) onSubmit;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _wrong = false;
  int _failures = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _controller.text.isEmpty) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    final ok = await widget.onSubmit(_controller.text);
    if (!mounted) return;
    if (ok) return; // the root replaces this screen
    _failures++;
    if (_failures >= 3) {
      await Future<void>.delayed(Duration(seconds: (_failures - 2).clamp(1, 8)));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _wrong = true;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.headphones, size: 56, color: t.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Aloud', style: t.textTheme.headlineMedium),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _controller,
                    obscureText: true,
                    autofocus: true,
                    enabled: !_busy,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Passphrase',
                      errorText: _wrong ? 'That passphrase is not correct.' : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
