import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';
import 'api_service.dart';
import 'mail_screen.dart';
import 'discord_screen.dart';
import 'train_vision.dart'; 
import 'dice_dialog.dart'; 
import 'othello_logic.dart'; // ★追加: オセロの判定ロジックを読み込む

class HomeScreen extends StatefulWidget {
  final String myRole;
  final String myName;

  const HomeScreen({
    super.key,
    required this.myRole,
    required this.myName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _nearestStation = "---";
  String _currentLine = "---";
  double _currentSpeed = 0.0;
  double _totalDistance = 0.0;
  int _visitedCount = 0;
  
  String? _nextGoalStation; 
  String? _finalGoalStation; 
  
  bool _isLoading = false;
  Map<String, dynamic> _gameData = {};
  Map<String, dynamic> _myData = {};
  Timer? _locationTimer;
  Timer? _exposureTimer;
  Timer? _penaltyTimer; 
  
  // ★追加: 画面のタイマーを1秒ごとに動かすためのタイマー
  Timer? _uiTimer;
  bool _isPassing = false; // 自動パス処理の重複実行を防ぐフラグ

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
    if (widget.myRole == 'RUNNER') {
      _startExposureCheck();
    }

    // ★追加: 1秒ごとに画面を更新してカウントダウンを動かす
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {}); // 画面を更新

      // ★追加：時間切れ自動パス処理
      if (_gameData['mode'] == 'E' && (_gameData['settings_othelloTurnBased'] ?? false)) {
        Timestamp? turnEndTs = _gameData['turnEndTime'];
        if (turnEndTs != null) {
          int remain = turnEndTs.toDate().difference(DateTime.now()).inSeconds;
          if (remain <= 0) {
            _forcePassTurn(); // 0秒になったら強制パスを実行！
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _exposureTimer?.cancel();
    _penaltyTimer?.cancel();
    _uiTimer?.cancel(); // ★追加: タイマー解除
    super.dispose();
  }

  // ★追加: 時間切れの時に強制的にターンを回す処理（トランザクションで安全に実行）
  Future<void> _forcePassTurn() async {
    if (_isPassing) return;
    _isPassing = true;
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference gameRef = FirebaseFirestore.instance.collection('games').doc('game_001');
        DocumentSnapshot snap = await transaction.get(gameRef);
        if (!snap.exists) return;
        
        var data = snap.data() as Map<String, dynamic>;
        Timestamp? ts = data['turnEndTime'];
        
        // 念のため、本当に時間が過ぎているか再確認
        if (ts != null && ts.toDate().difference(DateTime.now()).inSeconds <= 0) {
          String current = data['currentTurn'] ?? 'RED';
          String next = current == 'RED' ? 'BLUE' : 'RED'; // 相手のチームに切り替え
          int duration = data['turnDurationMinutes'] ?? 10;
          
          transaction.update(gameRef, {
            'currentTurn': next,
            'turnEndTime': Timestamp.fromDate(DateTime.now().add(Duration(minutes: duration))),
          });
        }
      });
    } catch (e) {
      print("Turn pass error: $e");
    } finally {
      _isPassing = false;
    }
  }

  String _normalizeStationName(String name) {
    if (name == '難波' || name == '大阪難波' || name == 'ＪＲ難波' || name == '近鉄難波') return 'なんば';
    if (name == '三ノ宮' || name == '神戸三宮' || name == '阪神神戸三宮' || name == '阪急神戸三宮') return '三宮';
    if (name == '大阪' || name == '大阪梅田' || name == '東梅田' || name == '西梅田') return '梅田';
    if (name == '大阪阿部野橋') return '天王寺';
    return name;
  }

  void _startLocationTracking() {
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _currentSpeed = (position.speed * 3.6);

      var station = await TrainApiService.getNearestStation(position.latitude, position.longitude);
      
      if (mounted) {
        setState(() {
          _nearestStation = station?['name'] ?? "駅圏外";
          if (_currentLine == "---" || _currentLine == "駅圏外") {
             _currentLine = station?['line'] ?? "---";
          }
        });
      }

      String uid = FirebaseAuth.instance.currentUser!.uid;
      try {
        await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({
          'location': {'lat': position.latitude, 'lng': position.longitude},
          'currentStation': _nearestStation,
          'currentLine': _currentLine,
          'speed': _currentSpeed,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) { }
    });
  }

  void _startExposureCheck() {
    _exposureTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (_gameData['mode'] != 'C') return;
      String uid = FirebaseAuth.instance.currentUser!.uid;
      var doc = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).get();
      if (!doc.exists) return;
      Timestamp? lastCheckIn = doc.data()?['lastCheckInAt'];
      if (lastCheckIn != null) {
        if (DateTime.now().difference(lastCheckIn.toDate()).inMinutes >= 30) {
           await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({'isExposed': true});
        }
      }
    });
  }

  Future<void> _checkIn() async {
    setState(() => _isLoading = true);
    String uid = FirebaseAuth.instance.currentUser!.uid;
    String mode = _gameData['mode'] ?? 'A';
    List<dynamic> allowedLines = _gameData['allowedLines'] ?? [];
    List<dynamic> allowedStations = _gameData['allowedStations'] ?? [];
    bool penaltyEnabled = _gameData['settings_penaltyEnabled'] ?? false; 

    try {
      if (_nearestStation == "---" || _nearestStation == "駅圏外") throw "駅の近くにいません。";

      List<String> possibleLines = [];
      if (allowedLines.isNotEmpty) {
        for (String line in allowedLines) {
          var stations = await TrainApiService.getStationsByLine(line);
          String normalizedCurrent = _normalizeStationName(_nearestStation);
          if (stations.any((s) => _normalizeStationName(s['name']) == normalizedCurrent)) {
            possibleLines.add(line);
          }
        }
      }

      String selectedLine = _currentLine;
      if (possibleLines.length > 1) {
        String? choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => SimpleDialog(
            backgroundColor: Colors.grey[900],
            title: Text("路線を選択\n($_nearestStation)", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            children: possibleLines.map((line) => SimpleDialogOption(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              onPressed: () => Navigator.pop(ctx, line),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(line, style: const TextStyle(color: Colors.white, fontSize: 18)), const Divider(color: Colors.grey)]),
            )).toList(),
          ),
        );
        if (choice == null) return; 
        selectedLine = choice;
      } else if (possibleLines.length == 1) {
        selectedLine = possibleLines.first;
      } else {
        if (allowedLines.isNotEmpty) throw "この駅は許可された路線に含まれていません！"; 
      }

      setState(() => _currentLine = selectedLine);
      await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({
        'currentLine': selectedLine,
      });

      if (allowedStations.isNotEmpty) {
        String normalizedCurrent = _normalizeStationName(_nearestStation);
        bool isAllowed = allowedStations.any((s) => _normalizeStationName(s.toString()) == normalizedCurrent);
        if (!isAllowed) throw "この駅は許可されていません！";
      }

      if (mode == 'A') await _handleModeA(uid);
      else if (mode == 'B') await _handleModeB(uid);
      else if (mode == 'C') await _handleModeC(uid);
      else if (mode == 'D') await _handleModeD(uid);
      else if (mode == 'E') await _handleModeE(uid);
      else if (mode == 'F') await _handleModeF(uid);

      if (mode != 'E') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$_nearestStation ($selectedLine) にチェックイン！")));
      }
    } catch (e) {
      String err = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("エラー: $err"), backgroundColor: Colors.red));
      
      bool isOthelloRuleError = err.contains("挟める相手の石がありません");
      bool isTurnError = err.contains("ターンです"); // 相手のターンの時のエラーもペナルティから除外
      
      if (penaltyEnabled && !isOthelloRuleError && !isTurnError && (err.contains("許可されていません") || err.contains("含まれていません"))) {
        await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({
          'penaltyUntil': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
        });
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleModeA(String uid) async { await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({'visitedStations': FieldValue.arrayUnion([_nearestStation]), 'stationCount': FieldValue.increment(1)}); }
  
  Future<void> _handleModeB(String uid) async { 
    if (_finalGoalStation == null) throw "まずはゴールを決めてください！"; if (_nextGoalStation == null) throw "サイコロを振って進む駅を決めてください！"; 
    if (_normalizeStationName(_nextGoalStation!) == _normalizeStationName(_nearestStation)) { 
      await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({'nextGoalStation': null, 'score': FieldValue.increment(100)}); 
      if (_normalizeStationName(_nearestStation) == _normalizeStationName(_finalGoalStation!)) _showGoalDialog(); 
      else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("チェックポイント到達！サイコロを振ってください。"))); 
    } else { throw "ここは目的地ではありません。次は: $_nextGoalStation"; } 
  }
  
  Future<void> _handleModeC(String uid) async { await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({'isExposed': false, 'lastCheckInAt': FieldValue.serverTimestamp()}); }
  Future<void> _handleModeD(String uid) async { String myTeam = _myData['team'] ?? 'RED'; await FirebaseFirestore.instance.collection('games').doc('game_001').collection('claimed_stations').doc(_nearestStation).set({'name': _nearestStation, 'ownerTeam': myTeam, 'ownerUid': uid, 'claimedAt': FieldValue.serverTimestamp(), 'lat': _myData['location']['lat'], 'lng': _myData['location']['lng'], 'line': _currentLine}); }
  
  Future<void> _handleModeE(String uid) async { 
    String myTeam = _myData['team'] ?? 'RED'; 
    bool turnBased = _gameData['settings_othelloTurnBased'] ?? false; 
    
    if (turnBased) { 
      String currentTurn = _gameData['currentTurn'] ?? 'RED'; 
      if (currentTurn != myTeam) throw "現在は ${currentTurn} チームのターンです。"; 
    } 
    
    var boardRef = FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board'); 
    var allCells = await boardRef.get();
    QueryDocumentSnapshot? targetDoc;
    String normalizedCurrent = _normalizeStationName(_nearestStation);

    for (var doc in allCells.docs) {
      if (_normalizeStationName(doc['station']) == normalizedCurrent) {
        targetDoc = doc;
        break;
      }
    }

    if (targetDoc == null) throw "この駅はオセロ盤に含まれていません"; 
    
    Map<String, dynamic> docData = targetDoc.data() as Map<String, dynamic>;
    if (docData.containsKey('ownerTeam') && docData['ownerTeam'] != null) {
      throw "既に石が置かれています"; 
    }

    int boardSize = _gameData['settings_boardSize'] ?? 8; 

    bool success = await OthelloLogic.tryPlacePiece(targetDoc['station'], myTeam, boardSize);

    if (!success) {
      throw "挟める相手の石がありません！ルールの範囲外です。";
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("石を置き、相手を裏返しました！"), backgroundColor: Colors.orange)); 
  }
  
  Future<void> _handleModeF(String uid) async { 
    List<dynamic> card = _myData['bingoCard'] ?? []; 
    if (card.isEmpty) throw "ビンゴカードがありません。"; 
    
    bool hit = false; 
    String normalizedCurrent = _normalizeStationName(_nearestStation);

    for (var cell in card) { 
      if (_normalizeStationName(cell['station']) == normalizedCurrent && cell['isOpen'] == false) { 
        cell['isOpen'] = true; 
        hit = true; 
      } 
    } 
    if (!hit) return; 
    
    int size = _gameData['settings_boardSize'] ?? 5; 
    int lines = _checkBingoLines(card, size); 
    int myRank = _myData['bingoRank'] ?? 0; 
    
    if (lines > 0 && myRank == 0) { 
      await FirebaseFirestore.instance.runTransaction((transaction) async { 
        DocumentReference gameRef = FirebaseFirestore.instance.collection('games').doc('game_001'); 
        DocumentSnapshot gameSnap = await transaction.get(gameRef); 
        int currentRank = (gameSnap['bingoCompleteCount'] ?? 0) + 1; 
        transaction.update(gameRef, {'bingoCompleteCount': currentRank}); 
        transaction.update(FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid), { 'bingoCard': card, 'bingoLines': lines, 'bingoRank': currentRank }); 
        myRank = currentRank; 
      }); 
      _showDialog("BINGO!", "$myRank 位でビンゴ達成です！"); 
    } else { 
      await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({ 'bingoCard': card, 'bingoLines': lines }); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ビンゴカードの穴を開けました！"), backgroundColor: Colors.greenAccent)); 
    } 
  }
  
  int _checkBingoLines(List<dynamic> card, int size) { bool isOpen(int i) => (i < card.length) && (card[i]['isOpen'] == true); int count = 0; for (int y = 0; y < size; y++) { bool win = true; for (int x = 0; x < size; x++) if (!isOpen(y * size + x)) win = false; if (win) count++; } for (int x = 0; x < size; x++) { bool win = true; for (int y = 0; y < size; y++) if (!isOpen(y * size + x)) win = false; if (win) count++; } bool diag1 = true; for (int i = 0; i < size; i++) if (!isOpen(i * size + i)) diag1 = false; if (diag1) count++; bool diag2 = true; for (int i = 0; i < size; i++) if (!isOpen(i * size + (size - 1 - i))) diag2 = false; if (diag2) count++; return count; }
  void _decideFinalGoal(String uid) async { if (_nearestStation == "---" || _nearestStation == "駅圏外") { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("駅の近くに移動してください"))); return; } try { 
    List<String> possibleLines = []; List<dynamic> allowedLines = _gameData['allowedLines'] ?? []; if(allowedLines.isNotEmpty) for(String l in allowedLines) { var s = await TrainApiService.getStationsByLine(l); if(s.any((x)=>_normalizeStationName(x['name'])==_normalizeStationName(_nearestStation))) possibleLines.add(l); } String targetLine = _currentLine; if(possibleLines.length > 1) { String? choice = await showDialog<String>(context: context, barrierDismissible: false, builder: (ctx) => SimpleDialog(title: const Text("路線を選択"), children: possibleLines.map((l)=>SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,l), child: Text(l))).toList())); if(choice==null) return; targetLine = choice; } else if(possibleLines.length==1) targetLine = possibleLines.first;
    var stations = await TrainApiService.getStationsByLine(targetLine); if (stations.isEmpty) throw "路線情報が取得できません ($targetLine)"; String goal = stations[Random().nextInt(stations.length)]['name']; await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({ 'finalGoalStation': goal }); _showDialog("ゴール決定", "あなたの最終目的地は\n「$goal」\nです！\n($targetLine)\n\nサイコロを振って進んでください。"); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("エラー: $e"))); } }
  void _rollDiceAndMove(String uid) { showDialog(context: context, barrierDismissible: false, builder: (ctx) => DiceDialog(onRollFinished: (dice) async { var stations = await TrainApiService.getStationsByLine(_currentLine); if (stations.isEmpty) return; int currentIndex = stations.indexWhere((s) => _normalizeStationName(s['name']) == _normalizeStationName(_nearestStation)); if (currentIndex == -1) currentIndex = 0; int goalIndex = stations.indexWhere((s) => _normalizeStationName(s['name']) == _normalizeStationName(_finalGoalStation!)); int direction = 1; if (goalIndex != -1 && goalIndex < currentIndex) direction = -1; int nextIndex = currentIndex + (dice * direction); if (nextIndex < 0) nextIndex = 0; if (nextIndex >= stations.length) nextIndex = stations.length - 1; String nextStation = stations[nextIndex]['name']; await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).update({ 'nextGoalStation': nextStation, 'diceResult': dice }); _showDialog("移動指示", "出目は「$dice」でした。\n次の目的地は\n「$nextStation」\nです！"); })); }
  void _showDialog(String title, String content) { showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(content), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))])); }
  void _showGoalDialog() { showDialog(context: context, builder: (ctx) => const AlertDialog(title: Text("GOAL!!"), content: Text("おめでとうございます！\n目的地に到達しました！"), actions: [])); }

  Widget _buildPenaltyScreen(DateTime penaltyEnd) {
    if (_penaltyTimer == null) {
      _penaltyTimer = Timer.periodic(const Duration(seconds: 1), (timer) => setState(() {}));
    }
    Duration remaining = penaltyEnd.difference(DateTime.now());
    if (remaining.isNegative) {
      _penaltyTimer?.cancel();
      _penaltyTimer = null;
      FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(FirebaseAuth.instance.currentUser!.uid).update({'penaltyUntil': null});
      return const SizedBox();
    }
    String timerText = "${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}";
    return Container(color: Colors.red.withOpacity(0.95), width: double.infinity, height: double.infinity, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.block, color: Colors.white, size: 100), const SizedBox(height: 20), const Text("PENALTY", style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 5)), const SizedBox(height: 10), const Text("不正なチェックインを検知しました\nしばらく操作できません", style: TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center), const SizedBox(height: 40), Text(timerText, style: const TextStyle(color: Colors.white, fontSize: 60, fontFamily: 'Courier', fontWeight: FontWeight.bold))]));
  }

  // ★追加: 画面上部に表示する、ターンと残り時間のバナー
  Widget _buildTurnBanner() {
    String currentTurn = _gameData['currentTurn'] ?? 'RED';
    Timestamp? turnEndTs = _gameData['turnEndTime'];
    int remaining = 0;
    if (turnEndTs != null) {
      remaining = turnEndTs.toDate().difference(DateTime.now()).inSeconds;
      if (remaining < 0) remaining = 0;
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: currentTurn == 'RED' ? Colors.redAccent : Colors.blueAccent,
      child: Text(
        "$currentTurn TEAM ターン  |  残り時間 ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}",
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("TRAIN RUN", style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, letterSpacing: 2)),
        backgroundColor: Colors.grey[900],
        leading: IconButton(icon: const Icon(Icons.logout), onPressed: () { FirebaseAuth.instance.signOut(); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
        actions: [
           IconButton(icon: const Icon(Icons.discord, color: Colors.indigoAccent), onPressed: () => Navigator.push(context, PageRouteBuilder(opaque: false, pageBuilder: (ctx, _, __) => const DiscordScreen()))),
           IconButton(icon: const Icon(Icons.mail, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MailScreen()))),
           IconButton(icon: const Icon(Icons.settings), onPressed: () { if (widget.myRole == 'GAME MASTER') Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsAppScreen())); }),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('games').doc('game_001').snapshots(),
        builder: (context, gameSnap) {
          if (!gameSnap.hasData || !gameSnap.data!.exists) return const Center(child: CircularProgressIndicator());
          
          _gameData = gameSnap.data!.data() as Map<String, dynamic>;
          String mode = _gameData['mode'] ?? 'A';
          Timestamp? endTime = _gameData['endTime'];
          
          List<dynamic> allowedStations = _gameData['allowedStations'] ?? [];
          bool isStationValid = true;
          String normalizedCurrent = _normalizeStationName(_nearestStation);
          
          if (_nearestStation == "---" || _nearestStation == "駅圏外") {
            isStationValid = false;
          } else if (allowedStations.isNotEmpty) {
            isStationValid = allowedStations.any((s) => _normalizeStationName(s.toString()) == normalizedCurrent);
          }
          
          if (_gameData['status'] == 'FINISHED') return const Center(child: Text("GAME FINISHED", style: TextStyle(color: Colors.white, fontSize: 30)));

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
            builder: (context, mySnap) {
              if (!mySnap.hasData) return const Center(child: CircularProgressIndicator());
              _myData = mySnap.data!.data() as Map<String, dynamic>;
              
              Widget overlay = const SizedBox();
              if (_myData['penaltyUntil'] != null) {
                DateTime penaltyEnd = (_myData['penaltyUntil'] as Timestamp).toDate();
                if (penaltyEnd.isAfter(DateTime.now())) {
                  overlay = _buildPenaltyScreen(penaltyEnd);
                }
              }

              _totalDistance = (_myData['totalDistance'] ?? 0).toDouble();
              _visitedCount = _myData['stationCount'] ?? 0;
              _nextGoalStation = _myData['nextGoalStation'];
              _finalGoalStation = _myData['finalGoalStation'];

              return Stack(
                children: [
                  Column(
                    children: [
                      // ★追加: オセロのターン制モードがONならバナーを表示！
                      if (mode == 'E' && (_gameData['settings_othelloTurnBased'] ?? false))
                        _buildTurnBanner(),
                        
                      _buildDashboard(mode, endTime),
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("NEAREST STATION", style: GoogleFonts.orbitron(color: Colors.grey, fontSize: 12)),
                              Text(_nearestStation, style: GoogleFonts.notoSansJp(color: isStationValid ? Colors.white : Colors.grey[700], fontSize: 32, fontWeight: FontWeight.bold)),
                              Text(_currentLine, style: const TextStyle(color: Colors.greenAccent, fontSize: 14)),
                              const SizedBox(height: 30),
                              GestureDetector(
                                onTap: _isLoading ? null : _checkIn,
                                child: Container(
                                  width: 200, height: 200,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.transparent, border: Border.all(color: isStationValid ? Colors.orangeAccent : Colors.grey, width: 4), boxShadow: [if(isStationValid) BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 20)]),
                                  child: Center(child: _isLoading ? const CircularProgressIndicator(color: Colors.orangeAccent) : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.touch_app, size: 50, color: isStationValid ? Colors.orangeAccent : Colors.grey), Text("CHECK IN", style: GoogleFonts.orbitron(color: isStationValid ? Colors.white : Colors.grey, fontSize: 20, fontWeight: FontWeight.bold))])),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 60, top: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              FloatingActionButton(heroTag: "map_btn", backgroundColor: Colors.blueAccent, child: const Icon(Icons.map, color: Colors.white, size: 30), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(myRole: widget.myRole, myName: widget.myName)))),
                              FloatingActionButton(heroTag: "vision_btn", backgroundColor: Colors.green, child: const Icon(Icons.list_alt, color: Colors.white, size: 30), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrainVisionScreen(myRole: widget.myRole, myName: widget.myName)))),
                              if (mode == 'B')
                                if (_finalGoalStation == null) FloatingActionButton.extended(heroTag: "goal_btn", label: const Text("ゴールを決める"), icon: const Icon(Icons.flag), backgroundColor: Colors.pinkAccent, onPressed: () => _decideFinalGoal(FirebaseAuth.instance.currentUser!.uid))
                                else if (_nextGoalStation == null) FloatingActionButton(heroTag: "dice_btn", backgroundColor: Colors.purpleAccent, child: const Icon(Icons.casino, color: Colors.white, size: 30), onPressed: () => _rollDiceAndMove(FirebaseAuth.instance.currentUser!.uid))
                                else FloatingActionButton.extended(heroTag: "moving_btn", label: const Text("移動中..."), icon: const Icon(Icons.train), backgroundColor: Colors.grey, onPressed: null),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  overlay,
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDashboard(String mode, Timestamp? endTime) {
    String timeLeft = "--:--";
    if (endTime != null) {
      Duration diff = endTime.toDate().difference(DateTime.now());
      if (diff.isNegative) timeLeft = "FINISHED"; else timeLeft = "${diff.inHours}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}";
    }
    String info = "";
    if (mode == 'F') info = "\nBINGO: ${_myData['bingoLines'] ?? 0} LINE"; 

    return Container(
      padding: const EdgeInsets.all(15), color: Colors.grey[900],
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildMeter("TIME", timeLeft, Colors.redAccent), _buildMeter("SPEED", "${_currentSpeed.toStringAsFixed(1)} km/h", Colors.cyanAccent), _buildMeter("DIST", "${_totalDistance.toStringAsFixed(1)} km", Colors.yellowAccent)]),
          const Divider(color: Colors.grey),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildMeter("MODE", "Mode $mode$info", Colors.white),
            if (mode == 'A') _buildMeter("SCORE", "$_visitedCount St.", Colors.greenAccent),
            if (mode == 'B') Expanded(child: _buildMeter("NEXT", _nextGoalStation ?? "WAITING...", Colors.purpleAccent, isWide: true)),
            if (mode == 'B') Expanded(child: _buildMeter("GOAL", _finalGoalStation ?? "---", Colors.pinkAccent, isWide: true)),
            if (mode == 'F' && (_myData['bingoRank']??0) > 0) _buildMeter("RANK", "${_myData['bingoRank']}位", Colors.amber),
          ]),
        ],
      ),
    );
  }

  Widget _buildMeter(String label, String value, Color color, {bool isWide = false}) {
    return Column(crossAxisAlignment: isWide ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [Text(label, style: GoogleFonts.orbitron(fontSize: 10, color: Colors.grey)), Text(value, style: GoogleFonts.orbitron(fontSize: isWide ? 16 : 18, color: color, fontWeight: FontWeight.bold))]);
  }
}