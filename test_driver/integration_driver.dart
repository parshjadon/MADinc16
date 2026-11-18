import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('evidence/raw/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
  responseDataCallback: (data) async {
    final file = File('private/integration_result.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
