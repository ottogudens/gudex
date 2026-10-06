import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/api_client.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({required this.api, required this.role, super.key});
  final ApiClient api;
  final String role;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _message = TextEditingController();
  String _contextType = 'general';
  bool _diagnostic = false;

  @override
  void dispose() { _message.dispose(); super.dispose(); }
  int? _selectedContextId;
  List<dynamic> _orders = [];
  List<dynamic> _vehicles = [];
  Map<String, dynamic>? _answer;
  int? _interactionId;
  bool _busy = false;
  String? _contextError;

  String get _path => widget.role == 'customer' ? '/api/v1/portal/assistant/query' : '/api/v1/assistant/query';

  @override
  void initState() {
    super.initState();
    _loadContextRecords();
  }

  Future<void> _loadContextRecords() async {
    try {
      final paths = widget.role == 'customer'
          ? ['/api/v1/portal/work-orders', '/api/v1/portal/profile']
          : ['/api/v1/work-orders', '/api/v1/vehicles'];
      final values = await Future.wait(paths.map(widget.api.get));
      if (!mounted) return;
      setState(() {
        _contextError = null;
        _orders = values[0] as List;
        final vehicleResponse = values[1];
        _vehicles = widget.role == 'customer'
            ? (vehicleResponse as Map)['vehicles'] as List? ?? []
            : vehicleResponse as List;
      });
    } catch (error) {
      if (mounted) setState(() => _contextError = error.toString());
    }
  }

  Future<void> _ask() async {
    if (_message.text.trim().length < 2) return;
    final id = _selectedContextId;
    if ((_contextType == 'work_order' || _contextType == 'vehicle') && id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona un registro')));
      return;
    }
    setState(() => _busy = true);
    try {
      final result = Map<String, dynamic>.from(await widget.api.postJson(_path, {
        'message': _message.text.trim(), 'context_type': _contextType,
        'mode': _diagnostic ? 'diagnostic' : 'general',
        if (id != null) 'context_id': id,
      }) as Map);
      if (!mounted) return;
      setState(() { _answer = result; _interactionId = result['interaction_id'] as int?; });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(bool approved) async {
    if (_interactionId == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.api.postJson('/api/v1/assistant/interactions/$_interactionId/confirm', {'approved': approved});
      if (!mounted) return;
      setState(() { _answer = {...?_answer, 'action_result': result, 'proposed_action': null}; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approved ? 'Acción confirmada y aplicada' : 'Propuesta descartada')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Asistente Gudex')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Consulta sobre una orden, vehículo, inventario, agenda o el uso del sistema. La IA puede equivocarse; verifica las recomendaciones mecánicas.'),
      if (widget.role != 'customer') SwitchListTile(
        title: const Text('Diagnóstico de falla'),
        subtitle: const Text('Cruza síntomas, vehículo, inspecciones, historial y PDF de scanners y documentos almacenados.'),
        value: _diagnostic, onChanged: _busy ? null : (value) => setState(() {
          _diagnostic = value; _contextType = value ? 'vehicle' : 'general';
          _selectedContextId = null; _answer = null;
        })),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(key: ValueKey(_diagnostic), initialValue: _contextType, decoration: const InputDecoration(labelText: 'Contexto'),
        items: [
          if (!_diagnostic) const DropdownMenuItem(value: 'general', child: Text('General')),
          const DropdownMenuItem(value: 'work_order', child: Text('Trabajo / orden')),
          const DropdownMenuItem(value: 'vehicle', child: Text('Vehículo / historial')),
          if (widget.role != 'customer' && !_diagnostic) ...[
            const DropdownMenuItem(value: 'inventory', child: Text('Inventario')),
            const DropdownMenuItem(value: 'agenda', child: Text('Agenda de 7 días')),
          ],
        ], onChanged: _busy ? null : (value) { if (value != null) setState(() { _contextType = value; _selectedContextId = null; _answer = null; _interactionId = null; }); }),
      if (_contextError != null) ...[
        Text('No se pudieron cargar los antecedentes: $_contextError'),
        TextButton(onPressed: _busy ? null : _loadContextRecords, child: const Text('Reintentar')),
      ],
      if (_contextType == 'work_order' || _contextType == 'vehicle') ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(key: ValueKey(_contextType), initialValue: _selectedContextId,
          decoration: InputDecoration(labelText: _contextType == 'work_order' ? 'Selecciona un trabajo' : 'Selecciona un vehículo'),
          items: [
            for (final raw in (_contextType == 'work_order' ? _orders : _vehicles))
              DropdownMenuItem<int>(value: raw['id'] as int,
                child: Text(_contextType == 'work_order'
                    ? '${raw['code'] ?? 'Orden'} · ${spanishStatus(raw['status'])}'
                    : '${raw['plate'] ?? ''} · ${raw['make'] ?? ''} ${raw['model'] ?? ''}')),
          ], onChanged: _busy ? null : (value) => setState(() { _selectedContextId = value; _answer = null; _interactionId = null; })),
        if ((_contextType == 'work_order' ? _orders : _vehicles).isEmpty)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('No hay registros disponibles para este perfil.')),
      ],
      const SizedBox(height: 10), TextField(controller: _message, minLines: 2, maxLines: 5,
        maxLength: 2000, decoration: InputDecoration(labelText: _diagnostic ? 'Describe la falla, cuándo ocurre y las pruebas realizadas' : '¿En qué te ayudo?')),
      const SizedBox(height: 10), FilledButton.icon(onPressed: _busy ? null : _ask,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
        label: Text(_diagnostic ? 'Analizar falla' : 'Consultar')),
      if (_answer != null) ...[
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Respuesta de IA', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8), Text('${_answer!['answer'] ?? ''}'),
          for (final pair in <String, String>{'Hechos registrados': 'known_facts', 'Posibles causas': 'possible_causes', 'Verificaciones sugeridas': 'suggested_checks'}.entries)
            if ((_answer![pair.value] as List? ?? []).isNotEmpty) ...[
              const SizedBox(height: 12), Text(pair.key, style: const TextStyle(fontWeight: FontWeight.bold)),
              for (final item in _answer![pair.value] as List) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $item')),
            ],
          if (_answer!['safety_warning'] != null) ...[
            const SizedBox(height: 12), Container(width: double.infinity, padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.errorContainer, child: Text('Seguridad: ${_answer!['safety_warning']}')),
          ],
          if (_answer!['proposed_action'] is Map) ...[
            const Divider(height: 24), Text((_answer!['proposed_action'] as Map)['confirmation_message']?.toString() ?? 'La IA propone actualizar información.'),
            const SizedBox(height: 8), Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _busy ? null : () => _confirm(false), child: const Text('Descartar')),
              FilledButton(onPressed: _busy ? null : () => _confirm(true), child: const Text('Confirmar acción')),
            ]),
          ],
          if (_answer!['coverage'] != null) ...[
            const Divider(), Text('Antecedentes consultados', style: Theme.of(context).textTheme.titleSmall),
            Text(_answer!['coverage'].toString()),
            for (final source in _answer!['sources'] as List? ?? [])
              ListTile(contentPadding: EdgeInsets.zero, dense: true,
                title: Text('${source['source_id']} · ${source['filename']}'),
                subtitle: Text(_sourceStatus(source['status'].toString()))),
          ],
          if (_answer!['action_result'] != null) Text('Resultado: ${_answer!['action_result']}'),
        ]))),
      ],
    ]),
  );
}

String _sourceStatus(String status) => const {
  'record': 'Registro del sistema', 'read': 'Texto leído', 'truncated': 'Lectura parcial por límite de tamaño o páginas',
  'missing': 'Archivo no disponible', 'unavailable': 'Archivo no accesible',
  'unreadable': 'No se pudo extraer el texto', 'no_text': 'PDF sin texto; requiere OCR o transcripción',
  'caption_only': 'Solo descripción; imagen no analizada', 'too_large': 'Archivo demasiado grande',
  'limit_reached': 'No leído: límite de documentos alcanzado',
}[status] ?? status;
