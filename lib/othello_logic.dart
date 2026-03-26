// lib/othello_logic.dart
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
    List<String> flippableDocs = []; // ひっくり返るマスのID(例: "2_3")を格納
    
    // もし既に誰かが置いているマスなら置けない
    if (boardData["${targetX}_$targetY"]?['ownerTeam'] != null) {
      return [];
    }

    // 8方向のベクトル (上, 下, 左, 右, 斜め4方向)
    final directions = [
      [0, -1], [0, 1], [-1, 0], [1, 0],
      [-1, -1], [1, -1], [-1, 1], [1, 1]
    ];

    String opponentTeam = (myTeam == 'RED') ? 'BLUE' : 'RED';

    for (var dir in directions) {
      int dx = dir[0];
      int dy = dir[1];
      int currX = targetX + dx;
      int currY = targetY + dy;
      
      List<String> tempFlippable = [];

      // 盤面の端に到達するまで進む
      while (currX >= 0 && currX < boardSize && currY >= 0 && currY < boardSize) {
        String docId = "${currX}_$currY";
        var cell = boardData[docId];
        
        // 空白マスならこの方向は挟めない
        if (cell == null || cell['ownerTeam'] == null) break;

        // 相手のコマなら候補に追加して次へ進む
        if (cell['ownerTeam'] == opponentTeam) {
          tempFlippable.add(docId);
        } 
        // 自分のコマなら、ここまで溜まった相手のコマを確定させてループを抜ける
        else if (cell['ownerTeam'] == myTeam) {
          flippableDocs.addAll(tempFlippable);
          break;
        }
        
        currX += dx;
        currY += dy;
      }
    }

    return flippableDocs;
  }

  /// 駅をチェックイン(獲得)する直前にこの関数を呼び出して判定してください！
  /// 返り値が true なら獲得成功、falseなら「挟めるマスがありません」とエラーを出します。
  static Future<bool> tryPlacePiece(String stationName, String myTeam, int boardSize) async {
    // 現在の盤面データを取得
    var snap = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').get();
    Map<String, Map<String, dynamic>> boardData = {};
    int targetX = -1;
    int targetY = -1;
    String targetDocId = "";

    for (var doc in snap.docs) {
      var data = doc.data();
      boardData[doc.id] = data;
      // プレイヤーがチェックインしようとしている駅の座標を探す
      if (data['station'] == stationName) {
        targetX = data['x'];
        targetY = data['y'];
        targetDocId = doc.id;
      }
    }

    // もし対象の駅が盤面に存在しない場合
    if (targetX == -1) return false;

    // ひっくり返せるマスを計算
    List<String> flippableDocs = getFlippableStations(targetX, targetY, myTeam, boardData, boardSize);

    // 1枚もひっくり返せない場合はオセロのルール違反なので false を返す
    if (flippableDocs.isEmpty) {
      return false;
    }

    // ひっくり返せる場合、対象のマスとひっくり返したマスを一気に更新
    WriteBatch batch = FirebaseFirestore.instance.batch();
    
    // 自分が置いたマス
    batch.update(
      FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').doc(targetDocId),
      {'ownerTeam': myTeam}
    );

    // 挟まれたマス
    for (String docId in flippableDocs) {
      batch.update(
        FirebaseFirestore.instance.collection('games').doc('game_001').collection('othello_board').doc(docId),
        {'ownerTeam': myTeam}
      );
    }

    // ターン制の場合は、ターンを相手に渡して時間をリセットする
    var gameDoc = await FirebaseFirestore.instance.collection('games').doc('game_001').get();
    if (gameDoc.exists && gameDoc.data()?['othelloTurnBased'] == true) {
       int turnDuration = gameDoc.data()?['turnDurationMinutes'] ?? 10;
       batch.update(FirebaseFirestore.instance.collection('games').doc('game_001'), {
         'currentTurn': (myTeam == 'RED') ? 'BLUE' : 'RED',
         'turnEndTime': Timestamp.fromDate(DateTime.now().add(Duration(minutes: turnDuration)))
       });
    }

    await batch.commit();
    return true; // 成功！
  }
}