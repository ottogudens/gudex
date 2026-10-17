import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../services/api_client.dart';
import '../services/draft_store.dart';
import '../widgets/quick_create_dialogs.dart';
import 'vehicle_history_screen.dart';

class WorkshopScreen extends StatefulWidget {
  const WorkshopScreen(
      {required this.api,
      required this.modulePath,
      required this.role,
      super.key});
  final ApiClient api;
  final String modulePath;
  final String role;

  @override
  State<WorkshopScreen> createState() => _WorkshopScreenState();
}

class _WorkshopScreenState extends State<WorkshopScreen> {
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _vehicles = [];
  int _customerSection = 0;
  bool _kanbanView = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _query = '';

  bool get _isOrders => widget.modulePath.startsWith('/api/v1/work-orders');
  bool get _canCreate => widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isOrders) {
        final values = await Future.wait([
          widget.modulePath == '/api/v1/work-orders'
              ? widget.api.getAll(widget.modulePath)
              : widget.api.get(widget.modulePath),
          widget.api.getAll('/api/v1/customers'),
          widget.api.getAll('/api/v1/vehicles'),
        ]);
        _records = _maps(values[0]);
        _customers = _maps(values[1]);
        _vehicles = _maps(values[2]);
      } else {
        final errors = <String>[];
        Future<void> load(String path, String label,
            void Function(List<Map<String, dynamic>>) accept) async {
          try {
            accept(await widget.api.getAll(path));
          } catch (error) {
            errors.add(
                '$label: ${error.toString().replaceFirst('Exception: ', '')}');
          }
        }

        await Future.wait([
          load('/api/v1/customers', 'Clientes', (rows) => _customers = rows),
          load('/api/v1/vehicles', 'Vehículos', (rows) => _vehicles = rows),
        ]);
        _error = errors.isEmpty ? null : errors.join('\n');
        _records = _customerSection == 0 ? _customers : _vehicles;
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];

  Future<void> _createCustomer() async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final rut = TextEditingController();
    final password = TextEditingController();
    final confirmPassword = TextEditingController();
    bool createPortalAccess = false;
    bool setManualPassword = false;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: const Text('Registrar cliente'),
                  content: SizedBox(
                      width: 480,
                      child: Form(
                          key: form,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                TextFormField(
                                    controller: name,
                                    decoration: const InputDecoration(
                                        labelText: 'Nombre completo *'),
                                    validator: (v) =>
                                        (v == null || v.trim().length < 2)
                                            ? 'Ingresa el nombre'
                                            : null),
                                const SizedBox(height: 10),
                                TextFormField(
                                    controller: rut,
                                    decoration: const InputDecoration(
                                        labelText: 'RUT (opcional)')),
                                const SizedBox(height: 10),
                                TextFormField(
                                    controller: phone,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                        labelText: 'Teléfono')),
                                const SizedBox(height: 10),
                                TextFormField(
                                    controller: email,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: InputDecoration(
                                        labelText: createPortalAccess
                                            ? 'Correo para acceso al portal *'
                                            : 'Correo'),
                                    validator: (v) => createPortalAccess &&
                                            (v == null || !v.contains('@'))
                                        ? 'Ingresa un correo válido'
                                        : null),
                                const SizedBox(height: 8),
                                SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    value: createPortalAccess,
                                    onChanged: (value) => update(() {
                                          createPortalAccess = value;
                                          if (!value) setManualPassword = false;
                                        }),
                                    title: const Text('Crear acceso al portal'),
                                    subtitle: const Text(
                                        'El cliente podrá consultar sus vehículos, trabajos y cotizaciones.')),
                                if (createPortalAccess) ...[
                                  CheckboxListTile.adaptive(
                                      contentPadding: EdgeInsets.zero,
                                      value: setManualPassword,
                                      onChanged: (value) => update(() =>
                                          setManualPassword = value == true),
                                      title: const Text(
                                          'Definir contraseña manualmente'),
                                      subtitle: const Text(
                                          'El cliente podrá cambiarla después desde el portal.')),
                                  if (setManualPassword) ...[
                                    TextFormField(
                                        controller: password,
                                        obscureText: true,
                                        autofillHints: const [
                                          AutofillHints.newPassword
                                        ],
                                        decoration: const InputDecoration(
                                            labelText: 'Contraseña inicial *',
                                            helperText: 'Mínimo 6 caracteres'),
                                        validator: (v) =>
                                            (v == null || v.length < 6)
                                                ? 'Usa al menos 6 caracteres'
                                                : null),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                        controller: confirmPassword,
                                        obscureText: true,
                                        decoration: const InputDecoration(
                                            labelText:
                                                'Confirmar contraseña *'),
                                        validator: (v) => v != password.text
                                            ? 'Las contraseñas no coinciden'
                                            : null),
                                  ],
                                ],
                              ])))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () {
                          if (!form.currentState!.validate()) return;
                          Navigator.pop(context, {
                            'full_name': name.text.trim(),
                            if (rut.text.trim().isNotEmpty)
                              'rut': rut.text.trim(),
                            if (phone.text.trim().isNotEmpty)
                              'phone': phone.text.trim(),
                            if (email.text.trim().isNotEmpty)
                              'email': email.text.trim(),
                            'create_portal_access': createPortalAccess,
                            if (setManualPassword) 'password': password.text,
                          });
                        },
                        child: const Text('Guardar')),
                  ],
                )),
      );
      if (data != null)
        await _save(
            data['create_portal_access'] == true
                ? '/api/v1/customers/with-portal-access'
                : '/api/v1/customers',
            data,
            data['password'] != null
                ? 'Cliente registrado y acceso configurado. Entrega la contraseña al cliente de forma segura.'
                : data['create_portal_access'] == true
                    ? 'Cliente registrado; invitación preparada para envío.'
                    : 'Cliente registrado');
    } finally {
      name.dispose();
      email.dispose();
      phone.dispose();
      rut.dispose();
      password.dispose();
      confirmPassword.dispose();
    }
  }

  Future<void> _createVehicle() async {
    if (_customers.isEmpty) {
      final created = await showQuickCreateCustomer(context, widget.api);
      if (created == null || !mounted) return;
      setState(() => _customers.add(created));
    }
    final form = GlobalKey<FormState>();
    final plate = TextEditingController();
    final make = TextEditingController();
    final model = TextEditingController();
    final year = TextEditingController();
    final vin = TextEditingController();
    final engine = TextEditingController();
    final mileage = TextEditingController();
    int customerId = _customers.first['id'] as int;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, updateDialog) => AlertDialog(
                  title: const Text('Registrar vehículo'),
                  content: Form(
                      key: form,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        DropdownButtonFormField<int>(
                          initialValue: customerId,
                          decoration:
                              const InputDecoration(labelText: 'Cliente *'),
                          items: [
                            ..._customers.map((item) => DropdownMenuItem<int>(
                                  value: item['id'] as int,
                                  child: Text('${item['full_name']}'))),
                            const DropdownMenuItem<int>(value: -1, child: Row(children: [Icon(Icons.person_add_alt_1), SizedBox(width: 8), Text('Crear nuevo cliente')]))
                          ],
                          onChanged: (value) async {
                            if (value == -1) {
                              final created = await showQuickCreateCustomer(context, widget.api);
                              if (created != null && context.mounted) updateDialog(() {
                                _customers.add(created);
                                customerId = created['id'] as int;
                              });
                            } else if (value != null) {
                              updateDialog(() => customerId = value);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: plate,
                            textCapitalization: TextCapitalization.characters,
                            decoration:
                                const InputDecoration(labelText: 'Patente *'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Ingresa la patente'
                                : null),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: make,
                            decoration:
                                const InputDecoration(labelText: 'Marca *'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Ingresa la marca'
                                : null),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: model,
                            decoration:
                                const InputDecoration(labelText: 'Modelo *'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Ingresa el modelo'
                                : null),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: year,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Año'),
                            validator: (v) => v == null ||
                                    v.trim().isEmpty ||
                                    int.tryParse(v.trim()) != null
                                ? null
                                : 'Ingresa un año válido'),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: vin,
                            decoration:
                                const InputDecoration(labelText: 'VIN')),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: engine,
                            decoration:
                                const InputDecoration(labelText: 'Motor')),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: mileage,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Kilometraje'),
                            validator: (v) => v == null ||
                                    v.trim().isEmpty ||
                                    int.tryParse(v.trim()) != null
                                ? null
                                : 'Ingresa un kilometraje válido'),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () {
                          if (!form.currentState!.validate()) return;
                          final parsedYear = int.tryParse(year.text.trim());
                          final parsedMileage =
                              int.tryParse(mileage.text.trim());
                          Navigator.pop(context, {
                            'customer_id': customerId,
                            'plate': plate.text.trim().toUpperCase(),
                            'make': make.text.trim(),
                            'model': model.text.trim(),
                            if (parsedYear != null) 'year': parsedYear,
                            if (vin.text.trim().isNotEmpty)
                              'vin': vin.text.trim().toUpperCase(),
                            if (engine.text.trim().isNotEmpty)
                              'engine': engine.text.trim(),
                            if (parsedMileage != null)
                              'current_mileage_km': parsedMileage,
                          });
                        },
                        child: const Text('Guardar')),
                  ],
                )),
      );
      if (data != null)
        await _save('/api/v1/vehicles', data, 'Vehículo registrado');
    } finally {
      plate.dispose();
      make.dispose();
      model.dispose();
      year.dispose();
      vin.dispose();
      engine.dispose();
      mileage.dispose();
    }
  }

  Future<void> _editCustomer(Map<String, dynamic> customer) async {
    final form = GlobalKey<FormState>();
    final name =
        TextEditingController(text: customer['full_name']?.toString() ?? '');
    final rut = TextEditingController(text: customer['rut']?.toString() ?? '');
    final phone =
        TextEditingController(text: customer['phone']?.toString() ?? '');
    final email =
        TextEditingController(text: customer['email']?.toString() ?? '');
    final notes =
        TextEditingController(text: customer['notes']?.toString() ?? '');
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Editar cliente'),
          content: Form(
              key: form,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'Nombre completo *'),
                    validator: (value) =>
                        value == null || value.trim().length < 2
                            ? 'Ingresa el nombre'
                            : null),
                const SizedBox(height: 10),
                TextFormField(
                    controller: rut,
                    decoration: const InputDecoration(labelText: 'RUT')),
                const SizedBox(height: 10),
                TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Teléfono')),
                const SizedBox(height: 10),
                TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo')),
                const SizedBox(height: 10),
                TextFormField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notas')),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  if (!form.currentState!.validate()) return;
                  Navigator.pop(context, {
                    'full_name': name.text.trim(),
                    'rut': rut.text.trim(),
                    'phone': phone.text.trim(),
                    'email': email.text.trim(),
                    'notes': notes.text.trim()
                  });
                },
                child: const Text('Guardar cambios')),
          ],
        ),
      );
      if (data == null) return;
      await widget.api
          .patchJson('/api/v1/customers/' + customer['id'].toString(), data);
      await _refresh();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Cliente actualizado')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      name.dispose();
      rut.dispose();
      phone.dispose();
      email.dispose();
      notes.dispose();
    }
  }

  Future<void> _setCustomerPassword(Map<String, dynamic> customer) async {
    if ((customer['email']?.toString() ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Agrega primero un correo al cliente.')));
      return;
    }
    final form = GlobalKey<FormState>();
    final password = TextEditingController();
    final confirm = TextEditingController();
    try {
      final value = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Definir contraseña del portal'),
                content: SizedBox(
                    width: 420,
                    child: Form(
                        key: form,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('Cuenta para ${customer['email']}'),
                          const SizedBox(height: 12),
                          TextFormField(
                              controller: password,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText: 'Nueva contraseña',
                                  helperText: 'Mínimo 6 caracteres'),
                              validator: (v) => v == null || v.length < 6
                                  ? 'Usa al menos 6 caracteres'
                                  : null),
                          const SizedBox(height: 10),
                          TextFormField(
                              controller: confirm,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText: 'Confirmar contraseña'),
                              validator: (v) => v != password.text
                                  ? 'Las contraseñas no coinciden'
                                  : null),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate())
                          Navigator.pop(context, password.text);
                      },
                      child: const Text('Guardar contraseña'))
                ],
              ));
      if (value == null) return;
      await widget.api.postJson(
          '/api/v1/customers/' +
              customer['id'].toString() +
              '/portal-access/password',
          {'password': value});
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Acceso al portal listo. Entrega la contraseña al cliente de forma segura.')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      password.dispose();
      confirm.dispose();
    }
  }

  Future<void> _editVehicle(Map<String, dynamic> vehicle) async {
    final form = GlobalKey<FormState>();
    final plate =
        TextEditingController(text: vehicle['plate']?.toString() ?? '');
    final make = TextEditingController(text: vehicle['make']?.toString() ?? '');
    final model =
        TextEditingController(text: vehicle['model']?.toString() ?? '');
    final year = TextEditingController(text: vehicle['year']?.toString() ?? '');
    final vin = TextEditingController(text: vehicle['vin']?.toString() ?? '');
    final engine =
        TextEditingController(text: vehicle['engine']?.toString() ?? '');
    final mileage = TextEditingController(
        text: vehicle['current_mileage_km']?.toString() ?? '');
    final notes =
        TextEditingController(text: vehicle['notes']?.toString() ?? '');
    int customerId = vehicle['customer_id'] as int;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, updateDialog) => AlertDialog(
                  title: const Text('Editar vehículo'),
                  content: Form(
                      key: form,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        DropdownButtonFormField<int>(
                            initialValue: customerId,
                            decoration:
                                const InputDecoration(labelText: 'Cliente *'),
                            items: _customers
                                .map((item) => DropdownMenuItem<int>(
                                    value: item['id'] as int,
                                    child: Text(item['full_name'].toString())))
                                .toList(),
                            onChanged: (value) {
                              if (value != null)
                                updateDialog(() => customerId = value);
                            }),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: plate,
                            textCapitalization: TextCapitalization.characters,
                            decoration:
                                const InputDecoration(labelText: 'Patente *'),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Ingresa la patente'
                                    : null),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: make,
                            decoration:
                                const InputDecoration(labelText: 'Marca *'),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Ingresa la marca'
                                    : null),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: model,
                            decoration:
                                const InputDecoration(labelText: 'Modelo *'),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Ingresa el modelo'
                                    : null),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: year,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Año'),
                            validator: (value) => value == null ||
                                    value.trim().isEmpty ||
                                    int.tryParse(value.trim()) != null
                                ? null
                                : 'Ingresa un año válido'),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: vin,
                            decoration:
                                const InputDecoration(labelText: 'VIN')),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: engine,
                            decoration:
                                const InputDecoration(labelText: 'Motor')),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: mileage,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Kilometraje'),
                            validator: (value) => value == null ||
                                    value.trim().isEmpty ||
                                    int.tryParse(value.trim()) != null
                                ? null
                                : 'Ingresa un kilometraje válido'),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: notes,
                            maxLines: 3,
                            decoration:
                                const InputDecoration(labelText: 'Notas')),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () {
                          if (!form.currentState!.validate()) return;
                          Navigator.pop(context, {
                            'customer_id': customerId,
                            'plate': plate.text.trim().toUpperCase(),
                            'make': make.text.trim(),
                            'model': model.text.trim(),
                            'year': int.tryParse(year.text.trim()),
                            'vin': vin.text.trim().toUpperCase(),
                            'engine': engine.text.trim(),
                            'current_mileage_km':
                                int.tryParse(mileage.text.trim()),
                            'notes': notes.text.trim()
                          });
                        },
                        child: const Text('Guardar cambios')),
                  ],
                )),
      );
      if (data == null) return;
      await widget.api
          .patchJson('/api/v1/vehicles/' + vehicle['id'].toString(), data);
      await _refresh();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vehículo actualizado')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      plate.dispose();
      make.dispose();
      model.dispose();
      year.dispose();
      vin.dispose();
      engine.dispose();
      mileage.dispose();
      notes.dispose();
    }
  }

  Future<void> _deleteRecord(Map<String, dynamic> item,
      {required bool vehicle}) async {
    final label =
        vehicle ? item['plate'].toString() : item['full_name'].toString();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(vehicle ? 'Eliminar vehículo' : 'Archivar cliente'),
              content: Text(vehicle
                  ? '¿Eliminar $label? Esta acción no se puede deshacer. Si tiene historial asociado, Gudex impedirá la eliminación.'
                  : '¿Archivar a $label? Su historial técnico y comercial se conservará, pero no podrá recibir nuevas atenciones ni usar el portal.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton.tonal(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(vehicle ? 'Eliminar' : 'Archivar'))
              ],
            ));
    if (confirmed != true) return;
    try {
      await widget.api.delete('/api/v1/' +
          (vehicle ? 'vehicles' : 'customers') +
          '/' +
          item['id'].toString());
      await _refresh();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(vehicle
                ? 'Vehículo eliminado'
                : 'Cliente archivado. Su historial se conserva.')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _createWorkOrder() async {
    if (_customers.isEmpty) {
      final customer = await showQuickCreateCustomer(context, widget.api);
      if (customer == null || !mounted) return;
      setState(() => _customers.add(customer));
    }
    if (_vehicles.isEmpty) {
      final vehicle = await showQuickCreateVehicle(context, widget.api, _customers,
          initialCustomerId: _customers.first['id'] as int);
      if (vehicle == null || !mounted) return;
      setState(() => _vehicles.add(vehicle));
    }
    final form = GlobalKey<FormState>();
    final mileage = TextEditingController();
    final symptoms = TextEditingController();
    final notes = TextEditingController();
    int customerId = _customers.first['id'] as int;
    int? vehicleId = _vehicles.firstWhere((v) => v['customer_id'] == customerId,
        orElse: () => _vehicles.first)['id'] as int;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, updateDialog) {
          final customerVehicles =
              _vehicles.where((v) => v['customer_id'] == customerId).toList();
          if (customerVehicles.isNotEmpty &&
              !customerVehicles.any((v) => v['id'] == vehicleId))
            vehicleId = customerVehicles.first['id'] as int;
          return AlertDialog(
            title: const Text('Abrir orden de trabajo'),
            content: Form(
                key: form,
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<int>(
                    initialValue: customerId,
                    decoration: const InputDecoration(labelText: 'Cliente *'),
                    items: [
                      ..._customers.map((item) => DropdownMenuItem<int>(
                            value: item['id'] as int,
                            child: Text('${item['full_name']}'))),
                      const DropdownMenuItem<int>(value: -1, child: Row(children: [Icon(Icons.person_add_alt_1), SizedBox(width: 8), Text('Crear nuevo cliente')]))
                    ],
                    onChanged: (value) async {
                      if (value == -1) {
                        final created = await showQuickCreateCustomer(context, widget.api);
                        if (created != null && context.mounted) updateDialog(() {
                          _customers.add(created);
                          customerId = created['id'] as int;
                          vehicleId = null;
                        });
                      } else if (value != null) {
                        updateDialog(() {
                          customerId = value;
                          vehicleId = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue:
                        customerVehicles.any((v) => v['id'] == vehicleId)
                            ? vehicleId
                            : null,
                    decoration: const InputDecoration(labelText: 'Vehículo *'),
                    items: [
                      ...customerVehicles.map((item) => DropdownMenuItem<int>(
                            value: item['id'] as int,
                            child: Text(
                                '${item['plate']} · ${item['make']} ${item['model']}'))),
                      const DropdownMenuItem<int>(value: -1, child: Row(children: [Icon(Icons.add_road), SizedBox(width: 8), Text('Crear nuevo vehículo')]))
                    ],
                    onChanged: (value) async {
                      if (value == -1) {
                        final created = await showQuickCreateVehicle(context, widget.api, _customers, initialCustomerId: customerId);
                        if (created != null && context.mounted) updateDialog(() {
                          _vehicles.add(created);
                          customerId = created['customer_id'] as int;
                          vehicleId = created['id'] as int;
                        });
                      } else if (value != null) {
                        updateDialog(() => vehicleId = value);
                      }
                    },
                    validator: (value) => value == null
                        ? 'Selecciona un vehículo del cliente'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                      controller: mileage,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Kilometraje de recepción'),
                      validator: (v) => v == null ||
                              v.trim().isEmpty ||
                              int.tryParse(v.trim()) != null
                          ? null
                          : 'Ingresa un kilometraje válido'),
                  const SizedBox(height: 10),
                  TextFormField(
                      controller: symptoms,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Síntomas informados')),
                  const SizedBox(height: 10),
                  TextFormField(
                      controller: notes,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Notas de recepción')),
                ]))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () {
                    if (!form.currentState!.validate() || vehicleId == null)
                      return;
                    final parsedMileage = int.tryParse(mileage.text.trim());
                    Navigator.pop(context, {
                      'customer_id': customerId,
                      'vehicle_id': vehicleId,
                      if (parsedMileage != null) 'mileage_km': parsedMileage,
                      if (symptoms.text.trim().isNotEmpty)
                        'reported_symptoms': symptoms.text.trim(),
                      if (notes.text.trim().isNotEmpty)
                        'initial_notes': notes.text.trim(),
                    });
                  },
                  child: const Text('Crear orden')),
            ],
          );
        }),
      );
      if (data != null)
        await _save('/api/v1/work-orders', data, 'Orden de trabajo creada');
    } finally {
      mileage.dispose();
      symptoms.dispose();
      notes.dispose();
    }
  }

  Future<void> _save(
      String path, Map<String, dynamic> data, String success) async {
    setState(() => _saving = true);
    try {
      await widget.api.postJson(path, data);
      if (!mounted) return;
      await _refresh();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openOrder(Map<String, dynamic> order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => WorkOrderDetails(
          api: widget.api,
          order: order,
          role: widget.role,
          onChanged: _refresh),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null &&
        (_isOrders || (_customers.isEmpty && _vehicles.isEmpty)))
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('No se pudieron cargar los datos.\n$_error',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar')),
              ])));

    final isCustomerPage = !_isOrders;
    final query = _query.trim().toLowerCase();
    final visibleRecords = _isOrders || query.isEmpty
        ? _records
        : _records.where((row) {
            final owner =
                _customers.where((c) => c['id'] == row['customer_id']);
            return [
                  'full_name',
                  'rut',
                  'email',
                  'phone',
                  'plate',
                  'make',
                  'model',
                  'vin'
                ]
                    .map((key) => '${row[key] ?? ''}')
                    .join(' ')
                    .toLowerCase()
                    .contains(query) ||
                owner.any(
                    (c) => '${c['full_name']}'.toLowerCase().contains(query));
          }).toList();
    final label = _isOrders
        ? 'órdenes de trabajo'
        : (_customerSection == 0 ? 'clientes' : 'vehículos');
    final activeOrders = _records
        .where((item) =>
            item['status'] != 'delivered' && item['status'] != 'cancelled')
        .length;
    return Stack(children: [
      Column(children: [
        if (_error != null)
          MaterialBanner(
            content: Text(
                'Carga incompleta. Los datos anteriores se conservan.\n$_error'),
            actions: [
              TextButton(onPressed: _refresh, child: const Text('Reintentar'))
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: _OperationalHeader(
            title: _isOrders ? 'Órdenes de trabajo' : 'Base de clientes',
            subtitle: _isOrders
                ? '$activeOrders activas · ${_records.length} en total'
                : '${_customers.length} clientes · ${_vehicles.length} vehículos',
            icon: _isOrders
                ? Icons.precision_manufacturing_outlined
                : Icons.groups_2_outlined,
          ),
        ),
        if (isCustomerPage)
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                      value: 0,
                      label: Text('Clientes'),
                      icon: Icon(Icons.people_outline)),
                  ButtonSegment(
                      value: 1,
                      label: Text('Vehículos'),
                      icon: Icon(Icons.directions_car_outlined)),
                ],
                selected: {_customerSection},
                onSelectionChanged: (value) => setState(() {
                  _customerSection = value.first;
                  _records = _customerSection == 0 ? _customers : _vehicles;
                }),
              )),
        if (isCustomerPage)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Buscar cliente, patente, marca o VIN'),
                onChanged: (value) => setState(() => _query = value),
              )),
        if (_isOrders)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: true,
                      icon: Icon(Icons.view_kanban_outlined),
                      label: Text('Tablero')),
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.view_list_outlined),
                      label: Text('Lista')),
                ],
                selected: {_kanbanView},
                onSelectionChanged: (value) =>
                    setState(() => _kanbanView = value.first),
              ),
            ),
          ),
        Expanded(
            child: visibleRecords.isEmpty
                ? RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(children: [
                      SizedBox(
                          height: 300,
                          child: Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Icon(
                                    _isOrders
                                        ? Icons.assignment_outlined
                                        : Icons.inbox_outlined,
                                    size: 42,
                                    color:
                                        Theme.of(context).colorScheme.outline),
                                const SizedBox(height: 12),
                                Text(query.isNotEmpty
                                    ? 'No hay coincidencias para la búsqueda.'
                                    : _error != null
                                        ? 'No se pudo confirmar el listado de $label.'
                                        : 'No hay $label registrados.'),
                                const SizedBox(height: 4),
                                Text(
                                    _isOrders
                                        ? 'Crea una orden para iniciar la recepción.'
                                        : 'Registra datos para comenzar a construir el historial.',
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.bodySmall)
                              ])))
                    ]))
                : _isOrders && _kanbanView
                    ? _kanbanBoard()
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                          itemCount: visibleRecords.length,
                          itemBuilder: (context, index) {
                            final item = visibleRecords[index];
                            if (_isOrders) return _workOrderTile(item);
                            if (_customerSection == 0)
                              return _customerTile(item);
                            return _vehicleTile(item);
                          },
                        ))),
      ]),
      if (_canCreate)
        Positioned(
          right: 18,
          bottom: 18,
          child: FloatingActionButton.extended(
            onPressed: _saving
                ? null
                : _isOrders
                    ? _createWorkOrder
                    : _customerSection == 0
                        ? _createCustomer
                        : _createVehicle,
            icon: Icon(_isOrders
                ? Icons.add_task
                : _customerSection == 0
                    ? Icons.person_add_alt_1
                    : Icons.add),
            label: Text(_isOrders
                ? 'Nueva orden'
                : _customerSection == 0
                    ? 'Nuevo cliente'
                    : 'Nuevo vehículo'),
          ),
        ),
    ]);
  }

  Widget _customerTile(Map<String, dynamic> item) {
    final owned = _vehicles
        .where((vehicle) => vehicle['customer_id'] == item['id'])
        .length;
    return Card(
        child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text('${item['full_name'] ?? 'Cliente'}'),
      subtitle: Text([item['phone'], item['email'], '$owned vehículo(s)']
          .where((value) => value != null && '$value'.isNotEmpty)
          .join(' · ')),
      trailing: widget.role != 'admin'
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Acciones del cliente',
              onSelected: (value) {
                if (value == 'edit')
                  _editCustomer(item);
                else if (value == 'password')
                  _setCustomerPassword(item);
                else
                  _deleteRecord(item, vehicle: false);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'))),
                PopupMenuItem(
                    value: 'password',
                    child: ListTile(
                        leading: Icon(Icons.lock_reset_outlined),
                        title: Text('Definir contraseña del portal'))),
                PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: Icon(Icons.archive_outlined),
                        title: Text('Archivar cliente'))),
              ],
            ),
      onTap: widget.role == 'admin' ? () => _editCustomer(item) : null,
    ));
  }

  Widget _vehicleTile(Map<String, dynamic> item) {
    final owner =
        _customers.where((customer) => customer['id'] == item['customer_id']);
    final customerName =
        owner.isEmpty ? 'Cliente no disponible' : '${owner.first['full_name']}';
    return Card(
        child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.directions_car_outlined)),
      title: Text('${item['plate']} · ${item['make']} ${item['model']}'),
      subtitle: Text(
          '$customerName${item['year'] == null ? '' : ' · ${item['year']}'}${item['current_mileage_km'] == null ? '' : ' · ${item['current_mileage_km']} km'}'),
      trailing: widget.role != 'admin'
          ? const Icon(Icons.chevron_right)
          : PopupMenuButton<String>(
              tooltip: 'Acciones del vehículo',
              onSelected: (value) {
                if (value == 'edit')
                  _editVehicle(item);
                else if (value == 'delete')
                  _deleteRecord(item, vehicle: true);
                else
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => VehicleHistoryScreen(
                              api: widget.api,
                              vehicleId: item['id'] as int,
                              portal: false)));
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                    value: 'history',
                    child: ListTile(
                        leading: Icon(Icons.history),
                        title: Text('Ver historial'))),
                PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'))),
                PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Eliminar'))),
              ],
            ),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VehicleHistoryScreen(
                  api: widget.api,
                  vehicleId: item['id'] as int,
                  portal: false))),
    ));
  }

  Widget _workOrderTile(Map<String, dynamic> item) {
    final vehicle = _vehicles.where((v) => v['id'] == item['vehicle_id']);
    final customer = _customers.where((c) => c['id'] == item['customer_id']);
    final vehicleLabel = vehicle.isEmpty
        ? 'Vehículo #${item['vehicle_id']}'
        : '${vehicle.first['plate']} · ${vehicle.first['make']} ${vehicle.first['model']}';
    final customerLabel = customer.isEmpty
        ? 'Cliente #${item['customer_id']}'
        : '${customer.first['full_name']}';
    final status = '${item['status'] ?? 'received'}';
    final color = _statusColor(context, status);
    return Card(
        child: ListTile(
      leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .14),
          foregroundColor: color,
          child: const Icon(Icons.build_outlined)),
      title: Text('${item['code'] ?? 'Orden'} · $vehicleLabel'),
      subtitle: Text(
          '$customerLabel${item['technician_name'] == null ? '' : ' · ${item['technician_name']}'}${item['reported_symptoms'] == null ? '' : '\n${item['reported_symptoms']}'}'),
      isThreeLine: true,
      trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusPill(label: spanishStatus(status), color: color),
            const SizedBox(height: 8),
            const Icon(Icons.chevron_right),
          ]),
      onTap: () => _openOrder(item),
    ));
  }

  Widget _kanbanBoard() {
    const columns = [
      (
        'Recepción',
        <String>{'received', 'inspecting'},
        Icons.assignment_outlined
      ),
      (
        'Cotización',
        <String>{'quoted', 'awaiting_approval', 'approved', 'quote_rejected'},
        Icons.request_quote_outlined
      ),
      ('En taller', <String>{'in_progress'}, Icons.build_outlined),
      ('Entrega', <String>{'ready', 'delivered'}, Icons.task_alt_outlined),
    ];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(builder: (context, constraints) {
        final columnWidth = constraints.maxWidth >= 960
            ? (constraints.maxWidth - 48) / 4
            : 300.0;
        return ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
          children: columns.map((column) {
            final orders = _records
                .where((order) => column.$2.contains('${order['status']}'))
                .toList();
            return SizedBox(
              width: columnWidth,
              child: Card(
                margin: const EdgeInsets.only(right: 12),
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(column.$3, size: 18),
                          const SizedBox(width: 7),
                          Expanded(
                              child: Text(column.$1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800))),
                          _StatusPill(
                              label: '${orders.length}',
                              color: Theme.of(context).colorScheme.primary)
                        ]),
                        const SizedBox(height: 8),
                        Expanded(
                            child: orders.isEmpty
                                ? Center(
                                    child: Text('Sin órdenes',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall))
                                : ListView(
                                    children:
                                        orders.map(_workOrderTile).toList())),
                      ]),
                ),
              ),
            );
          }).toList(),
        );
      }),
    );
  }
}

Color _statusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'ready' || 'delivered' => Colors.green.shade700,
    'cancelled' || 'quote_rejected' => scheme.error,
    'awaiting_approval' || 'quoted' => Colors.orange.shade800,
    'in_progress' => Colors.blue.shade700,
    'inspecting' => Colors.purple.shade700,
    _ => scheme.primary,
  };
}

class _OperationalHeader extends StatelessWidget {
  const _OperationalHeader(
      {required this.title, required this.subtitle, required this.icon});
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          CircleAvatar(
              backgroundColor: scheme.onPrimaryContainer.withValues(alpha: .12),
              foregroundColor: scheme.onPrimaryContainer,
              child: Icon(icon)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onPrimaryContainer))
              ])),
        ]),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
      );
}

class WorkOrderDetails extends StatefulWidget {
  const WorkOrderDetails(
      {required this.api,
      required this.order,
      required this.role,
      required this.onChanged,
      super.key});
  final ApiClient api;
  final Map<String, dynamic> order;
  final String role;
  final Future<void> Function() onChanged;

  @override
  State<WorkOrderDetails> createState() => _WorkOrderDetailsState();
}

class _WorkOrderDetailsState extends State<WorkOrderDetails> {
  late final TextEditingController _diagnosis;
  late String _status;
  late Future<List<Map<String, dynamic>>> _inspections;
  late Future<List<Map<String, dynamic>>> _quotes;
  late Future<List<Map<String, dynamic>>> _templates;
  late Future<List<Map<String, dynamic>>> _evidence;
  late Future<Map<String, dynamic>> _report;
  late Future<Map<String, dynamic>> _workSessions;
  bool _saving = false;
  bool _restoringDraft = true;
  String? _error;

  static const _statuses = [
    'received',
    'inspecting',
    'quoted',
    'awaiting_approval',
    'quote_rejected',
    'approved',
    'in_progress',
    'ready',
    'delivered',
    'cancelled',
  ];

  List<String> get _availableStatuses {
    const transitions = <String, List<String>>{
      'received': ['received', 'inspecting', 'cancelled'],
      'inspecting': [
        'inspecting',
        'quoted',
        'awaiting_approval',
        'approved',
        'in_progress',
        'cancelled'
      ],
      'quoted': [
        'quoted',
        'awaiting_approval',
        'approved',
        'quote_rejected',
        'cancelled'
      ],
      'awaiting_approval': [
        'awaiting_approval',
        'approved',
        'quote_rejected',
        'cancelled'
      ],
      'quote_rejected': ['quote_rejected', 'inspecting', 'quoted', 'cancelled'],
      'approved': ['approved', 'in_progress', 'cancelled'],
      'in_progress': ['in_progress', 'ready', 'cancelled'],
      'ready': ['ready', 'in_progress', 'delivered', 'cancelled'],
      'delivered': ['delivered'],
      'cancelled': ['cancelled'],
    };
    final choices = transitions[_status] ?? _statuses;
    if (widget.role != 'mechanic') return choices;
    return choices
        .where((status) =>
            status == _status ||
            const {'inspecting', 'in_progress', 'ready'}.contains(status))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _diagnosis =
        TextEditingController(text: '${widget.order['diagnosis'] ?? ''}');
    _status = '${widget.order['status'] ?? 'received'}';
    _inspections = _loadInspections();
    _quotes = _loadQuotes();
    _templates = _loadList('/api/v1/inspection-templates');
    _evidence = _loadList('/api/v1/work-orders/${widget.order['id']}/evidence');
    _report = _loadReport();
    _workSessions = _loadWorkSessions();
    _restoreDraft();
  }

  @override
  void dispose() {
    _diagnosis.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadInspections() async {
    final result = await widget.api
        .get('/api/v1/work-orders/${widget.order['id']}/inspections');
    return result is List
        ? result
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : [];
  }

  Future<List<Map<String, dynamic>>> _loadQuotes() async {
    final result = await widget.api
        .get('/api/v1/work-orders/${widget.order['id']}/quotes');
    return result is List
        ? result
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : [];
  }

  Future<List<Map<String, dynamic>>> _loadList(String path) async {
    final result = await widget.api.get(path);
    return result is List
        ? result
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : [];
  }

  Future<Map<String, dynamic>> _loadReport() async {
    final result = await widget.api
        .get('/api/v1/work-orders/${widget.order['id']}/inspection-report');
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _loadWorkSessions() async {
    final result = await widget.api
        .get('/api/v1/work-orders/${widget.order['id']}/work-sessions');
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<void> _workTimer(String action, [int? sessionId]) async {
    try {
      final path = action == 'start'
          ? '/api/v1/work-orders/${widget.order['id']}/work-sessions/start'
          : '/api/v1/work-sessions/$sessionId/$action';
      await widget.api.post(path);
      if (mounted) setState(() => _workSessions = _loadWorkSessions());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  int? get _orderId => int.tryParse('${widget.order['id']}');

  Future<void> _restoreDraft() async {
    final orderId = _orderId;
    final draft =
        orderId == null ? null : await WorkOrderDraftStore.load(orderId);
    if (!mounted) return;
    setState(() => _restoringDraft = false);
    if (draft == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final restore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Borrador local encontrado'),
          content: const Text(
              'Hay cambios de estado y diagnóstico guardados en este dispositivo. ¿Quieres recuperarlos?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Descartar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Recuperar')),
          ],
        ),
      );
      if (!mounted) return;
      if (restore == true) {
        final status = '${draft['status'] ?? ''}';
        setState(() {
          if (_statuses.contains(status)) _status = status;
          _diagnosis.text = '${draft['diagnosis'] ?? ''}';
        });
      } else if (orderId != null) {
        await WorkOrderDraftStore.clear(orderId);
      }
    });
  }

  Future<void> _saveLocalDraft({bool showFeedback = true}) async {
    final orderId = _orderId;
    if (orderId == null) return;
    await WorkOrderDraftStore.save(orderId,
        status: _status, diagnosis: _diagnosis.text.trim());
    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Borrador guardado en este dispositivo')));
    }
  }

  Future<void> _printInspectionReport() async {
    try {
      await openGudexPdf(
          widget.api,
          '/api/v1/work-orders/${widget.order['id']}/inspection-report.pdf',
          'Gudex-inspeccion-${widget.order['id']}.pdf');
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo abrir el informe: $error')));
    }
  }

  Future<void> _saveOrder() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.patchJson('/api/v1/work-orders/${widget.order['id']}', {
        'status': _status,
        'diagnosis': _diagnosis.text.trim(),
      });
      final orderId = _orderId;
      if (orderId != null) await WorkOrderDraftStore.clear(orderId);
      if (!mounted) return;
      await widget.onChanged();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Orden actualizada')));
    } catch (error) {
      try {
        await _saveLocalDraft(showFeedback: false);
      } catch (_) {
        // El fallo de almacenamiento local no debe ocultar el error de la API.
      }
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addInspection() async {
    final form = GlobalKey<FormState>();
    final category = TextEditingController();
    final item = TextEditingController();
    final notes = TextEditingController();
    final measured = TextEditingController();
    String result = 'normal';
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, updateDialog) => AlertDialog(
                  title: const Text('Nueva inspección'),
                  content: Form(
                      key: form,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        TextFormField(
                            controller: category,
                            decoration: const InputDecoration(
                                labelText: 'Sistema / categoría *'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Campo obligatorio'
                                : null),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: item,
                            decoration: const InputDecoration(
                                labelText: 'Punto inspeccionado *'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Campo obligatorio'
                                : null),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: result,
                          decoration:
                              const InputDecoration(labelText: 'Resultado'),
                          items: const [
                            DropdownMenuItem(
                                value: 'normal', child: Text('Normal')),
                            DropdownMenuItem(
                                value: 'observation',
                                child: Text('Requiere atención')),
                            DropdownMenuItem(
                                value: 'failed',
                                child: Text('Falla detectada')),
                          ],
                          onChanged: (value) {
                            if (value != null)
                              updateDialog(() => result = value);
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: measured,
                            decoration: const InputDecoration(
                                labelText: 'Medición (opcional)')),
                        const SizedBox(height: 10),
                        TextFormField(
                            controller: notes,
                            maxLines: 3,
                            decoration: const InputDecoration(
                                labelText: 'Observaciones')),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () {
                          if (!form.currentState!.validate()) return;
                          Navigator.pop(context, {
                            'category': category.text.trim(),
                            'item': item.text.trim(),
                            'result': result,
                            if (measured.text.trim().isNotEmpty)
                              'measured_value': measured.text.trim(),
                            if (notes.text.trim().isNotEmpty)
                              'notes': notes.text.trim(),
                          });
                        },
                        child: const Text('Guardar')),
                  ],
                )),
      );
      if (data == null) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      await widget.api.postJson(
          '/api/v1/work-orders/${widget.order['id']}/inspections', data);
      if (!mounted) return;
      setState(() => _inspections = _loadInspections());
      await widget.onChanged();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Inspección guardada')));
    } catch (error) {
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      category.dispose();
      item.dispose();
      notes.dispose();
      measured.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyTemplate() async {
    try {
      final templates = await _templates;
      if (!mounted) return;
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Aplicar lista de inspección'),
          children: templates
              .map((template) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, template),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.checklist_outlined),
                      title: Text('${template['name']}'),
                      subtitle: Text('${template['description'] ?? ''}'),
                    ),
                  ))
              .toList(),
        ),
      );
      if (selected == null) return;
      setState(() => _saving = true);
      final response = await widget.api.post(
          '/api/v1/work-orders/${widget.order['id']}/inspection-templates/${selected['id']}/apply');
      if (!mounted) return;
      setState(() {
        _inspections = _loadInspections();
        _report = _loadReport();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${response['created_count']} puntos agregados')));
    } catch (error) {
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editInspection(Map<String, dynamic> inspection) async {
    final orderId = _orderId;
    final inspectionId = int.tryParse('${inspection['id']}');
    final savedDraft = orderId == null || inspectionId == null
        ? null
        : await WorkOrderDraftStore.loadInspection(orderId, inspectionId);
    final initial = savedDraft ?? inspection;
    final notes = TextEditingController(text: '${initial['notes'] ?? ''}');
    final measured =
        TextEditingController(text: '${initial['measured_value'] ?? ''}');
    String result = '${initial['result'] ?? 'not_inspected'}';
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text('${inspection['item']}'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (savedDraft != null) ...[
                      const Text(
                          'Estás editando un borrador local pendiente de envío.',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: result,
                      decoration: const InputDecoration(labelText: 'Resultado'),
                      items: const [
                        DropdownMenuItem(
                            value: 'not_inspected',
                            child: Text('No inspeccionado')),
                        DropdownMenuItem(
                            value: 'normal', child: Text('Normal')),
                        DropdownMenuItem(
                            value: 'observation', child: Text('Observación')),
                        DropdownMenuItem(value: 'failed', child: Text('Falla')),
                        DropdownMenuItem(
                            value: 'not_applicable', child: Text('No aplica')),
                      ],
                      onChanged: (value) {
                        if (value != null) update(() => result = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                        controller: measured,
                        decoration:
                            const InputDecoration(labelText: 'Medición')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: notes,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(labelText: 'Observaciones')),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, {
                              'result': result,
                              'measured_value': measured.text.trim(),
                              'notes': notes.text.trim(),
                            }),
                        child: const Text('Guardar')),
                  ],
                )),
      );
      if (data == null) return;
      await widget.api
          .patchJson('/api/v1/inspections/${inspection['id']}', data);
      if (orderId != null && inspectionId != null)
        await WorkOrderDraftStore.clearInspection(orderId, inspectionId);
      if (!mounted) return;
      setState(() {
        _inspections = _loadInspections();
        _report = _loadReport();
      });
    } catch (error) {
      if (orderId != null && inspectionId != null) {
        try {
          await WorkOrderDraftStore.saveInspection(orderId, inspectionId, {
            'result': result,
            'measured_value': measured.text.trim(),
            'notes': notes.text.trim(),
          });
        } catch (_) {
          // Conserva el error de API aunque el dispositivo no pueda guardar el borrador.
        }
      }
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      notes.dispose();
      measured.dispose();
    }
  }

  Future<void> _editReception() async {
    final orderId = _orderId;
    final savedDraft = orderId == null
        ? null
        : await WorkOrderDraftStore.loadReception(orderId);
    Map<String, dynamic> current = savedDraft ?? <String, dynamic>{};
    try {
      final currentRaw = await widget.api
          .get('/api/v1/work-orders/${widget.order['id']}/reception');
      if (savedDraft == null && currentRaw is Map)
        current = Map<String, dynamic>.from(currentRaw);
    } catch (_) {
      if (savedDraft == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Sin conexión: puedes preparar y guardar un borrador de recepción local.')));
      }
    }
    final damage =
        TextEditingController(text: '${current['visible_damage'] ?? ''}');
    final accessories =
        TextEditingController(text: '${current['accessories'] ?? ''}');
    final observations = TextEditingController(
        text: '${current['customer_observations'] ?? ''}');
    final acceptedBy =
        TextEditingController(text: '${current['accepted_by_name'] ?? ''}');
    int? fuel = current['fuel_level_percent'] as int?;
    bool accepted = current['terms_accepted'] == true;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: const Text('Recepción del vehículo'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (savedDraft != null) ...[
                      const Text(
                          'Estás editando un borrador local pendiente de envío.',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                    ],
                    DropdownButtonFormField<int>(
                        initialValue: fuel,
                        decoration:
                            const InputDecoration(labelText: 'Combustible'),
                        items: [0, 25, 50, 75, 100]
                            .map((v) =>
                                DropdownMenuItem(value: v, child: Text('$v%')))
                            .toList(),
                        onChanged: (value) => update(() => fuel = value)),
                    const SizedBox(height: 10),
                    TextField(
                        controller: damage,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(labelText: 'Daños visibles')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: accessories,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Accesorios entregados')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: observations,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Observaciones del cliente')),
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: accepted,
                        title: const Text('Cliente conforme con el registro'),
                        onChanged: (v) => update(() => accepted = v ?? false)),
                    TextField(
                        controller: acceptedBy,
                        decoration: const InputDecoration(
                            labelText: 'Nombre de quien acepta')),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, {
                              'fuel_level_percent': fuel,
                              'visible_damage': damage.text.trim(),
                              'accessories': accessories.text.trim(),
                              'customer_observations': observations.text.trim(),
                              'terms_accepted': accepted,
                              'accepted_by_name': acceptedBy.text.trim(),
                            }),
                        child: const Text('Guardar recepción')),
                  ],
                )),
      );
      if (data == null) return;
      await widget.api
          .putJson('/api/v1/work-orders/${widget.order['id']}/reception', data);
      if (orderId != null) await WorkOrderDraftStore.clearReception(orderId);
      if (!mounted) return;
      setState(() => _report = _loadReport());
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Recepción actualizada')));
    } catch (error) {
      if (orderId != null) {
        try {
          final draft = <String, dynamic>{
            'fuel_level_percent': fuel,
            'visible_damage': damage.text.trim(),
            'accessories': accessories.text.trim(),
            'customer_observations': observations.text.trim(),
            'terms_accepted': accepted,
            'accepted_by_name': acceptedBy.text.trim(),
          };
          await WorkOrderDraftStore.saveReception(orderId, draft);
        } catch (_) {
          // Conserva el error de API aunque el dispositivo no pueda guardar el borrador.
        }
      }
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      damage.dispose();
      accessories.dispose();
      observations.dispose();
      acceptedBy.dispose();
    }
  }

  Future<void> _attachEvidence() async {
    final source = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Tomar fotografía'),
                  onTap: () => Navigator.pop(context, 'camera')),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Elegir fotografía'),
                  onTap: () => Navigator.pop(context, 'gallery')),
              ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('Adjuntar archivo o PDF'),
                  onTap: () => Navigator.pop(context, 'file')),
            ])));
    if (source == null) return;
    try {
      List<int>? bytes;
      String? name;
      if (source == 'file') {
        final picked = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
            withData: true);
        if (picked == null) return;
        bytes = picked.files.single.bytes;
        name = picked.files.single.name;
      } else {
        final picked = await ImagePicker().pickImage(
            source:
                source == 'camera' ? ImageSource.camera : ImageSource.gallery,
            imageQuality: 85);
        if (picked == null) return;
        bytes = await picked.readAsBytes();
        name = picked.name;
      }
      if (bytes == null) throw Exception('No fue posible leer el archivo');
      await widget.api.uploadBytes(
          '/api/v1/work-orders/${widget.order['id']}/evidence', bytes, name);
      if (!mounted) return;
      setState(() {
        _evidence =
            _loadList('/api/v1/work-orders/${widget.order['id']}/evidence');
        _report = _loadReport();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Evidencia adjuntada')));
    } catch (error) {
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _assignTechnician() async {
    try {
      final raw = await widget.api.get('/api/v1/team/mechanics');
      final mechanics = raw is List
          ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      if (mechanics.isEmpty)
        throw Exception('No hay mecánicos activos para asignar');
      int? selected;
      for (final mechanic in mechanics) {
        if ('${mechanic['full_name']}' ==
            '${widget.order['technician_name'] ?? ''}')
          selected = mechanic['id'] as int?;
      }
      final decision = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Asignar mecánico'),
                content: StatefulBuilder(
                    builder: (context, update) => DropdownButtonFormField<int?>(
                          initialValue: selected,
                          decoration:
                              const InputDecoration(labelText: 'Responsable'),
                          items: [
                            const DropdownMenuItem<int?>(
                                value: null, child: Text('Sin asignar')),
                            ...mechanics.map((item) => DropdownMenuItem<int?>(
                                value: item['id'] as int,
                                child: Text('${item['full_name']}')))
                          ],
                          onChanged: (value) => update(() => selected = value),
                        )),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(
                          context, {'technician_user_id': selected}),
                      child: const Text('Guardar'))
                ],
              ));
      if (decision == null) return;
      final updated = await widget.api.putJson(
          '/api/v1/work-orders/${widget.order['id']}/assignment', decision);
      if (updated is Map)
        widget.order.addAll(Map<String, dynamic>.from(updated));
      await widget.onChanged();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _createQuote() async {
    final form = GlobalKey<FormState>();
    final description = TextEditingController();
    final labor = TextEditingController(text: '0');
    final parts = TextEditingController(text: '0');
    final notes = TextEditingController();
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Preparar cotización'),
          content: Form(
              key: form,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                    controller: description,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Trabajo propuesto *'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Describe el trabajo'
                        : null),
                const SizedBox(height: 10),
                TextFormField(
                    controller: labor,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Mano de obra (CLP)', prefixText: '\$'),
                    validator: _nonNegativeInteger),
                const SizedBox(height: 10),
                TextFormField(
                    controller: parts,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Repuestos (CLP)', prefixText: '\$'),
                    validator: _nonNegativeInteger),
                const SizedBox(height: 10),
                TextFormField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Observaciones / alcance')),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  if (!form.currentState!.validate()) return;
                  Navigator.pop(context, {
                    'description': description.text.trim(),
                    'labor_clp': int.parse(labor.text.trim()),
                    'parts_clp': int.parse(parts.text.trim()),
                    if (notes.text.trim().isNotEmpty)
                      'notes': notes.text.trim(),
                  });
                },
                child: const Text('Guardar borrador')),
          ],
        ),
      );
      if (data == null) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      await widget.api
          .postJson('/api/v1/work-orders/${widget.order['id']}/quotes', data);
      if (!mounted) return;
      setState(() => _quotes = _loadQuotes());
      await widget.onChanged();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cotización guardada como borrador')));
    } catch (error) {
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      description.dispose();
      labor.dispose();
      parts.dispose();
      notes.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nonNegativeInteger(String? value) {
    final amount = int.tryParse((value ?? '').trim());
    return amount == null || amount < 0
        ? 'Ingresa un monto válido en CLP'
        : null;
  }

  Future<void> _publishQuote(Map<String, dynamic> quote) async {
    final total = (_asInt(quote['labor_clp']) + _asInt(quote['parts_clp']));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publicar cotización'),
        content: Text(
            'Se enviará al portal del cliente la propuesta “${quote['description']}” por ${_currency(total)}. Confirma que el alcance y los valores estén revisados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir revisando')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publicar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.post('/api/v1/quotes/${quote['id']}/publish');
      if (!mounted) return;
      setState(() => _quotes = _loadQuotes());
      await widget.onChanged();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cotización publicada para el cliente')));
    } catch (error) {
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _asInt(dynamic value) =>
      value is num ? value.round() : int.tryParse('$value') ?? 0;
  String _currency(int amount) => '\$${amount.toString()} CLP';

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: ListView(shrinkWrap: true, children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 18),
          Text('${widget.order['code'] ?? 'Orden de trabajo'}',
              style: Theme.of(context).textTheme.headlineSmall),
          if (widget.role == 'admin') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _saving ? null : _assignTechnician,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(widget.order['technician_name'] == null
                    ? 'Asignar mecánico'
                    : 'Responsable: ${widget.order['technician_name']}')),
          ],
          const SizedBox(height: 8),
          Text(
              'Síntomas informados: ${widget.order['reported_symptoms'] ?? 'Sin síntomas registrados'}'),
          if (widget.order['initial_notes'] != null) ...[
            const SizedBox(height: 4),
            Text('Recepción: ${widget.order['initial_notes']}'),
          ],
          const SizedBox(height: 14),
          FutureBuilder<Map<String, dynamic>>(
            future: _workSessions,
            builder: (context, snapshot) {
              final data = snapshot.data ?? <String, dynamic>{};
              final sessions = data['sessions'] is List
                  ? (data['sessions'] as List)
                      .whereType<Map>()
                      .map((item) => Map<String, dynamic>.from(item))
                      .toList()
                  : <Map<String, dynamic>>[];
              final activeRows =
                  sessions.where((item) => item['ended_at'] == null).toList();
              final active = activeRows.isEmpty ? null : activeRows.first;
              final seconds = data['total_seconds'] is num
                  ? (data['total_seconds'] as num).toInt()
                  : 0;
              final time =
                  '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}';
              return Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Icon(Icons.timer_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Tiempo de trabajo'),
                              Text('$time acumulado',
                                  style: Theme.of(context).textTheme.bodySmall)
                            ])),
                        if (active == null)
                          FilledButton.icon(
                              onPressed:
                                  _saving ? null : () => _workTimer('start'),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Iniciar'))
                        else ...[
                          IconButton(
                              onPressed: () => _workTimer(
                                  active['paused_at'] == null
                                      ? 'pause'
                                      : 'resume',
                                  active['id'] as int?),
                              icon: Icon(active['paused_at'] == null
                                  ? Icons.pause_outlined
                                  : Icons.play_arrow),
                              tooltip: active['paused_at'] == null
                                  ? 'Pausar'
                                  : 'Reanudar'),
                          IconButton(
                              onPressed: () =>
                                  _workTimer('stop', active['id'] as int?),
                              icon: const Icon(Icons.stop_outlined),
                              tooltip: 'Finalizar registro'),
                        ],
                      ])));
            },
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            key: ValueKey('work-order-status-$_status-${widget.role}'),
            initialValue: _availableStatuses.contains(_status)
                ? _status
                : _availableStatuses.first,
            decoration: const InputDecoration(labelText: 'Estado del trabajo'),
            items: _availableStatuses
                .map((value) => DropdownMenuItem(
                    value: value, child: Text(spanishStatus(value))))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          if (widget.role == 'mechanic')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                  'Puedes avanzar la orden asignada; las etapas comerciales las gestiona administración.'),
            ),
          const SizedBox(height: 12),
          TextField(
              controller: _diagnosis,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Diagnóstico / pruebas pendientes',
                  alignLabelWithHint: true)),
          const SizedBox(height: 12),
          if (_restoringDraft) const LinearProgressIndicator(),
          if (_restoringDraft) const SizedBox(height: 12),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FilledButton.icon(
              onPressed: _saving ? null : _saveOrder,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Guardando…' : 'Guardar cambios')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: _saving ? null : _saveLocalDraft,
              icon: const Icon(Icons.save_as_outlined),
              label: const Text('Guardar borrador local')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: _saving ? null : _editReception,
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('Completar recepción')),
          const Divider(height: 28),
          Row(children: [
            Expanded(
                child: Text('Inspecciones',
                    style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
                onPressed: _saving ? null : _applyTemplate,
                icon: const Icon(Icons.playlist_add_check),
                tooltip: 'Aplicar plantilla'),
            IconButton(
                onPressed: _saving ? null : _addInspection,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Agregar inspección'),
          ]),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _inspections,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()));
              if (snapshot.hasError)
                return Text(
                    'No se pudieron cargar las inspecciones: ${snapshot.error}');
              final records = snapshot.data ?? [];
              if (records.isEmpty)
                return const Text(
                    'Todavía no hay puntos de inspección registrados.');
              return Column(
                  children: records
                      .map((inspection) => Card(
                              child: ListTile(
                            leading: Icon(inspection['result'] == 'normal'
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_outlined),
                            title: Text(
                                '${inspection['category']}: ${inspection['item']}'),
                            subtitle: Text(
                                '${inspection['result']}${inspection['measured_value'] == null ? '' : ' · ${inspection['measured_value']}'}${inspection['notes'] == null ? '' : '\n${inspection['notes']}'}'),
                            isThreeLine: inspection['notes'] != null,
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => _editInspection(inspection),
                          )))
                      .toList());
            },
          ),
          const Divider(height: 28),
          Row(children: [
            Expanded(
                child: Text('Evidencias',
                    style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
                onPressed: _saving ? null : _attachEvidence,
                icon: const Icon(Icons.attach_file),
                tooltip: 'Adjuntar foto o archivo'),
          ]),
          FutureBuilder<List<Map<String, dynamic>>>(
              future: _evidence,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const LinearProgressIndicator();
                final records = snapshot.data ?? [];
                if (records.isEmpty)
                  return const Text('No hay fotografías o archivos adjuntos.');
                return Column(
                    children: records
                        .map((item) => ListTile(
                              leading: Icon(
                                  '${item['content_type']}'.startsWith('image/')
                                      ? Icons.image_outlined
                                      : Icons.picture_as_pdf_outlined),
                              title: Text('${item['filename']}'),
                              subtitle: Text(
                                  '${item['caption'] ?? 'Evidencia de la orden'}'),
                            ))
                        .toList());
              }),
          const Divider(height: 28),
          Row(children: [
            Expanded(
                child: Text('Resumen para el cliente',
                    style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
                tooltip: 'Imprimir / guardar informe PDF',
                onPressed: _printInspectionReport,
                icon: const Icon(Icons.picture_as_pdf_outlined)),
          ]),
          FutureBuilder<Map<String, dynamic>>(
              future: _report,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const LinearProgressIndicator();
                if (snapshot.hasError)
                  return Text(
                      'No se pudo generar el resumen: ${snapshot.error}');
                final summary = snapshot.data?['summary'] is Map
                    ? Map<String, dynamic>.from(
                        snapshot.data!['summary'] as Map)
                    : <String, dynamic>{};
                final scanners = snapshot.data?['scanner_reports'] is List
                    ? snapshot.data!['scanner_reports'] as List
                    : const [];
                return Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'Normales: ${summary['normal'] ?? 0} · Observaciones: ${summary['observation'] ?? 0} · Fallas: ${summary['failed'] ?? 0}\n'
                          'Pendientes: ${summary['not_inspected'] ?? 0} · Informes LAUNCH: ${scanners.length}',
                        )));
              }),
          const Divider(height: 28),
          Row(children: [
            Expanded(
                child: Text('Cotizaciones',
                    style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
                onPressed: _saving ? null : _createQuote,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Preparar cotización'),
          ]),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _quotes,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()));
              if (snapshot.hasError)
                return Text(
                    'No se pudieron cargar las cotizaciones: ${snapshot.error}');
              final records = snapshot.data ?? [];
              if (records.isEmpty)
                return const Text(
                    'Todavía no hay cotizaciones para esta orden.');
              return Column(
                  children: records.map((quote) {
                final amount =
                    _asInt(quote['labor_clp']) + _asInt(quote['parts_clp']);
                final isDraft = quote['status'] == 'draft';
                return Card(
                    child: ListTile(
                  leading: Icon(
                      isDraft ? Icons.edit_note : Icons.request_quote_outlined),
                  title: Text('${quote['description']}'),
                  subtitle: Text(
                      '${_currency(amount)} · ${spanishStatus(quote['status'] ?? 'draft')}${quote['notes'] == null ? '' : '\n${quote['notes']}'}'),
                  isThreeLine: quote['notes'] != null,
                  trailing: isDraft
                      ? IconButton(
                          onPressed:
                              _saving ? null : () => _publishQuote(quote),
                          icon: const Icon(Icons.send_outlined),
                          tooltip: 'Publicar para cliente')
                      : null,
                ));
              }).toList());
            },
          ),
        ]),
      );
}
