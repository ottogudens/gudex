import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../services/api_client.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({required this.api, required this.role, super.key});
  final ApiClient api;
  final String role;
  
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late Future<List<Map<String, dynamic>>> _vehicles;
  late Future<List<Map<String, dynamic>>> _orders;
  int? _vehicleId;
  int? _orderId;
  late Future<List<Map<String, dynamic>>> _reports;
  
  @override
  void initState() {
    super.initState();
    _vehicles = _list('/api/v1/vehicles');
    _orders = _list('/api/v1/work-orders');
    _reports = Future.value(<Map<String, dynamic>>[]);
  }
  
  Future<List<Map<String, dynamic>>> _list(String path) async {
    final raw = await widget.api.get(path);
    return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }
  
  Future<void> _selectVehicle(int? value) async {
    setState(() { 
      _vehicleId = value; 
      _orderId = null; 
      _reports = value == null ? Future.value(<Map<String, dynamic>>[]) : _list('/api/v1/vehicles/$value/scanner-reports'); 
    });
  }
  
  Future<void> _upload() async {
    if (_vehicleId == null) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona un vehículo antes de adjuntar el informe.'))); 
      return; 
    }
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (picked == null || picked.files.single.bytes == null) return;
    try {
      var path = '/api/v1/scanner-reports?vehicle_id=$_vehicleId';
      if (_orderId != null) path += '&work_order_id=$_orderId';
      await widget.api.uploadBytes(path, picked.files.single.bytes!, picked.files.single.name, contentType: 'application/pdf');
      if (mounted) { 
        setState(() => _reports = _list('/api/v1/vehicles/$_vehicleId/scanner-reports')); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe LAUNCH adjuntado.'))); 
      }
    } catch (error) { 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); 
    }
  }
  
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _vehicles,
    builder: (context, vehiclesSnapshot) {
      if (vehiclesSnapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (vehiclesSnapshot.hasError) return Center(child: Text(vehiclesSnapshot.error.toString()));
      final vehicles = vehiclesSnapshot.data ?? [];
      return FutureBuilder<List<Map<String, dynamic>>>(future: _orders, builder: (context, ordersSnapshot) {
        final orders = ordersSnapshot.data ?? [];
        final availableOrders = orders.where((order) => order['vehicle_id'] == _vehicleId).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Scanner automotriz LAUNCH X-431 PRO', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6), const Text('Vincula el informe PDF al vehículo y, cuando corresponda, a su orden de trabajo.'),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _vehicleId, 
            decoration: const InputDecoration(labelText: 'Vehículo'), 
            items: vehicles.map((v) => DropdownMenuItem(value: v['id'] as int, child: Text('${v['plate']} · ${v['make']} ${v['model']}'))).toList(), 
            onChanged: _selectVehicle
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: _orderId, 
            decoration: const InputDecoration(labelText: 'Orden de trabajo (opcional)'), 
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Solo historial del vehículo')), 
              ...availableOrders.map((o) => DropdownMenuItem<int?>(value: o['id'] as int, child: Text(o['code'].toString())))
            ], 
            onChanged: (value) => setState(() => _orderId = value)
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _upload, icon: const Icon(Icons.upload_file_outlined), label: const Text('Adjuntar informe PDF')),
          const SizedBox(height: 20), Text('Informes asociados', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<List<Map<String, dynamic>>>(future: _reports, builder: (context, reportsSnapshot) {
            if (reportsSnapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            final reports = reportsSnapshot.data ?? [];
            if (_vehicleId == null) return const Padding(padding: EdgeInsets.only(top: 12), child: Text('Selecciona un vehículo para ver sus informes.'));
            if (reports.isEmpty) return const Padding(padding: EdgeInsets.only(top: 12), child: Text('No hay informes para este vehículo.'));
            return Column(children: reports.map((report) => Card(child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined), 
              title: Text(report['filename'].toString()), 
              subtitle: Text(report['scanned_at'].toString().replaceFirst('T', ' ').substring(0, 16)), 
              trailing: IconButton(
                onPressed: () async { 
                  try { 
                    await openGudexPdf(widget.api, '/api/v1/scanner-reports/${report['id']}/file', report['filename'].toString()); 
                  } catch (_) {} 
                }, 
                icon: const Icon(Icons.open_in_new)
              )
            ))).toList());
          }),
        ]);
      });
    },
  );
}
