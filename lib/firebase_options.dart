// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return android;
      case TargetPlatform.iOS: return ios;
      case TargetPlatform.macOS: return macos;
      case TargetPlatform.windows: return windows;
      case TargetPlatform.linux: throw UnsupportedError('Linux not configured');
      default: throw UnsupportedError('Platform not supported');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDl36627utjIfv4aY3dEfvj23ZGeXKRwR8',
    appId: '1:871703895373:android:01f3339da93cd1e966eb04',
    messagingSenderId: '871703895373',
    projectId: 'train-run-389dd',
    storageBucket: 'train-run-389dd.firebasestorage.app',
  );

  // ★Train Run用の新しい設定

  // ダミー設定（Android以外でエラーにならないように）

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBKB0fU8e9jlk0tq2NxhHOOMxZvd59oWiY',
    appId: '1:871703895373:ios:64c8c81cbe3a3dd466eb04',
    messagingSenderId: '871703895373',
    projectId: 'train-run-389dd',
    storageBucket: 'train-run-389dd.firebasestorage.app',
    iosBundleId: 'com.example.trainRun',
  );

  static const FirebaseOptions web = FirebaseOptions(apiKey: '', appId: '', messagingSenderId: '', projectId: '');
  static const FirebaseOptions macos = FirebaseOptions(apiKey: '', appId: '', messagingSenderId: '', projectId: '');
  static const FirebaseOptions windows = FirebaseOptions(apiKey: '', appId: '', messagingSenderId: '', projectId: '');
}