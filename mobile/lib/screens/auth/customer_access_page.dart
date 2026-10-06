import 'package:flutter/material.dart';

import '../../core/widgets/theme_button.dart';
import '../../services/api_client.dart';

class CustomerAccessPage extends StatefulWidget {
  const CustomerAccessPage({required this.token, required this.passwordReset, required this.apiBaseUrl, super.key});
  final String token;
  final bool passwordReset;
  final String apiBaseUrl;
  
  @override
  State<CustomerAccessPage> createState() => _CustomerAccessPageState();
}

class _CustomerAccessPageState extends State<CustomerAccessPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  
  @override
  void dispose() { 
    _password.dispose(); 
    _confirm.dispose(); 
    super.dispose(); 
  }
  
  Future<void> _submit() async {
    if (_password.text.length < 6) { setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.'); return; }
    if (_password.text != _confirm.text) { setState(() => _error = 'Las contraseñas no coinciden.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final path = widget.passwordReset ? '/auth/customer/password-reset/confirm' : '/auth/customer/activate';
      await ApiClient(widget.apiBaseUrl).postJson(path, {'token': widget.token, 'password': _password.text});
      if (mounted) setState(() => _error = 'Listo. Ya puedes cerrar esta página e iniciar sesión.');
    } catch (error) { 
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', '')); 
    } finally { 
      if (mounted) setState(() => _busy = false); 
    }
  }
  
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.passwordReset ? 'Nueva contraseña' : 'Activar acceso'), 
      actions: const [GudexThemeButton()]
    ), 
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460), 
        child: ListView(
          padding: const EdgeInsets.all(24), 
          children: [
            Text(widget.passwordReset ? 'Crea una nueva contraseña para tu portal.' : 'Crea una contraseña para acceder a tu portal Gudex.'), 
            const SizedBox(height: 18),
            TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña (6 caracteres mínimo)')),
            const SizedBox(height: 12), 
            TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmar contraseña')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 18), 
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Guardando…' : 'Guardar')),
          ]
        )
      )
    )
  );
}
