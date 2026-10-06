import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/api_client.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({required this.api, super.key});
  final ApiClient api;
  
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<Map<String, dynamic>>> _users;
  
  @override 
  void initState() { 
    super.initState(); 
    _users = _load(); 
  }
  
  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.api.get('/api/v1/users');
    return raw is List ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : [];
  }
  
  Future<void> _edit(Map<String, dynamic>? user) async {
    final isNew = user == null;
    final name = TextEditingController(text: user?['full_name']?.toString() ?? '');
    final email = TextEditingController(text: user?['email']?.toString() ?? '');
    final password = TextEditingController();
    String role = user?['role']?.toString() ?? 'mechanic';
    bool active = user?['active'] != false;
    final saved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(isNew ? 'Nuevo usuario' : 'Editar usuario'),
      content: StatefulBuilder(builder: (context, update) => SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre completo')),
        if (isNew) TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
        if (isNew) TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña inicial (12 caracteres mínimo)')),
        DropdownButtonFormField<String>(initialValue: role, decoration: const InputDecoration(labelText: 'Rol'), items: const [DropdownMenuItem(value: 'admin', child: Text('Administración')), DropdownMenuItem(value: 'mechanic', child: Text('Mecánico'))], onChanged: (value) { if (value != null) update(() => role = value); }),
        if (!isNew) SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (value) => update(() => active = value), title: const Text('Cuenta activa')),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), 
        FilledButton(onPressed: () async {
          try {
            if (isNew) {
              await widget.api.postJson('/api/v1/users', {'full_name': name.text.trim(), 'email': email.text.trim(), 'password': password.text, 'role': role});
            } else {
              await widget.api.patchJson('/api/v1/users/${user['id']}', {'full_name': name.text.trim(), 'role': role, 'active': active});
            }
            if (context.mounted) Navigator.pop(context, true);
          } catch (error) { 
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); 
          }
        }, child: const Text('Guardar'))
      ],
    ));
    name.dispose(); 
    email.dispose(); 
    password.dispose();
    if (saved == true && mounted) setState(() => _users = _load());
  }
  
  @override 
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: _users, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
    final users = snapshot.data ?? [];
    return Stack(children: [
      RefreshIndicator(
        onRefresh: () async => setState(() => _users = _load()), 
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), 
          children: users.map((user) => Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(user['role'] == 'admin' ? Icons.admin_panel_settings_outlined : Icons.handyman_outlined)), 
              title: Text(user['full_name'].toString()), 
              subtitle: Text('${user['email']} · ${spanishRole(user['role'])}${user['active'] == true ? '' : ' · Inactivo'}'), 
              trailing: const Icon(Icons.edit_outlined), 
              onTap: () => _edit(user)
            )
          )).toList()
        )
      ), 
      Positioned(
        right: 18, 
        bottom: 18, 
        child: FloatingActionButton.extended(
          onPressed: () => _edit(null), 
          icon: const Icon(Icons.person_add_alt_1), 
          label: const Text('Nuevo usuario')
        )
      )
    ]);
  });
}
