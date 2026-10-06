/// Barrel file that re-exports the public API of the app.
///
/// Screens can import this single file to access shared constants,
/// helpers, services and providers.
library;

export 'services/api_client.dart';
export 'core/constants.dart';
export 'core/theme.dart';
export 'providers/auth_provider.dart';
