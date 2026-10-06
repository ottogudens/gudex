import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../services/api_client.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.api, required this.onOpenModule, super.key});
  final ApiClient api;
  final void Function(int index) onOpenModule;
  
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> _data;
  
  @override
  void initState() { super.initState(); _data = _load(); }
  
  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(await widget.api.get('/api/v1/dashboard') as Map);
  
  int _number(dynamic value) => value is num ? value.round() : int.tryParse(value.toString()) ?? 0;
  
  String _money(dynamic value) => '\$${_number(value)} CLP';
  
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
      final data = snapshot.data!;
      final metrics = Map<String, dynamic>.from(data['metrics'] as Map);
      final urgent = data['urgent_orders'] is List ? data['urgent_orders'] as List : const [];
      final schedule = data['today_schedule'] is List ? data['today_schedule'] as List : const [];
      final stock = data['low_stock_items'] is List ? data['low_stock_items'] as List : const [];
      return RefreshIndicator(onRefresh: () async => setState(() => _data = _load()), child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
        Text('Panel principal', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4), const Text('Resumen operativo del taller para hoy.'),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _DashboardMetric(label: 'Órdenes activas', value: _number(metrics['active_orders']).toString(), icon: Icons.build_outlined, color: GudexColors.primary, onTap: () => widget.onOpenModule(1)),
          _DashboardMetric(label: 'Trabajos atrasados', value: _number(metrics['overdue_orders']).toString(), icon: Icons.warning_amber_outlined, color: Colors.deepOrange, onTap: () => widget.onOpenModule(1)),
          _DashboardMetric(label: 'Citas de hoy', value: _number(metrics['today_appointments']).toString(), icon: Icons.calendar_today_outlined, color: GudexColors.success, onTap: () => widget.onOpenModule(4)),
          _DashboardMetric(label: 'Solicitudes nuevas', value: _number(metrics['requested_appointments']).toString(), icon: Icons.mark_email_unread_outlined, color: Colors.amber.shade800, onTap: () => widget.onOpenModule(4)),
          _DashboardMetric(label: 'Stock bajo', value: _number(metrics['low_stock']).toString(), icon: Icons.inventory_2_outlined, color: Colors.deepPurple, onTap: () => widget.onOpenModule(3)),
          _DashboardMetric(label: 'Ventas cobradas hoy', value: _money(metrics['sales_today_clp']), icon: Icons.point_of_sale_outlined, color: Colors.teal, onTap: () => widget.onOpenModule(6)),
        ]),
        const SizedBox(height: 20),
        Text('Requiere atención', style: Theme.of(context).textTheme.titleLarge),
        if (urgent.isEmpty) const Card(child: ListTile(leading: Icon(Icons.check_circle_outline, color: GudexColors.success), title: Text('No hay órdenes vencidas.'))),
        ...urgent.map((item) => Card(child: ListTile(leading: const Icon(Icons.warning_amber_outlined), title: Text(item['code'].toString()), subtitle: Text('Estado: ${spanishStatus(item['status'])}${item['technician_name'] == null ? '' : ' · ${item['technician_name']}'}'), onTap: () => widget.onOpenModule(1)))),
        const SizedBox(height: 12),
        Text('Agenda de hoy', style: Theme.of(context).textTheme.titleLarge),
        if (schedule.isEmpty) const Card(child: ListTile(leading: Icon(Icons.event_available_outlined), title: Text('No hay citas pendientes hoy.'))),
        ...schedule.map((item) => Card(child: ListTile(leading: const Icon(Icons.event_outlined), title: Text(item['service_type'].toString()), subtitle: Text('${item['starts_at'].toString().replaceFirst('T', ' ').substring(0, 16)} · ${spanishStatus(item['status'])}'), onTap: () => widget.onOpenModule(4)))),
        const SizedBox(height: 12),
        Text('Reposición prioritaria', style: Theme.of(context).textTheme.titleLarge),
        if (stock.isEmpty) const Card(child: ListTile(leading: Icon(Icons.inventory_outlined), title: Text('No hay alertas de stock.'))),
        ...stock.map((item) => Card(child: ListTile(leading: const Icon(Icons.inventory_2_outlined), title: Text(item['name'].toString()), subtitle: Text('Disponible: ${item['stock_quantity']} ${item['unit']} · mínimo: ${item['minimum_quantity']}'), onTap: () => widget.onOpenModule(3)))),
      ]));
    },
  );
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({required this.label, required this.value, required this.icon, required this.color, required this.onTap});
  final String label; final String value; final IconData icon; final Color color; final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) => SizedBox(width: 170, child: Card(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: color), const SizedBox(height: 12), Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), Text(label, style: Theme.of(context).textTheme.bodySmall),
  ])))));
}
