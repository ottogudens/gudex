import 'package:flutter/material.dart';

String formatClp(int amount) {
  final digits = amount.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );
  return '${amount < 0 ? '-' : ''}\$$digits CLP';
}

/// Brand colours used throughout the Gudex application.
abstract final class GudexColors {
  static const ink = Color(0xFF242424);
  static const primary = Color(0xFFED0606);
  static const secondary = Color(0xFFFFE600);
  static const canvas = Color(0xFFF7F7F7);
  static const line = Color(0xFFE3E3E3);
  static const success = Color(0xFF237A57);
}

/// Translated status labels used to display work‑order /
/// payment / appointment statuses in Spanish.
const statusLabels = <String, String>{
  'received': 'Recibida', 'inspecting': 'En inspección', 'quoted': 'Cotizada',
  'awaiting_approval': 'Esperando autorización', 'quote_rejected': 'Cotización rechazada',
  'approved': 'Aprobada', 'in_progress': 'En proceso', 'ready': 'Lista',
  'delivered': 'Entregada', 'cancelled': 'Cancelada', 'draft': 'Borrador',
  'sent': 'Enviada', 'rejected': 'Rechazada', 'paid': 'Pagada', 'open': 'Abierta',
  'requested': 'Solicitada', 'confirmed': 'Confirmada', 'completed': 'Completada',
  'pending': 'Pendiente', 'pending_external': 'Pago externo pendiente',
  'refunded': 'Reembolsada', 'charged_back': 'Contracargo', 'needs_refund': 'Requiere devolución',
  'recorded': 'Registrado', 'normal': 'Normal', 'observation': 'Observación',
  'failed': 'Falla', 'not_inspected': 'No inspeccionado', 'not_applicable': 'No aplica',
  'active': 'Activo', 'inactive': 'Inactivo', 'cash': 'Efectivo',
  'card': 'Tarjeta', 'mercado_pago': 'Mercado Pago',
};

/// Translated field labels for form / detail views.
const fieldLabels = <String, String>{
  'service_type': 'Tipo de servicio', 'starts_at': 'Inicio', 'ends_at': 'Fin',
  'created_at': 'Creado', 'updated_at': 'Actualizado', 'stock_quantity': 'Stock',
  'price_clp': 'Precio', 'cost_clp': 'Costo', 'payment_method': 'Medio de pago',
  'full_name': 'Nombre', 'phone': 'Teléfono', 'email': 'Correo', 'plate': 'Patente',
  'make': 'Marca', 'model': 'Modelo', 'year': 'Año', 'current_mileage_km': 'Kilometraje',
  'reported_symptoms': 'Síntomas informados', 'diagnosis': 'Diagnóstico', 'notes': 'Notas',
  'technician_name': 'Técnico', 'status': 'Estado', 'role': 'Perfil',
};

/// Convenience: returns the Spanish translation of a status string.
String spanishStatus(dynamic value) {
  final status = value?.toString() ?? '';
  return statusLabels[status] ?? status.replaceAll('_', ' ');
}

/// Convenience: returns the Spanish translation of a field key.
String spanishField(String key) => fieldLabels[key] ?? key.replaceAll('_', ' ');

/// Returns a user‑facing Spanish label for a role identifier.
String spanishRole(dynamic value) {
  switch (value?.toString()) {
    case 'admin': return 'Administración';
    case 'mechanic': return 'Mecánico';
    case 'customer': return 'Cliente';
    default: return value?.toString() ?? '';
  }
}

/// Default API URL, overridable via `--dart-define=API_URL=…`
const apiBaseUrl = String.fromEnvironment('API_URL', defaultValue: String.fromEnvironment('API_BASE_URL', defaultValue: 'https://bknd.gudex.cl'));
