import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../services/api_client.dart';

class CustomerAppointmentsScreen extends StatefulWidget {
  const CustomerAppointmentsScreen({required this.api, super.key});
  final ApiClient api;
  
  @override
  State<CustomerAppointmentsScreen> createState() => _CustomerAppointmentsScreenState();
}

class _CustomerAppointmentsScreenState extends State<CustomerAppointmentsScreen> {
  late Future<List<Map<String, dynamic>>> _appointments;
  late Future<List<Map<String, dynamic>>> _vehicles;
  
  @override
  void initState() { 
    super.initState(); 
    _appointments = _loadAppointments(); 
    _vehicles = _loadVehicles(); 
  }
  
  Future<List<Map<String, dynamic>>> _maps(String path) async {
    final raw = await widget.api.get(path);
    return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }
  
  Future<List<Map<String, dynamic>>> _loadAppointments() => _maps('/api/v1/portal/appointments');
  
  Future<List<Map<String, dynamic>>> _loadVehicles() async {
    final raw = await widget.api.get('/api/v1/portal/profile');
    final rows = raw is Map ? raw['vehicles'] : null;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }
  
  Future<void> _request() async {
    final vehicles = await _vehicles;
    if (!mounted) return;
    if (vehicles.isEmpty) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Primero registra un vehículo con el taller.'))); 
      return; 
    }
    int vehicleId = vehicles.first['id'] as int;
    final service = TextEditingController(text: 'Mantención preventiva');
    final notes = TextEditingController();
    final date = await showDatePicker(
      context: context, 
      initialDate: DateTime.now().add(const Duration(days: 1)), 
      firstDate: DateTime.now(), 
      lastDate: DateTime.now().add(const Duration(days: 365))
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (time == null || !mounted) return;
    final accepted = await showDialog<bool>(
      context: context, 
      builder: (context) => AlertDialog(
        title: const Text('Solicitar cita'),
        content: StatefulBuilder(builder: (context, update) => SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            value: vehicleId, 
            decoration: const InputDecoration(labelText: 'Vehículo'), 
            items: vehicles.map((v) => DropdownMenuItem(value: v['id'] as int, child: Text('${v['plate']} · ${v['make']}'))).toList(), 
            onChanged: (value) { if (value != null) update(() => vehicleId = value); }
          ),
          const SizedBox(height: 10), 
          TextField(controller: service, decoration: const InputDecoration(labelText: 'Servicio solicitado')),
          const SizedBox(height: 10), 
          TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Observaciones')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), 
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enviar solicitud'))
        ],
      )
    );
    if (accepted != true) { service.dispose(); notes.dispose(); return; }
    try {
      final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      await widget.api.postJson('/api/v1/portal/appointments', {
        'vehicle_id': vehicleId, 
        'starts_at': start.toUtc().toIso8601String(), 
        'ends_at': start.add(const Duration(hours: 1)).toUtc().toIso8601String(), 
        'service_type': service.text.trim(), 
        if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim()
      });
      if (mounted) { 
        setState(() => _appointments = _loadAppointments()); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solicitud enviada al taller.'))); 
      }
    } catch (error) { 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); 
    }
    service.dispose(); 
    notes.dispose();
  }
  
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _appointments, 
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
      final appointments = snapshot.data ?? [];
      return Stack(children: [
        RefreshIndicator(
          onRefresh: () async => setState(() => _appointments = _loadAppointments()), 
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), 
            children: [
              if (appointments.isEmpty) const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: Text('Aún no tienes citas solicitadas.'))),
              ...appointments.map((item) => Card(child: ListTile(
                leading: const Icon(Icons.event_outlined), 
                title: Text(item['service_type'].toString()), 
                subtitle: Text(item['starts_at'].toString().replaceFirst('T', ' ').substring(0, 16)), 
                trailing: Text(spanishStatus(item['status']))
              ))),
            ]
          )
        ), 
        Positioned(
          right: 18, 
          bottom: 18, 
          child: FloatingActionButton.extended(
            onPressed: _request, 
            icon: const Icon(Icons.add), 
            label: const Text('Solicitar cita')
          )
        )
      ]);
    }
  );
}
