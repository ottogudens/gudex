import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class BulkImportScreen extends StatefulWidget {
  const BulkImportScreen({required this.api, required this.kind, super.key});
  final ApiClient api;
  final String kind;
  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  bool _busy = false;
  String? _error, _success;
  Map<String, dynamic>? _preview;
  List<dynamic> _history = [];
  int _page = 0;
  bool _showUnchanged = false;
  String get _root => '/api/v1/bulk/${widget.kind}';
  String get _label => widget.kind == 'products' ? 'productos' : 'servicios';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await widget.api.get('$_root/history') as List;
      if (mounted) setState(() => _history = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final Uint8List bytes = await widget.api.getBytes('$_root/export');
      final path = await FilePicker.saveFile(
          dialogTitle: 'Guardar planilla',
          fileName: '$_label.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: bytes);
      if (mounted && (kIsWeb || path != null))
        setState(() => _success =
            'Planilla de $_label ${kIsWeb ? 'enviada a descargas' : 'guardada'}.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
      if (picked == null || !mounted) return;
      setState(() {
        _preview = null;
        _page = 0;
      });
      final file = picked.files.single;
      if (file.size > 5 * 1024 * 1024)
        throw Exception('La planilla supera 5 MB.');
      if (file.bytes == null) throw Exception('No se pudo leer el archivo.');
      final result = await widget.api
          .uploadBytes('$_root/preview', file.bytes!, file.name);
      if (mounted)
        setState(() {
          _preview = Map<String, dynamic>.from(result as Map);
          _showUnchanged = false;
        });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final id = _preview?['import_id'];
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.post('$_root/$id/confirm') as Map;
      if (!mounted) return;
      setState(() {
        _success =
            'Importación completada: ${result['created']} nuevos, ${result['updated']} actualizados y ${result['unchanged']} sin cambios.';
        _preview = null;
      });
      await _loadHistory();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final errors = preview?['errors'] as List? ?? [];
    final allChanges = preview?['changes'] as List? ?? [];
    final changes = allChanges
        .where((c) => _showUnchanged || c['action'] != 'unchanged')
        .toList();
    final entries = errors.isNotEmpty ? errors : changes;
    final pageCount = (entries.length / 100).ceil().clamp(1, 100000);
    final page = _page.clamp(0, pageCount - 1);
    final visible = entries.skip(page * 100).take(100);
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: Text('Carga masiva de $_label')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                '1. Descarga los registros actuales.\n2. Edita la hoja Datos y agrega las filas nuevas con ID vacío.\n3. Sube la planilla, revisa y confirma los cambios.'),
            const SizedBox(height: 8),
            const Text(
                'Conserva los ID, encabezados y la columna oculta _version. Quitar filas no elimina registros. Máximo: 5000 filas y 5 MB; sin fórmulas.'),
            if (widget.kind == 'products')
              const Text(
                  'La descarga incluye productos archivados. Activo=No archiva. Los cambios de stock quedan registrados como ajustes.'),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: _busy ? null : _download,
                  icon: const Icon(Icons.download),
                  label: const Text('Descargar Excel')),
              FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Subir planilla')),
            ]),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator()),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SelectableText(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (_success != null)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_success!))),
            if (preview != null) ...[
              const Divider(height: 32),
              Text('Revisión de la planilla',
                  style: Theme.of(context).textTheme.titleLarge),
              Text(
                  '${preview['created']} nuevos · ${preview['updated']} actualizados · ${preview['unchanged']} sin cambios · ${errors.length} errores'),
              if ((preview['new_categories'] as List).isNotEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                        'Categorías que se crearán al confirmar: ${(preview['new_categories'] as List).join(', ')}')),
              if (errors.isNotEmpty)
                const Text(
                    'No se ha guardado ninguna fila. Corrige los errores en Excel y vuelve a subirlo.')
              else ...[
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                        'Revisa los cambios antes de confirmar. Esta revisión vence en 30 minutos. Si los datos cambian mientras tanto, deberás validar de nuevo.')),
                Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                        onPressed: _busy ? null : _confirm,
                        icon: const Icon(Icons.check),
                        label: const Text('Confirmar importación'))),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mostrar también filas sin cambios'),
                    value: _showUnchanged,
                    onChanged: (value) => setState(() {
                          _showUnchanged = value ?? false;
                          _page = 0;
                        })),
              ],
              if (entries.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No hay cambios para mostrar.')),
              for (final item in visible)
                if (errors.isNotEmpty)
                  ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text('Fila ${item['row']}'),
                      subtitle: Text(item['message'].toString()))
                else
                  Card(
                      child: ExpansionTile(
                    title: Text('Fila ${item['row']} · ${item['name']}'),
                    subtitle: Text(const {
                          'created': 'Nuevo',
                          'updated': 'Actualizar',
                          'unchanged': 'Sin cambios'
                        }[item['action']] ??
                        ''),
                    children: [
                      for (final field in item['fields'] as List)
                        ListTile(
                            dense: true,
                            title: Text(_fieldLabel(field.toString())),
                            subtitle: Text(
                                '${(item['before'] as Map)[field] ?? '—'} → ${(item['data'] as Map)[field] ?? '—'}'))
                    ],
                  )),
              if (pageCount > 1)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                      onPressed: page > 0
                          ? () => setState(() => _page = page - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left)),
                  Text('Página ${page + 1} de $pageCount'),
                  IconButton(
                      onPressed: page + 1 < pageCount
                          ? () => setState(() => _page = page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right)),
                ]),
            ],
            const Divider(height: 32),
            Text('Últimas importaciones',
                style: Theme.of(context).textTheme.titleMedium),
            if (_history.isEmpty)
              const Text('No hay importaciones confirmadas.'),
            for (final row in _history)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      '${row['filename']} · ${row['created']} nuevos / ${row['updated']} actualizados'),
                  subtitle: Text(
                      '${row['created_by']} · ${_date(row['confirmed_at'].toString())}')),
          ]),
        ));
  }
}

String _date(String value) =>
    (DateTime.tryParse(value.endsWith('Z') || value.contains('+')
                    ? value
                    : '${value}Z')
                ?.toLocal()
                .toString() ??
            value)
        .split('.')
        .first;
String _fieldLabel(String value) =>
    const {
      'sku': 'SKU',
      'code': 'Código',
      'name': 'Nombre',
      'category': 'Categoría',
      'description': 'Descripción',
      'unit': 'Unidad',
      'stock_quantity': 'Stock',
      'minimum_quantity': 'Stock mínimo',
      'cost_clp': 'Costo CLP',
      'price_clp': 'Precio CLP',
      'active': 'Activo'
    }[value] ??
    value;
