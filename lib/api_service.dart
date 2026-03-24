import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class TrainApiService {
  static const String _baseUrl = "http://express.heartrails.com/api/json";

  // 最寄り駅を取得
  static Future<Map<String, dynamic>?> getNearestStation(double lat, double lng) async {
    final Uri url = Uri.parse("$_baseUrl?method=getStations&x=$lng&y=$lat");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['response'] != null && data['response']['station'] != null) {
          return data['response']['station'][0];
        }
      }
    } catch (e) {
      print("API Error: $e");
    }
    return null;
  }

  // 指定エリア内の路線リストを取得（座標指定）
  static Future<List<String>> getLinesInArea(LatLng center) async {
    final Uri url = Uri.parse("$_baseUrl?method=getStations&x=${center.longitude}&y=${center.latitude}");
    Set<String> lines = {};
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['response'] != null && data['response']['station'] != null) {
          for (var s in data['response']['station']) {
            lines.add(s['line']);
          }
        }
      }
    } catch (e) {
      print("API Error: $e");
    }
    return lines.toList();
  }

  // ★追加: 地域名（エリア）から路線リストを取得
  static Future<List<String>> getLinesByRegion(String areaName) async {
    // HeartRails APIでは area パラメータで都道府県や地域を指定可能
    final Uri url = Uri.parse("$_baseUrl?method=getLines&area=${Uri.encodeComponent(areaName)}");
    List<String> lines = [];
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['response'] != null && data['response']['line'] != null) {
          lines = List<String>.from(data['response']['line']);
        }
      }
    } catch (e) {
      print("API Error: $e");
    }
    return lines;
  }
  
  // 指定路線の駅一覧を取得
  static Future<List<Map<String, dynamic>>> getStationsByLine(String lineName) async {
    final Uri url = Uri.parse("$_baseUrl?method=getStations&line=${Uri.encodeComponent(lineName)}");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['response'] != null && data['response']['station'] != null) {
          return List<Map<String, dynamic>>.from(data['response']['station']);
        }
      }
    } catch (e) {
      print("API Error: $e");
    }
    return [];
  }
}