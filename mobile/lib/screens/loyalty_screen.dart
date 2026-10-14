import 'package:flutter/material.dart';
import '../services/api_client.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({required this.api, super.key});
  final ApiClient api;
  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  late Future<Map<String, dynamic>> _data;
  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final raw = await widget.api.get('/api/v1/portal/loyalty');
    return raw is Map ? Map<String, dynamic>.from(raw) : {};
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
              child: OutlinedButton.icon(
                  onPressed: () => setState(() => _data = _load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar')));
        final data = snapshot.data ?? {};
        final transactions = data['transactions'] is List
            ? data['transactions'] as List
            : const [];
        return RefreshIndicator(
            onRefresh: () async => setState(() => _data = _load()),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Beneficios Gudex'),
                        const SizedBox(height: 8),
                        Text('${data['points'] ?? 0}',
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const Text('puntos disponibles'),
                        const SizedBox(height: 12),
                        const Text(
                            'Tus puntos se generan automáticamente con tus compras pagadas. Próximamente podrás canjearlos por beneficios del taller.'),
                      ])),
              const SizedBox(height: 24),
              Text('Historial de puntos',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (transactions.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text(
                            'Todavía no registras movimientos de puntos.'))),
              ...transactions.whereType<Map>().map((row) => Card(
                  child: ListTile(
                      leading: const Icon(Icons.stars_outlined),
                      title: Text('${row['points'] ?? 0} puntos'),
                      subtitle: Text(
                          '${row['note'] ?? 'Movimiento de fidelización'}'),
                      trailing: Text('${row['kind'] ?? ''}')))),
            ]));
      });
}
