import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/secrets.dart';

Future<Secrets> loadSecrets() async {
  final String response = await rootBundle.loadString('assets/secrets.json');
  final data = json.decode(response);
  return Secrets.fromJson(data);
}
