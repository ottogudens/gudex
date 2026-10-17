import 'package:flutter/material.dart';

import '../services/api_client.dart';

String? _requiredText(String? value) =>
    value == null || value.trim().isEmpty ? 'Este dato es obligatorio' : null;

String _message(Object error) => error.toString().replaceFirst('Exception: ', '');

Future<Map<String, dynamic>?> showQuickCreateCustomer(
    BuildContext context, ApiClient api) async {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final rut = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  String? error;
  var saving = false;
  try {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Crear cliente'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre completo *'), validator: _requiredText),
                  TextFormField(controller: rut, decoration: const InputDecoration(labelText: 'RUT')),
                  TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
                  TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
                  if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
            FilledButton(
              onPressed: saving ? null : () async {
                if (!form.currentState!.validate()) return;
                update(() { saving = true; error = null; });
                try {
                  final result = await api.postJson('/api/v1/customers', {
                    'full_name': name.text.trim(),
                    'rut': rut.text.trim().isEmpty ? null : rut.text.trim(),
                    'email': email.text.trim().isEmpty ? null : email.text.trim(),
                    'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext, Map<String, dynamic>.from(result as Map));
                } catch (exception) {
                  update(() { saving = false; error = _message(exception); });
                }
              },
              child: Text(saving ? 'Guardando…' : 'Crear y seleccionar'),
            ),
          ],
        ),
      ),
    );
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose(); rut.dispose(); email.dispose(); phone.dispose();
  }
}

Future<Map<String, dynamic>?> showQuickCreateVehicle(
  BuildContext context,
  ApiClient api,
  List<Map<String, dynamic>> customers, {
  int? initialCustomerId,
}) async {
  if (customers.isEmpty) return null;
  final form = GlobalKey<FormState>();
  final plate = TextEditingController();
  final make = TextEditingController();
  final model = TextEditingController();
  final year = TextEditingController();
  final mileage = TextEditingController();
  var customerId = initialCustomerId ?? customers.first['id'] as int;
  String? error;
  var saving = false;
  try {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Crear vehículo'),
          content: SizedBox(width: 460, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: customerId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cliente *'),
              items: customers.map((item) => DropdownMenuItem<int>(value: item['id'] as int, child: Text(item['full_name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (value) { if (value != null) update(() => customerId = value); },
            ),
            TextFormField(controller: plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Patente *'), validator: _requiredText),
            TextFormField(controller: make, decoration: const InputDecoration(labelText: 'Marca *'), validator: _requiredText),
            TextFormField(controller: model, decoration: const InputDecoration(labelText: 'Modelo *'), validator: _requiredText),
            TextFormField(controller: year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Año'), validator: (value) => value == null || value.trim().isEmpty || int.tryParse(value.trim()) != null ? null : 'Ingresa un año válido'),
            TextFormField(controller: mileage, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kilometraje'), validator: (value) => value == null || value.trim().isEmpty || int.tryParse(value.trim()) != null ? null : 'Ingresa un kilometraje válido'),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ])))),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
            FilledButton(onPressed: saving ? null : () async {
              if (!form.currentState!.validate()) return;
              update(() { saving = true; error = null; });
              try {
                final result = await api.postJson('/api/v1/vehicles', {
                  'customer_id': customerId,
                  'plate': plate.text.trim(),
                  'make': make.text.trim(),
                  'model': model.text.trim(),
                  if (int.tryParse(year.text.trim()) != null) 'year': int.parse(year.text.trim()),
                  if (int.tryParse(mileage.text.trim()) != null) 'current_mileage_km': int.parse(mileage.text.trim()),
                });
                if (dialogContext.mounted) Navigator.pop(dialogContext, Map<String, dynamic>.from(result as Map));
              } catch (exception) {
                update(() { saving = false; error = _message(exception); });
              }
            }, child: Text(saving ? 'Guardando…' : 'Crear y seleccionar')),
          ],
        ),
      ),
    );
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    plate.dispose(); make.dispose(); model.dispose(); year.dispose(); mileage.dispose();
  }
}

Future<Map<String, dynamic>?> showQuickCreateProduct(
    BuildContext context, ApiClient api) async {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final sku = TextEditingController();
  final category = TextEditingController();
  final stock = TextEditingController(text: '0');
  final price = TextEditingController(text: '0');
  String? error;
  var saving = false;
  try {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('Crear producto'),
        content: SizedBox(width: 460, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre *'), validator: _requiredText),
          TextFormField(controller: sku, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'SKU / código')),
          TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Categoría')),
          TextFormField(controller: stock, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock inicial *'), validator: (value) => double.tryParse((value ?? '').trim()) == null ? 'Ingresa una cantidad válida' : null),
          TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio de venta (CLP) *'), validator: (value) => int.tryParse((value ?? '').trim()) == null ? 'Ingresa un precio válido' : null),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ])))),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: saving ? null : () async {
            if (!form.currentState!.validate()) return;
            update(() { saving = true; error = null; });
            try {
              final result = await api.postJson('/api/v1/products', {
                'name': name.text.trim(),
                'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
                'category': category.text.trim().isEmpty ? null : category.text.trim(),
                'unit': 'unidad',
                'stock_quantity': double.parse(stock.text.trim()),
                'minimum_quantity': 0,
                'cost_clp': 0,
                'price_clp': int.parse(price.text.trim()),
              });
              if (dialogContext.mounted) Navigator.pop(dialogContext, Map<String, dynamic>.from(result as Map));
            } catch (exception) {
              update(() { saving = false; error = _message(exception); });
            }
          }, child: Text(saving ? 'Guardando…' : 'Crear y seleccionar')),
        ],
      )),
    );
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose(); sku.dispose(); category.dispose(); stock.dispose(); price.dispose();
  }
}

Future<Map<String, dynamic>?> showQuickCreateWorkOrder(
  BuildContext context,
  ApiClient api, {
  required int customerId,
  required List<Map<String, dynamic>> vehicles,
}) async {
  if (vehicles.isEmpty) return null;
  final form = GlobalKey<FormState>();
  final mileage = TextEditingController();
  final symptoms = TextEditingController();
  var vehicleId = vehicles.first['id'] as int;
  String? error;
  var saving = false;
  try {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('Crear orden de trabajo'),
        content: SizedBox(width: 460, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(initialValue: vehicleId, isExpanded: true, decoration: const InputDecoration(labelText: 'Vehículo *'), items: vehicles.map((item) => DropdownMenuItem<int>(value: item['id'] as int, child: Text('${item['plate']} · ${item['make']} ${item['model']}', overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) { if (value != null) update(() => vehicleId = value); }),
          TextFormField(controller: mileage, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kilometraje'), validator: (value) => value == null || value.trim().isEmpty || int.tryParse(value.trim()) != null ? null : 'Ingresa un kilometraje válido'),
          TextFormField(controller: symptoms, maxLines: 2, decoration: const InputDecoration(labelText: 'Síntomas informados')),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ])))),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: saving ? null : () async {
            if (!form.currentState!.validate()) return;
            update(() { saving = true; error = null; });
            try {
              final result = await api.postJson('/api/v1/work-orders', {
                'customer_id': customerId,
                'vehicle_id': vehicleId,
                if (int.tryParse(mileage.text.trim()) != null) 'mileage_km': int.parse(mileage.text.trim()),
                if (symptoms.text.trim().isNotEmpty) 'reported_symptoms': symptoms.text.trim(),
              });
              if (dialogContext.mounted) Navigator.pop(dialogContext, Map<String, dynamic>.from(result as Map));
            } catch (exception) {
              update(() { saving = false; error = _message(exception); });
            }
          }, child: Text(saving ? 'Guardando…' : 'Crear y seleccionar')),
        ],
      )),
    );
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    mileage.dispose(); symptoms.dispose();
  }
}
