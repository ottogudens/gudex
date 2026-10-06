import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/api_client.dart';

class VehicleHistoryScreen extends StatefulWidget {
  const VehicleHistoryScreen({required this.api, required this.vehicleId, required this.portal, super.key});
  final ApiClient api;
  final int vehicleId;
  final bool portal;
  
  @override
  State<VehicleHistoryScreen> createState() => _VehicleHistoryScreenState();
}

class _VehicleHistoryScreenState extends State<VehicleHistoryScreen> {
  late Future<Map<String, dynamic>> _history;
  
  @override
  void initState() { super.initState(); _history = _load(); }
  
  Future<Map<String, dynamic>> _load() async {
    final prefix = widget.portal ? '/api/v1/portal' : '/api/v1';
    final raw = await widget.api.get('$prefix/vehicles/${widget.vehicleId}/history');
    return Map<String, dynamic>.from(raw as Map);
  }
  
  List<Map<String, dynamic>> _maps(dynamic raw) => raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  
  String _date(dynamic value) {
    final text = value.toString().replaceFirst('T', ' ');
    return text.length > 16 ? text.substring(0, 16) : text;
  }
  
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ficha e historial')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
        final data = snapshot.data!;
        final vehicle = Map<String, dynamic>.from(data['vehicle'] as Map);
        final customer = data['customer'] is Map ? Map<String, dynamic>.from(data['customer'] as Map) : <String, dynamic>{};
        final orders = _maps(data['work_orders']);
        final reports = _maps(data['scanner_reports']);
        final appointments = _maps(data['appointments']);
        return RefreshIndicator(
          onRefresh: () async => setState(() => _history = _load()),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${vehicle['plate']} · ${vehicle['make']} ${vehicle['model']}', style: Theme.of(context).textTheme.titleLarge),
              Text('Año ${vehicle['year'] ?? 'sin registro'} · ${vehicle['current_mileage_km'] ?? '—'} km'),
              if (vehicle['vin'] != null) Text('VIN: ${vehicle['vin']}'),
              if (customer.isNotEmpty) Text('Cliente: ${customer['full_name']}${customer['phone'] == null ? '' : ' · ${customer['phone']}'}'),
            ]))),
            const SizedBox(height: 12),
            Text('Órdenes de trabajo', style: Theme.of(context).textTheme.titleMedium),
            if (orders.isEmpty) const ListTile(title: Text('Sin trabajos registrados')),
            ...orders.map((order) => Card(child: ListTile(
              leading: const Icon(Icons.build_outlined),
              title: Text('${order['code']} · ${spanishStatus(order['status'])}'),
              subtitle: Text('${_date(order['opened_at'])}${order['diagnosis'] == null ? '' : '\n${order['diagnosis']}'}'),
              isThreeLine: order['diagnosis'] != null,
            ))),
            const SizedBox(height: 12),
            Text('Informes scanner LAUNCH', style: Theme.of(context).textTheme.titleMedium),
            if (reports.isEmpty) const ListTile(title: Text('Sin informes scanner adjuntos')),
            ...reports.map((report) => Card(child: ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(report['filename'].toString()),
              subtitle: Text('${_date(report['scanned_at'])}${report['mileage_km'] == null ? '' : ' · ${report['mileage_km']} km'}'),
              trailing: IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () async {
                try { await openGudexPdf(widget.api, report['download_url'].toString(), report['filename'].toString()); } catch (_) {}
              }),
            ))),
            const SizedBox(height: 12),
            Text('Citas', style: Theme.of(context).textTheme.titleMedium),
            ...appointments.map((appointment) => ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(appointment['service_type'].toString()),
              subtitle: Text('${_date(appointment['starts_at'])} · ${spanishStatus(appointment['status'])}'),
            )),
          ]),
        );
      },
    ),
  );
}
