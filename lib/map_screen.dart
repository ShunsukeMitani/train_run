import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'api_service.dart';

class MapScreen extends StatefulWidget {
  final String myRole;
  final String myName;
  // 'NORMAL', 'SELECT_AREA', 'PLACE_BOX', 'SELECT_LOCATION'
  final String initialMode;

  const MapScreen({
    super.key,
    required this.myRole,
    required this.myName,
    this.initialMode = 'NORMAL',
  });

  bool get isSelectionMode => initialMode != 'NORMAL';

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng _myLocation = const LatLng(35.681236, 139.767125);
  bool _isFirstLocationUpdate = true;
  double _currentHeading = 0.0;
  Timer? _positionTimer;
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  bool _isSurrenderPossible = false;
  bool _isOutOfArea = false;
  bool _isConnected = true;
  bool? _prevOutOfAreaState;

  // ★追加: サイバーモード（地図タイル非表示）フラグ
  bool _isCyberMode = false;

  late String _editMode;
  List<LatLng> _tempAreaPoints = [];
  List<Marker> _tempBoxMarkers = [];
  LatLng? _selectedSinglePoint;

  List<dynamic> _cachedSurrenderPoints = [];
  List<dynamic> _cachedCurrentAreaPoints = [];
  bool _cachedAllowSurrender = true;

  // 路線描画用
  List<Polyline> _linePolylines = [];
  List<Marker> _stationMarkers = [];
  bool _linesLoaded = false;
  
  // 駅座標キャッシュ
  Map<String, LatLng> _stationPositions = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialMode == 'SELECT_AREA') {
      _editMode = 'AREA';
    } else if (widget.initialMode == 'PLACE_BOX') {
      _editMode = 'BOX';
    } else if (widget.initialMode == 'SELECT_LOCATION') {
      _editMode = 'LOCATION';
    } else {
      _editMode = 'NONE';
    }

    _startTracking();
    _fetchLineData();
    
    FirebaseFirestore.instance
        .collection('.info')
        .doc('connected')
        .snapshots()
        .listen((_) => setState(() => _isConnected = true), onError: (_) => setState(() => _isConnected = false));
  }

  // ★全路線対応カラー定義
  Color _getLineColor(String name) {
    const Map<String, Color> colorMap = {
      // --- 新幹線 ---
      '東海道新幹線': Color(0xFF003366), '山陽新幹線': Color(0xFF003366), '九州新幹線': Color(0xFFFF0000),
      '西九州新幹線': Color(0xFFFF0000), '東北新幹線': Color(0xFF008000), '北海道新幹線': Color(0xFF9ACD32),
      '上越新幹線': Color(0xFFF15A22), '北陸新幹線': Color(0xFF800080), '秋田新幹線': Color(0xFFFF1493),
      '山形新幹線': Color(0xFFFF8C00), 
      // --- JR北海道 ---
      '千歳線': Color(0xFF036FC2), '室蘭': Color(0xFF036FC2), '石北': Color(0xFFF17714), 
      '宗谷': Color(0xFF983A4A), '石勝': Color(0xFF31C04C), '根室': Color(0xFF31C04C),
      '学園都市': Color(0xFF0C9436), '富良野': Color(0xFF9830CF), '釧網': Color(0xFFE0429B), 
      '函館本線': Color(0xFF036FC2),
      // --- JR東日本 ---
      '山手': Color(0xFF85C023), '京浜東北': Color(0xFF00A7E3), '根岸': Color(0xFF00A7E3),
      '中央線': Color(0xFFEB5C01), '中央本線': Color(0xFF0071C5), '中央・総武': Color(0xFFFFE500),
      '総武線': Color(0xFFFFE500), '総武本線': Color(0xFF00008B), '総武快速': Color(0xFF00008B),
      '横須賀': Color(0xFF00008B), '湘南新宿': Color(0xFFFF0000), '上野東京': Color(0xFF800080),
      '埼京': Color(0xFF00AC9A), '京葉': Color(0xFFCF1225), '武蔵野': Color(0xFFEB5C01),
      '横浜': Color(0xFF85C023), '南武': Color(0xFFFFE400), '鶴見': Color(0xFFFFE500),
      '相模': Color(0xFF00BFFF), '常磐': Color(0xFF00B261), '高崎': Color(0xFFF68B1E),
      '宇都宮': Color(0xFFF68B1E), '東海道': Color(0xFFF68B1E), '伊東': Color(0xFF378640),
      '青梅': Color(0xFFFF4500), '五日市': Color(0xFFFF4500), '川越': Color(0xFFA6A9AB),
      // --- JR東海 ---
      '御殿場': Color(0xFF3D733D), '身延': Color(0xFF6B3174), '飯田': Color(0xFF719CDF),
      '武豊': Color(0xFF76432C), '高山': Color(0xFFA61E2B), '太多': Color(0xFFB1A548),
      // --- JR西日本 ---
      '大阪環状': Color(0xFFF8405C), 'ゆめ咲': Color(0xFF003C88), '大和路': Color(0xFF00B17B),
      '阪和': Color(0xFFFF8E1F), '関西空港': Color(0xFF0072BA), 'ＪＲ神戸': Color(0xFF0072BA),
      'ＪＲ京都': Color(0xFF0072BA), '琵琶湖': Color(0xFF0072BA), '湖西': Color(0xFF00ACD1),
      'ＪＲ宝塚': Color(0xFFFFBA00), '福知山': Color(0xFFFFBA00), 'ＪＲ東西': Color(0xFFE25C83),
      '学研都市': Color(0xFFE25C83), 'おおさか東': Color(0xFF467088), '嵯峨野': Color(0xFF878DDC),
      '山陰': Color(0xFF878DDC), '奈良': Color(0xFF00B261), '和歌山': Color(0xFFF79FBA),
      'きのくに': Color(0xFF00A6B4), '万葉まほろば': Color(0xFFB31C31), '北陸': Color(0xFF0072BA),
      '山陽本線': Color(0xFF0072BA), '赤穂': Color(0xFFFFD700), '瀬戸大橋': Color(0xFF0072BA),
      '伯備': Color(0xFF008000), '津山': Color(0xFFFFBA00), '桃太郎': Color(0xFFF79FBA),
      '福塩': Color(0xFF5726B7), '宇野': Color(0xFF63D2D3), '因美': Color(0xFFAA731C),
      '境線': Color(0xFF005B94), '木次': Color(0xFFFFBA00), '呉線': Color(0xFFDB8E00),
      '可部': Color(0xFF00A6B4), '芸備': Color(0xFF8F76D6), '岩徳': Color(0xFF008F65),
      '山口': Color(0xFFFF7860), '宇部': Color(0xFFA52F5D), '小野田': Color(0xFF776493),
      '美祢': Color(0xFFDC208F), '関西本線': Color(0xFF00B261),
      // --- JR四国 ---
      '予讃': Color(0xFFF5AC13), '内子': Color(0xFFF5AC13), '土讃': Color(0xFFDC4586),
      '牟岐': Color(0xFF2EBDB1), '徳島': Color(0xFF366481), '鳴門': Color(0xFF881F61),
      '予土': Color(0xFF009656), '高徳': Color(0xFF87CA3B),
      // --- JR九州 ---
      '鹿児島': Color(0xFFEE3D49), '日豊': Color(0xFF00BFFF), '長崎': Color(0xFF00BFFF),
      '佐世保': Color(0xFF00B261), '筑肥': Color(0xFFFFD700), '唐津': Color(0xFFFFD700),
      '篠栗': Color(0xFFEAC700), '筑豊': Color(0xFF000000), '久大': Color(0xFF008000),
      '豊肥': Color(0xFFA52A2A), '指宿': Color(0xFFFFD700), '宮崎': Color(0xFF00BFFF),
      '福北ゆたか': Color(0xFFFAAF18), '香椎': Color(0xFF0095D9), '若松': Color(0xFF36B558),
      '原田': Color(0xFF36B558), '日田彦山': Color(0xFFB96F30), '後藤寺': Color(0xFF8F3E97),
      // --- 地下鉄 ---
      '銀座': Color(0xFFFF9500), '丸ノ内': Color(0xFFF62E36), '日比谷': Color(0xFFB5B5AC),
      '東西': Color(0xFF009BBF), '千代田': Color(0xFF00BB85), '有楽町': Color(0xFFC1A470),
      '半蔵門': Color(0xFF8F76D6), '南北': Color(0xFF00AC9B), '副都心': Color(0xFF9C5E31),
      '浅草': Color(0xFFE14131), '三田': Color(0xFF006CB6), '新宿線': Color(0xFFB0C124),
      '大江戸': Color(0xFFC6035D), '御堂筋': Color(0xFFE5171F), '谷町': Color(0xFFAA1B86),
      '四つ橋': Color(0xFF0073BD), '中央': Color(0xFF00A53C), '千日前': Color(0xFFEB74A8),
      '堺筋': Color(0xFF663300), '長堀': Color(0xFFBBD300), '今里筋': Color(0xFFF49F00),
      'ニュートラム': Color(0xFF00A6E2), '東山': Color(0xFFF0B54A), '名城': Color(0xFFA67DB5),
      '名港': Color(0xFFA67DB5), '鶴舞': Color(0xFF00A1E8), '桜通': Color(0xFFD9283A),
      '上飯田': Color(0xFFEE82B0), '烏丸': Color(0xFF009944), '西神': Color(0xFF009A78),
      '山手線': Color(0xFF009A78), '海岸': Color(0xFF0191D7), '空港線': Color(0xFFFB7F09),
      '箱崎': Color(0xFF00A0E9), '七隈': Color(0xFF008B4F), '札幌市営南北': Color(0xFF35A16B),
      '札幌市営東西': Color(0xFFFF9900), '札幌市営東豊': Color(0xFF0041FF), '仙台市営南北': Color(0xFF317C66),
      '仙台市営東西': Color(0xFF00B1DD), 'ブルーライン': Color(0xFF0070C0), 'グリーンライン': Color(0xFF00B050),
      // --- 私鉄 ---
      '東急': Color(0xFFFF0000), '田園都市': Color(0xFF00B261), '目黒': Color(0xFF009CD3),
      '東横': Color(0xFFDA0042), '小田急': Color(0xFF0085CE), '京王': Color(0xFFC60076),
      '井の頭': Color(0xFF004385), '京成': Color(0xFF0166B3), 'スカイアクセス': Color(0xFFF47B21),
      '西武': Color(0xFFEE7A00), '池袋線': Color(0xFFEE7A00), '西武新宿': Color(0xFF00A6BF),
      '多摩湖': Color(0xFFF7AF0E), '国分寺': Color(0xFF1EAD4C), '西武園': Color(0xFF1EAD4C),
      '多摩川': Color(0xFFEF7A00), '東武': Color(0xFF00008B), 'スカイツリー': Color(0xFF226BB8),
      '亀戸': Color(0xFF226BB8), '大師': Color(0xFF226BB8), '伊勢崎': Color(0xFFE72019),
      '東武日光': Color(0xFFF6A202), '鬼怒川': Color(0xFFF6A202), '野田': Color(0xFF41B3E5),
      'アーバンパーク': Color(0xFF41B3E5), '東上': Color(0xFF10428E), '越生': Color(0xFF10428E),
      '京急': Color(0xFF0096E0), '相鉄': Color(0xFF0073BC), 'つくば': Color(0xFFFF0000),
      'ゆりかもめ': Color(0xFF0065A6), 'みなとみらい': Color(0xFF1A55A1), 'りんかい': Color(0xFF00418E),
      '名鉄': Color(0xFFC41721), '豊川': Color(0xFFD1031F), '西尾': Color(0xFF654D9D),
      '蒲郡': Color(0xFF654D9D), '三河': Color(0xFF00A0E9), '常滑': Color(0xFF0068B6),
      '河和': Color(0xFF00A0E9), '知多': Color(0xFF00A0E9), '津島': Color(0xFFEA5504),
      '尾西': Color(0xFFEA5504), '竹鼻': Color(0xFFD8A50F), '羽島': Color(0xFFD8A50F),
      '犬山': Color(0xFF008B41), '小牧': Color(0xFFE75297), '瀬戸': Color(0xFF7F1084),
      '近鉄': Color(0xFFE20826), '難波線': Color(0xFFE20826), '奈良線': Color(0xFFE20826),
      '生駒': Color(0xFFE20826), '大阪線': Color(0xFF2E89D9), '信貴': Color(0xFF2E89D9),
      '京都線': Color(0xFFE7A61A), '橿原': Color(0xFFE7A61A), '天理': Color(0xFFE7A61A),
      '田原本': Color(0xFFE7A61A), '南大阪': Color(0xFF00843B), '吉野': Color(0xFF00843B),
      '道明寺': Color(0xFF00843B), '御所': Color(0xFF00843B), '山田線': Color(0xFF0099CC),
      '鳥羽': Color(0xFF0099CC), '志摩': Color(0xFF0099CC), '名古屋線': Color(0xFF1B3DB0),
      '湯の山': Color(0xFF1B3DB0), '鈴鹿': Color(0xFF1B3DB0), 'けいはんな': Color(0xFF70C03A),
      '南海': Color(0xFF0077CE), '高野': Color(0xFF04873E), '泉北': Color(0xFFB1BC3A),
      '京阪': Color(0xFF1D2088), '京津': Color(0xFFAACE24), '石山坂本': Color(0xFF70C8E0),
      '阪急': Color(0xFF800000), '神戸線': Color(0xFF0D6FB8), '宝塚線': Color(0xFFEE7700),
      '阪神': Color(0xFF1F64B1), '山陽電気': Color(0xFFD0101A), '山陽電鉄': Color(0xFFD0101A),
      '西鉄': Color(0xFF004EA2), 'ゆいレール': Color(0xFFE60012),
    };

    for (var key in colorMap.keys) {
      if (name.contains(key)) return colorMap[key]!;
    }
    int hash = name.hashCode;
    return Color((hash & 0xFFFFFF) | 0xFF000000).withOpacity(1.0);
  }

  Future<void> _fetchLineData() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('games').doc('game_001').get();
      if (!doc.exists) return;
      var data = doc.data() as Map<String, dynamic>;
      
      List<dynamic> allowedLines = data['allowedLines'] ?? [];
      List<dynamic> allowedStations = data['allowedStations'] ?? [];

      if (allowedLines.isEmpty) return;

      List<Polyline> polylines = [];
      List<Marker> markers = [];
      
      _stationPositions = {};

      var claimedDocs = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('claimed_stations').get();
      Map<String, String> claimedMap = {};
      for (var d in claimedDocs.docs) {
        claimedMap[d.data()['name']] = d.data()['ownerTeam'];
      }

      for (String line in allowedLines) {
        var stations = await TrainApiService.getStationsByLine(line);
        List<LatLng> points = [];
        Color lineColor = _getLineColor(line);

        for (int i = 0; i < stations.length; i++) {
          var s = stations[i];
          double lat = (s['y'] as num).toDouble();
          double lng = (s['x'] as num).toDouble();
          String name = s['name'];
          LatLng pos = LatLng(lat, lng);
          points.add(pos);
          
          _stationPositions[name] = pos;

          if (allowedStations.isEmpty || allowedStations.contains(name)) {
            String? owner = claimedMap[name];
            Color stationBg = Colors.white;
            Color textColor = Colors.black;
            
            if (owner == 'RED') { stationBg = Colors.redAccent; textColor = Colors.white; }
            else if (owner == 'BLUE') { stationBg = Colors.blueAccent; textColor = Colors.white; }
            else if (owner == 'YELLOW') { stationBg = Colors.yellowAccent; }
            else if (owner == 'GREEN') { stationBg = Colors.greenAccent; }

            markers.add(
              Marker(
                point: pos,
                width: 100, height: 50,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: stationBg, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2))),
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: stationBg.withOpacity(0.9), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black54, width: 1)),
                      child: Text(name, style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            );
          }

          // 路線名ラベル（駅と駅の中間）
          if (i < stations.length - 1 && i % 5 == 2) {
            var nextS = stations[i + 1];
            double nextLat = (nextS['y'] as num).toDouble();
            double nextLng = (nextS['x'] as num).toDouble();
            LatLng midPos = LatLng((lat + nextLat) / 2, (lng + nextLng) / 2);

            markers.add(
              Marker(
                point: midPos,
                width: 100, height: 20,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: lineColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    line,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
          }
        }
        
        if (points.length > 1) {
          polylines.add(Polyline(points: points, color: lineColor.withOpacity(0.7), strokeWidth: 5));
        }
      }

      if (mounted) setState(() { _linePolylines = polylines; _stationMarkers = markers; _linesLoaded = true; });
    } catch (e) { print("Line Fetch Error: $e"); }
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  void _startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    _updatePosition();
    _positionTimer = Timer.periodic(const Duration(seconds: 5), (_) => _updatePosition());
  }

  Future<void> _updatePosition() async {
    try {
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng newLoc = LatLng(p.latitude, p.longitude);

      if (mounted) {
        setState(() {
          _myLocation = newLoc;
          _currentHeading = p.heading;
          _isConnected = true;
        });

        if (_isFirstLocationUpdate) {
          _mapController.move(newLoc, 15.0);
          _isFirstLocationUpdate = false;
        }
        _checkAreaOutSync();
        _checkSurrenderZoneSync();
      }

      if (_editMode == 'NONE' && !widget.isSelectionMode) {
        await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(_uid).update({
          'location': {'lat': p.latitude, 'lng': p.longitude},
          'heading': p.heading,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  void _checkAreaOutSync() async {
    if (widget.myRole != 'RUNNER') {
      if (_isOutOfArea) setState(() => _isOutOfArea = false);
      return;
    }
    bool isNowOut = false;
    if (_cachedCurrentAreaPoints.isNotEmpty) {
      List<LatLng> polygon = _cachedCurrentAreaPoints.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
      bool isInside = _isPointInPolygon(_myLocation, polygon);
      isNowOut = !isInside;
    } else {
      isNowOut = false;
    }
    if (isNowOut != _isOutOfArea) {
      setState(() => _isOutOfArea = isNowOut);
    }
    if (_prevOutOfAreaState != isNowOut) {
      _prevOutOfAreaState = isNowOut;
      await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(_uid).update({'isOutOfArea': isNowOut});
    }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      int j = (i + 1) % polygon.length;
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * (point.latitude - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }

  void _checkSurrenderZoneSync() {
    if (!_cachedAllowSurrender) {
      if (_isSurrenderPossible) setState(() => _isSurrenderPossible = false);
      return;
    }
    bool hit = false;
    for (var p in _cachedSurrenderPoints) {
      double dist = Geolocator.distanceBetween(_myLocation.latitude, _myLocation.longitude, (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
      if (dist <= ((p['radius'] as num?)?.toDouble() ?? 20.0)) {
        hit = true;
        break;
      }
    }
    if (hit != _isSurrenderPossible) setState(() => _isSurrenderPossible = hit);
  }

  void _onMapTap(TapPosition t, LatLng p) {
    if (_editMode == 'AREA') { setState(() => _tempAreaPoints.add(p)); return; }
    if (_editMode == 'BOX') { setState(() { _tempBoxMarkers.add(Marker(point: p, width: 40, height: 40, child: const Icon(Icons.check_box_outline_blank, color: Colors.purpleAccent, size: 40))); }); return; }
    if (_editMode == 'LOCATION') { setState(() => _selectedSinglePoint = p); return; }
    if (widget.myRole == 'GAME MASTER' && _editMode == 'NONE' && !widget.isSelectionMode) { _showGMMenu(p); }
  }

  void _confirmAreaSelection() {
    if (_tempAreaPoints.length < 3) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("最低3点必要です"))); return; }
    Navigator.pop(context, _tempAreaPoints);
  }
  void _confirmBoxPlacement() {
    if (_tempBoxMarkers.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("BOXを配置してください"))); return; }
    List<LatLng> boxes = _tempBoxMarkers.map((m) => m.point).toList();
    Navigator.pop(context, boxes);
  }
  void _confirmLocationSelection() {
    if (_selectedSinglePoint == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("地点を選択してください"))); return; }
    Navigator.pop(context, _selectedSinglePoint);
  }

  void _showGMMenu(LatLng p) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Container(
          color: Colors.grey[900],
          child: Wrap(
            children: [
              ListTile(leading: const Icon(Icons.edit_location, color: Colors.blue), title: const Text("基本エリア作成", style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); setState(() { _editMode = 'AREA'; _tempAreaPoints = []; }); }),
              ListTile(leading: const Icon(Icons.phone_in_talk, color: Colors.yellow), title: const Text("自首P設置", style: TextStyle(color: Colors.white)), onTap: () => _addSurrenderPoint(p)),
              const Divider(color: Colors.grey),
              ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("リセット(エリア)", style: TextStyle(color: Colors.white)), onTap: () { _resetData('areaPoints'); Navigator.pop(context); }),
              ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("リセット(BOX/自首P)", style: TextStyle(color: Colors.white)), onTap: () { _resetData('surrenderPoints'); _resetData('hunterBoxes'); Navigator.pop(context); }),
            ],
          ),
        ),
      ),
    );
  }

  void _resetData(String f) { FirebaseFirestore.instance.collection('games').doc('game_001').update({f: []}); }

  void _finishAreaCreation() {
    if (_tempAreaPoints.length < 3) return;
    List<Map<String, double>> pts = _tempAreaPoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
    FirebaseFirestore.instance.collection('games').doc('game_001').update({'areaPoints': pts});
    setState(() { _editMode = 'NONE'; _tempAreaPoints = []; });
  }

  void _addSurrenderPoint(LatLng p) {
    Navigator.pop(context);
    FirebaseFirestore.instance.collection('games').doc('game_001').update({'surrenderPoints': FieldValue.arrayUnion([{'lat': p.latitude, 'lng': p.longitude, 'radius': 20.0}])});
  }

  void _lockHunterBox(Map b) async {
    double dist = Geolocator.distanceBetween(_myLocation.latitude, _myLocation.longitude, b['lat'], b['lng']);
    if (dist > 30) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("遠すぎます！BOXまであと${(dist - 30).toInt()}m 近づいてください"), backgroundColor: Colors.red)); return; }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("ハンター封印", style: TextStyle(color: Colors.white)),
        content: const Text("このBOXを封印し、ハンター放出を阻止しますか？", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () async { Navigator.pop(ctx); await _executeSealHunterBox(b); }, child: const Text("封印する!")),
        ],
      ),
    );
  }

  Future<void> _executeSealHunterBox(Map targetBox) async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference gameRef = FirebaseFirestore.instance.collection('games').doc('game_001');
        DocumentSnapshot snapshot = await transaction.get(gameRef);
        if (!snapshot.exists) return;
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        List<dynamic> boxes = List.from(data['hunterBoxes'] ?? []);
        bool found = false;
        for (var i = 0; i < boxes.length; i++) {
          if ((boxes[i]['id'] != null && boxes[i]['id'] == targetBox['id']) || (boxes[i]['lat'] == targetBox['lat'] && boxes[i]['lng'] == targetBox['lng'])) {
            if (boxes[i]['isLocked'] == true) throw "既に封印されています";
            boxes[i]['isLocked'] = true; boxes[i]['sealedBy'] = widget.myName; found = true; break;
          }
        }
        if (found) {
          transaction.update(gameRef, {'hunterBoxes': boxes});
          DocumentReference msgRef = FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').doc();
          transaction.set(msgRef, {'title': "ハンター阻止！", 'body': "${widget.myName} がハンター1体を阻止しました！", 'type': 'SUCCESS', 'fromName': "SYSTEM", 'toUid': "ALL", 'createdAt': FieldValue.serverTimestamp()});
        }
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("封印完了！通知を送信しました。")));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("エラー: $e"))); }
  }

  void _doSurrender() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("自首しますか？", style: TextStyle(color: Colors.white)),
        content: const Text("現在の賞金を獲得してゲームから離脱します。\nこの操作は取り消せません。", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () async { Navigator.pop(ctx); await _executeSurrender(); }, child: const Text("自首する")),
        ],
      ),
    );
  }

  Future<void> _executeSurrender() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    var gameDoc = await FirebaseFirestore.instance.collection('games').doc('game_001').get();
    var gameData = gameDoc.data()!;
    DateTime startTime = (gameData['startTime'] as Timestamp).toDate();
    DateTime now = DateTime.now();
    double rate = (gameData['settings_moneyRate'] ?? 100).toDouble();
    int elapsed = now.difference(startTime).inSeconds;
    if (elapsed < 0) elapsed = 0;
    int prize = (elapsed * rate).toInt();

    await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({
      'status': 'SURRENDERED', 'money': prize, 'isExposed': false, 'isReported': false, 'isOutOfArea': false, 'location': null,
    });
    await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
      'title': "自首成立", 'body': "${widget.myName} が自首しました。\n獲得賞金: ¥$prize", 'type': 'info', 'toUid': 'ALL', 'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("自首が成立しました"))); Navigator.pop(context); }
  }

  void _catchRunner() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("確保対象を選択"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').where('role', isEqualTo: 'RUNNER').where('status', isEqualTo: 'ALIVE').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  var p = snapshot.data!.docs[index];
                  var pData = p.data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(pData['name']),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await p.reference.update({'status': 'CAUGHT', 'isExposed': false, 'isReported': false, 'isOutOfArea': false, 'location': null});
                        String title = "確保情報"; String body = "${pData['name']} が確保されました";
                        if (pData['isReported'] == true && pData['reportedBy'] != null) body = "${pData['reportedBy']} の密告により\n${pData['name']} が確保されました。";
                        
                        var gameRef = FirebaseFirestore.instance.collection('games').doc('game_001');
                        var gameSnap = await gameRef.get();
                        var gameData = gameSnap.data() as Map<String, dynamic>;
                        var mission = gameData['activeMission'];
                        if (mission != null && mission['type'] == 'INFORM' && mission['hunterRelease'] == true) {
                          int currentCaught = (mission['caughtCount'] ?? 0) + 1; int limit = mission['hunterCount'] ?? 1;
                          await gameRef.update({'activeMission.caughtCount': currentCaught});
                          body += "\n(密告ミッションによる確保: $currentCaught/$limit 人)";
                          if (currentCaught >= limit) {
                            await gameRef.update({'activeMission': null});
                            await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({'title': "ミッション終了", 'body': "規定人数が確保されたため、密告ミッションは終了しました。", 'type': 'SUCCESS', 'toUid': 'ALL', 'createdAt': FieldValue.serverTimestamp()});
                          }
                        }
                        await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({'title': title, 'body': body, 'type': 'CAUGHT', 'createdAt': FieldValue.serverTimestamp()});
                      },
                      child: const Text("確保"),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isGM = (widget.myRole == 'GAME MASTER');
    bool isHunter = (widget.myRole == 'HUNTER');
    Widget? actionBtn;
    if (isHunter) {
      actionBtn = FloatingActionButton.extended(heroTag: "catch", backgroundColor: Colors.red, label: const Text("確保", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: _catchRunner);
    } else if (!isGM) {
      if (_isOutOfArea) {
        actionBtn = FloatingActionButton.extended(heroTag: "alert", backgroundColor: Colors.red, label: const Text("⚠️ エリア外", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: null);
      } else if (_isSurrenderPossible) {
        actionBtn = FloatingActionButton.extended(heroTag: "surrender", backgroundColor: Colors.yellowAccent, label: const Text("自首する", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), onPressed: _doSurrender);
      }
    }

    String title = "MAP";
    if (_editMode == 'AREA') title = "範囲をタップで囲む";
    if (_editMode == 'BOX') title = "タップでBOX配置";
    if (_editMode == 'LOCATION') title = "地点をタップ";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.grey[900],
        actions: [
          // ★追加: 地図表示/非表示切り替えボタン
          if (_editMode == 'NONE')
            IconButton(
              icon: Icon(_isCyberMode ? Icons.map : Icons.layers_clear, color: Colors.cyanAccent),
              onPressed: () {
                setState(() => _isCyberMode = !_isCyberMode);
              },
            ),
          
          if (_editMode == 'AREA') IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: _confirmAreaSelection),
          if (_editMode == 'BOX') IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: _confirmBoxPlacement),
          if (_editMode == 'LOCATION') IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: _confirmLocationSelection),
          if (_editMode == 'NONE') Padding(padding: const EdgeInsets.all(16), child: Icon(Icons.circle, size: 12, color: _isConnected ? Colors.green : Colors.red)),
        ],
      ),
      body: Stack(
        children: [
          _buildMapLayer(isHunter, isGM),
          if (_isOutOfArea && _editMode == 'NONE')
            Container(
              color: Colors.red.withOpacity(0.3),
              child: const Center(child: Text("AREA ALERT\n位置情報が公開されています", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
            ),
          if (_editMode == 'AREA' && widget.initialMode == 'NORMAL') Positioned(top: 20, child: ElevatedButton(onPressed: _finishAreaCreation, child: const Text("完了"))),
          if (_editMode == 'NONE') SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [if (actionBtn != null) actionBtn, FloatingActionButton(onPressed: () => _mapController.move(_myLocation, 15), backgroundColor: Colors.grey[800], child: const Icon(Icons.my_location, color: Colors.white))],))),
        ],
      ),
    );
  }

  Widget _buildMapLayer(bool isHunter, bool isGM) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('games').doc('game_001').snapshots(),
      builder: (context, gameSnap) {
        if (!gameSnap.hasData) return const Center(child: CircularProgressIndicator());
        var d = gameSnap.data!.data() as Map<String, dynamic>;

        List surrenderPoints = d['surrenderPoints'] ?? [];
        List hunterBoxes = d['hunterBoxes'] ?? [];
        var mission = d['activeMission'];
        String mode = d['mode'] ?? 'A';
        bool isBoxMission = mission != null && mission['type'] == 'HUNTER_BOX';
        bool isVotingMission = mission != null && mission['type'] == 'VOTING';

        List<Polygon> polygons = [];
        List<Polyline> polylines = [];
        List<Marker> markers = [];
        List<CircleMarker> circles = [];

        List<LatLng> displayPolygon = [];
        Map assignments = d['areaAssignments'] ?? {};
        Map splitAreas = d['splitAreas'] ?? {};
        List defaultArea = d['areaPoints'] ?? [];
        List<dynamic> targetPoints = defaultArea;
        String? myAssigned = assignments[_uid];
        if (myAssigned != null && splitAreas.containsKey(myAssigned)) targetPoints = splitAreas[myAssigned];
        if (targetPoints.isNotEmpty) displayPolygon = targetPoints.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
        if (displayPolygon.isNotEmpty) polygons.add(Polygon(points: displayPolygon, color: Colors.blueAccent.withOpacity(0.1), borderColor: Colors.blueAccent, borderStrokeWidth: 2));

        if (isVotingMission) {
          List<dynamic> rawA = mission['areaPointsA'] ?? []; List<dynamic> rawB = mission['areaPointsB'] ?? [];
          if (rawA.isNotEmpty) polygons.add(Polygon(points: rawA.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList(), color: Colors.red.withOpacity(0.3), borderColor: Colors.redAccent, borderStrokeWidth: 2, label: "エリアA"));
          if (rawB.isNotEmpty) polygons.add(Polygon(points: rawB.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList(), color: Colors.blue[900]!.withOpacity(0.4), borderColor: Colors.blue[900]!, borderStrokeWidth: 2, label: "エリアB"));
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _cachedCurrentAreaPoints = targetPoints; _cachedSurrenderPoints = surrenderPoints; _cachedAllowSurrender = d['settings_allowSurrender'] ?? true; _checkAreaOutSync();
          }
        });

        if (_linesLoaded) {
          polylines.addAll(_linePolylines);
          markers.addAll(_stationMarkers);
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').snapshots(),
          builder: (context, playerSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('claimed_stations').snapshots(),
              builder: (context, claimedSnap) {
                if (_tempAreaPoints.isNotEmpty && _editMode == 'AREA') {
                  polygons.add(Polygon(points: _tempAreaPoints, color: Colors.yellowAccent.withOpacity(0.2), borderColor: Colors.yellow, borderStrokeWidth: 2));
                  for (var p in _tempAreaPoints) markers.add(Marker(point: p, width: 20, height: 20, child: const Icon(Icons.circle, color: Colors.yellow, size: 10)));
                }
                if (_editMode == 'BOX') markers.addAll(_tempBoxMarkers);
                if (_editMode == 'LOCATION' && _selectedSinglePoint != null) markers.add(Marker(point: _selectedSinglePoint!, width: 40, height: 40, child: const Icon(Icons.location_on, color: Colors.greenAccent, size: 40)));

                for (var b in hunterBoxes) {
                  bool locked = b['isLocked'] ?? false;
                  markers.add(Marker(point: LatLng(b['lat'], b['lng']), width: 50, height: 50, child: GestureDetector(onTap: () { if (!locked && isBoxMission && widget.myRole == 'RUNNER') _lockHunterBox(b); }, child: Column(children: [Icon(locked ? Icons.lock : Icons.check_box_outline_blank, color: locked ? Colors.green : Colors.red, size: 30), Text(locked ? "LOCKED" : "UNLOCK", style: TextStyle(fontSize: 8, color: locked ? Colors.green : Colors.red, backgroundColor: Colors.white))]))));
                }
                for (var p in surrenderPoints) {
                  circles.add(CircleMarker(point: LatLng(p['lat'], p['lng']), radius: 20, color: Colors.yellowAccent.withOpacity(0.2), borderColor: Colors.yellow, borderStrokeWidth: 2, useRadiusInMeter: true));
                  markers.add(Marker(point: LatLng(p['lat'], p['lng']), width: 40, height: 40, child: const Icon(Icons.phone_in_talk, color: Colors.blueAccent)));
                }

                if (mode == 'D' && claimedSnap.hasData) {
                  for (var doc in claimedSnap.data!.docs) {
                    var cData = doc.data() as Map<String, dynamic>;
                    Color teamColor = Colors.white;
                    if(cData['ownerTeam'] == 'RED') teamColor = Colors.red;
                    else if(cData['ownerTeam'] == 'BLUE') teamColor = Colors.blue;
                    else if(cData['ownerTeam'] == 'YELLOW') teamColor = Colors.yellow;
                    else if(cData['ownerTeam'] == 'GREEN') teamColor = Colors.green;

                    markers.add(Marker(point: LatLng(cData['lat'], cData['lng']), width: 80, height: 80, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.flag, color: teamColor, size: 40), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: Text(cData['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))])));
                  }
                }

                if (playerSnap.hasData && _editMode == 'NONE') {
                  for (var doc in playerSnap.data!.docs) {
                    var pd = doc.data() as Map<String, dynamic>;
                    if ((isHunter || isGM) && pd['isReported'] == true && pd['reportLocation'] != null && pd['role'] == 'RUNNER' && pd['status'] == 'ALIVE') {
                      var rLoc = pd['reportLocation']; double? rLat = (rLoc['lat'] as num?)?.toDouble(); double? rLng = (rLoc['lng'] as num?)?.toDouble();
                      if (rLat != null && rLng != null) markers.add(Marker(point: LatLng(rLat, rLng), width: 80, height: 80, child: Column(children: [const Icon(Icons.warning, color: Colors.red, size: 40), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: Text("密告: ${pd['name']}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))])));
                    }
                    if (pd['location'] == null) continue;
                    double? pLat = (pd['location']['lat'] as num?)?.toDouble(); double? pLng = (pd['location']['lng'] as num?)?.toDouble();
                    if (pLat == null || pLng == null) continue;
                    bool isMe = (doc.id == _uid); bool isExposed = pd['isExposed'] ?? false; bool isOutOfArea = pd['isOutOfArea'] ?? false; bool isCaught = pd['status'] == 'CAUGHT'; bool isSurrendered = pd['status'] == 'SURRENDERED';
                    if (isCaught || isSurrendered) continue;
                    bool visible = false;
                    if (isMe || isGM) visible = true; else if (pd['role'] == 'HUNTER' && isHunter) visible = true; else if (isHunter && (isExposed || isOutOfArea)) visible = true;
                    if (!visible) continue;
                    
                    Color iconColor = Colors.white;
                    if (pd['role'] == 'HUNTER') iconColor = Colors.red;
                    else if (pd['team'] == 'RED') iconColor = Colors.redAccent;
                    else if (pd['team'] == 'BLUE') iconColor = Colors.blueAccent;
                    else if (pd['team'] == 'YELLOW') iconColor = Colors.yellowAccent;
                    else if (pd['team'] == 'GREEN') iconColor = Colors.greenAccent;
                    
                    double rotation = 0.0;
                    if (isMe) rotation = (_currentHeading * (math.pi / 180));
                    else rotation = (((pd['heading'] as num?)?.toDouble() ?? 0.0) * (math.pi / 180));

                    markers.add(Marker(point: LatLng(pLat, pLng), width: 120, height: 120, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(4), border: Border.all(color: iconColor, width: 1.5)), child: Text("${pd['name']}\n${pd['currentStation'] ?? '移動中'}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black), overflow: TextOverflow.ellipsis, maxLines: 2)), Transform.rotate(angle: rotation, child: Icon(Icons.navigation, color: iconColor, size: 40))])));

                    // すごろくゴール・NEXTマーカー
                    if (isMe) {
                      String? finalGoal = pd['finalGoalStation'];
                      String? nextGoal = pd['nextGoalStation'];
                      if (finalGoal != null && _stationPositions.containsKey(finalGoal)) {
                        markers.add(Marker(
                          point: _stationPositions[finalGoal]!, width: 80, height: 80,
                          child: Column(children: [const Icon(Icons.flag, color: Colors.pinkAccent, size: 40), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.pinkAccent, borderRadius: BorderRadius.circular(4)), child: const Text("GOAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)))]),
                        ));
                      }
                      if (nextGoal != null && _stationPositions.containsKey(nextGoal)) {
                        markers.add(Marker(
                          point: _stationPositions[nextGoal]!, width: 80, height: 80,
                          child: Column(children: [const Icon(Icons.location_on, color: Colors.purpleAccent, size: 40), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.purpleAccent, borderRadius: BorderRadius.circular(4)), child: const Text("NEXT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)))]),
                        ));
                      }
                    }
                  }
                }

                return FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _myLocation,
                    initialZoom: 15,
                    onTap: _onMapTap,
                  ),
                  children: [
                    // ★修正: 地図タイル表示制御 (サイバーモードなら非表示)
                    if (!_isCyberMode)
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.train_run',
                      ),
                    CircleLayer(circles: circles),
                    PolylineLayer(polylines: polylines),
                    PolygonLayer(polygons: polygons),
                    MarkerLayer(markers: markers),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}