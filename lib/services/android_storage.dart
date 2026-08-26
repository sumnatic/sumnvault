import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AndroidStorage {
  static const _channel = MethodChannel('com.sumnatic.sumnvault/storage');

  static Future<String> prepareDestination(String uri) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) return uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
    return (await _channel.invokeMethod<String>('prepareDestination', {'uri': uri}))!;
  }

  static Future<String> importDocument(String uri) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) return uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
    return (await _channel.invokeMethod<String>('importDocument', {'uri': uri}))!;
  }

  static Future<void> commitDocument(String uri, String cachePath) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) return;
    await _channel.invokeMethod<void>('commitDocument', {'uri': uri, 'cachePath': cachePath});
  }

  static Future<void> persistUri(String uri) async {
    if (Platform.isAndroid && uri.startsWith('content://')) {
      await _channel.invokeMethod<void>('persistUri', {'uri': uri});
    }
    final preferences = await SharedPreferences.getInstance();
    final uris = preferences.getStringList('recent_vault_uris') ?? <String>[];
    uris.remove(uri);
    uris.insert(0, uri);
    await preferences.setStringList('recent_vault_uris', uris.take(20).toList());
  }

  static Future<List<String>> recentUris() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList('recent_vault_uris') ?? <String>[];
  }
}
