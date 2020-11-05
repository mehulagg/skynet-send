import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path/path.dart' as p;

import 'package:mime_type/mime_type.dart';
import 'package:skynet_send/ansi_pens.dart';
import 'package:skynet_send/encrypt_block_stream.dart';

import 'const.dart';

void startEncryptAndUpload(
  File file,
) async {
  print('Upload portals: ${publicPortals}');

  print('uploading file...');
  // print(file.type);

  final totalChunks = (file.lengthSync() / (chunkSize + 32)).abs().toInt() + 1;

  final metadata = {
    'filename': p.basename(file.path),
    'type': mime(file.path),
    'chunksize': chunkSize,
    'totalchunks': totalChunks,
    'filesize': file.lengthSync(),
  };

  //print(metadata);

/*   final md = json.encode(metadata);

  final mdBytes = utf8.encode(md); */

  //int mdL = mdBytes.length;

  // Metadata start (mdL + 32)

  final task = EncryptionUploadTask();

  task.progress.stream.listen((event) {
    print(event);
  });

  final stream = getStreamOfIOFile(file.openRead());

  final chunkSkylinks =
      await task.uploadChunkedStreamToSkynet(file.lengthSync(), stream);

  print('uploading chunk index...');

  final links = await utf8.encode(json.encode({
    'chunks': chunkSkylinks,
    'metadata': metadata,
  }));

  String skylink;

  while (skylink == null) {
    try {
      skylink = await task.uploadFileToSkynet(links);

      if ((skylink ?? '').isEmpty) throw Exception('oops');
    } catch (e, st) {
      print(e);
      print(st);
      print('retry');
    }
  }

  final link = 'https://skynet-send.hns.siasky.net/#b-$skylink';

  print('Secure Download Link for ${greenBold(metadata['filename'])}: $link');
}

Stream<List<int>> getStreamOfIOFile(Stream<List<int>> stream) async* {
  List<int> tmp = [];

  await for (final element in stream) {
    tmp.addAll(element);

    if (tmp.length >= chunkSize) {
      yield tmp.sublist(0, chunkSize);

      tmp.removeRange(0, chunkSize);
    }
  }
  yield tmp;
}
