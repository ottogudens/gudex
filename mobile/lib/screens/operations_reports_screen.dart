import 'package:flutter/material.dart';
import '../services/api_client.dart';

class OperationsReportsScreen extends StatefulWidget {
  const OperationsReportsScreen(
      {required this.api, required this.productivity, super.key});
  final ApiClient api;
  final bool productivity;
  @override
  State<OperationsReportsScreen> createState() =>
      _OperationsReportsScreenState();
}

class _OperationsReportsScreenState extends State<OperationsReportsScreen> {
  late Future<List<Map<String, dynamic>>> _data;
  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.api.get(widget.productivity
        ? '/api/v1/team/productivity'
        : '/api/v1/maintenance-plans/due');
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  Future<void> _createPlan() async {
    final vehicles = await widget.api.getAll('/api/v1/vehicles');
    if (!mounted || vehicles.isEmpty) return;
    var vehicleId = vehicles.first['id'] as int;
    final name = TextEditingController(text: 'Mantención preventiva');
    final km = TextEditingController();
    final days = TextEditingController();
    final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Nuevo plan preventivo'),
                content: StatefulBuilder(
                    builder: (context, update) => SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              DropdownButtonFormField<int>(
                                  initialValue: vehicleId,
                                  decoration: const InputDecoration(
                                      labelText: 'Vehículo'),
                                  items: vehicles
                                      .map((v) => DropdownMenuItem(
                                          value: v['id'] as int,
                                          child: Text(
                                              '${v['plate']} · ${v['make']} ${v['model']}')))
                                      .toList(),
                                  onChanged: (v) =>
                                      update(() => vehicleId = v!)),
                              TextField(
                                  controller: name,
                                  decoration: const InputDecoration(
                                      labelText: 'Plan / servicio')),
                              TextField(
                                  controller: km,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Intervalo kilometraje (opcional)')),
                              TextField(
                                  controller: days,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Intervalo días (opcional)')),
                            ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, {
                            'vehicle_id': vehicleId,
                            'name': name.text.trim(),
                            if (int.tryParse(km.text) != null)
                              'interval_km': int.parse(km.text),
                            if (int.tryParse(days.text) != null)
                              'interval_days': int.parse(days.text)
                          }),
                      child: const Text('Crear plan'))
                ]));
    name.dispose();
    km.dispose();
    days.dispose();
    if (data == null ||
        data['name'].toString().length < 2 ||
        (!data.containsKey('interval_km') &&
            !data.containsKey('interval_days'))) return;
    try {
      await widget.api.postJson('/api/v1/maintenance-plans', data);
      if (mounted) {
        setState(() => _data = _load());
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Plan preventivo creado.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            final rows = snapshot.data ?? [];
            return RefreshIndicator(
                onRefresh: () async => setState(() => _data = _load()),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text(
                      widget.productivity
                          ? 'Productividad del equipo'
                          : 'Mantenciones preventivas',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(widget.productivity
                      ? 'Horas netas y carga activa por mecánico.'
                      : 'Vehículos que requieren atención por kilometraje o fecha.'),
                  if (!widget.productivity)
                    Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                            onPressed: _createPlan,
                            icon: const Icon(Icons.add),
                            label: const Text('Nuevo plan'))),
                  const SizedBox(height: 18),
                  if (rows.isEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Center(
                            child: Text(widget.productivity
                                ? 'No hay actividad registrada todavía.'
                                : 'No hay mantenciones vencidas.'))),
                  ...rows.map((row) {
                    final vehicle = row['vehicle'] as Map?;
                    final plan = row['plan'] as Map?;
                    final customer = row['customer'] as Map?;
                    return Card(
                        child: ListTile(
                            leading: CircleAvatar(
                                child: Icon(widget.productivity
                                    ? Icons.engineering_outlined
                                    : Icons.car_repair_outlined)),
                            title: Text(widget.productivity
                                ? '${row['full_name']}'
                                : '${vehicle?['plate'] ?? 'Vehículo'} · ${plan?['name'] ?? 'Mantención'}'),
                            subtitle: Text(widget.productivity
                                ? '${((row['net_seconds'] ?? 0) / 3600).toStringAsFixed(1)} h netas · ${row['active_orders']} órdenes activas'
                                : '${customer?['full_name'] ?? 'Cliente'} · ${row['due_by_km'] == true ? 'Kilometraje vencido' : 'Fecha vencida'}')));
                  }),
                ]));
          });
}
