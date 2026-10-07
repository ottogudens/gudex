import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_client.dart';

Future<bool?> showInventoryEditor(
  BuildContext context, {
  required ApiClient api,
  Map<String, dynamic>? product,
  bool stockAdjustment = false,
}) {
  final editor = InventoryEditor(
    api: api,
    product: product,
    stockAdjustment: stockAdjustment,
  );
  if (MediaQuery.sizeOf(context).width >= 960) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Editor de inventario',
      pageBuilder: (context, animation, secondaryAnimation) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(width: 520, height: double.infinity, child: editor),
      ),
    );
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (context) =>
        FractionallySizedBox(heightFactor: .95, child: editor),
  );
}

class InventoryEditor extends StatefulWidget {
  const InventoryEditor({
    required this.api,
    this.product,
    this.stockAdjustment = false,
    super.key,
  });
  final ApiClient api;
  final Map<String, dynamic>? product;
  final bool stockAdjustment;

  @override
  State<InventoryEditor> createState() => _InventoryEditorState();
}

class _InventoryEditorState extends State<InventoryEditor> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  bool _busy = false;
  bool _dirty = false;
  bool _closing = false;
  bool _allowPop = false;
  String? _error;
  String _movement = 'in';

  @override
  void initState() {
    super.initState();
    final p = widget.product ?? {};
    _fields = {
      for (final key in [
        'name',
        'sku',
        'category',
        'unit',
        'stock_quantity',
        'minimum_quantity',
        'cost_clp',
        'price_clp',
        'quantity',
        'reason',
      ])
        key: TextEditingController(
          text: '${p[key] ?? (key == 'unit' ? 'unidad' : [
              'stock_quantity',
              'minimum_quantity',
              'cost_clp',
              'price_clp'
            ].contains(key) ? '0' : '')}',
        ),
    };
    for (final controller in _fields.values) {
      controller.addListener(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _fields[key]!.text.trim();
  double _quantity(String key) => double.parse(_text(key).replaceAll(',', '.'));

  Future<void> _close() async {
    if (_busy || _closing) return;
    _closing = true;
    final discard = !_dirty ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('¿Descartar cambios?'),
                content: const Text(
                  'Los cambios de este formulario todavía no se han guardado.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Seguir editando'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Descartar'),
                  ),
                ],
              ),
            ) ==
            true;
    _closing = false;
    if (discard && mounted) _finish(false);
  }

  void _finish(bool saved) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, saved);
    });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.stockAdjustment) {
        await widget.api.postJson(
          '/api/v1/products/${widget.product!['id']}/stock-movements',
          {
            'quantity_change':
                _quantity('quantity') * (_movement == 'in' ? 1 : -1),
            'reason': _text('reason'),
          },
        );
      } else {
        final data = <String, dynamic>{
          'name': _text('name'),
          'unit': _text('unit'),
          'sku': _text('sku'),
          'category': _text('category'),
          'minimum_quantity': _quantity('minimum_quantity'),
          'cost_clp': int.parse(_text('cost_clp')),
          'price_clp': int.parse(_text('price_clp')),
          if (widget.product == null)
            'stock_quantity': _quantity('stock_quantity'),
        };
        if (widget.product == null) {
          if (data['sku'] == '') data.remove('sku');
          await widget.api.postJson('/api/v1/products', data);
        } else {
          await widget.api.patchJson(
            '/api/v1/products/${widget.product!['id']}',
            data,
          );
        }
      }
      if (mounted) _finish(true);
    } catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    bool number = false,
    bool money = false,
    bool positive = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: _fields[key],
          enabled: !_busy,
          autofocus: key == (widget.stockAdjustment ? 'quantity' : 'name'),
          decoration: InputDecoration(labelText: label),
          keyboardType: number
              ? TextInputType.numberWithOptions(decimal: !money)
              : TextInputType.text,
          textInputAction: TextInputAction.next,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (required && text.isEmpty) return 'Campo obligatorio';
            if (key == 'reason' && text.length < 3)
              return 'Describe el motivo del movimiento';
            if (number) {
              final parsed = money
                  ? int.tryParse(text)
                  : double.tryParse(text.replaceAll(',', '.'));
              if (parsed == null ||
                  !parsed.isFinite ||
                  parsed < 0 ||
                  (positive && parsed == 0)) {
                return money
                    ? 'Ingresa un monto CLP entero igual o mayor que cero'
                    : positive
                        ? 'Ingresa una cantidad mayor que cero'
                        : 'Ingresa una cantidad igual o mayor que cero';
              }
            }
            return null;
          },
        ),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _close();
        },
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.stockAdjustment
                                  ? 'Ajustar stock · ${widget.product!['name']}'
                                  : widget.product == null
                                      ? 'Nuevo producto'
                                      : 'Editar producto',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            onPressed: _busy ? null : _close,
                            tooltip: 'Cerrar editor',
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    'No se pudo confirmar el guardado. $_error\nTus datos siguen aquí. Si hubo un problema de conexión, comprueba el registro antes de volver a guardar.',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ),
                            AbsorbPointer(
                              absorbing: _busy,
                              child: Form(
                                key: _form,
                                child: Column(
                                  children: widget.stockAdjustment
                                      ? [
                                          DropdownButtonFormField<String>(
                  isExpanded: true,
                                            initialValue: _movement,
                                            decoration: const InputDecoration(
                                              labelText: 'Movimiento',
                                            ),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'in',
                                                child:
                                                    Text('Ingreso / recepción'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'out',
                                                child: Text('Salida / merma'),
                                              ),
                                            ],
                                            onChanged: (value) {
                                              if (value != null)
                                                setState(() {
                                                  _movement = value;
                                                  _dirty = true;
                                                });
                                            },
                                          ),
                                          const SizedBox(height: 16),
                                          _field(
                                            'quantity',
                                            'Cantidad (${widget.product!['unit'] ?? 'unidad'})',
                                            number: true,
                                            positive: true,
                                          ),
                                          _field(
                                            'reason',
                                            'Motivo *',
                                            required: true,
                                          ),
                                        ]
                                      : [
                                          _field(
                                            'name',
                                            'Nombre *',
                                            required: true,
                                          ),
                                          _field('sku', 'SKU / código'),
                                          _field('category', 'Categoría'),
                                          _field(
                                            'unit',
                                            'Unidad *',
                                            required: true,
                                          ),
                                          if (widget.product == null)
                                            _field(
                                              'stock_quantity',
                                              'Stock inicial',
                                              number: true,
                                            ),
                                          _field(
                                            'minimum_quantity',
                                            'Stock mínimo',
                                            number: true,
                                          ),
                                          _field(
                                            'cost_clp',
                                            'Costo unitario (CLP)',
                                            number: true,
                                            money: true,
                                          ),
                                          _field(
                                            'price_clp',
                                            'Precio de venta (CLP)',
                                            number: true,
                                            money: true,
                                          ),
                                        ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: _busy ? null : _close,
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy ? null : _save,
                              child: Text(
                                _busy
                                    ? 'Guardando…'
                                    : widget.stockAdjustment
                                        ? 'Registrar movimiento'
                                        : 'Guardar producto',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
