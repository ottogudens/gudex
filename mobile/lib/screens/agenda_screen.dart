import 'dart:async';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/api_client.dart';
import '../widgets/quick_create_dialogs.dart';

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
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _appointments = _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final rows = await _load();
      if (mounted) setState(() => _appointments = Future.value(rows));
    } catch (_) {
      // A temporary network error must not hide the existing agenda.
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final now = DateTime.now();
    final from = Uri.encodeQueryComponent(now.subtract(const Duration(days: 90)).toUtc().toIso8601String());
    final to = Uri.encodeQueryComponent(now.add(const Duration(days: 730)).toUtc().toIso8601String());
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; offset < 2000; offset += 200) {
      final raw = await widget.api.get('/api/v1/appointments?from_date=$from&to_date=$to&limit=200&offset=$offset');
      final page = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      rows.addAll(page);
      if (page.length < 200) break;
    }
    return rows;
  }

  Future<void> _refresh() async {
    setState(() => _appointments = _load());
    await _appointments;
  }

  DateTime _at(dynamic value) =>
      DateTime.tryParse(value.toString())?.toLocal() ?? DateTime(2000);

  String _time(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  bool _isToday(DateTime date) {
    final today = DateTime.now();
    return date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
  }

  Future<void> _changeStatus(int id, String status) async {
    await widget.api
        .patchJson('/api/v1/appointments/$id/status?status=$status', {});
    if (mounted) setState(() => _appointments = _load());
  }

  Future<void> _createAppointment() async {
    final loaded = await Future.wait([
      widget.api.get('/api/v1/customers'),
      widget.api.get('/api/v1/vehicles'),
      widget.api.get('/api/v1/workshop/bays'),
      widget.api.get('/api/v1/team/mechanics'),
    ]);
    final customers = loaded[0] is List
        ? (loaded[0] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final vehicles = loaded[1] is List
        ? (loaded[1] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final bays = loaded[2] is List
        ? (loaded[2] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final mechanics = loaded[3] is List
        ? (loaded[3] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    if (customers.isEmpty && widget.role == 'admin' && mounted) {
      final created = await showQuickCreateCustomer(context, widget.api);
      if (created != null) customers.add(created);
    }
    if (customers.isEmpty || !mounted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registra un cliente antes de agendar.')));
      return;
    }
    int customerId = customers.first['id'] as int;
    int? vehicleId;
    int? bayId;
    int? technicianUserId;
    final service = TextEditingController(text: 'Mantención preventiva');
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) {
      service.dispose();
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !mounted) {
      service.dispose();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agendar cita'),
        content: StatefulBuilder(
          builder: (context, update) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: customerId,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: [
                  ...customers.map((c) => DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text(c['full_name'].toString()),
                        )),
                  if (widget.role == 'admin') const DropdownMenuItem<int>(value: -1, child: Row(children: [Icon(Icons.person_add_alt_1), SizedBox(width: 8), Text('Crear nuevo cliente')]))
                ],
                onChanged: (value) async {
                  if (value == -1) {
                    final created = await showQuickCreateCustomer(context, widget.api);
                    if (created != null && context.mounted) update(() {
                      customers.add(created); customerId = created['id'] as int; vehicleId = null;
                    });
                  } else if (value != null) {
                    update(() { customerId = value; vehicleId = null; });
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                key: ValueKey('appointment-vehicle-$customerId-$vehicleId'),
                initialValue: vehicles.any((v) => v['id'] == vehicleId) ? vehicleId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Vehículo (opcional)'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Sin vehículo')),
                  ...vehicles.where((v) => v['customer_id'] == customerId).map((v) => DropdownMenuItem<int?>(value: v['id'] as int, child: Text('${v['plate']} · ${v['make']} ${v['model']}', overflow: TextOverflow.ellipsis))),
                  if (widget.role == 'admin') const DropdownMenuItem<int?>(value: -1, child: Row(children: [Icon(Icons.add_road), SizedBox(width: 8), Text('Crear nuevo vehículo')]))
                ],
                onChanged: (value) async {
                  if (value == -1) {
                    final created = await showQuickCreateVehicle(context, widget.api, customers, initialCustomerId: customerId);
                    if (created != null && context.mounted) update(() { vehicles.add(created); vehicleId = created['id'] as int; });
                  } else {
                    update(() => vehicleId = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                key: ValueKey('appointment-bay-$bayId'),
                initialValue: bayId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Bahía o puesto',
                    helperText: 'Permite planificar servicios simultáneos'),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Sin asignar · reserva general')),
                  ...bays.where((bay) => bay['active'] != false).map((bay) =>
                      DropdownMenuItem<int?>(
                          value: bay['id'] as int,
                          child: Text(bay['name'].toString(), overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (value) => update(() => bayId = value),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                key: ValueKey('appointment-technician-$technicianUserId'),
                initialValue: technicianUserId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Técnico responsable'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Sin asignar')),
                  ...mechanics.map((mechanic) => DropdownMenuItem<int?>(
                      value: mechanic['id'] as int,
                      child: Text(mechanic['full_name'].toString(),
                          overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (value) => update(() => technicianUserId = value),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: service,
                decoration: const InputDecoration(labelText: 'Servicio'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agendar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final start = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        await widget.api.postJson('/api/v1/appointments', {
          'customer_id': customerId,
          if (vehicleId != null) 'vehicle_id': vehicleId,
          if (bayId != null) 'bay_id': bayId,
          if (technicianUserId != null) 'technician_user_id': technicianUserId,
          'starts_at': start.toUtc().toIso8601String(),
          'ends_at':
              start.add(const Duration(hours: 1)).toUtc().toIso8601String(),
          'service_type': service.text.trim(),
        });
        if (mounted) await _refresh();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(error.toString().replaceFirst('Exception: ', ''))),
          );
        }
      }
    }
    service.dispose();
  }

  Future<void> _manageBays() async {
    List<Map<String, dynamic>> bays = const [];
    try {
      final raw = await widget.api.get('/api/v1/workshop/bays');
      bays = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!mounted) return;
    final name = TextEditingController();
    final notes = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Puestos de trabajo'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (bays.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Crea los puestos reales del taller para permitir atenciones simultáneas.'),
                  ),
                for (final bay in bays)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(bay['name'].toString()),
                    subtitle: Text((bay['notes'] ?? '').toString().isEmpty
                        ? 'Sin observaciones'
                        : bay['notes'].toString()),
                    value: bay['active'] != false,
                    onChanged: (value) async {
                      try {
                        final saved = await widget.api.patchJson('/api/v1/workshop/bays/${bay['id']}', {
                          'active': value,
                        });
                        update(() => bays = bays.map((item) => item['id'] == bay['id']
                            ? Map<String, dynamic>.from(saved as Map)
                            : item).toList());
                      } catch (error) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
                      }
                    },
                  ),
                const Divider(height: 26),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del puesto')),
                const SizedBox(height: 8),
                TextField(controller: notes, decoration: const InputDecoration(labelText: 'Observaciones (opcional)')),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar puesto'),
                    onPressed: () async {
                      if (name.text.trim().isEmpty) return;
                      try {
                        final saved = await widget.api.postJson('/api/v1/workshop/bays', {
                          'name': name.text.trim(),
                          'notes': notes.text.trim(),
                        });
                        update(() {
                          bays = [...bays, Map<String, dynamic>.from(saved as Map)];
                          name.clear(); notes.clear();
                        });
                      } catch (error) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
                      }
                    },
                  ),
                ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
        ),
      ),
    );
    name.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _appointments,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _AgendaFailure(onRetry: _refresh);
          }
          final rows = snapshot.data ?? [];
          final start = DateTime(_week.year, _week.month, _week.day)
              .subtract(Duration(days: _week.weekday - 1));
          final requested = rows
              .where((row) => row['status']?.toString() == 'requested')
              .toList();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
              children: [
                _AgendaHeader(
                  start: start,
                  total: rows.length,
                  requested: requested.length,
                  onPrevious: () => setState(
                      () => _week = _week.subtract(const Duration(days: 7))),
                  onNext: () => setState(
                      () => _week = _week.add(const Duration(days: 7))),
                  onToday: () => setState(() => _week = DateTime.now()),
                  onCreate: widget.role == 'admin' ? _createAppointment : null,
                  onManageBays: widget.role == 'admin' ? _manageBays : null,
                ),
                const SizedBox(height: 18),
                if (requested.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE8A3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.notifications_active_rounded,
                            color: Color(0xFF8C3700), size: 32),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          requested.length == 1
                              ? '1 nueva cita pendiente de confirmar'
                              : '${requested.length} nuevas citas pendientes de confirmar',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
                              color: Color(0xFF512A0B)),
                        )),
                      ]),
                      const SizedBox(height: 8),
                      for (final row in requested.take(3))
                        TextButton.icon(
                          onPressed: () => setState(() => _week = _at(row['starts_at'])),
                          icon: const Icon(Icons.event_outlined),
                          label: Text('${row['service_type']} · ${_at(row['starts_at']).day}/${_at(row['starts_at']).month} ${_time(_at(row['starts_at']))} — Ver semana'),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                ],
                for (var index = 0; index < 7; index++)
                  _DayScheduleCard(
                    day: start.add(Duration(days: index)),
                    label: const [
                      'Lunes',
                      'Martes',
                      'Miércoles',
                      'Jueves',
                      'Viernes',
                      'Sábado',
                      'Domingo',
                    ][index],
                    records: rows.where((row) {
                      final date = _at(row['starts_at']);
                      final day = start.add(Duration(days: index));
                      return date.year == day.year &&
                          date.month == day.month &&
                          date.day == day.day;
                    }).toList(),
                    isToday: _isToday(start.add(Duration(days: index))),
                    timeOf: _time,
                    canConfirm: widget.role == 'admin',
                    onConfirm: _changeStatus,
                  ),
              ],
            ),
          );
        },
      );
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
    required this.start,
    required this.total,
    required this.requested,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    this.onCreate,
    this.onManageBays,
  });

  final DateTime start;
  final int total;
  final int requested;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback? onCreate;
  final VoidCallback? onManageBays;

  String get _range {
    final end = start.add(const Duration(days: 6));
    return '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}'
        ' – ${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: GudexColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: GudexColors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.calendar_month_outlined,
                color: GudexColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Agenda del taller',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text('Planifica recepciones y confirma solicitudes.',
                    style: Theme.of(context).textTheme.bodySmall),
              ])),
          if (onManageBays != null)
            IconButton(
              tooltip: 'Configurar puestos',
              onPressed: onManageBays,
              icon: const Icon(Icons.garage_outlined),
            ),
          if (onCreate != null)
            IconButton.filled(
              tooltip: 'Agendar cita',
              onPressed: onCreate,
              icon: const Icon(Icons.add),
            ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          IconButton(
            tooltip: 'Semana anterior',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              _range,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Semana siguiente',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: onToday,
            icon: const Icon(Icons.today_outlined, size: 18),
            label: const Text('Hoy'),
          ),
          _AgendaMetric(
            icon: Icons.event_available_outlined,
            label: '$total cita${total == 1 ? '' : 's'}',
            color: GudexColors.success,
          ),
          if (requested > 0)
            _AgendaMetric(
              icon: Icons.mark_email_unread_outlined,
              label: '$requested por confirmar',
              color: const Color(0xFF9A6700),
            ),
        ]),
      ]),
    );
  }
}

class _AgendaMetric extends StatelessWidget {
  const _AgendaMetric(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _DayScheduleCard extends StatelessWidget {
  const _DayScheduleCard({
    required this.day,
    required this.label,
    required this.records,
    required this.isToday,
    required this.timeOf,
    required this.canConfirm,
    required this.onConfirm,
  });

  final DateTime day;
  final String label;
  final List<Map<String, dynamic>> records;
  final bool isToday;
  final String Function(DateTime) timeOf;
  final bool canConfirm;
  final Future<void> Function(int, String) onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isToday ? GudexColors.secondary.withValues(alpha: .16) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:
                    isToday ? GudexColors.primary : colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$label · ${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: isToday ? Colors.white : colors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Spacer(),
            if (isToday)
              Text('HOY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: GudexColors.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8)),
          ]),
          const SizedBox(height: 8),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Icon(Icons.event_available_outlined, size: 19),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sin citas programadas',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            )
          else
            for (final item in records)
              _AppointmentRow(
                item: item,
                timeOf: timeOf,
                canConfirm: canConfirm,
                onConfirm: onConfirm,
              ),
        ]),
      ),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.item,
    required this.timeOf,
    required this.canConfirm,
    required this.onConfirm,
  });

  final Map<String, dynamic> item;
  final String Function(DateTime) timeOf;
  final bool canConfirm;
  final Future<void> Function(int, String) onConfirm;

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return GudexColors.success;
      case 'requested':
        return const Color(0xFF9A6700);
      case 'cancelled':
        return const Color(0xFF9A3D3D);
      default:
        return const Color(0xFF6251A8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final startsAt =
        DateTime.tryParse(item['starts_at'].toString())?.toLocal() ??
            DateTime(2000);
    final status = item['status']?.toString() ?? 'requested';
    final color = _statusColor(status);
    return ListTile(
      onTap: item['source'] == 'google' ? () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(item['service_type']?.toString() ?? 'Evento de Google'),
          content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['all_day'] == true ? 'Todo el día' :
                'Inicio: ${startsAt.day}/${startsAt.month}/${startsAt.year} ${timeOf(startsAt)}'),
              if ('${item['notes'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 12), Text('${item['notes']}'),
              ],
              const SizedBox(height: 12),
              const Text('Importado desde el calendario de Google seleccionado.'),
            ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'))],
        )) : null,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(item['all_day'] == true ? 'Día' : timeOf(startsAt),
            style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ),
      title: Text(item['service_type']?.toString() ?? 'Servicio',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(item['source'] == 'google'
          ? 'Google Calendar${item['all_day'] == true ? ' · Todo el día' : ''}'
          : [
              'Cliente #${item['customer_id']}',
              if ('${item['bay_name'] ?? ''}'.trim().isNotEmpty)
                'Bahía: ${item['bay_name']}',
              if ('${item['technician_name'] ?? ''}'.trim().isNotEmpty)
                'Técnico: ${item['technician_name']}',
            ].join(' · ')),
      trailing: canConfirm && status == 'requested' && item['source'] != 'google'
          ? FilledButton.tonal(
              onPressed: () => onConfirm(item['id'] as int, 'confirmed'),
              child: const Text('Confirmar'),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(spanishStatus(status),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ),
    );
  }
}

class _AgendaFailure extends StatelessWidget {
  const _AgendaFailure({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No pudimos cargar la agenda',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Revisa tu conexión e inténtalo nuevamente.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ]),
        ),
      );
}
