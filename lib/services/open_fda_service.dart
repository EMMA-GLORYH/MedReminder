// lib/services/open_fda_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenFDAService {
  OpenFDAService._();
  static final OpenFDAService instance = OpenFDAService._();

  static const String _baseUrl = 'https://api.fda.gov/drug/label.json';

  Future<List<FdaDrugResult>> searchByName(String query) async {
    if (query.trim().length < 2) return [];

    final encoded = Uri.encodeComponent(query.trim());
    final url = '$_baseUrl?search='
        'openfda.brand_name:"$encoded"+OR+'
        'openfda.generic_name:"$encoded"&limit=8';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List<dynamic>? ?? [];
        return results.map((json) => FdaDrugResult.fromJson(json)).toList();
      } else if (response.statusCode == 404) {
        return [];
      }
      throw Exception('FDA API error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Failed to connect to FDA database: $e');
    }
  }
}

class FdaDrugResult {
  final String? brandName;
  final String? genericName;
  final String? manufacturer;
  final List<String>? indications;
  final List<String>? warnings;
  final List<String>? adverseReactions;
  final String? dosageAndAdministration;
  final String? setId;

  FdaDrugResult({
    this.brandName,
    this.genericName,
    this.manufacturer,
    this.indications,
    this.warnings,
    this.adverseReactions,
    this.dosageAndAdministration,
    this.setId,
  });

  factory FdaDrugResult.fromJson(Map<String, dynamic> json) {
    final openfda = json['openfda'] as Map<String, dynamic>? ?? {};

    return FdaDrugResult(
      brandName: (openfda['brand_name'] as List?)?.first as String?,
      genericName: (openfda['generic_name'] as List?)?.first as String?,
      manufacturer: (openfda['manufacturer_name'] as List?)?.first as String?,
      indications: _toStringList(json['indications_and_usage']),
      warnings: _toStringList(json['warnings']),
      adverseReactions: _toStringList(json['adverse_reactions']),
      dosageAndAdministration: json['dosage_and_administration']?.toString(),
      setId: openfda['set_id']?.first as String?,
    );
  }

  static List<String>? _toStringList(dynamic value) {
    if (value is List) return value.cast<String>();
    if (value is String) return [value];
    return null;
  }

  String get formattedClinicalInfo {
    final buffer = StringBuffer();

    if (manufacturer != null) {
      buffer.writeln('Manufacturer: $manufacturer\n');
    }
    if (indications != null && indications!.isNotEmpty) {
      buffer.writeln('Indications:\n${indications!.join('\n• ')}\n');
    }
    if (warnings != null && warnings!.isNotEmpty) {
      buffer.writeln('⚠️ Warnings:\n${warnings!.join('\n• ')}\n');
    }

    return buffer.toString().trim();
  }
}