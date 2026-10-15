import 'package:flutter/material.dart';
import '../services/api_client.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({required this.api, super.key});
  final ApiClient api;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _items;
  @override
  void initState() {
    super.initState();
    _items = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.api.get('/api/v1/portal/notifications');
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
          future: _items,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            final items = s.data ?? [];
            return RefreshIndicator(
                onRefresh: () async => setState(() => _items = _load()),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text('Notificaciones',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                      'Información relevante de tus atenciones y beneficios.'),
                  const SizedBox(height: 16),
                  if (items.isEmpty)
                    const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(
                            child:
                                Text('No tienes notificaciones pendientes.'))),
                  ...items.map((item) => Card(
                      child: ListTile(
                          leading: Icon(item['type'] == 'maintenance'
                              ? Icons.car_repair_outlined
                              : item['type'] == 'quote'
                                  ? Icons.request_quote_outlined
                                  : Icons.calendar_month_outlined),
                          title: Text('${item['title']}'),
                          subtitle: Text('${item['message']}'))))
                ]));
          });
}
