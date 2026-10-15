import 'package:flutter/material.dart';
import '../services/api_client.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({required this.api, super.key});
  final ApiClient api;
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late Future<List<Map<String, dynamic>>> _docs;
  @override
  void initState() {
    super.initState();
    _docs = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.api.get('/api/v1/portal/documents');
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
          future: _docs,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data ?? [];
            return RefreshIndicator(
                onRefresh: () async => setState(() => _docs = _load()),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text('Mis documentos',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                      'Cotizaciones e informes técnicos de tus atenciones.'),
                  const SizedBox(height: 16),
                  if (docs.isEmpty)
                    const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(
                            child: Text('Aún no hay documentos disponibles.'))),
                  ...docs.map((doc) => Card(
                      child: ListTile(
                          leading: Icon(doc['type'] == 'quote'
                              ? Icons.request_quote_outlined
                              : Icons.fact_check_outlined),
                          title: Text('${doc['title']}'),
                          trailing: const Icon(Icons.picture_as_pdf_outlined),
                          onTap: () => openGudexPdf(widget.api, '${doc['url']}',
                              '${doc['title']}.pdf')))),
                ]));
          });
}
