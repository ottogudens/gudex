import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../core/constants.dart';
import 'vehicle_history_screen.dart';

/// Describes a navigable module tab (used by [ModuleList]).
class AppModule {
  const AppModule({
    required this.title,
    required this.icon,
    required this.path,
    this.keyName,
  });
  final String title;
  final IconData icon;
  final String path;
  final String? keyName;
}

class ModuleList extends StatefulWidget {
  const ModuleList({required this.api, required this.module, required this.role, super.key});
  final ApiClient api;
  final AppModule module;
  final String role;

  @override
  State<ModuleList> createState() => _ModuleListState();
}

class _ModuleListState extends State<ModuleList> {
  late Future<List<dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = _load();
  }

  @override
  void didUpdateWidget(covariant ModuleList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module.path != widget.module.path) _items = _load();
  }

  Future<List<dynamic>> _load() async {
    final data = await widget.api.get(widget.module.path);
    if (data is List) return data;
    if (data is Map && widget.module.keyName != null) {
      final value = data[widget.module.keyName];
      return value is List ? value : <dynamic>[];
    }
    return <dynamic>[];
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(), SizedBox(height: 12), Text('Cargando información…'),
            ]),
          );
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('No se pudo cargar ${widget.module.title.toLowerCase()}.', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('${snapshot.error}'.replaceFirst('Exception: ', ''), textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: () => setState(() => _items = _load()),
                icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
            ],
          )));
          final items = snapshot.data ?? [];
          if (items.isEmpty) return RefreshIndicator(
            onRefresh: () async => setState(() => _items = _load()),
            child: ListView(children: [SizedBox(height: 360, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 64, height: 64, decoration: const BoxDecoration(color: Color(0xFFE5F2F4), shape: BoxShape.circle),
                child: const Icon(Icons.inbox_outlined, color: GudexColors.primary, size: 30)),
              const SizedBox(height: 14),
              Text('Aún no hay ${widget.module.title.toLowerCase()}.', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              const Text('Desliza hacia abajo para actualizar.', style: TextStyle(color: Color(0xFF637986))),
            ])))]),
          );
          return RefreshIndicator(
            onRefresh: () async => setState(() => _items = _load()),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final data = Map<String, dynamic>.from(items[index] as Map);
                final canApprove = widget.module.path == '/api/v1/portal/quotes' && data['status'] == 'sent' && data['id'] is int;
                return RecordCard(
                  data: data,
                  onApprove: canApprove ? () => _answerQuote(data['id'] as int, true) : null,
                  onReject: canApprove ? () => _answerQuote(data['id'] as int, false) : null,
                  onOpen: widget.module.path == '/api/v1/portal/work-orders' && data['id'] is int
                      ? () => _showInspectionReport(data['id'] as int)
                      : widget.module.path == '/api/v1/portal/profile' && data['id'] is int
                          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => VehicleHistoryScreen(api: widget.api, vehicleId: data['id'] as int, portal: true)))
                      : null,
                );
              },
            ),
          );
        },
      );

  Future<void> _answerQuote(int id, bool approved) async {
    try {
      await widget.api.post('/api/v1/portal/quotes/$id/approval?approved=$approved');
      if (!mounted) return;
      setState(() => _items = _load());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Respuesta registrada')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showInspectionReport(int orderId) async {
    try {
      final raw = await widget.api.get('/api/v1/portal/work-orders/$orderId/inspection-report');
      final report = Map<String, dynamic>.from(raw as Map);
      final summary = Map<String, dynamic>.from(report['summary'] as Map? ?? {});
      final inspections = report['inspections'] is List ? report['inspections'] as List : const [];
      final scanner = report['scanner_reports'] is List ? report['scanner_reports'] as List : const [];
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text('Informe ${report['order']?['code'] ?? ''}'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Normales: ${summary['normal'] ?? 0} · Observaciones: ${summary['observation'] ?? 0} · Fallas: ${summary['failed'] ?? 0}'),
          Text('Pendientes: ${summary['not_inspected'] ?? 0} · Informes LAUNCH: ${scanner.length}'),
          const Divider(),
          for (final rawItem in inspections)
            ListTile(contentPadding: EdgeInsets.zero, dense: true,
              leading: Icon(rawItem['result'] == 'normal' ? Icons.check_circle_outline : Icons.info_outline),
              title: Text('${rawItem['category']}: ${rawItem['item']}'),
              subtitle: Text('${rawItem['result']}${rawItem['notes'] == null ? '' : ' · ${rawItem['notes']}'}')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          FilledButton.icon(onPressed: () async {
            try {
              await openGudexPdf(widget.api, '/api/v1/portal/work-orders/$orderId/inspection-report.pdf', 'Gudex-inspeccion-$orderId.pdf');
            } catch (error) {
              if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('No se pudo abrir el informe: $error')));
            }
          }, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF')),
        ],
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class RecordCard extends StatelessWidget {
  const RecordCard({required this.data, this.onApprove, this.onReject, this.onOpen, super.key});
  final Map<String, dynamic> data;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onOpen;

  String _displayValue(String key, dynamic value) {
    if (value == null || value is Map || value is List) return '';
    if (key.endsWith('_clp')) return '\$${value.toString()}';
    return spanishStatus(value);
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((entry) =>
        !{'id', 'customer_id', 'vehicle_id', 'work_order_id', 'storage_path', 'google_event_id'}.contains(entry.key) &&
        _displayValue(entry.key, entry.value).isNotEmpty).take(4).toList();
    final title = (data['code'] ?? data['plate'] ?? data['full_name'] ?? data['name'] ?? data['description'] ?? data['service_type'] ?? 'Registro').toString();
    final status = data['status']?.toString();
    final statusStyle = _statusStyle(context, status);
    return Card(margin: const EdgeInsets.symmetric(vertical: 6), child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface))),
          if (statusStyle != null) ...[
            const SizedBox(width: 8),
            Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: statusStyle.$1, borderRadius: BorderRadius.circular(30)),
              child: Text(spanishStatus(status), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: statusStyle.$2, fontSize: 10, fontWeight: FontWeight.w700)))),
          ],
        ]),
        for (final entry in entries)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('${spanishField(entry.key)}: ${_displayValue(entry.key, entry.value)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        if (onApprove != null || onReject != null || onOpen != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            if (onOpen != null) OutlinedButton.icon(onPressed: onOpen, icon: const Icon(Icons.fact_check_outlined), label: const Text('Ver inspección')),
            if (onReject != null) OutlinedButton(onPressed: onReject, child: const Text('Rechazar')),
            if (onApprove != null) FilledButton(onPressed: onApprove, child: const Text('Aprobar')),
          ]),
        ],
      ]),
    ));
  }

  (Color, Color)? _statusStyle(BuildContext context, String? status) {
    if (status == null) return null;
    if ({'failed', 'cancelled', 'rejected', 'quote_rejected'}.contains(status)) {
      return (Theme.of(context).colorScheme.errorContainer, Theme.of(context).colorScheme.onErrorContainer);
    }
    if ({'ready', 'delivered', 'approved', 'paid', 'normal', 'completed'}.contains(status)) {
      return (const Color(0xFFE3F3E9), GudexColors.success);
    }
    if ({'in_progress', 'inspecting', 'awaiting_approval', 'requested', 'sent', 'pending'}.contains(status)) {
      return (const Color(0xFFFFF2D8), const Color(0xFF835A00));
    }
    return (const Color(0xFFE5F2F4), GudexColors.primary);
  }
}
