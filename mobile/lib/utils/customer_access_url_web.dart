import 'dart:html' as html;

/// Remove the one-time token from the address bar without reloading Flutter.
void clearCustomerAccessUrl() {
  final current = Uri.base;
  final query = Map<String, String>.from(current.queryParameters)
    ..remove('invite')
    ..remove('reset');
  final clean = current.replace(
    query: query.isEmpty ? '' : null,
    queryParameters: query.isEmpty ? null : query,
  );
  html.window.history.replaceState(null, '', clean.toString());
}
