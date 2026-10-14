import 'package:flutter/material.dart';
import '../services/api_client.dart';

class RedemptionsScreen extends StatefulWidget {
  const RedemptionsScreen({required this.api, super.key});
  final ApiClient api;
  @override
  State<RedemptionsScreen> createState() => _RedemptionsScreenState();
}

class _RedemptionsScreenState extends State<RedemptionsScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.api.get('/api/v1/loyalty/redemptions');
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  Future<void> _set(Map<String, dynamic> row, String status) async {
    try {
      await widget.api.post('/api/v1/loyalty/redemptions/${row['id']}/$status');
      if (mounted) setState(() => _rows = _load());
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
          future: _rows,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            final rows = snapshot.data ?? [];
            return RefreshIndicator(
                onRefresh: () async => setState(() => _rows = _load()),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text('Canjes de beneficios',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  const Text(
                      'Aprueba y registra la entrega de recompensas solicitadas por clientes.'),
                  const SizedBox(height: 18),
                  if (rows.isEmpty)
                    const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(
                            child: Text('No hay solicitudes de canje.'))),
                  ...rows.map((row) {
                    final status = '${row['status']}';
                    return Card(
                        child: ListTile(
                            leading: const Icon(Icons.card_giftcard_outlined),
                            title: Text(
                                '${row['reward_name']} · ${row['points_cost']} puntos'),
                            subtitle: Text(
                                '${row['customer_name']} · ${status == 'requested' ? 'Pendiente de revisión' : status}'),
                            trailing: status == 'requested'
                                ? Wrap(spacing: 4, children: [
                                    IconButton(
                                        tooltip: 'Rechazar',
                                        onPressed: () => _set(row, 'rejected'),
                                        icon: const Icon(Icons.close,
                                            color: Colors.red)),
                                    IconButton(
                                        tooltip: 'Aprobar',
                                        onPressed: () => _set(row, 'approved'),
                                        icon: const Icon(Icons.check,
                                            color: Colors.green))
                                  ])
                                : status == 'approved'
                                    ? FilledButton(
                                        onPressed: () => _set(row, 'delivered'),
                                        child: const Text('Entregar'))
                                    : null));
                  }),
                ]));
          });
}
