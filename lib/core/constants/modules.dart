abstract final class AppModules {
  static const String recetarioAgronomico = 'recetario_agronomico';

  static const List<String> availableModules = [recetarioAgronomico];

  static const Map<String, String> labels = {
    recetarioAgronomico: 'Recetario Agronomico',
  };

  static String labelOf(String moduleKey) {
    return labels[moduleKey] ?? moduleKey;
  }
}
