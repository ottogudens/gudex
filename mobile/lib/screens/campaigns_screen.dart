import 'package:flutter/material.dart';
import '../services/api_client.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({required this.api, super.key});
  final ApiClient api;
  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.api.get('/api/v1/marketing/campaigns');
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final message = TextEditingController();
    var audience = 'all';
    final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Nueva campaña'),
                content: StatefulBuilder(
                    builder: (c, set) =>
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                              controller: title,
                              decoration:
                                  const InputDecoration(labelText: 'Título')),
                          TextField(
                              controller: message,
                              maxLines: 3,
                              decoration:
                                  const InputDecoration(labelText: 'Mensaje')),
                          DropdownButtonFormField<String>(
                            initialValue: audience,
                              items: const [
                                DropdownMenuItem(
                                    value: 'all', child: Text('Todos')),
                                DropdownMenuItem(
                                    value: 'inactive',
                                    child: Text('Clientes inactivos')),
                                DropdownMenuItem(
                                    value: 'maintenance_due',
                                    child: Text('Mantención próxima')),
                                DropdownMenuItem(
                                    value: 'loyalty',
                                    child: Text('Fidelización'))
                              ],
                              onChanged: (v) => set(() => audience = v!))
                        ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, {
                            'title': title.text,
                            'message': message.text,
                            'audience': audience
                          }),
                      child: const Text('Guardar'))
                ]));
    title.dispose();
    message.dispose();
    if (data == null) return;
    try {
      await widget.api.postJson('/api/v1/marketing/campaigns', data);
      if (mounted) setState(() => _rows = _load());
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _status(Map row, String status) async {
    await widget.api
        .post('/api/v1/marketing/campaigns/${row['id']}/status?status=$status');
    if (mounted) setState(() => _rows = _load());
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data ?? [];
          return Scaffold(
            floatingActionButton: FloatingActionButton.extended(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Nueva campaña')),
            body: RefreshIndicator(
              onRefresh: () async => setState(() => _rows = _load()),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('Campañas y promociones',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('Prepara y controla promociones por audiencia.'),
                ...rows.map((row) => Card(
                        child: ListTile(
                      title: Text('${row['title']}'),
                      isThreeLine: true,
                      subtitle: Text(
                          '${row['audience']} · ${row['status']}\n${row['message']}'),
                      trailing: PopupMenuButton<String>(
                          onSelected: (value) => _status(row, value),
                          itemBuilder: (context) => const [
                                PopupMenuItem(
                                    value: 'active', child: Text('Activar')),
                                PopupMenuItem(
                                    value: 'paused', child: Text('Pausar')),
                                PopupMenuItem(
                                    value: 'completed',
                                    child: Text('Finalizar')),
                              ]),
                    ))),
              ]),
            ),
          );
        },
      );
}
