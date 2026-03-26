import 'package:cloud_firestore/cloud_firestore.dart';

class OthelloLogic {
  /// 指定した座標(x, y)にチーム(team)が置いた場合、ひっくり返せるマスのリストを返す
  static List<String> getFlippableStations(
    int targetX, 
    int targetY, 
    String myTeam, 
    Map<String, Map<String, dynamic>> boardData, 
    int boardSize
  ) {
    List<String> flippableDocs = []; 
    if (boardData["${targetX}_$targetY"]?['ownerTeam'] != null) return [];

    final directions = [
      [0, -1], [0, 1], [-1, 0], [1, 0],
      [-1, -1], [1, -1], [-1, 1], [1, 1]
    ];

    String opponentTeam = (myTeam == 'RED') ? 'BLUE' : 'RED';

    for (var dir in directions) {
      int dx = dir[0]; int dy = dir[1];
      int currX = targetX + dx; int currY = targetY + dy;
      List<String> tempFlippable = [];

      while (currX >= 0 && currX < boardSize && currY >= 0 && currY < boardSize) {
        String docId = "${currX}_$currY";
        var cell = boardData[docId];
        
        if (cell == null || cell['ownerTeam'] == null) break;

        if (cell['ownerTeam'] == opponentTeam) {
          tempFlippable.add(docId);
        } else if (cell['ownerTeam'] == myTeam) {
          flippableDocs.addAll(tempFlippable);
          break;
        }
        currX += dx; currY += dy;
      }
    }
    return flippableDocs;
  }

  /// ★新規追加：盤面全体をスキャンして、自分が置ける(相手を挟める)マスのIDリストを返す
  static List<String> getValidMoves(
    String myTeam, 
    Map<String, Map<String, dynamic>> boardData, 
    int boardSize
  ) {
    List<String> validMoves = [];
    for (int y = 0; y < boardSize; y++) {
      for (int x = 0; x < boardSize; x++) {
        String docId = "${x}_$y";
        // 既に置かれている場合はスキップ
        if (boardData[docId]?['ownerTeam'] != null) continue;

        // ひっくり返せるマスがあるかチェック
        List<String> flippable = getFlippableStations(x, y, myTeam, boardData, boardSize);
        if (flippable.isNotEmpty) {
          validMoves.add(docId);
        }
      }
    }
    return validMoves;
  }

  /// 駅をチェックイン(獲得)する直前に呼び出して判定する
  static Future<bool> tryPlacePiece(String stationName, String myTeam, int boardSize) async {
    var snap = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').get();
    Map<String, Map<String, dynamic>> boardData = {};
    int targetX = -1; int targetY = -1; String targetDocId = "";

    for (var doc in snap.docs) {
      var data = doc.data();
      boardData[doc.id] = data;
      if (data['station'] == stationName) {
        targetX = data['x']; targetY = data['y']; targetDocId = doc.id;
      }
    }

    if (targetX == -1) return false;

    List<String> flippableDocs = getFlippableStations(targetX, targetY, myTeam, boardData, boardSize);
    if (flippableDocs.isEmpty) return false;

    WriteBatch batch = FirebaseFirestore.instance.batch();
    batch.update(
      FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').doc(targetDocId),
      {'ownerTeam': myTeam}
    );

    for (String docId in flippableDocs) {
      batch.update(
        FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').doc(docId),
        {'ownerTeam': myTeam}
      );
    }

    var gameDoc = await FirebaseFirestore.instance.collection('games').doc('game_001').get();
    if (gameDoc.exists && gameDoc.data()?['othelloTurnBased'] == true) {
       int turnDuration = gameDoc.data()?['turnDurationMinutes'] ?? 10;
       batch.update(FirebaseFirestore.instance.collection('games').doc('game_001'), {
         'currentTurn': (myTeam == 'RED') ? 'BLUE' : 'RED',
         'turnEndTime': Timestamp.fromDate(DateTime.now().add(Duration(minutes: turnDuration)))
       });
    }

    await batch.commit();
    return true; 
  }
}