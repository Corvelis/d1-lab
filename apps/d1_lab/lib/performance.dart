/// Never derive prefill speed from total latency: it includes loading/media work.
double? metric(Map<String, dynamic> data, String key) {
  final value = data[key];
  return value is num && value.isFinite && value >= 0 ? value.toDouble() : null;
}

String metricNumber(double? value, {int decimals = 1}) =>
    value == null ? '—' : value.toStringAsFixed(decimals);

double? timingOverhead(Map<String, dynamic> data) {
  final total = metric(data, 'endToEndMs');
  final phases = [
    'verifyMs',
    'loadCallMs',
    'inputPrepareMs',
    'mediaEncodeMs',
    'forwardMs',
    'postprocessMs',
    'unloadMs',
  ].map((key) => metric(data, key)).toList();
  if (total == null || phases.any((v) => v == null)) return null;
  return (total - phases.fold<double>(0, (sum, v) => sum + v!)).clamp(
    0.0,
    total,
  );
}

({String value, String unit}) durationMetric(double? ms) => ms == null
    ? (value: '—', unit: 'ms')
    : ms >= 1000
    ? (value: (ms / 1000).toStringAsFixed(2), unit: 's')
    : (value: ms.toStringAsFixed(1), unit: 'ms');
