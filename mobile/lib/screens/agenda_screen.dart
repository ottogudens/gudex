import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/api_client.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({required this.api, required this.role, super.key});
  final ApiClient api;
  final String role;
  
  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _week = DateTime.now();
  late Future<List<Map<String, dynamic>>> _appointments;
  
  @override
  void initState() { super.initState(); _appointments = _load(); }
  
  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.api.get('/api/v1/appointments');
    return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }
  
  DateTime _at(dynamic value) => DateTime.tryParse(value.toString())?.toLocal() ?? DateTime(2000);
  String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  
  Future<void> _changeStatus(int id, String status) async {
    await widget.api.patchJson('/api/v1/appointments/$id/status?status=$status', {});
    if (mounted) setState(() => _appointments = _load());
  }
  
  Future<void> _createAppointment() async {
    final raw = await widget.api.get('/api/v1/customers');
    final customers = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    if (customers.isEmpty || !mounted) { 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registra un cliente antes de agendar.'))); 
      return; 
    }
    int customerId = customers.first['id'] as int;
    final service = TextEditingController(text: 'Mantención preventiva');
    final date = await showDatePicker(
      context: context, 
      initialDate: DateTime.now(), 
      firstDate: DateTime.now().subtract(const Duration(days: 1)), 
      lastDate: DateTime.now().add(const Duration(days: 365))
    );
    if (date == null || !mounted) { service.dispose(); return; }
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (time == null || !mounted) { service.dispose(); return; }
    final confirmed = await showDialog<bool>(
      context: context, 
      builder: (context) => AlertDialog(
        title: const Text('Agendar cita'), 
        content: StatefulBuilder(builder: (context, update) => Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            initialValue: customerId,
            decoration: const InputDecoration(labelText: 'Cliente'), 
            items: customers.map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['full_name'].toString()))).toList(), 
            onChanged: (value) { if (value != null) update(() => customerId = value); }
          ),
          const SizedBox(height: 10), 
          TextField(controller: service, decoration: const InputDecoration(labelText: 'Servicio')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), 
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Agendar'))
        ],
      )
    );
    if (confirmed == true) {
      try {
        final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        await widget.api.postJson('/api/v1/appointments', {
          'customer_id': customerId, 
          'starts_at': start.toUtc().toIso8601String(), 
          'ends_at': start.add(const Duration(hours: 1)).toUtc().toIso8601String(), 
          'service_type': service.text.trim()
        });
        if (mounted) setState(() => _appointments = _load());
      } catch (error) { 
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); 
      }
    }
    service.dispose();
  }
  
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _appointments, 
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
      final rows = snapshot.data ?? [];
      final start = DateTime(_week.year, _week.month, _week.day).subtract(Duration(days: _week.weekday - 1));
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 8), child: Row(children: [
          IconButton(onPressed: () => setState(() => _week = _week.subtract(const Duration(days: 7))), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('Agenda · semana del ${_date(start)}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(onPressed: () => setState(() => _week = _week.add(const Duration(days: 7))), icon: const Icon(Icons.chevron_right)),
          if (widget.role == 'admin') IconButton(onPressed: _createAppointment, icon: const Icon(Icons.add_circle_outline), tooltip: 'Agendar cita'),
        ])),
        Expanded(child: RefreshIndicator(
          onRefresh: () async => setState(() => _appointments = _load()), 
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), 
            itemCount: 7,
            itemBuilder: (context, index) {
              final day = start.add(Duration(days: index));
              final records = rows.where((row) { 
                final date = _at(row['starts_at']); 
                return date.year == day.year && date.month == day.month && date.day == day.day; 
              }).toList();
              return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_date(day)} · ${const ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'][index]}', style: Theme.of(context).textTheme.titleSmall),
                if (records.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Sin citas')),
                ...records.map((item) { 
                  final at = _at(item['starts_at']); 
                  return ListTile(
                    contentPadding: EdgeInsets.zero, 
                    leading: const Icon(Icons.event_available_outlined),
                    title: Text('${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} · ${item['service_type']}'),
                    subtitle: Text('Cliente #${item['customer_id']} · ${spanishStatus(item['status'])}'),
                    trailing: widget.role == 'admin' && item['status'] == 'requested' ? FilledButton(onPressed: () => _changeStatus(item['id'] as int, 'confirmed'), child: const Text('Confirmar')) : null,
                  ); 
                }),
              ])));
            },
          )
        )),
      ]);
    }
  );
}
