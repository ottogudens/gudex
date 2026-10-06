import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/widgets/theme_button.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final session = await ApiClient(apiBaseUrl).login(_email.text.trim(), _password.text);
      await ref.read(authProvider.notifier).signIn(session);
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(actions: const [GudexThemeButton()]),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [GudexColors.ink, GudexColors.primary],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: EdgeInsets.all(constraints.maxWidth < 380 ? 22 : 30),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Align(alignment: Alignment.centerLeft, child: Container(
                          width: 250, height: 70,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.all(8),
                          child: Image.asset('assets/gudex-logo.png', fit: BoxFit.contain),
                        )),
                        const SizedBox(height: 22),
                        Text('Gestión simple para tu lubricentro', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 28),
                        TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline))),
                        const SizedBox(height: 14),
                        TextField(controller: _password, obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline)),
                          onSubmitted: (_) => _submit()),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Ingresar'),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            )),
          ),
        ),
      );
}
