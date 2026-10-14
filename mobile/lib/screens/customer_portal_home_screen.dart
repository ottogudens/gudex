import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/api_client.dart';
import 'vehicle_history_screen.dart';

/// The customer landing screen surfaces the information that needs attention
/// instead of exposing the raw profile response as a generic record list.
class CustomerPortalHomeScreen extends StatefulWidget {
  const CustomerPortalHomeScreen({required this.api, super.key});
  final ApiClient api;

  @override
  State<CustomerPortalHomeScreen> createState() =>
      _CustomerPortalHomeScreenState();
}

class _CustomerPortalHomeScreenState extends State<CustomerPortalHomeScreen> {
  late Future<Map<String, dynamic>> _profile;

  @override
  void initState() {
    super.initState();
    _profile = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final raw = await widget.api.get('/api/v1/portal/profile');
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> _records(Map<String, dynamic> data, String key) {
    final raw = data[key];
    return raw is List
        ? raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 12),
                const Text('No pudimos cargar tu información.'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _profile = _load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ]),
            ));
          }
          final data = snapshot.data ?? <String, dynamic>{};
          final customer = data['customer'] is Map
              ? Map<String, dynamic>.from(data['customer'] as Map)
              : <String, dynamic>{};
          final vehicles = _records(data, 'vehicles');
          final orders = _records(data, 'work_orders');
          final activeOrders = orders
              .where((order) =>
                  order['status'] != 'delivered' &&
                  order['status'] != 'cancelled')
              .toList();
          final scheme = Theme.of(context).colorScheme;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _profile = _load()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hola, ${customer['full_name'] ?? 'cliente'}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(
                            'Aquí puedes revisar el estado de tu vehículo y tus atenciones.',
                            style: TextStyle(color: scheme.onPrimaryContainer)),
                        const SizedBox(height: 18),
                        Wrap(spacing: 24, runSpacing: 10, children: [
                          _Metric(
                              value: vehicles.length.toString(),
                              label: 'vehículos'),
                          _Metric(
                              value: activeOrders.length.toString(),
                              label: 'atenciones activas'),
                        ]),
                      ]),
                ),
                const SizedBox(height: 24),
                Text('Atenciones activas',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (activeOrders.isEmpty)
                  const _PortalEmpty(
                    icon: Icons.task_alt_outlined,
                    text:
                        'No tienes atenciones en curso. Cuando tu vehículo ingrese al taller, verás su avance aquí.',
                  )
                else
                  ...activeOrders
                      .take(3)
                      .map((order) => _OrderCard(order: order)),
                const SizedBox(height: 24),
                Text('Mis vehículos',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (vehicles.isEmpty)
                  const _PortalEmpty(
                    icon: Icons.directions_car_outlined,
                    text: 'Aún no hay vehículos asociados a tu cuenta.',
                  )
                else
                  ...vehicles.map((vehicle) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                              child: Icon(Icons.directions_car_outlined)),
                          title: Text(
                              '${vehicle['plate'] ?? 'Sin patente'} · ${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'),
                          subtitle: Text([
                            if (vehicle['year'] != null) '${vehicle['year']}',
                            if (vehicle['current_mileage_km'] != null)
                              '${vehicle['current_mileage_km']} km',
                          ].join(' · ')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: vehicle['id'] is int
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VehicleHistoryScreen(
                                      api: widget.api,
                                      vehicleId: vehicle['id'] as int,
                                      portal: true,
                                    ),
                                  ))
                              : null,
                        ),
                      )),
              ],
            ),
          );
        },
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        Text(label),
      ]);
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.build_outlined)),
          title: Text('${order['code'] ?? 'Atención'}'),
          subtitle: Text(
              order['reported_symptoms']?.toString().isNotEmpty == true
                  ? order['reported_symptoms'].toString()
                  : 'El taller está actualizando esta atención.'),
          trailing: _PortalStatus(status: '${order['status'] ?? 'received'}'),
        ),
      );
}

class _PortalStatus extends StatelessWidget {
  const _PortalStatus({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final isAlert = {'awaiting_approval', 'quoted'}.contains(status);
    final color = isAlert ? Colors.orange.shade800 : GudexColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(spanishStatus(status),
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _PortalEmpty extends StatelessWidget {
  const _PortalEmpty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: .45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );
}
