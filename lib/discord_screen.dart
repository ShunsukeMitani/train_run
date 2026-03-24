import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class DiscordScreen extends StatefulWidget {
  // サーバーIDは固定（あなたのDiscordサーバーのIDを入れてください）
  final String serverId = "YOUR_SERVER_ID_HERE"; 

  const DiscordScreen({super.key});

  @override
  State<DiscordScreen> createState() => _DiscordScreenState();
}

class _DiscordScreenState extends State<DiscordScreen> {
  String _status = "チャンネルを確認中...";
  String? _assignedChannelId;
  String _myName = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _assignVoiceChannel();
  }

  Future<void> _assignVoiceChannel() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    
    try {
      // プレイヤー名取得
      var pDoc = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).get();
      if(pDoc.exists) {
        _myName = pDoc['name'] ?? "Unknown";
      }

      // 1. 既に割り当てられているか確認
      if (pDoc.exists && pDoc.data()!.containsKey('discordChannelId') && pDoc['discordChannelId'] != null) {
        setState(() {
          _assignedChannelId = pDoc['discordChannelId'];
          _status = "通話準備完了";
          _isLoading = false;
        });
        return;
      }

      // 2. 割り当てがない場合、在庫から取得
      var poolQuery = await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('discord_pool')
          .where('isUsed', isEqualTo: false)
          .limit(1)
          .get();

      if (poolQuery.docs.isEmpty) {
        setState(() {
          _status = "空きチャンネルがありません\nGMに連絡してください";
          _isLoading = false;
        });
        return;
      }

      // 3. 確保処理
      var poolDoc = poolQuery.docs.first;
      String channelId = poolDoc['id'];
      
      await poolDoc.reference.update({
        'isUsed': true,
        'assignedTo': uid,
        'assignedName': _myName,
        'assignedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('players')
          .doc(uid)
          .update({
            'discordChannelId': channelId,
          });

      setState(() {
        _assignedChannelId = channelId;
        _status = "チャンネルを確保しました";
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _status = "エラーが発生しました";
        _isLoading = false;
      });
    }
  }

  Future<void> _launchDiscord() async {
    if (_assignedChannelId == null) return;
    
    // アプリで開くURLスキーム
    final String urlString = widget.serverId == "YOUR_SERVER_ID_HERE"
        ? "https://discord.com/app" 
        : "https://discord.com/channels/${widget.serverId}/$_assignedChannelId";

    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Discordを開けませんでした")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.9),
      body: Center(
        child: Container(
          width: 320,
          height: 500,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.purpleAccent.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ],
          ),
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ヘッダー
              Column(
                children: [
                  Container(height: 4, width: 40, color: Colors.grey[700]),
                  const SizedBox(height: 30),
                  const Text(
                    "SECURE LINE",
                    style: TextStyle(color: Colors.purpleAccent, fontFamily: 'Courier', fontSize: 14, letterSpacing: 2),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "CONTACTS (Discord)",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              // メインエリア
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isLoading)
                      const CircularProgressIndicator(color: Colors.purpleAccent)
                    else
                      ListTile(
                        leading: const Icon(Icons.headset_mic, size: 40, color: Colors.white),
                        title: Text(_myName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                        subtitle: Text(_assignedChannelId != null ? "待機可能" : _status, 
                           style: const TextStyle(color: Colors.greenAccent)),
                        trailing: _assignedChannelId != null 
                           ? IconButton(
                               icon: const Icon(Icons.call, color: Colors.purpleAccent, size: 30),
                               onPressed: _launchDiscord,
                             )
                           : null,
                      ),
                    
                    if (_assignedChannelId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          "CH ID: $_assignedChannelId",
                          style: const TextStyle(color: Colors.grey, fontFamily: 'Courier', fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CLOSE", style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}