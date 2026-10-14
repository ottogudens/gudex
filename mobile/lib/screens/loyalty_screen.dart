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
    final values = await Future.wait([
      widget.api.get('/api/v1/portal/loyalty'),
      widget.api.get('/api/v1/portal/rewards')
    ]);
    final data = values[0] is Map
        ? Map<String, dynamic>.from(values[0] as Map)
        : <String, dynamic>{};
    data['rewards'] = values[1];
    return data;
  }

  Future<void> _redeem(Map reward) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Solicitar canje'),
                content: Text(
                    '¿Quieres solicitar “${reward['name']}” por ${reward['points_cost']} puntos? El taller confirmará la entrega.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Volver')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Solicitar'))
                ]));
    if (confirmed != true) return;
    try {
      await widget.api.post('/api/v1/portal/rewards/${reward['id']}/redeem');
      if (mounted) {
        setState(() => _data = _load());
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Canje solicitado al taller.')));
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
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
        final rewards =
            data['rewards'] is List ? data['rewards'] as List : const [];
        final points =
            data['points'] is num ? (data['points'] as num).toInt() : 0;
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
                        Text('$points',
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const Text('puntos disponibles'),
                        const SizedBox(height: 12),
                        const Text(
                            'Tus puntos se generan automáticamente con tus compras pagadas y puedes canjearlos por beneficios disponibles.'),
                      ])),
              const SizedBox(height: 24),
              Text('Recompensas disponibles',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (rewards.isEmpty)
                const Text('El taller aún no ha publicado beneficios.'),
              ...rewards.whereType<Map>().map((reward) => Card(
                  child: ListTile(
                      leading: const Icon(Icons.card_giftcard_outlined),
                      title: Text('${reward['name']}'),
                      subtitle: Text(
                          '${reward['description'] ?? 'Beneficio Gudex'} · ${reward['points_cost']} puntos'),
                      trailing: FilledButton(
                          onPressed:
                              points >= (reward['points_cost'] as num? ?? 0)
                                  ? () => _redeem(reward)
                                  : null,
                          child: const Text('Canjear'))))),
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
