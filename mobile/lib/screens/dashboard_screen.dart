import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/api_client.dart';

/// Centro de control operativo para administración.
///
/// La información prioriza decisiones de taller: qué requiere acción, qué
/// viene en agenda y qué stock puede bloquear una atención.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.api,
    required this.onOpenModule,
    super.key,
  });

  final ApiClient api;
  final void Function(int index) onOpenModule;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(
        await widget.api.get('/api/v1/dashboard') as Map,
      );

  Future<void> _refresh() async {
    setState(() => _data = _load());
    await _data;
  }

  int _number(dynamic value) =>
      value is num ? value.round() : int.tryParse(value.toString()) ?? 0;

  String _money(dynamic value) => formatClp(_number(value));

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _DashboardFailure(onRetry: _refresh);
          }

          final data = snapshot.data!;
          final metrics = Map<String, dynamic>.from(data['metrics'] as Map);
          final urgent = data['urgent_orders'] is List
              ? data['urgent_orders'] as List
              : const [];
          final schedule = data['today_schedule'] is List
              ? data['today_schedule'] as List
              : const [];
          final stock = data['low_stock_items'] is List
              ? data['low_stock_items'] as List
              : const [];

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                _DashboardHero(
                  urgentCount: urgent.length,
                  appointmentCount: _number(metrics['today_appointments']),
                  onRefresh: _refresh,
                  onOpenAgenda: () => widget.onOpenModule(4),
                ),
                const SizedBox(height: 20),
                _MetricsGrid(
                  metrics: [
                    _MetricData(
                      'Órdenes activas',
                      _number(metrics['active_orders']).toString(),
                      Icons.build_outlined,
                      GudexColors.primary,
                      () => widget.onOpenModule(1),
                    ),
                    _MetricData(
                      'Trabajos atrasados',
                      _number(metrics['overdue_orders']).toString(),
                      Icons.warning_amber_rounded,
                      const Color(0xFFD85A1A),
                      () => widget.onOpenModule(1),
                    ),
                    _MetricData(
                      'Citas de hoy',
                      _number(metrics['today_appointments']).toString(),
                      Icons.calendar_today_outlined,
                      GudexColors.success,
                      () => widget.onOpenModule(4),
                    ),
                    _MetricData(
                      'Solicitudes nuevas',
                      _number(metrics['requested_appointments']).toString(),
                      Icons.mark_email_unread_outlined,
                      const Color(0xFF9A6700),
                      () => widget.onOpenModule(4),
                    ),
                    _MetricData(
                      'Stock bajo',
                      _number(metrics['low_stock']).toString(),
                      Icons.inventory_2_outlined,
                      const Color(0xFF6251A8),
                      () => widget.onOpenModule(3),
                    ),
                    _MetricData(
                      'Ventas cobradas hoy',
                      _money(metrics['sales_today_clp']),
                      Icons.point_of_sale_outlined,
                      const Color(0xFF147A6C),
                      () => widget.onOpenModule(6),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _OperationalSection(
                  title: 'Requiere atención',
                  subtitle:
                      'Prioridades que pueden afectar la entrega al cliente.',
                  icon: Icons.priority_high_rounded,
                  color: urgent.isEmpty
                      ? GudexColors.success
                      : const Color(0xFFD85A1A),
                  actionLabel: 'Ver órdenes',
                  onAction: () => widget.onOpenModule(1),
                  child: urgent.isEmpty
                      ? const _EmptyOperationalState(
                          icon: Icons.task_alt_rounded,
                          title: 'Todo bajo control',
                          detail: 'No hay órdenes vencidas ni bloqueadas.',
                        )
                      : Column(
                          children: [
                            for (final item in urgent)
                              _PriorityRow(
                                icon: Icons.warning_amber_rounded,
                                iconColor: const Color(0xFFD85A1A),
                                title: item['code'].toString(),
                                detail:
                                    'Estado: ${spanishStatus(item['status'])}${item['technician_name'] == null ? '' : ' · ${item['technician_name']}'}',
                                onTap: () => widget.onOpenModule(1),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                _OperationalSection(
                  title: 'Agenda de hoy',
                  subtitle: 'Preparación de recepciones y recursos del taller.',
                  icon: Icons.event_available_outlined,
                  color: GudexColors.success,
                  actionLabel: 'Abrir agenda',
                  onAction: () => widget.onOpenModule(4),
                  child: schedule.isEmpty
                      ? _EmptyOperationalState(
                          icon: Icons.event_available_outlined,
                          title: 'No hay citas pendientes',
                          detail:
                              'Puedes reservar una atención desde la agenda.',
                          actionLabel: 'Agendar cita',
                          onAction: () => widget.onOpenModule(4),
                        )
                      : Column(
                          children: [
                            for (final item in schedule)
                              _PriorityRow(
                                icon: Icons.schedule_outlined,
                                iconColor: GudexColors.success,
                                title: item['service_type'].toString(),
                                detail:
                                    '${_shortDate(item['starts_at'])} · ${spanishStatus(item['status'])}',
                                onTap: () => widget.onOpenModule(4),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                _OperationalSection(
                  title: 'Reposición prioritaria',
                  subtitle:
                      'Productos que podrían detener una venta o mantención.',
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFF6251A8),
                  actionLabel: 'Ver inventario',
                  onAction: () => widget.onOpenModule(3),
                  child: stock.isEmpty
                      ? const _EmptyOperationalState(
                          icon: Icons.inventory_outlined,
                          title: 'Inventario saludable',
                          detail:
                              'No hay productos bajo el mínimo configurado.',
                        )
                      : Column(
                          children: [
                            for (final item in stock)
                              _PriorityRow(
                                icon: Icons.inventory_2_outlined,
                                iconColor: const Color(0xFF6251A8),
                                title: item['name'].toString(),
                                detail:
                                    'Disponible: ${item['stock_quantity']} ${item['unit']} · mínimo: ${item['minimum_quantity']}',
                                onTap: () => widget.onOpenModule(3),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      );

  String _shortDate(dynamic raw) {
    final value = raw?.toString() ?? '';
    return value
        .replaceFirst('T', ' ')
        .substring(0, value.length >= 16 ? 16 : value.length);
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.urgentCount,
    required this.appointmentCount,
    required this.onRefresh,
    required this.onOpenAgenda,
  });

  final int urgentCount;
  final int appointmentCount;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenAgenda;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasUrgent = urgentCount > 0;
    return Semantics(
      header: true,
      label: 'Centro de control del taller',
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.primary, const Color(0xFF7F0202)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Centro de control',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        'Operación del taller en tiempo real',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'Actualizar panel',
                  color: Colors.white,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              hasUrgent
                  ? 'Hay $urgentCount prioridad${urgentCount == 1 ? '' : 'es'} que revisar.'
                  : 'La operación está al día.',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '$appointmentCount cita${appointmentCount == 1 ? '' : 's'} programada${appointmentCount == 1 ? '' : 's'} para hoy.',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: colors.primary,
                  ),
                  onPressed: onOpenAgenda,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Ver agenda'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: onRefresh,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 920
              ? 3
              : constraints.maxWidth >= 570
                  ? 2
                  : 1;
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // En teléfonos el valor y la etiqueta requieren una altura extra
            // para respetar tamaños de fuente accesibles sin recortar texto.
            childAspectRatio: columns == 1 ? 2.8 : 1.85,
            children: [
              for (final metric in metrics) _DashboardMetric(data: metric),
            ],
          );
        },
      );
}

class _MetricData {
  const _MetricData(this.label, this.value, this.icon, this.color, this.onTap);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '${data.label}: ${data.value}',
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: data.onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(data.icon, color: data.color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          data.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
}

class _OperationalSection extends StatelessWidget {
  const _OperationalSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: onAction, child: Text(actionLabel)),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        minVerticalPadding: 10,
        leading: Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 21),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}

class _EmptyOperationalState extends StatelessWidget {
  const _EmptyOperationalState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      );
}

class _DashboardFailure extends StatelessWidget {
  const _DashboardFailure({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 44,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 14),
                Text(
                  'No pudimos cargar el panel',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Revisa tu conexión e inténtalo nuevamente.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
}
