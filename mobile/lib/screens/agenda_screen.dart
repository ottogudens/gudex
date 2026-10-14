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
  void initState() {
    super.initState();
    _appointments = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.api.get('/api/v1/appointments');
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
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
    final raw = await widget.api.get('/api/v1/customers');
    final customers = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    if (customers.isEmpty || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Registra un cliente antes de agendar.')),
        );
      }
      return;
    }
    int customerId = customers.first['id'] as int;
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
                items: customers
                    .map((c) => DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text(c['full_name'].toString()),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) update(() => customerId = value);
                },
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
              .length;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
              children: [
                _AgendaHeader(
                  start: start,
                  total: rows.length,
                  requested: requested,
                  onPrevious: () => setState(
                      () => _week = _week.subtract(const Duration(days: 7))),
                  onNext: () => setState(
                      () => _week = _week.add(const Duration(days: 7))),
                  onToday: () => setState(() => _week = DateTime.now()),
                  onCreate: widget.role == 'admin' ? _createAppointment : null,
                ),
                const SizedBox(height: 18),
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
  });

  final DateTime start;
  final int total;
  final int requested;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback? onCreate;

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
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(timeOf(startsAt),
            style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ),
      title: Text(item['service_type']?.toString() ?? 'Servicio',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('Cliente #${item['customer_id']}'),
      trailing: canConfirm && status == 'requested'
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
