import 'dart:convert';
import 'package:flutter/services.dart';

abstract class DecisionRuntime {
  Future<Map<String, dynamic>> prepareImage(
    String input,
    String output, {
    int maxPixelSize = 2048,
  });
  Future<Map<String, dynamic>> load(Map<String, dynamic> request);
  Future<Map<String, dynamic>> run(Map<String, dynamic> request);
  Future<void> cancel();
  Future<void> unload();
}

class MethodChannelDecisionRuntime implements DecisionRuntime {
  @override
  Future<Map<String, dynamic>> prepareImage(
    String input,
    String output, {
    int maxPixelSize = 2048,
  }) => _call('prepareImage', {
    'input': input,
    'output': output,
    'maxPixelSize': maxPixelSize,
  });
  static const _channel = MethodChannel('d1_lab/runtime');
  Future<Map<String, dynamic>> _call(
    String method,
    Map<String, dynamic> request,
  ) async {
    final text = await _channel.invokeMethod<String>(
      method,
      jsonEncode(request),
    );
    final result = Map<String, dynamic>.from(jsonDecode(text!) as Map);
    if (result['error'] != null) throw StateError(result['error'] as String);
    return result;
  }

  @override
  Future<Map<String, dynamic>> load(Map<String, dynamic> request) =>
      _call('load', request);
  @override
  Future<Map<String, dynamic>> run(Map<String, dynamic> request) =>
      _call('run', request);
  @override
  Future<void> cancel() => _channel.invokeMethod('cancel');
  @override
  Future<void> unload() => _channel.invokeMethod('unload');
}
