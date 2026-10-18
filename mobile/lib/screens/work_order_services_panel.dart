import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';

const _kinds = <String, String>{
  'inspection': 'Inspección',
  'scanner': 'Diagnóstico con scanner',
  'preventive': 'Mantención preventiva',
  'corrective': 'Reparación correctiva',
  'pre_purchase': 'Inspección precompra',
  'pre_technical_review': 'Inspección prerevisión técnica',
  'other': 'Otro servicio',
};
const _serviceStatuses = {'pending': 'Pendiente', 'in_progress': 'En ejecución',
  'blocked': 'Bloqueado', 'completed': 'Terminado', 'cancelled': 'Cancelado'};
const _partStatuses = {'received': 'Recibido', 'installed': 'Instalado',
  'not_installed': 'No instalado'};
const _kindIcons = <String, IconData>{
  'inspection': Icons.fact_check_outlined,
  'scanner': Icons.monitor_heart_outlined,
  'preventive': Icons.build_circle_outlined,
  'corrective': Icons.handyman_outlined,
  'pre_purchase': Icons.car_rental_outlined,
  'pre_technical_review': Icons.verified_outlined,
  'other': Icons.add_task_outlined,
};

class WorkOrderServicesPanel extends StatefulWidget {
  const WorkOrderServicesPanel({required this.api, required this.orderId,
    required this.vehicleId, required this.role, this.onChanged, this.onAddInspection,
    this.onApplyTemplate, this.onEditInspection, super.key});
  final ApiClient api;
  final int orderId;
  final int vehicleId;
  final String role;
  final VoidCallback? onChanged;
  final Future<void> Function(int serviceId)? onAddInspection;
  final Future<void> Function(int serviceId)? onApplyTemplate;
  final Future<void> Function(Map<String, dynamic> inspection)? onEditInspection;

  @override
  State<WorkOrderServicesPanel> createState() => _WorkOrderServicesPanelState();
}

class _WorkOrderServicesPanelState extends State<WorkOrderServicesPanel> {
  late Future<List<Map<String, dynamic>>> _services;
  late Future<List<Map<String, dynamic>>> _parts;
  late Future<Map<String, dynamic>> _sessions;
  late Future<List<Map<String, dynamic>>> _inspections;
  late Future<List<Map<String, dynamic>>> _scannerReports;
  late Future<List<Map<String, dynamic>>> _evidence;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final rows = await widget.api.get(path);
    return rows is List
        ? rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
        : [];
  }

  void _reload() {
    setState(() {
      _services = _list('/api/v1/work-orders/${widget.orderId}/services');
      _parts = _list('/api/v1/work-orders/${widget.orderId}/parts');
      _sessions = widget.api.get('/api/v1/work-orders/${widget.orderId}/work-sessions')
          .then((value) => Map<String, dynamic>.from(value as Map));
      _inspections = _list('/api/v1/work-orders/${widget.orderId}/inspections');
      _scannerReports = _list('/api/v1/vehicles/${widget.vehicleId}/scanner-reports');
      _evidence = _list('/api/v1/work-orders/${widget.orderId}/evidence');
    });
  }

  Future<void> _timer(Map<String, dynamic> service, String action, [int? sessionId]) async {
    try {
      final path = action == 'start'
          ? '/api/v1/work-orders/${widget.orderId}/work-sessions/start?work_order_service_id=${service['id']}'
          : '/api/v1/work-sessions/$sessionId/$action';
      await widget.api.post(path);
      _reload();
    } catch (error) { _notice(error); }
  }

  Widget _serviceTimer(Map<String, dynamic> service) => FutureBuilder<Map<String, dynamic>>(
    future: _sessions, builder: (context, snapshot) {
      final rows = snapshot.data?['sessions'] is List
          ? (snapshot.data!['sessions'] as List).whereType<Map>()
              .where((row) => row['work_order_service_id'] == service['id']).toList()
          : <Map>[];
      final now = DateTime.now();
      var seconds = 0;
      Map? active;
      for (final row in rows) {
        final start = DateTime.tryParse('${row['started_at']}');
        final end = DateTime.tryParse('${row['ended_at'] ?? row['paused_at']}') ?? now;
        if (start != null) seconds += (end.difference(start).inSeconds -
            ((row['paused_seconds'] as num?)?.toInt() ?? 0)).clamp(0, 999999999).toInt();
        if (row['ended_at'] == null && row['is_mine'] == true) active = row;
      }
      final time = '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
          '${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}';
      return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
        const Icon(Icons.timer_outlined, size: 18), Text('$time h trabajadas'),
        if (active == null) TextButton.icon(onPressed: () => _timer(service, 'start'),
          icon: const Icon(Icons.play_arrow), label: const Text('Iniciar tiempo'))
        else ...[
          IconButton(tooltip: active!['paused_at'] == null ? 'Pausar' : 'Reanudar',
            onPressed: () => _timer(service, active!['paused_at'] == null ? 'pause' : 'resume',
              active!['id'] as int),
            icon: Icon(active!['paused_at'] == null ? Icons.pause : Icons.play_arrow)),
          IconButton(tooltip: 'Finalizar tiempo',
            onPressed: () => _timer(service, 'stop', active!['id'] as int),
            icon: const Icon(Icons.stop)),
        ],
      ]);
    });

  void _notice(Object error) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))));
  }

  Future<void> _chooseModule() async {
    final kind = await showDialog<String>(context: context, builder: (context) =>
      SimpleDialog(title: const Text('Agregar módulo a la orden'),
        children: _kinds.entries.map((entry) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, entry.key),
          child: ListTile(
            leading: Icon(_kindIcons[entry.key]),
            title: Text(entry.value),
            dense: true,
          ))).toList()));
    if (kind != null && mounted) await _addService(kind);
  }

  Future<void> _addService(String kind) async {
    final name = TextEditingController(text: _kinds[kind]);
    final description = TextEditingController();
    int? catalogId;
    int? assignee;
    try {
      final catalog = await _list('/api/v1/services');
      final mechanics = await _list('/api/v1/team/mechanics');
      if (!mounted) return;
      final accepted = await showDialog<bool>(context: context, builder: (context) =>
        StatefulBuilder(builder: (context, redraw) => AlertDialog(
          title: Text('Nuevo módulo · ${_kinds[kind]}'),
          content: SizedBox(width: 430, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int?>(initialValue: catalogId,
                decoration: const InputDecoration(labelText: 'Servicio del catálogo (opcional)'),
                items: [const DropdownMenuItem<int?>(value: null, child: Text('Servicio manual')),
                  ...catalog.map((row) => DropdownMenuItem<int?>(value: row['id'] as int,
                    child: Text('${row['name']}')))],
                onChanged: (value) => redraw(() {
                  catalogId = value;
                  final selected = catalog.where((row) => row['id'] == value);
                  if (selected.isNotEmpty) name.text = '${selected.first['name']}';
                })),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del trabajo')),
              TextField(controller: description, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Alcance / instrucciones')),
              DropdownButtonFormField<int?>(initialValue: assignee,
                decoration: const InputDecoration(labelText: 'Mecánico (opcional)'),
                items: [const DropdownMenuItem<int?>(value: null, child: Text('Responsable de la orden')),
                  ...mechanics.map((row) => DropdownMenuItem<int?>(value: row['id'] as int,
                    child: Text('${row['full_name']}')))],
                onChanged: (value) => redraw(() => assignee = value)),
            ]))),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Agregar'))],
        )));
      if (accepted != true) return;
      await widget.api.postJson('/api/v1/work-orders/${widget.orderId}/services', {
        'kind': kind, 'name': name.text.trim(), 'description': description.text.trim(),
        if (catalogId != null) 'catalog_service_id': catalogId,
        if (assignee != null) 'assigned_user_id': assignee,
      });
      _reload();
      widget.onChanged?.call();
    } catch (error) { _notice(error); }
    finally { name.dispose(); description.dispose(); }
  }

  Future<void> _updateService(Map<String, dynamic> service, String status) async {
    try {
      await widget.api.patchJson('/api/v1/work-orders/${widget.orderId}/services/${service['id']}',
        {'status': status});
      _reload();
    } catch (error) { _notice(error); }
  }

  Future<void> _editFindings(Map<String, dynamic> service) async {
    final controller = TextEditingController(text: '${service['findings'] ?? ''}');
    try {
      final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Hallazgos y trabajo realizado'),
        content: SizedBox(width: 430, child: TextField(controller: controller, maxLines: 5,
          decoration: const InputDecoration(labelText: 'Observaciones técnicas'))),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar'))]));
      if (accepted == true) {
        await widget.api.patchJson('/api/v1/work-orders/${widget.orderId}/services/${service['id']}',
          {'findings': controller.text.trim()});
        _reload();
      }
    } catch (error) { _notice(error); }
    finally { controller.dispose(); }
  }

  Future<void> _assignService(Map<String, dynamic> service) async {
    try {
      final mechanics = await _list('/api/v1/team/mechanics');
      if (!mounted) return;
      final selected = await showDialog<int>(context: context, builder: (context) => SimpleDialog(
        title: const Text('Asignar responsable del servicio'),
        children: [SimpleDialogOption(onPressed: () => Navigator.pop(context, -1),
          child: const Text('Responsable general de la orden')),
          ...mechanics.map((row) => SimpleDialogOption(onPressed: () => Navigator.pop(context, row['id'] as int),
            child: Text('${row['full_name']}')))]));
      if (selected == null) return;
      await widget.api.patchJson('/api/v1/work-orders/${widget.orderId}/services/${service['id']}',
        {'assigned_user_id': selected == -1 ? null : selected});
      _reload();
    } catch (error) { _notice(error); }
  }

  Future<void> _addPart(Map<String, dynamic> service) async {
    final name = TextEditingController();
    final category = TextEditingController();
    final brand = TextEditingController();
    final number = TextEditingController();
    final oem = TextEditingController();
    final specs = TextEditingController();
    final qty = TextEditingController(text: '1');
    var origin = 'customer';
    try {
      final accepted = await showDialog<bool>(context: context, builder: (context) =>
        StatefulBuilder(builder: (context, redraw) => AlertDialog(
          title: const Text('Registrar repuesto'),
          content: SizedBox(width: 430, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(initialValue: origin,
                decoration: const InputDecoration(labelText: 'Aportado por'),
                items: const [DropdownMenuItem(value: 'customer', child: Text('Cliente')),
                  DropdownMenuItem(value: 'workshop', child: Text('Taller'))],
                onChanged: (value) => redraw(() => origin = value ?? origin)),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre de la pieza')),
              TextField(controller: category, decoration: const InputDecoration(labelText: 'Categoría / sistema')),
              TextField(controller: brand, decoration: const InputDecoration(labelText: 'Marca')),
              TextField(controller: number, decoration: const InputDecoration(labelText: 'Número de parte')),
              TextField(controller: oem, decoration: const InputDecoration(labelText: 'Número OEM')),
              TextField(controller: specs, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Características / especificaciones')),
              TextField(controller: qty, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cantidad')),
            ]))),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar'))],
        )));
      if (accepted != true) return;
      await widget.api.postJson('/api/v1/work-orders/${widget.orderId}/parts', {
        'work_order_service_id': service['id'], 'supplied_by': origin,
        'name': name.text.trim(), 'category': category.text.trim(),
        'brand': brand.text.trim(), 'part_number': number.text.trim(),
        'oem_number': oem.text.trim(), 'specifications': specs.text.trim(),
        'quantity': double.tryParse(qty.text.replaceAll(',', '.')) ?? 0,
      });
      _reload();
    } catch (error) { _notice(error); }
    finally { for (final c in [name, category, brand, number, oem, specs, qty]) { c.dispose(); } }
  }

  Future<void> _updatePart(Map<String, dynamic> part, Map<String, dynamic> data) async {
    try {
      await widget.api.patchJson('/api/v1/work-orders/${widget.orderId}/parts/${part['id']}', data);
      _reload();
    } catch (error) { _notice(error); }
  }

  Future<void> _attachPhoto(Map<String, dynamic> part) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image, withData: true);
      final file = picked?.files.single;
      if (file == null || file.bytes == null) return;
      final evidence = Map<String, dynamic>.from(await widget.api.uploadBytes(
        '/api/v1/work-orders/${widget.orderId}/evidence?work_order_service_id=${part['work_order_service_id']}',
        file.bytes!, file.name) as Map);
      await _updatePart(part, {'evidence_id': evidence['id']});
    } catch (error) { _notice(error); }
  }

  Future<void> _attachScannerReport(Map<String, dynamic> service) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom,
        allowedExtensions: ['pdf'], withData: true);
      final file = picked?.files.single;
      if (file == null || file.bytes == null) return;
      await widget.api.uploadBytes(
        '/api/v1/scanner-reports?vehicle_id=${widget.vehicleId}'
        '&work_order_id=${widget.orderId}&work_order_service_id=${service['id']}',
        file.bytes!, file.name);
      _reload();
    } catch (error) { _notice(error); }
  }

  Future<void> _attachInspectionEvidence(Map<String, dynamic> inspection) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'], withData: true);
      final file = picked?.files.single;
      if (file == null || file.bytes == null) return;
      await widget.api.uploadBytes('/api/v1/work-orders/${widget.orderId}/evidence'
        '?work_order_service_id=${inspection['work_order_service_id']}',
        file.bytes!, file.name, fields: {'inspection_id': '${inspection['id']}'});
      _reload();
    } catch (error) { _notice(error); }
  }

  Future<void> _openEvidence(Map<String, dynamic> evidence) async {
    try {
      final path = '${evidence['download_url']}';
      if ('${evidence['content_type']}' == 'application/pdf') {
        await openGudexPdf(widget.api, path, '${evidence['filename']}');
        return;
      }
      final bytes = await widget.api.getBytes(path);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Image.memory(bytes, fit: BoxFit.contain))));
    } catch (error) { _notice(error); }
  }

  Future<void> _viewPhoto(Map<String, dynamic> part) async {
    try {
      final bytes = await widget.api.getBytes('${part['photo_url']}');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Image.memory(bytes, fit: BoxFit.contain))));
    } catch (error) { _notice(error); }
  }

  Future<void> _verify(Map<String, dynamic> part) async {
    final source = TextEditingController();
    try {
      final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Verificar compatibilidad'),
        content: TextField(controller: source, decoration: const InputDecoration(
          labelText: 'Fuente técnica (manual, catálogo OEM, prueba documentada)')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Verificar'))]));
      if (accepted == true) await _updatePart(part,
        {'fitment_status': 'verified', 'verification_source': source.text.trim()});
    } catch (error) { _notice(error); }
    finally { source.dispose(); }
  }

  Widget _legacyRecords(List<Map<String, dynamic>> inspections,
      List<Map<String, dynamic>> reports, List<Map<String, dynamic>> evidence) {
    final legacyInspections = inspections.where((row) => row['work_order_service_id'] == null);
    final legacyReports = reports.where((row) => row['work_order_id'] == widget.orderId &&
        row['work_order_service_id'] == null);
    final linkedInspectionIds = inspections.where((row) => row['work_order_service_id'] != null)
        .map((row) => row['id']).toSet();
    final legacyEvidence = evidence.where((row) => !linkedInspectionIds.contains(row['inspection_id']));
    if (legacyInspections.isEmpty && legacyReports.isEmpty && legacyEvidence.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(child: ExpansionTile(title: const Text('Registros anteriores sin módulo'),
      subtitle: const Text('Historial conservado de órdenes previas'),
      children: [
        ...legacyInspections.map((row) => ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: Text('${row['category']}: ${row['item']}'),
          subtitle: const Text('Inspección anterior'),
          onTap: widget.role != 'admin' || widget.onEditInspection == null
              ? null : () => widget.onEditInspection!(row),
        )),
        ...legacyReports.map((row) => ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text('${row['filename']}'),
          onTap: () => openGudexPdf(widget.api,
            '/api/v1/scanner-reports/${row['id']}/file', '${row['filename']}'),
        )),
        ...legacyEvidence.map((row) => ListTile(
          leading: const Icon(Icons.attachment_outlined),
          title: Text('${row['filename']}'),
          onTap: () => _openEvidence(row),
        )),
      ]));
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
      children: [Text('Módulos de servicio',
      style: Theme.of(context).textTheme.titleLarge),
      if (widget.role == 'admin') FilledButton.icon(onPressed: _chooseModule,
        icon: const Icon(Icons.add), label: const Text('Agregar módulo'))]),
    const SizedBox(height: 6),
    const Text('Cada módulo tiene su responsable, avance, tiempo, hallazgos y repuestos. Puedes combinar varios en una orden.'),
    const SizedBox(height: 12),
    FutureBuilder<List<Map<String, dynamic>>>(future: _services, builder: (context, snapshot) {
      if (snapshot.hasError) return Text('Error al cargar servicios: ${snapshot.error}');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final services = snapshot.data!;
      if (services.isEmpty) return FutureBuilder<List<Map<String, dynamic>>>(
        future: _inspections, builder: (context, inspectionSnapshot) =>
        FutureBuilder<List<Map<String, dynamic>>>(future: _scannerReports,
          builder: (context, scannerSnapshot) =>
          FutureBuilder<List<Map<String, dynamic>>>(future: _evidence,
            builder: (context, evidenceSnapshot) => Column(children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Icon(Icons.dashboard_customize_outlined, size: 36),
          const SizedBox(height: 8),
          const Text('Esta orden todavía no tiene módulos de servicio.'),
          const SizedBox(height: 8),
          if (widget.role == 'admin') OutlinedButton.icon(onPressed: _chooseModule,
            icon: const Icon(Icons.add), label: const Text('Elegir primer módulo')),
        ]))),
      _legacyRecords(inspectionSnapshot.data ?? [], scannerSnapshot.data ?? [],
        evidenceSnapshot.data ?? []),
      ]))));
      return FutureBuilder<List<Map<String, dynamic>>>(future: _parts, builder: (context, partSnapshot) {
        final parts = partSnapshot.data ?? [];
        return FutureBuilder<List<Map<String, dynamic>>>(future: _inspections, builder: (context, inspectionSnapshot) {
        final inspections = inspectionSnapshot.data ?? [];
        return FutureBuilder<List<Map<String, dynamic>>>(future: _scannerReports, builder: (context, scannerSnapshot) {
        final scannerReports = scannerSnapshot.data ?? [];
        return FutureBuilder<List<Map<String, dynamic>>>(future: _evidence, builder: (context, evidenceSnapshot) {
        final evidence = evidenceSnapshot.data ?? [];
        return Column(children: [...services.map((service) {
          final serviceParts = parts.where((part) => part['work_order_service_id'] == service['id']);
          final serviceInspections = inspections.where((row) => row['work_order_service_id'] == service['id']);
          final serviceReports = scannerReports.where((row) => row['work_order_service_id'] == service['id']);
          final isInspection = const {'inspection', 'pre_purchase', 'pre_technical_review'}
              .contains(service['kind']);
          final canEdit = service['can_edit'] == true;
          return Card(child: ExpansionTile(initiallyExpanded: services.length == 1,
            leading: Icon(_kindIcons[service['kind']] ?? Icons.handyman_outlined),
            title: Text('${service['name']}'),
            subtitle: Text('${_kinds[service['kind']] ?? service['kind']} · ${_serviceStatuses[service['status']] ?? service['status']} · ${serviceParts.length} repuesto(s)'),
            children: [
              if ('${service['description'] ?? ''}'.isNotEmpty)
                ListTile(title: Text('${service['description']}')),
              if ('${service['findings'] ?? ''}'.isNotEmpty)
                ListTile(title: Text('Hallazgos: ${service['findings']}')),
              if (canEdit) _serviceTimer(service),
              if (isInspection || serviceInspections.isNotEmpty) ...[
                Wrap(spacing: 8, children: [
                  if (isInspection && canEdit && widget.onApplyTemplate != null) OutlinedButton.icon(
                    onPressed: () async { await widget.onApplyTemplate!(service['id'] as int); _reload(); },
                    icon: const Icon(Icons.playlist_add_check), label: const Text('Aplicar lista')),
                  if (isInspection && canEdit && widget.onAddInspection != null) OutlinedButton.icon(
                    onPressed: () async { await widget.onAddInspection!(service['id'] as int); _reload(); },
                    icon: const Icon(Icons.add), label: const Text('Agregar punto')),
                ]),
                if (isInspection && serviceInspections.isEmpty) const ListTile(
                  title: Text('Sin puntos de inspección registrados')),
                ...serviceInspections.map((row) => ListTile(
                  leading: Icon(row['result'] == 'normal' ? Icons.check_circle_outline
                      : Icons.fact_check_outlined),
                  title: Text('${row['category']}: ${row['item']}'),
                  subtitle: Text('${row['result']}${row['notes'] == null ? '' : ' · ${row['notes']}'}'),
                  onTap: canEdit && widget.onEditInspection != null ? () async {
                    await widget.onEditInspection!(row);
                    _reload();
                  } : null,
                  trailing: canEdit ? IconButton(
                    onPressed: () => _attachInspectionEvidence(row),
                    tooltip: 'Adjuntar evidencia', icon: const Icon(Icons.attach_file)) : null,
                )),
                ...evidence.where((item) => serviceInspections.any(
                  (inspection) => inspection['id'] == item['inspection_id']))
                    .map((item) => ListTile(
                      leading: const Icon(Icons.attachment_outlined),
                      title: Text('${item['filename']}'),
                      subtitle: Text('Evidencia de inspección'),
                      onTap: () => _openEvidence(item),
                    )),
              ],
              if (service['kind'] == 'scanner') ...[
                if (canEdit) OutlinedButton.icon(
                  onPressed: () => _attachScannerReport(service),
                  icon: const Icon(Icons.upload_file), label: const Text('Adjuntar informe PDF')),
                if (serviceReports.isEmpty) const ListTile(title: Text('Sin informes de escáner')),
                ...serviceReports.map((report) => ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text('${report['filename']}'),
                  subtitle: Text('Informe de diagnóstico'),
                  onTap: () => openGudexPdf(widget.api,
                    '/api/v1/scanner-reports/${report['id']}/file', '${report['filename']}'),
                )),
              ],
              Wrap(spacing: 8, children: [
                if (widget.role == 'admin') OutlinedButton.icon(onPressed: () => _assignService(service),
                  icon: const Icon(Icons.person_outline), label: const Text('Asignar')),
                if (canEdit) OutlinedButton.icon(onPressed: () => _editFindings(service),
                  icon: const Icon(Icons.edit_note), label: const Text('Hallazgos')),
                if (canEdit && (service['status'] == 'pending' || service['status'] == 'blocked'))
                  OutlinedButton(onPressed: () => _updateService(service, 'in_progress'),
                    child: const Text('Iniciar')),
                if (canEdit && service['status'] == 'in_progress') ...[
                  OutlinedButton(onPressed: () => _updateService(service, 'blocked'),
                    child: const Text('Bloquear')),
                  FilledButton(onPressed: () => _updateService(service, 'completed'),
                    child: const Text('Completar')),
                ],
                if (canEdit) OutlinedButton.icon(onPressed: () => _addPart(service), icon: const Icon(Icons.add),
                  label: const Text('Registrar repuesto')),
              ]),
              ...serviceParts.map((part) => ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text('${part['name']} · ${part['brand'] ?? ''}'),
                subtitle: Text('OEM: ${part['oem_number'] == '' ? 'sin registrar' : part['oem_number']} · '
                  '${part['supplied_by'] == 'customer' ? 'Cliente' : 'Taller'} · ${_partStatuses[part['status']] ?? part['status']}\n'
                  '${part['specifications'] ?? ''}'),
                isThreeLine: true,
                trailing: !canEdit && part['photo_url'] == null ? null : PopupMenuButton<String>(onSelected: (action) {
                  if (action == 'photo') _attachPhoto(part);
                  if (action == 'view_photo') _viewPhoto(part);
                  if (action == 'verify') _verify(part);
                  if (action == 'installed') _updatePart(part, {'status': 'installed'});
                  if (action == 'not_installed') _updatePart(part, {'status': 'not_installed'});
                }, itemBuilder: (context) => [
                  if (canEdit) const PopupMenuItem(value: 'photo', child: Text('Adjuntar imagen')),
                  if (part['photo_url'] != null)
                    const PopupMenuItem(value: 'view_photo', child: Text('Ver imagen')),
                  if (canEdit && part['status'] != 'installed')
                    const PopupMenuItem(value: 'installed', child: Text('Marcar instalado')),
                  if (canEdit && part['fitment_status'] != 'verified')
                    const PopupMenuItem(value: 'verify', child: Text('Verificar compatibilidad')),
                  if (canEdit) const PopupMenuItem(value: 'not_installed', child: Text('No instalado')),
                ]),
              )),
            ]));
        }),
          _legacyRecords(inspections, scannerReports, evidence),
        ]);
        });
        });
        });
      });
    }),
  ]);
}
