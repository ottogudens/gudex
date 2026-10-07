import 'package:flutter/material.dart';
import '../services/api_client.dart';
import 'bulk_import_screen.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({required this.api, super.key});
  final ApiClient api;
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  List<Map<String, dynamic>> _services = [], _categories = [];
  bool _loading = true, _busy = false;
  String? _error;
  String _search = '';
  int? _category;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final rows = await Future.wait([widget.api.get('/api/v1/services'), widget.api.get('/api/v1/service-categories')]);
      if (!mounted) return;
      setState(() {
        _services = (rows[0] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _categories = (rows[1] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (!_categories.any((c) => c['id'] == _category)) _category = null;
        _error = null;
      });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _delete(Map<String, dynamic> row, bool category) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Eliminar ${category ? 'categoría' : 'servicio'}'),
      content: Text('¿Eliminar "${row['name']}"? ${category ? 'La categoría debe estar vacía.' : 'Las cotizaciones existentes conservarán su descripción.'}'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar'))],
    ));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.delete('/api/v1/${category ? 'service-categories' : 'services'}/${row['id']}');
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _edit(bool category, [Map<String, dynamic>? row]) async {
    if (!category && _categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crea una categoría antes de agregar servicios.')));
      return;
    }
    final name = TextEditingController(text: row?['name']?.toString());
    final code = TextEditingController(text: row?['code']?.toString());
    final description = TextEditingController(text: row?['description']?.toString());
    final price = TextEditingController(text: row?['price_clp']?.toString() ?? '0');
    int? categoryId = row?['category_id'] as int? ?? _category ?? (_categories.isEmpty ? null : _categories.first['id'] as int);
    final form = GlobalKey<FormState>();
    bool saving = false;
    String? error;
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => PopScope(canPop: !saving, child: AlertDialog(
        title: Text('${row == null ? 'Agregar' : 'Editar'} ${category ? 'categoría' : 'servicio'}'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, maxLength: category ? 80 : 160, decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa un nombre' : null),
          if (!category) ...[
            TextFormField(controller: code, maxLength: 40, decoration: const InputDecoration(labelText: 'Código único'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa un código' : null),
            DropdownButtonFormField<int>(initialValue: categoryId, isExpanded: true, decoration: const InputDecoration(labelText: 'Categoría'),
              items: _categories.map((c) => DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['name'].toString()))).toList(),
              onChanged: saving ? null : (v) => update(() => categoryId = v)),
            TextFormField(controller: description, maxLength: 2000, minLines: 2, maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descripción')),
            TextFormField(controller: price, keyboardType: TextInputType.number, maxLength: 10,
              decoration: const InputDecoration(labelText: 'Precio sugerido (CLP)'),
              validator: (value) => int.tryParse(value?.trim() ?? '') == null || int.parse(value!.trim()) < 0
                ? 'Ingresa un precio entero igual o mayor a cero' : null),
          ],
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])))),
        actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: saving ? null : () async {
            if (!form.currentState!.validate()) return;
            update(() { saving = true; error = null; });
            try {
              final data = <String, dynamic>{'name': name.text.trim(), if (!category) ...{
                'code': code.text.trim(), 'category_id': categoryId, 'description': description.text.trim(),
                'price_clp': int.parse(price.text.trim())}};
              final path = '/api/v1/${category ? 'service-categories' : 'services'}';
              if (row == null) { await widget.api.postJson(path, data); }
              else { await widget.api.putJson('$path/${row['id']}', data); }
              if (dialogContext.mounted) { update(() => saving = false); Navigator.pop(dialogContext, true); }
            } catch (e) { if (dialogContext.mounted) update(() { saving = false; error = e.toString(); }); }
          }, child: Text(saving ? 'Guardando…' : 'Guardar'))],
      )),
    ));
    // Wait for the dialog route to finish its closing animation before disposal.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose(); code.dispose(); description.dispose(); price.dispose();
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!),
      TextButton(onPressed: _load, child: const Text('Reintentar'))]));
    final services = _services.where((s) => (_category == null || s['category_id'] == _category) &&
      '${s['name']} ${s['code']} ${s['category']}'.toLowerCase().contains(_search.toLowerCase())).toList();
    return DefaultTabController(length: 2, child: Column(children: [
      const TabBar(tabs: [Tab(text: 'Servicios'), Tab(text: 'Categorías')]),
      Expanded(child: TabBarView(children: [
        Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Row(children: [Expanded(child: Text('Catálogo de servicios', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(onPressed: _busy ? null : () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => BulkImportScreen(api: widget.api, kind: 'services')));
                if (mounted) await _load();
              }, icon: const Icon(Icons.table_view_outlined), tooltip: 'Carga masiva'),
              IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
              FilledButton.icon(onPressed: _busy ? null : () => _edit(false), icon: const Icon(Icons.add), label: const Text('Agregar'))]),
            const SizedBox(height: 12),
            TextField(decoration: const InputDecoration(labelText: 'Buscar por nombre o código', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _search = v)),
            DropdownButtonFormField<int>(key: ValueKey(_category), initialValue: _category, isExpanded: true, decoration: const InputDecoration(labelText: 'Categoría'),
              items: [const DropdownMenuItem<int>(value: null, child: Text('Todas las categorías')),
                ..._categories.map((c) => DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['name'].toString())))],
              onChanged: (v) => setState(() => _category = v)),
          ])),
          Expanded(child: services.isEmpty ? const Center(child: Text('No hay servicios. Agrega uno para comenzar.')) : ListView.builder(
            itemCount: services.length, itemBuilder: (context, i) => _tile(services[i], false))),
        ]),
        Column(children: [Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerRight,
          child: FilledButton.icon(onPressed: _busy ? null : () => _edit(true), icon: const Icon(Icons.add), label: const Text('Agregar categoría')))),
          Expanded(child: _categories.isEmpty ? const Center(child: Text('No hay categorías.')) : ListView.builder(
            itemCount: _categories.length, itemBuilder: (context, i) => _tile(_categories[i], true)))])
      ])),
    ]));
  }

  Widget _tile(Map<String, dynamic> row, bool category) => Card(child: ListTile(
    title: Text(row['name'].toString()),
    subtitle: Text(category ? '${_services.where((s) => s['category_id'] == row['id']).length} servicios' : '${row['code']} · ${row['category']} · \$${row['price_clp'] ?? 0} CLP\n${row['description'] ?? ''}'),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(onPressed: _busy ? null : () => _edit(category, row), icon: const Icon(Icons.edit_outlined), tooltip: 'Editar'),
      IconButton(onPressed: _busy ? null : () => _delete(row, category), icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar'),
    ]),
  ));
}
