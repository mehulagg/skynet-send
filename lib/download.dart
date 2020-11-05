import 'dart:async';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:filesize/filesize.dart';
import 'package:skynet_send/config.dart';

class DownloadTask {
  Map chunkIndex;
  Map metadata;

  final progress = StreamController<String>.broadcast();

  Future<void> downloadAndDecryptMetadata(
    String skylink,
  ) async {
    final res = await http.get('${SkynetConfig.dlPortal}/$skylink');

    chunkIndex = json.decode(utf8.decode(res.bodyBytes));

    // print("chunkIndex: $chunkIndex");

    metadata = chunkIndex['metadata'];

    return;
  }

  void setDLState(String s) {
    progress.add(s);
  }

  // List<Uint8List> chunks = [];

  int chunksLength = 0;

  final chunkCtrl = StreamController<Uint8List>();

  int totalChunks;

  int iDone = 0;

  void downloadAndDecryptFile() async {
    // print('onDownloadStart');

    int i = 0;

    totalChunks = metadata['totalchunks'];

    //   querySelector('.upload-section-active').style.display = '';

    setDLState('Downloading chunk 1 of $totalChunks...');

    for (final chunkSkylink in chunkIndex['chunks']) {
      final currentI = i;

      //  print('dl $currentI');

      downloadAndDecryptChunk(
        chunkSkylink: chunkSkylink,
        currentI: currentI,
      );

      await Future.delayed(Duration(milliseconds: 100));

      while (i > iDone + 5) {
        await Future.delayed(Duration(milliseconds: 20));
      }

      i++;
    }

    return;
  }

  void downloadAndDecryptChunk({
    String chunkSkylink,
    final int currentI,
  }) async {
    while (true) {
      try {
        final chunkRes = await http.get(
          '${SkynetConfig.dlPortal}/$chunkSkylink',
        );

        while (chunksLength < currentI) {
          await Future.delayed(Duration(milliseconds: 20));
        }
        // print('done $currentI');

        chunkCtrl.add(chunkRes.bodyBytes);
        chunksLength++;

        if (currentI == totalChunks - 1) {
          chunkCtrl.add(null);
          return;
        } else {
          setDLState('Downloading chunk ${currentI + 2} of $totalChunks...');
        }
        iDone++;

        return;
      } catch (e, st) {
        print(e);
        print(st);
        print('retrying in 3 seconds...');
        await Future.delayed(Duration(seconds: 3));
      }
    }
  }
}
