import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

abstract class Model {
  const Model();

  Map<String, dynamic> toJson();

  @override
  String toString() {
    return toJson().toString();
  }

  String? stringFromJson(Map map, String key, {String? defaultVal}) {
    if (isNotNull(map[key])) {
      return map[key].toString().trim();
    }
    return defaultVal;
  }

  Color? colorFromJson(Map map, String key, {Color? defaultVal}) {
    if (isNotNull(map[key])) {
      String colorCode = map[key].toString();
      var hexColor = colorCode.replaceAll("#", "");
      if (hexColor.length == 6) {
        hexColor = "FF$hexColor";
      }
      if (hexColor.length == 8) {
        return Color(int.parse("0x$hexColor"));
      }
    }
    return defaultVal;
  }

  int? intFromJson(Map map, String key, {int? defaultVal}) {
    if (isNotNull(map[key])) {
      return num.tryParse(map[key].toString())?.toInt() ?? defaultVal;
    }
    return defaultVal;
  }

  bool? boolFromJson(Map map, String key, {bool? defaultVal}) {
    if (isNotNull(map[key]) && map[key] is bool) {
      return map[key];
    }
    return defaultVal;
  }

  double? doubleFromJson(Map map, String key, {double? defaultVal}) {
    if (isNotNull(map[key])) {
      return num.tryParse(map[key].toString())?.toDouble() ?? defaultVal;
    }
    return defaultVal;
  }

  num? numFromJson(Map map, String key, {num? defaultVal}) {
    if (isNotNull(map[key])) {
      if (map[key] is String) {
        return num.tryParse(map[key].toString()) ?? defaultVal;
      }
      if (map[key] is num) {
        return map[key];
      }
    }
    return defaultVal;
  }

  DateTime? dateFromJson(Map map, String key, {DateTime? defaultVal}) {
    if (isNotNull(map[key])) {
      if (map[key] is String) {
        return DateTime.tryParse(map[key])?.toLocal() ?? defaultVal;
      } else if (map[key] is Timestamp) {
        Timestamp timestamp = map[key];
        return DateTime.fromMillisecondsSinceEpoch(
          timestamp.millisecondsSinceEpoch,
        ).toLocal();
      } else if (map[key] is num) {
        num number = map[key];
        return DateTime.fromMillisecondsSinceEpoch(number.toInt()).toLocal();
      }
    }
    return defaultVal;
  }

  TimeOfDay? timeFromJson(Map map, String key, {TimeOfDay? defaultVal}) {
    var val = map[key];
    if (isNotNull(val)) {
      if (val is String) {
        final parts = val.split(':');
        if (parts.length == 2) {
          final hours = int.tryParse(parts[0]) ?? 0;
          final minutes = int.tryParse(parts[1]) ?? 0;
          return TimeOfDay(hour: hours, minute: minutes);
        }
      } else if (val is Timestamp) {
        Timestamp timestamp = val;
        var date = DateTime.fromMillisecondsSinceEpoch(
          timestamp.millisecondsSinceEpoch,
        ).toLocal();
        return TimeOfDay.fromDateTime(date);
      } else if (val is num) {
        var date = DateTime.fromMillisecondsSinceEpoch(val.toInt()).toLocal();
        return TimeOfDay.fromDateTime(date);
      }
    }
    return defaultVal;
  }

  List listFromJson(Map map, String key) {
    if (isNotNull(map[key]) && map[key] is List) {
      return List.from(map[key]);
    }
    return [];
  }

  List<TextEditingController> listFromArtistName(Map map, String key) {
    if (isNotNull(map[key]) && map[key] is List) {
      return List.from(map[key]);
    }
    return [];
  }

  bool isNotNull(Object? val) {
    return val != null && val != 'null' && val != 'Null';
  }
}

extension HexColor on Color {
  /// String is in the format "aabbcc" or "ffaabbcc" with an optional leading "#".
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  /// Prefixes a hash sign if [leadingHashSign] is set to `true` (default is `true`).
  String toHex({bool leadingHashSign = true}) {
    // Preserve ARGB output using the current non-deprecated color API.
    final hex = toARGB32().toRadixString(16).padLeft(8, '0');
    return '${leadingHashSign ? '#' : ''}$hex';
  }
}
