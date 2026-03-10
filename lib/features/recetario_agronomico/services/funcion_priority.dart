const int funcionPriorityHigh = 0;
const int funcionPriorityNormal = 10;

const Set<String> _priorityHighFunctions = <String>{
  'corrector_ph',
  'secuestrante_dureza',
  'acondicionador_agua',
};

const Set<String> _allowedFunctions = <String>{
  'ninguna',
  'corrector_ph',
  'secuestrante_dureza',
  'antideriva',
  'antiespumante',
  'adherente',
  'humectante',
  'penetrante',
  'acondicionador_agua',
  'otro',
};

String normalizeFuncionKey(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (_allowedFunctions.contains(normalized)) {
    return normalized;
  }
  return 'ninguna';
}

int funcionPriority(String? value) {
  final normalized = normalizeFuncionKey(value);
  if (_priorityHighFunctions.contains(normalized)) {
    return funcionPriorityHigh;
  }
  return funcionPriorityNormal;
}
