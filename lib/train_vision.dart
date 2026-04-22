import 'dart:math';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';
import 'othello_logic.dart'; // ★追加: オセロ判定ロジック

class TrainVisionScreen extends StatefulWidget {
  final String myRole;
  final String myName;

  const TrainVisionScreen({
    super.key,
    required this.myRole,
    required this.myName,
  });

  @override
  State<TrainVisionScreen> createState() => _TrainVisionScreenState();
}

class _TrainVisionScreenState extends State<TrainVisionScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _glowController; // ★追加: ピカピカ光るアニメーション用
  
  List<String> _lines = [];
  Map<String, List<Map<String, dynamic>>> _stationsCache = {};
  bool _isLoading = true;
  String _currentLine = "";
  String _myTeam = "RED"; // ★追加: 自分のチームカラー
  
  bool _isOthelloMode = false;
  bool _isBingoMode = false;
  bool _isJintoriMode = false;
  bool _isSurvivalMode = false;
  bool _isSugorokuMode = false;
  int _boardSize = 8;
  
  // ★追加：ターン制用の変数
  bool _isTurnBased = false;
  String _currentTurnTeam = "RED";
  DateTime? _turnEndTime;

  String? _highlightedStation;
  List<String> _allowedStations = [];

  List<Map<String, dynamic>> _mailbox = [];
  int _unreadCount = 0;
  bool _showResultScreen = false;
  
  Timer? _gameTimer;
  int _remainingSeconds = 18000; // 5時間

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  String _normalizeStationName(String name) {
    if (name == '難波' || name == '大阪難波' || name == 'ＪＲ難波' || name == '近鉄難波' || name == '南海なんば') return 'なんば';
    if (name == '大阪' || name == '大阪梅田' || name == '東梅田' || name == '西梅田') return '梅田';
    if (name == '三ノ宮' || name == '神戸三宮' || name == '阪神神戸三宮' || name == '阪急神戸三宮') return '三宮';
    if (name == '大阪阿部野橋') return '天王寺';
    name = name.replaceAll(RegExp(r'^(ＪＲ|JR|山陽|京王|京急|京成|西武|東武|名鉄|近鉄|阪神|阪急|小田急|南海|西鉄)'), '');
    return name;
  }

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

  @override
  void initState() {
    super.initState();
    _initNotifications(); 
    _fetchGameData();
    _startTimer();
    
    // ★追加: 1秒かけて光り、1秒かけて消えるループアニメーション
    _glowController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 1)
    )..repeat(reverse: true);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendNotification("ゲームスタート！", "制限時間が始まりました。目的地へ向かってください！");
    });
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    
    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
  }

  void _startTimer() {
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          _checkTimeNotifications(_remainingSeconds);
        } else {
          timer.cancel();
          _sendNotification("ゲーム終了！", "制限時間になりました。結果を確認しましょう！");
          setState(() { _showResultScreen = true; });
        }
      });
    });
  }

  void _checkTimeNotifications(int seconds) {
    if (seconds == 1800) _sendNotification("残り時間のお知らせ", "残り30分です！");
    if (seconds == 600) _sendNotification("残り時間のお知らせ", "残り10分です！");
    if (seconds == 300) _sendNotification("残り時間のお知らせ", "残り5分です！");
  }

  Future<void> _sendNotification(String title, String content) async {
    setState(() {
      _mailbox.insert(0, {
        'time': DateTime.now(),
        'title': title, 
        'content': content,
        'read': false
      });
      _unreadCount++;
    });
    
    HapticFeedback.heavyImpact(); 

    await _flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecond, 
      title: title,
      body: content,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'train_vision_channel',
          'システム通知',
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  Future<void> _fetchGameData() async {
    var myDoc = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(FirebaseAuth.instance.currentUser!.uid).get();
    if (mounted && myDoc.exists) {
      setState(() {
        _currentLine = myDoc.data()?['currentLine'] ?? "";
        _myTeam = myDoc.data()?['team'] ?? 'RED';
      });
    }

    FirebaseFirestore.instance.collection('games').doc('game_001').snapshots().listen((doc) async {
      if (!doc.exists || !mounted) return;
      var data = doc.data()!;
      
      List<dynamic> allowedLines = data['allowedLines'] ?? [];
      List<dynamic> settingsStations = data['allowedStations'] ?? [];
      String mode = data['mode'] ?? 'A';
      
      setState(() {
        _isJintoriMode = (mode == 'D');
        _isOthelloMode = (mode == 'E');
        _isBingoMode = (mode == 'F');
        _isSurvivalMode = (mode == 'C');
        _isSugorokuMode = (mode == 'B');
        _boardSize = data['settings_boardSize'] ?? 8;
        _isTurnBased = data['othelloTurnBased'] ?? false;
        _currentTurnTeam = data['currentTurn'] ?? 'RED';
        if (data['turnEndTime'] != null) {
          _turnEndTime = (data['turnEndTime'] as Timestamp).toDate();
        }
      });

      if (_lines.isEmpty) {
        for (String line in allowedLines) {
          var stations = await TrainApiService.getStationsByLine(line);
          _stationsCache[line] = stations;
        }
        
        Set<String> activeStations = {};
        if (mode == 'E') {
          var snap = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').get();
          for (var d in snap.docs) activeStations.add(_normalizeStationName(d.data()['station']));
        } else if (mode == 'F') {
          List card = myDoc.data()?['bingoCard'] ?? [];
          for (var c in card) activeStations.add(_normalizeStationName(c['station']));
        } else {
          activeStations.addAll(settingsStations.map((e) => _normalizeStationName(e.toString())));
        }

        if (mounted) {
          setState(() {
            _lines = List<String>.from(allowedLines);
            _allowedStations = activeStations.toList();
            _isLoading = false;
            int initialIndex = 0;
            if (_lines.contains(_currentLine)) initialIndex = _lines.indexOf(_currentLine) + 1; 
            _tabController = TabController(length: _lines.length + 1, vsync: this, initialIndex: initialIndex);
          });
        }
      }
    });
  }

  void _showRouteSearch() {
    String startStation = "";
    String endStation = "";
    List<String> routeResult = [];
    List<String> allStations = _stationsCache.values.expand((list) => list.map((s) => s['name'] as String)).toSet().toList();

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            void calculateRoute() {
              if (startStation.isEmpty || endStation.isEmpty) return;
              String start = _normalizeStationName(startStation);
              String end = _normalizeStationName(endStation);
              if (start == end) {
                setModalState(() { routeResult = ["出発駅と到着駅が同じです"]; });
                return;
              }

              Map<String, List<Map<String, String>>> graph = {};
              for (String line in _stationsCache.keys) {
                List<Map<String, dynamic>> stations = _stationsCache[line]!;
                if (stations.isEmpty) continue;
                String firstStation = stations.first['name'];
                String lastStation = stations.last['name'];

                for (int i = 0; i < stations.length; i++) {
                  String current = _normalizeStationName(stations[i]['name']);
                  if (!graph.containsKey(current)) graph[current] = [];
                  if (i > 0) {
                    String prev = _normalizeStationName(stations[i - 1]['name']);
                    graph[current]!.add({'to': prev, 'line': line, 'dir': firstStation});
                  }
                  if (i < stations.length - 1) {
                    String next = _normalizeStationName(stations[i + 1]['name']);
                    graph[current]!.add({'to': next, 'line': line, 'dir': lastStation});
                  }
                }
              }

              if (!graph.containsKey(start) || !graph.containsKey(end)) {
                setModalState(() { routeResult = ["入力された駅間の経路が見つかりません"]; });
                return;
              }

              Queue<List<Map<String, String>>> queue = Queue();
              Set<String> visited = {start};

              for (var edge in graph[start]!) {
                queue.add([edge]);
                visited.add(edge['to']!);
              }

              List<Map<String, String>>? shortestPath;

              while (queue.isNotEmpty) {
                var path = queue.removeFirst();
                String current = path.last['to']!;

                if (current == end) {
                  shortestPath = path;
                  break;
                }

                for (var edge in graph[current]!) {
                  if (!visited.contains(edge['to'])) {
                    visited.add(edge['to']!);
                    List<Map<String, String>> newPath = List.from(path)..add(edge);
                    queue.add(newPath);
                  }
                }
              }

              if (shortestPath == null) {
                setModalState(() { routeResult = ["ルートが見つかりませんでした"]; });
                return;
              }

              List<String> result = [];
              result.add("🟢 出発: $startStation");

              String currentLine = shortestPath.first['line']!;
              String currentDir = shortestPath.first['dir']!;
              result.add("🚆 乗車: $currentLine ($currentDir行)");

              int stationCount = 0;
              for (int i = 0; i < shortestPath.length; i++) {
                var step = shortestPath[i];
                if (step['line'] != currentLine) {
                  result.add("↓ ($stationCount駅通過)");
                  String transferStation = shortestPath[i - 1]['to']!;
                  result.add("🔄 乗換: $transferStation");

                  currentLine = step['line']!;
                  currentDir = step['dir']!;
                  result.add("🚆 乗車: $currentLine ($currentDir行)");
                  stationCount = 1;
                } else {
                  stationCount++;
                }
              }

              result.add("↓ ($stationCount駅通過)");
              result.add("🏁 到着: $endStation");

              setModalState(() { routeResult = result; });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("経路探索ツール", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))
                    ],
                  ),
                  const SizedBox(height: 10),
                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') return const Iterable<String>.empty();
                      return allStations.where((option) => option.contains(textEditingValue.text));
                    },
                    onSelected: (selection) => startStation = selection,
                    fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(labelText: "出発駅", prefixIcon: Icon(Icons.trip_origin, color: Colors.green)),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') return const Iterable<String>.empty();
                      return allStations.where((option) => option.contains(textEditingValue.text));
                    },
                    onSelected: (selection) => endStation = selection,
                    fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(labelText: "到着駅", prefixIcon: Icon(Icons.place, color: Colors.red)),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        calculateRoute();
                      },
                      child: const Text("ルートを検索", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const Divider(height: 40, thickness: 2),
                  Expanded(
                    child: routeResult.isEmpty
                      ? const Center(child: Text("出発駅と到着駅を入力してください", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: routeResult.length,
                          itemBuilder: (context, index) {
                            String text = routeResult[index];
                            bool isHighlight = text.contains("出発") || text.contains("乗車") || text.contains("到着") || text.contains("乗換");
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(text, style: TextStyle(
                                fontSize: isHighlight ? 16 : 14,
                                fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                                color: text.contains("↓") ? Colors.grey[600] : Colors.black
                              )),
                            );
                          },
                        ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _showMailbox() {
    setState(() => _unreadCount = 0);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey[900], borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("受信箱", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx))
                  ]
                ),
              ),
              Expanded(
                child: _mailbox.isEmpty
                  ? const Center(child: Text("通知はありません", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _mailbox.length,
                      itemBuilder: (ctx, index) {
                        var mail = _mailbox[index];
                        String timeStr = "${mail['time'].hour.toString().padLeft(2,'0')}:${mail['time'].minute.toString().padLeft(2,'0')}";
                        return ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.mail, color: Colors.white, size: 18)),
                          title: Text(mail['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(mail['content']),
                          trailing: Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        );
                      },
                    ),
              )
            ],
          ),
        );
      }
    );
  }

  Widget _buildTurnBanner() {
    int remaining = 0;
    if (_turnEndTime != null) {
      remaining = _turnEndTime!.difference(DateTime.now()).inSeconds;
      if (remaining < 0) remaining = 0;
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: _currentTurnTeam == 'RED' ? Colors.redAccent : Colors.blueAccent,
      child: Text(
        "$_currentTurnTeam TEAM ターン  |  残り ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}",
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Colors.white, body: Center(child: CircularProgressIndicator()));
    if (_showResultScreen) return _buildResultScreen();

    String firstTabTitle = "全線一覧";
    IconData firstTabIcon = Icons.grid_view;
    if (_isOthelloMode) {
      firstTabTitle = "オセロ盤";
      firstTabIcon = Icons.grid_4x4;
    }
    if (_isBingoMode) {
      firstTabTitle = "BINGO CARD";
      firstTabIcon = Icons.grid_on;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(firstTabTitle == "BINGO CARD" ? "BINGO VISION" : "TRAIN VISION", style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _showRouteSearch),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(icon: const Icon(Icons.notifications), onPressed: _showMailbox),
              if (_unreadCount > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('$_unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                )
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          indicatorColor: Colors.greenAccent,
          tabs: [
            Tab(icon: Icon(firstTabIcon), text: firstTabTitle),
            ..._lines.map((line) => Tab(text: line)),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_isOthelloMode && _isTurnBased) _buildTurnBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildSpecialTab(), 
                ..._lines.map((line) {
                  if (line.contains("環状") || line.contains("山手")) {
                    return _buildLoopLineView(line);
                  } else {
                    return _buildVerticalLineView(line);
                  }
                }),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.redAccent,
        onPressed: () => setState(() => _showResultScreen = true),
        label: const Text("結果を見る"),
        icon: const Icon(Icons.emoji_events),
      ),
    );
  }

  Widget _buildResultScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("RESULT", style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 5)),
              const SizedBox(height: 40),
              if (_isOthelloMode) _buildOthelloResultAnimation(),
              if (_isJintoriMode) _buildJintoriPieChart(),
              if (_isBingoMode || _isSugorokuMode || _isSurvivalMode) _buildLeaderboardResult(),
              const SizedBox(height: 50),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                onPressed: () => setState(() => _showResultScreen = false),
                child: const Text("マップに戻る", style: TextStyle(fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOthelloResultAnimation() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        int redCount = 0;
        int blueCount = 0;
        for (var doc in snapshot.data!.docs) {
          var data = doc.data() as Map<String, dynamic>;
          if (data['ownerTeam'] == 'RED') redCount++;
          if (data['ownerTeam'] == 'BLUE') blueCount++;
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _animatedCounter(redCount, Colors.redAccent, "RED"),
            const Text("VS", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            _animatedCounter(blueCount, Colors.blueAccent, "BLUE"),
          ],
        );
      }
    );
  }

  Widget _animatedCounter(int targetValue, Color color, String label) {
    return TweenAnimationBuilder<int>(
      key: ValueKey(targetValue),
      tween: IntTween(begin: 0, end: targetValue),
      duration: const Duration(seconds: 2),
      builder: (context, value, child) {
        if (value > 0 && value < targetValue) HapticFeedback.selectionClick();
        if (value == targetValue) HapticFeedback.heavyImpact();
        return Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            Text('$value', style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.bold)),
          ],
        );
      },
    );
  }

  Widget _buildJintoriPieChart() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('claimed_stations').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        int redCount = 0;
        int blueCount = 0;
        for (var doc in snapshot.data!.docs) {
          var data = doc.data() as Map<String, dynamic>;
          if (data['ownerTeam'] == 'RED') redCount++;
          if (data['ownerTeam'] == 'BLUE') blueCount++;
        }

        return Column(
          children: [
            SizedBox(
              width: 200, height: 200,
              child: CustomPaint(painter: PieChartPainter(redCount, blueCount)), 
            ),
            const SizedBox(height: 20),
            Text("RED: $redCount駅  /  BLUE: $blueCount駅", style: const TextStyle(color: Colors.white, fontSize: 18)),
          ],
        );
      }
    );
  }

  Widget _buildLeaderboardResult() {
    List<String> survivors = ["プレイヤーA", "プレイヤーB", "プレイヤーC"];
    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(_isSurvivalMode ? "SURVIVORS" : "ランキング", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...List.generate(survivors.length, (index) {
            return ListTile(
              leading: CircleAvatar(backgroundColor: Colors.amber, child: Text('${index + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
              title: Text(survivors[index], style: const TextStyle(color: Colors.white, fontSize: 18)),
            );
          })
        ],
      ),
    );
  }

  Widget _buildSpecialTab() {
    if (_isOthelloMode) return _buildOthelloBoard();
    if (_isBingoMode) return _buildBingoCard();
    return _buildJintoriOverview();
  }

  Widget _buildExcelGrid({required int rows, required int cols, required Widget Function(int x, int y) cellBuilder}) {
    const double cellSize = 70.0; 
    const double headerSize = 30.0;
    List<Widget> colHeaders = [];
    for (int x = 0; x < cols; x++) {
      colHeaders.add(
        Container(
          width: cellSize, 
          height: headerSize, 
          alignment: Alignment.center, 
          decoration: BoxDecoration(color: Colors.grey[200], border: Border.all(color: Colors.grey)), 
          child: Text(String.fromCharCode(65 + x), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))
        )
      );
    }
    
    List<TableRow> tableRows = [];
    for (int y = 0; y < rows; y++) {
      List<Widget> rowChildren = [];
      rowChildren.add(
        Container(
          width: headerSize, 
          height: cellSize, 
          alignment: Alignment.center, 
          decoration: BoxDecoration(color: Colors.grey[200], border: Border.all(color: Colors.grey)), 
          child: Text("${y + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))
        )
      );
      
      for (int x = 0; x < cols; x++) {
        rowChildren.add(SizedBox(width: cellSize, height: cellSize, child: cellBuilder(x, y)));
      }
      tableRows.add(TableRow(children: rowChildren));
    }
    
    return SingleChildScrollView(
      scrollDirection: Axis.vertical, 
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Row(
              children: [
                Container(width: headerSize, height: headerSize, color: Colors.grey[300]), 
                ...colHeaders
              ]
            ), 
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(), 
              border: TableBorder.all(color: Colors.grey, width: 0.5), 
              children: tableRows
            )
          ]
        )
      )
    );
  }

  Widget _buildBingoCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        var data = snapshot.data!.data() as Map<String, dynamic>;
        List<dynamic> card = data['bingoCard'] ?? [];
        int rank = data['bingoRank'] ?? 0;

        if (card.isEmpty) return const Center(child: Text("カードが配布されていません", style: TextStyle(color: Colors.black)));

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10), 
              width: double.infinity, 
              color: rank > 0 ? Colors.amber : Colors.blue[900],
              child: Text(
                rank > 0 ? "🎉 BINGO達成! $rank位" : "対象駅で穴を開けろ！", 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), 
                textAlign: TextAlign.center
              ),
            ),
            Expanded(
              child: _buildExcelGrid(
                rows: _boardSize, 
                cols: _boardSize,
                cellBuilder: (x, y) {
                  int index = y * _boardSize + x;
                  var cell = card.firstWhere((e) => e['index'] == index, orElse: () => {'station': '', 'isOpen': false});
                  bool isOpen = cell['isOpen']; 
                  String name = cell['station'];
                  
                  return Container(
                    color: isOpen ? Colors.orange[100] : Colors.white, 
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center, 
                      children: [
                        Text(
                          name, 
                          textAlign: TextAlign.center, 
                          style: TextStyle(color: isOpen ? Colors.black : Colors.black87, fontWeight: FontWeight.bold, fontSize: 10), 
                          overflow: TextOverflow.ellipsis, 
                          maxLines: 3
                        ),
                        if(isOpen) const Icon(Icons.circle_outlined, color: Colors.red, size: 40),
                      ]
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOthelloBoard() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        Map<String, Map<String, dynamic>> boardData = {}; 
        for (var doc in snapshot.data!.docs) { 
          var d = doc.data() as Map<String, dynamic>; 
          boardData["${d['x']}_${d['y']}"] = d; 
        }
        
        int red = 0;
        int blue = 0; 
        boardData.values.forEach((v) { 
          if (v['ownerTeam'] == 'RED') red++; 
          if (v['ownerTeam'] == 'BLUE') blue++; 
        });
        
        // ★追加: ピカピカ光らせる対象チームを決定
        String highlightTeam = _myTeam;
        if (widget.myRole == 'GAME MASTER' || widget.myRole == 'GM' || widget.myRole == 'developer' || widget.myRole == 'ADMIN') {
          highlightTeam = _currentTurnTeam; // GMは現在のターンのチームの置ける場所を見る
        } else if (_isTurnBased && _currentTurnTeam != _myTeam) {
          highlightTeam = ""; // ターン制の場合、自分のターンじゃない時は光らせない
        }

        // 盤面全体から「置ける場所」のリストを抽出
        List<String> validMoves = [];
        if (highlightTeam.isNotEmpty) {
          validMoves = OthelloLogic.getValidMoves(highlightTeam, boardData, _boardSize);
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0), 
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                children: [
                  Text("RED: $red", style: const TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold)), 
                  Text("BLUE: $blue", style: const TextStyle(color: Colors.blueAccent, fontSize: 20, fontWeight: FontWeight.bold))
                ]
              )
            ), 
            Expanded(
              child: _buildExcelGrid(
                rows: _boardSize, 
                cols: _boardSize,
                cellBuilder: (x, y) {
                  var cell = boardData["${x}_$y"]; 
                  String stationName = cell?['station'] ?? ""; 
                  String? owner = cell?['ownerTeam']; 
                  
                  // このマスが置ける場所かどうかを判定
                  bool isValidMove = validMoves.contains("${x}_$y");

                  Widget content = Container(
                    color: Colors.white, 
                    alignment: Alignment.center, 
                    child: owner != null 
                      ? Container(
                          width: 40, 
                          height: 40, 
                          decoration: BoxDecoration(color: owner == 'RED' ? Colors.red : Colors.blue, shape: BoxShape.circle), 
                          alignment: Alignment.center, 
                          child: Text(stationName, style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 2)
                        ) 
                      : Text(stationName, style: const TextStyle(fontSize: 10, color: Colors.black), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 2)
                  ); 

                  // ★置ける場所なら、アニメーションで光らせる！
                  if (isValidMove) {
                    return AnimatedBuilder(
                      animation: _glowController,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            // 枠線と影の強さが0.0〜1.0で変化してホタルのように光る
                            border: Border.all(color: Colors.amber, width: 2 + (_glowController.value * 2)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withOpacity(0.3 + (_glowController.value * 0.3)), 
                                blurRadius: 5 + (_glowController.value * 10), 
                                spreadRadius: _glowController.value * 3
                              )
                            ]
                          ),
                          child: content,
                        );
                      },
                    );
                  }
                  
                  // 置けない場所は普通に描画
                  return content;
                },
              ),
            ),
          ],
        );
      }
    );
  }
  
  Widget _buildJintoriOverview() { 
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('claimed_stations').snapshots(), 
      builder: (context, claimedSnap) { 
        Map<String, String> ownership = {}; 
        if (claimedSnap.hasData) {
          for (var doc in claimedSnap.data!.docs) {
            ownership[doc['name']] = doc['ownerTeam']; 
          }
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(10), 
          itemCount: _lines.length, 
          itemBuilder: (context, index) { 
            String lineName = _lines[index]; 
            List<Map<String, dynamic>> stations = _stationsCache[lineName] ?? []; 
            Color lineColor = _getLineColor(lineName); 
            int redCount = 0; 
            int blueCount = 0; 
            
            for(var s in stations) { 
              String sName = s['name']; 
              if (ownership[sName] == 'RED') redCount++; 
              if (ownership[sName] == 'BLUE') blueCount++; 
            } 
            
            return Card(
              color: Colors.white, 
              elevation: 2, 
              margin: const EdgeInsets.only(bottom: 10), 
              child: Padding(
                padding: const EdgeInsets.all(12.0), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children: [
                        Text(lineName, style: TextStyle(color: lineColor, fontWeight: FontWeight.bold, fontSize: 16)), 
                        Text("RED: $redCount  BLUE: $blueCount", style: const TextStyle(color: Colors.black54, fontSize: 12))
                      ]
                    ), 
                    const SizedBox(height: 10), 
                    Wrap(
                      spacing: 4, 
                      runSpacing: 4, 
                      children: stations.map((s) { 
                        String sName = s['name']; 
                        Color dotColor = Colors.grey[200]!; 
                        if (ownership[sName] == 'RED') dotColor = Colors.redAccent; 
                        if (ownership[sName] == 'BLUE') dotColor = Colors.blueAccent; 
                        
                        return Tooltip(
                          message: sName, 
                          child: Container(
                            width: 12, 
                            height: 12, 
                            decoration: BoxDecoration(
                              color: dotColor, 
                              shape: BoxShape.circle, 
                              border: Border.all(color: Colors.black, width: 1)
                            )
                          )
                        ); 
                      }).toList()
                    )
                  ]
                )
              )
            ); 
          }
        ); 
      }
    ); 
  }

  Widget _buildLoopLineView(String lineName) { 
    return _buildCommonLineView(lineName, isLoop: true); 
  }
  
  Widget _buildVerticalLineView(String lineName) { 
    return _buildCommonLineView(lineName, isLoop: false); 
  }
  
  Widget _buildCommonLineView(String lineName, {required bool isLoop}) {
    List<Map<String, dynamic>> stations = _stationsCache[lineName] ?? []; 
    Color lineColor = _getLineColor(lineName);
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').snapshots(), 
      builder: (context, playerSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').snapshots(), 
          builder: (context, claimedSnap) {
            Map<String, String> ownership = {}; 
            if (claimedSnap.hasData) {
              for (var doc in claimedSnap.data!.docs) { 
                if(doc.data().toString().contains('ownerTeam') && doc['ownerTeam'] != null) {
                  ownership[doc['station']] = doc['ownerTeam']; 
                }
              }
            }
            
            Map<String, List<Map<String, dynamic>>> playerPos = {}; 
            if (playerSnap.hasData) {
              for (var doc in playerSnap.data!.docs) { 
                var pd = doc.data() as Map<String, dynamic>; 
                if (pd['currentStation'] != null) { 
                  if (playerPos[pd['currentStation']] == null) {
                    playerPos[pd['currentStation']] = []; 
                  }
                  playerPos[pd['currentStation']]!.add(pd); 
                } 
              }
            }

            if (isLoop) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  double centerX = constraints.maxWidth / 2; 
                  double centerY = constraints.maxHeight / 2; 
                  double radius = min(centerX, centerY) - 60;
                  
                  return Stack(
                    alignment: Alignment.center, 
                    children: [
                      Text(lineName, style: TextStyle(color: lineColor.withOpacity(0.1), fontSize: 30, fontWeight: FontWeight.bold)), 
                      Container(width: radius * 2, height: radius * 2, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: lineColor, width: 8))), 
                      ...List.generate(stations.length, (index) { 
                        final station = stations[index]; 
                        String sName = station['name']; 
                        bool isValid = _allowedStations.isEmpty || _allowedStations.any((s) => _normalizeStationName(s) == _normalizeStationName(sName)); 
                        double angle = (2 * pi * index / stations.length) - (pi / 2); 
                        double x = centerX + radius * cos(angle); 
                        double y = centerY + radius * sin(angle); 
                        Color stationColor = isValid ? Colors.white : Colors.grey[200]!; 
                        Color borderColor = isValid ? Colors.black : Colors.grey[300]!; 
                        
                        if (ownership[sName] == 'RED') {
                          stationColor = Colors.red; 
                        } else if (ownership[sName] == 'BLUE') {
                          stationColor = Colors.blue; 
                        }
                        
                        bool isHighlighted = (_normalizeStationName(sName) == _normalizeStationName(_highlightedStation ?? "")); 
                        Widget? playerIcon; 
                        
                        if (playerPos.containsKey(sName)) { 
                          var p = playerPos[sName]!.first; 
                          Color pColor = Colors.grey; 
                          IconData pIcon = Icons.train;
                          
                          if (p['team'] == 'RED') {
                            pColor = Colors.red; 
                          } else if (p['team'] == 'BLUE') {
                            pColor = Colors.blue; 
                          }
                          
                          // ★変更：GM（デベロッパー）は金色の星アイコンに！
                          if (p['role'] == 'GAME MASTER' || p['role'] == 'GM' || p['role'] == 'developer' || p['role'] == 'ADMIN') { 
                            pColor = Colors.amber; 
                            pIcon = Icons.star; 
                          }
                          
                          playerIcon = Container(
                            padding: const EdgeInsets.all(4), 
                            decoration: BoxDecoration(color: pColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), 
                            child: Icon(pIcon, color: Colors.white, size: 14)
                          ); 
                        } 
                        
                        return Positioned(
                          left: x - 40, 
                          top: y - 20, 
                          child: SizedBox(
                            width: 80, 
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.topCenter, 
                                  children: [
                                    playerIcon ?? Container(width: 16, height: 16, decoration: BoxDecoration(color: stationColor, shape: BoxShape.circle, border: Border.all(color: borderColor, width: 2))), 
                                    if(isHighlighted) const Positioned(top: -20, child: Icon(Icons.push_pin, color: Colors.redAccent, size: 24))
                                  ]
                                ), 
                                const SizedBox(height: 4), 
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), 
                                  decoration: BoxDecoration(color: isValid ? Colors.white.withOpacity(0.8) : Colors.transparent, borderRadius: BorderRadius.circular(4)), 
                                  child: Text(sName, style: TextStyle(color: isValid ? Colors.black : Colors.grey[300], fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)
                                )
                              ]
                            )
                          )
                        ); 
                      })
                    ]
                  );
                }
              );
            } else {
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 20), 
                itemCount: stations.length, 
                itemBuilder: (context, index) { 
                  final station = stations[index]; 
                  String sName = station['name']; 
                  bool isValid = _allowedStations.isEmpty || _allowedStations.any((s) => _normalizeStationName(s) == _normalizeStationName(sName)); 
                  Color dotColor = isValid ? Colors.white : Colors.grey[200]!; 
                  Color borderColor = isValid ? lineColor : Colors.grey[300]!; 
                  Color textColor = isValid ? Colors.black : Colors.grey[300]!; 
                  
                  if (ownership[sName] == 'RED') {
                    dotColor = Colors.red; 
                  } else if (ownership[sName] == 'BLUE') {
                    dotColor = Colors.blue; 
                  }
                  
                  bool isHighlighted = (_normalizeStationName(sName) == _normalizeStationName(_highlightedStation ?? "")); 
                  List<Widget> icons = []; 
                  
                  if (playerPos.containsKey(sName)) { 
                    for (var p in playerPos[sName]!) { 
                      Color tc = Colors.grey; 
                      IconData ti = Icons.train;
                      
                      if(p['team'] == 'RED') {
                        tc = Colors.red; 
                      } else if(p['team'] == 'BLUE') {
                        tc = Colors.blue; 
                      }
                      
                      // ★変更：GM（デベロッパー）は金色の星アイコンに！
                      if (p['role'] == 'GAME MASTER' || p['role'] == 'GM' || p['role'] == 'developer' || p['role'] == 'ADMIN') { 
                        tc = Colors.amber; 
                        ti = Icons.star; 
                      }
                      
                      icons.add(Container(margin:const EdgeInsets.only(left:4), child: Icon(ti, color: tc, size:20))); 
                    } 
                  } 
                  
                  return SizedBox(
                    height: 60, 
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4, 
                          child: Container(
                            alignment: Alignment.centerRight, 
                            padding: const EdgeInsets.only(right: 16), 
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end, 
                              children: [
                                if(isHighlighted) const Icon(Icons.push_pin, color: Colors.redAccent, size: 20), 
                                const SizedBox(width: 8), 
                                Text(sName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))
                              ]
                            )
                          )
                        ), 
                        SizedBox(
                          width: 40, 
                          child: Stack(
                            alignment: Alignment.center, 
                            children: [
                              Container(width: 10, color: borderColor, margin: EdgeInsets.only(top: index == 0 ? 30 : 0, bottom: index == stations.length - 1 ? 30 : 0)), 
                              Container(
                                width: 18, 
                                height: 18, 
                                decoration: BoxDecoration(
                                  color: Colors.white, 
                                  shape: BoxShape.circle, 
                                  border: Border.all(color: borderColor, width: 4), 
                                  boxShadow: [BoxShadow(color: dotColor == Colors.white ? Colors.transparent : dotColor, blurRadius: 5)]
                                )
                              )
                            ]
                          )
                        ), 
                        Expanded(flex: 4, child: Row(children: icons))
                      ]
                    )
                  ); 
                }
              );
            }
          }
        );
      }
    );
  }
}

class PieChartPainter extends CustomPainter {
  final int red;
  final int blue;
  PieChartPainter(this.red, this.blue);

  @override
  void paint(Canvas canvas, Size size) {
    final total = red + blue;
    if (total == 0) return;
    final redAngle = (red / total) * 2 * pi;
    final paint = Paint()..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    
    paint.color = Colors.redAccent;
    canvas.drawArc(rect, -pi / 2, redAngle, true, paint);
    
    paint.color = Colors.blueAccent;
    canvas.drawArc(rect, -pi / 2 + redAngle, 2 * pi - redAngle, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
} //完成！