import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'api_service.dart';
import 'map_screen.dart';
import 'mission_control_screen.dart';

class SettingsAppScreen extends StatefulWidget {
  const SettingsAppScreen({super.key});
  @override
  State<SettingsAppScreen> createState() => _SettingsAppScreenState();
}

class _SettingsAppScreenState extends State<SettingsAppScreen> {
  final TextEditingController _timeCtrl = TextEditingController(text: "60");
  final TextEditingController _moneyCtrl = TextEditingController(text: "100");
  final TextEditingController _cntCtrl = TextEditingController(text: "10");
  final TextEditingController _intervalCtrl = TextEditingController(text: "5");
  final TextEditingController _delayCtrl = TextEditingController(text: "0");
  
  bool _hunterVision = false;
  bool _allowSurrender = true;
  bool _penaltyEnabled = false; 
  
  double _boardSize = 5; 
  bool _othelloStandardInit = true; 
  bool _othelloTurnBased = false;

  String _selectedMode = 'A';
  final Map<String, String> _modeNames = {
    'A': 'スコアアタック (通常)',
    'B': '鉄道すごろく',
    'C': '生存競争 (サバイバル)',
    'D': '陣取り合戦 (単純塗りつぶし)',
    'E': '鉄道オセロ (挟んでひっくり返す)',
    'F': '鉄道ビンゴ (スピード勝負)',
  };

  List<LatLng>? _gameAreaPoints;
  List<String> _allowedLines = [];
  List<String> _allowedStations = [];

  final List<String> _regions = ["関東", "近畿", "中部", "九州", "東北", "中国", "四国", "北海道"];

  // ★追加: 駅名正規化メソッド (盤面生成時に統一する)
  String _normalizeStationName(String name) {
    if (name == '難波' || name == '大阪難波' || name == 'ＪＲ難波' || name == '近鉄難波') return 'なんば';
    return name;
  }

  Future<String?> _showJankenDialog() async {
    return await showDialog<String>(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("奇数盤面: 中心決定", style: TextStyle(color: Colors.white)),
        content: const Text("勝ったチームを中心に配置します。\n勝者はどちらですか？", style: TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, 'RED'), child: const Text("RED 勝利")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent), onPressed: () => Navigator.pop(ctx, 'BLUE'), child: const Text("BLUE 勝利")),
        ],
      ),
    );
  }

  void _startGame() async {
    String? oddWinner;
    if (_selectedMode == 'E' && _othelloStandardInit && _boardSize.toInt() % 2 != 0) {
      oddWinner = await _showJankenDialog();
      if (oddWinner == null) return;
    }

    int min = int.tryParse(_timeCtrl.text) ?? 60;
    int cd = int.tryParse(_cntCtrl.text) ?? 10;
    DateTime now = DateTime.now();
    DateTime start = now.add(Duration(seconds: cd));
    DateTime end = start.add(Duration(minutes: min));

    List<Map<String, double>>? areaData;
    if (_gameAreaPoints != null) {
      areaData = _gameAreaPoints!.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
    }

    // 設定保存
    await FirebaseFirestore.instance.collection('games').doc('game_001').update(
      {
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
        'status': 'COUNTDOWN',
        'mode': _selectedMode,
        'areaPoints': areaData ?? [],
        'allowedLines': _allowedLines,
        
        // ★許可駅リストも正規化して保存
        'allowedStations': _allowedStations.map((s) => _normalizeStationName(s)).toSet().toList(),
        
        'settings_moneyRate': double.tryParse(_moneyCtrl.text) ?? 100.0,
        'settings_updateInterval': int.tryParse(_intervalCtrl.text) ?? 5,
        'settings_hunterVision': _hunterVision,
        'settings_hunterDelay': int.tryParse(_delayCtrl.text) ?? 0,
        'settings_allowSurrender': _allowSurrender,
        'settings_penaltyEnabled': _penaltyEnabled,
        'settings_reversi': (_selectedMode == 'E'), 
        'settings_boardSize': _boardSize.toInt(),
        'settings_othelloTurnBased': _othelloTurnBased,
        'currentTurn': 'RED',
        'bingoCompleteCount': 0,
      },
    );
    
    var p = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').get();
    for (var d in p.docs) {
      d.reference.update({
        'status': 'ALIVE', 'money': 0, 'isReported': false, 'photoVerificationStatus': null,
        'bingoCard': FieldValue.delete(), 'bingoLines': 0, 'bingoRank': 0,
        'penaltyUntil': null,
      });
    }
    
    var c = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('claimed_stations').get();
    for(var d in c.docs) d.reference.delete();
    var o = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').get();
    for(var d in o.docs) d.reference.delete();
    
    if (_selectedMode == 'E') {
      await _generateOthelloBoard(oddWinner);
    } else if (_selectedMode == 'F') {
      await _generateBingoCardsForEveryone();
    }

    if (mounted) Navigator.pop(context);
  }

  // ★ Mode F: ビンゴカード生成 (正規化対応)
  Future<void> _generateBingoCardsForEveryone() async {
    Set<String> allStations = {};
    
    if (_allowedStations.isNotEmpty) {
      allStations.addAll(_allowedStations.map((s) => _normalizeStationName(s)));
    } else {
      for (String line in _allowedLines) {
        var stations = await TrainApiService.getStationsByLine(line);
        // ここで正規化してSetに追加 (重複排除)
        for (var s in stations) allStations.add(_normalizeStationName(s['name']));
      }
    }
    
    int size = _boardSize.toInt();
    int totalCells = size * size;
    
    if (allStations.length < totalCells) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("駅数が足りないためFREEマスが含まれます"), backgroundColor: Colors.orange));
    }

    var players = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').get();
    var batch = FirebaseFirestore.instance.batch();

    for (var player in players.docs) {
      List<String> stationList = allStations.toList()..shuffle();
      List<Map<String, dynamic>> cardData = [];
      
      for (int i = 0; i < totalCells; i++) {
        String name = "FREE";
        bool isOpen = false;
        
        if (size % 2 != 0 && i == (totalCells ~/ 2)) {
          name = "FREE";
          isOpen = true; 
        } else if (i < stationList.length) {
          name = stationList[i];
        } else {
          name = "FREE"; 
          isOpen = true;
        }

        cardData.add({
          'index': i,
          'station': name,
          'isOpen': isOpen,
        });
      }
      
      batch.update(player.reference, {
        'bingoCard': cardData,
        'bingoLines': 0,
        'bingoRank': 0,
      });
    }
    await batch.commit();
  }

  // ★ Mode E: オセロ盤面生成 (正規化対応)
  Future<void> _generateOthelloBoard([String? oddWinner]) async {
    Set<String> allStations = {};
    if (_allowedStations.isNotEmpty) {
      allStations.addAll(_allowedStations.map((s) => _normalizeStationName(s)));
    } else {
      for (String l in _allowedLines) { 
        var s = await TrainApiService.getStationsByLine(l); 
        for (var i in s) allStations.add(_normalizeStationName(i['name'])); 
      }
    }
    
    List<String> stationList = allStations.toList()..shuffle();
    var batch = FirebaseFirestore.instance.batch();
    var boardRef = FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board');
    
    var oldDocs = await boardRef.get(); 
    for(var d in oldDocs.docs) batch.delete(d.reference);

    int size = _boardSize.toInt();
    int center = size ~/ 2; 
    int stationIndex = 0;

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        String stationName = "FREE"; 
        if (stationIndex < stationList.length) { 
          stationName = stationList[stationIndex]; 
          stationIndex++; 
        }
        
        String docId = "${x}_$y";
        String? initialOwner;
        
        if (_othelloStandardInit) {
          if (size % 2 == 0) {
            if (x == center - 1 && y == center - 1) initialOwner = 'RED'; 
            else if (x == center && y == center - 1) initialOwner = 'BLUE'; 
            else if (x == center - 1 && y == center) initialOwner = 'BLUE'; 
            else if (x == center && y == center) initialOwner = 'RED';
          } else {
            if (x == center && y == center) initialOwner = oddWinner ?? 'RED';
          }
        }
        batch.set(boardRef.doc(docId), {'x': x, 'y': y, 'station': stationName, 'ownerTeam': initialOwner});
      }
    }
    await batch.commit();
  }

  void _finishGame() async { 
    await FirebaseFirestore.instance.collection('games').doc('game_001').update({'status': 'FINISHED'}); 
    if (mounted) Navigator.pop(context); 
  }

  void _resetTimer() async {
    final m = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('games').doc('game_001').update({
      'status': 'WAITING', 'mission': '', 'activeMission': FieldValue.delete(), 
      'informerPoints': FieldValue.delete(), 'hunterBoxes': FieldValue.delete(), 
      'allowedLines': [], 'allowedStations': [], 'areaPoints': [], 'bingoCompleteCount': 0
    });
    await _clearMessages(); 
    await _resetDiscordAssignments();
    
    var c = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('claimed_stations').get(); 
    for(var d in c.docs) d.reference.delete();
    
    var o = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').get(); 
    for(var d in o.docs) d.reference.delete();
    
    m.showSnackBar(const SnackBar(content: Text("完全リセット完了")));
  }

  Future<void> _clearMessages() async { 
    var msgs = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').get(); 
    for (var doc in msgs.docs) await doc.reference.delete(); 
  }

  Future<void> _resetDiscordAssignments() async { 
    var p = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').get(); 
    for(var d in p.docs) d.reference.update({'discordId': null, 'isBusy': false, 'talkingWith': null}); 
    
    var pl = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('discord_pool').get(); 
    for(var d in pl.docs) d.reference.update({'isUsed': false, 'assignedTo': null}); 
  }

  void _clearPlayers() async { 
    var p = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').get(); 
    for (var d in p.docs) d.reference.delete(); 
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("データ消去完了"))); 
  }

  void _setAreaOnMap() async { 
    final res = await Navigator.push(context, MaterialPageRoute(builder: (c) => const MapScreen(myRole: 'GAME MASTER', myName: 'GM', initialMode: 'SELECT_AREA'))); 
    if (res != null) setState(() => _gameAreaPoints = res); 
  }

  Future<void> _showLineSelectDialog() async { 
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900], 
        title: const Text("路線検索方法", style: TextStyle(color: Colors.white)), 
        content: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            ListTile(
              leading: const Icon(Icons.my_location, color: Colors.blueAccent), 
              title: const Text("現在地周辺", style: TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); _searchLines(null); }
            ), 
            ListTile(
              leading: const Icon(Icons.map, color: Colors.greenAccent), 
              title: const Text("地図指定", style: TextStyle(color: Colors.white)), 
              onTap: () async { 
                Navigator.pop(ctx); 
                final res = await Navigator.push(context, MaterialPageRoute(builder: (c) => const MapScreen(myRole: 'GM', myName: 'GM', initialMode: 'SELECT_LOCATION'))); 
                if (res!=null) _searchLines(res); 
              }
            ), 
            ListTile(
              leading: const Icon(Icons.public, color: Colors.orangeAccent), 
              title: const Text("地域選択", style: TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); _showRegionSelectDialog(); }
            )
          ]
        )
      )
    ); 
  }

  void _showRegionSelectDialog() { 
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900], 
        content: SizedBox(
          width: double.maxFinite, 
          height: 300, 
          child: ListView.builder(
            itemCount: _regions.length, 
            itemBuilder: (c, i) => ListTile(
              title: Text(_regions[i], style: const TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); _searchLinesByRegion(_regions[i]); }
            )
          )
        )
      )
    ); 
  }

  Future<void> _searchLinesByRegion(String r) async { 
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator())); 
    try { 
      var l = await TrainApiService.getLinesByRegion(r); 
      if(mounted) Navigator.pop(context); 
      if(mounted) _showMultiSelectDialog(l, r); 
    } catch(e) { 
      if(mounted) Navigator.pop(context); 
    } 
  }

  Future<void> _searchLines(LatLng? p) async { 
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator())); 
    try { 
      LatLng t;
      if (p != null) {
        t = p;
      } else {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        t = LatLng(pos.latitude, pos.longitude);
      }
      var l = await TrainApiService.getLinesInArea(t); 
      if(mounted) Navigator.pop(context); 
      if(mounted) _showMultiSelectDialog(l, "周辺"); 
    } catch(e) { 
      if(mounted) Navigator.pop(context); 
    } 
  }

  void _showMultiSelectDialog(List<String> lines, String title) { 
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900], 
        title: Text(title, style: const TextStyle(color: Colors.white)), 
        content: SizedBox(
          width: double.maxFinite, 
          height: 400, 
          child: StatefulBuilder(
            builder: (ctx, ss) => ListView.builder(
              itemCount: lines.length, 
              itemBuilder: (c, i) => CheckboxListTile(
                title: Text(lines[i], style: const TextStyle(color: Colors.white)), 
                value: _allowedLines.contains(lines[i]), 
                onChanged: (v) { 
                  ss(() { 
                    if(v!) { _allowedLines.add(lines[i]); _addAllStationsDefault(lines[i]); } 
                    else { _allowedLines.remove(lines[i]); } 
                  }); 
                  setState((){}); 
                }
              )
            )
          )
        ), 
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("完了", style: TextStyle(color: Colors.greenAccent)))]
      )
    ); 
  }

  Future<void> _addAllStationsDefault(String l) async { 
    var s = await TrainApiService.getStationsByLine(l); 
    for(var i in s) if(!_allowedStations.contains(i['name'])) setState(() => _allowedStations.add(i['name'])); 
  }

  Future<void> _showStationSelectDialog() async { 
    if(_allowedLines.isEmpty) return; 
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator())); 
    Map<String, List<String>> m = {}; 
    for(var l in _allowedLines) { 
      var s = await TrainApiService.getStationsByLine(l); 
      m[l] = s.map((e)=>e['name'] as String).toList(); 
    } 
    if(mounted) Navigator.pop(context); 
    if(mounted) showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900], 
        content: SizedBox(
          width: double.maxFinite, 
          height: 500, 
          child: StatefulBuilder(
            builder: (ctx, ss) => ListView.builder(
              itemCount: _allowedLines.length, 
              itemBuilder: (c, i) => ExpansionTile(
                title: Text(_allowedLines[i], style: const TextStyle(color: Colors.green)), 
                children: m[_allowedLines[i]]!.map((s) => CheckboxListTile(
                  title: Text(s, style: const TextStyle(color: Colors.white)), 
                  value: _allowedStations.contains(s), 
                  onChanged: (v) { 
                    ss(() { if(v!) _allowedStations.add(s); else _allowedStations.remove(s); }); 
                    setState((){}); 
                  }
                )).toList()
              )
            )
          )
        ), 
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("完了", style: TextStyle(color: Colors.blueAccent)))]
      )
    ); 
  }

  // ★盤面シャッフル処理
  Future<void> _shuffleOthelloBoard() async {
    var snap = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').get();
    
    // まだ盤面が1度も作られていない場合はエラーメッセージを出す
    if (snap.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('まだ盤面が生成されていません。先に「開始」を押して盤面を作成してください。'), backgroundColor: Colors.redAccent));
      }
      return;
    }

    // 現在の駅リストを抽出してシャッフル
    List<String> stations = snap.docs.map((d) => d.data()['station'] as String).toList();
    stations.shuffle();

    int boardSize = _boardSize.toInt(); // 現在の盤面サイズを適用
    WriteBatch batch = FirebaseFirestore.instance.batch();
    
    int index = 0;
    for (int y = 0; y < boardSize; y++) {
      for (int x = 0; x < boardSize; x++) {
        if (index < stations.length) {
          String st = stations[index];
          DocumentReference docRef = FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').doc('${x}_$y');
          
          // 中央マスをオセロの初期配置(赤・青)にセット、それ以外は空(null)にする
          String? owner;
          if (_othelloStandardInit) {
            if (boardSize % 2 == 0) {
              int center = boardSize ~/ 2;
              if (x == center - 1 && y == center - 1) owner = 'RED';
              else if (x == center && y == center - 1) owner = 'BLUE';
              else if (x == center - 1 && y == center) owner = 'BLUE';
              else if (x == center && y == center) owner = 'RED';
            } else {
              int center = boardSize ~/ 2;
              if (x == center && y == center) owner = 'RED'; // 奇数サイズの場合はとりあえずRED
            }
          }

          batch.update(docRef, {
            'station': st,
            'ownerTeam': owner,
          });
          index++;
        }
      }
    }
    await batch.commit();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('盤面の配置をシャッフルしました！', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.orangeAccent));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("SETTINGS"), backgroundColor: Colors.grey[900]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(5)),
            child: DropdownButton<String>(
              value: _selectedMode, isExpanded: true, dropdownColor: Colors.grey[900], style: const TextStyle(color: Colors.white, fontSize: 16), underline: const SizedBox(),
              items: _modeNames.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text("Mode ${entry.key}: ${entry.value}"))).toList(),
              onChanged: (v) => setState(() {
                _selectedMode = v!;
                if(_selectedMode == 'E') _boardSize = 8;
                if(_selectedMode == 'F') _boardSize = 5;
              }),
            ),
          ),
          
          if (_selectedMode == 'E' || _selectedMode == 'F') ...[
            const SizedBox(height: 20),
            Text(
              _selectedMode == 'E' ? "オセロ盤面サイズ: ${_boardSize.toInt()}x${_boardSize.toInt()}" : "ビンゴカードサイズ: ${_boardSize.toInt()}x${_boardSize.toInt()}", 
              style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)
            ),
            Slider(value: _boardSize, min: 3, max: 20, divisions: 17, activeColor: Colors.cyanAccent, label: "${_boardSize.toInt()}", onChanged: (v) => setState(() => _boardSize = v)),
            
            if (_selectedMode == 'E') ...[
              SwitchListTile(title: const Text("初期配置 (中央の石)", style: TextStyle(color: Colors.white)), subtitle: Text(_othelloStandardInit ? "あり" : "なし", style: const TextStyle(color: Colors.grey, fontSize: 12)), value: _othelloStandardInit, activeColor: Colors.cyanAccent, onChanged: (v) => setState(() => _othelloStandardInit = v)),
              SwitchListTile(title: const Text("ターン制モード", style: TextStyle(color: Colors.white)), subtitle: Text(_othelloTurnBased ? "ON" : "OFF", style: const TextStyle(color: Colors.grey, fontSize: 12)), value: _othelloTurnBased, activeColor: Colors.purpleAccent, onChanged: (v) => setState(() => _othelloTurnBased = v)),
            ] else ...[
              const Text("※ゲーム開始時に全員にランダムなカードが配布されます", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ],

          const SizedBox(height: 10),
          SwitchListTile(title: const Text("ペナルティモード (不正・連打防止)", style: TextStyle(color: Colors.white)), subtitle: const Text("リスト外の駅でチェックインすると5分間操作不能になります", style: TextStyle(color: Colors.grey, fontSize: 12)), value: _penaltyEnabled, activeColor: Colors.redAccent, onChanged: (v) => setState(() => _penaltyEnabled = v)),
          const SizedBox(height: 10),

          ElevatedButton.icon(icon: const Icon(Icons.map), label: Text(_gameAreaPoints == null ? "エリア範囲を設定 (地図)" : "地図範囲: 設定済み"), style: ElevatedButton.styleFrom(backgroundColor: _gameAreaPoints == null ? Colors.grey : Colors.blueAccent, foregroundColor: Colors.white), onPressed: _setAreaOnMap),
          const SizedBox(height: 10),
          ElevatedButton.icon(icon: const Icon(Icons.train), label: Text(_allowedLines.isEmpty ? "対象路線を設定 (リスト選択)" : "路線: ${_allowedLines.length}件 設定済み"), style: ElevatedButton.styleFrom(backgroundColor: _allowedLines.isEmpty ? Colors.grey : Colors.green, foregroundColor: Colors.white), onPressed: _showLineSelectDialog),
          if (_allowedLines.isNotEmpty) ...[const SizedBox(height: 5), ElevatedButton.icon(icon: const Icon(Icons.list), label: Text("対象駅を詳細設定 (${_allowedStations.length}駅 許可中)"), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800], foregroundColor: Colors.white), onPressed: _showStationSelectDialog), Padding(padding: const EdgeInsets.all(8.0), child: Text(_allowedLines.join(", "), style: const TextStyle(color: Colors.greenAccent, fontSize: 11)))],
          
          const SizedBox(height: 20),
          _buildTF("ゲーム時間(分)", _timeCtrl), const SizedBox(height: 10), _buildTF("賞金単価", _moneyCtrl), const SizedBox(height: 10), _buildTF("カウントダウン(秒)", _cntCtrl), const SizedBox(height: 10),
          
          const Divider(color: Colors.grey),
          SwitchListTile(title: const Text("ハンターに位置公開", style: TextStyle(color: Colors.white)), value: _hunterVision, activeColor: Colors.redAccent, onChanged: (v) => setState(() => _hunterVision = v)),
          SwitchListTile(title: const Text("自首を許可", style: TextStyle(color: Colors.white)), value: _allowSurrender, activeColor: Colors.yellowAccent, onChanged: (v) => setState(() => _allowSurrender = v)),
          const Divider(color: Colors.grey),
          
          const SizedBox(height: 20),
          // ★追加: オセロモードの時だけ、開始ボタンの前にシャッフルボタンを表示
          if (_selectedMode == 'E') ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.shuffle),
              label: const Text("対象駅はそのままに盤面だけシャッフル"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(15)
              ),
              onPressed: _shuffleOthelloBoard,
            ),
            const SizedBox(height: 10),
          ],
          
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(15)), onPressed: _startGame, child: const Text("開始", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          if (_selectedMode == 'C') ...[const SizedBox(height: 20), ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], padding: const EdgeInsets.all(15)), icon: const Icon(Icons.flash_on), label: const Text("ミッション管理画面へ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const MissionScreen())); })],
          const SizedBox(height: 40),
          ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.all(15)), icon: const Icon(Icons.stop_circle), label: const Text("ゲーム終了", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: _finishGame),
          const SizedBox(height: 20),
          TextButton(onPressed: _resetTimer, child: const Text("リセット", style: TextStyle(color: Colors.orange))),
          TextButton(onPressed: _clearPlayers, child: const Text("全プレイヤー削除", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildTF(String l, TextEditingController c) => TextField(controller: c, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: l, labelStyle: const TextStyle(color: Colors.grey)));
}

extension on Position { get latitude => this.latitude; get longitude => this.longitude; }
extension on LatLng { get latitude => this.latitude; get longitude => this.longitude; }