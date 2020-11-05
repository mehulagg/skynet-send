import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:math';
import 'dart:typed_data';
import 'package:filesize/filesize.dart';

import 'package:skynet_send/const.dart';
import 'package:skynet_send/download.dart';
import 'package:skynet_send/encrypt_block_stream.dart';

import 'package:uuid/uuid.dart';

void main() async {
  /*  try { */
  String hash = window.location.hash;

  if (hash.startsWith('#')) {
    hash = hash.substring(1);
  }

  if (hash.isNotEmpty) {
    if (hash.startsWith(RegExp(r'[0-9]'))) {
      setState('Redirecting to old version...');

      window.location.href =
          'https://siasky.net/CACxu3qIoxiXQdyDBmrcS7dkC4sGzz4NrXpReKnehKEwFQ/index.html#$hash';
      return;
    }

    // hash = hash.substring(1);
    // setState('Downloading file index...');

    final lengthSep = hash.indexOf('-');

    final version = hash.substring(0, lengthSep);
    if (version == 'a') {
      setState('Redirecting to old version...');

      window.location.href =
          'https://siasky.net/CADnRQe4AztQnaDkwPaBP6G3vofZzYaaikE5246uZadXiQ/index.html#$hash';
      return;
    }

    hash = hash.substring(lengthSep + 1);

    final sep = hash.indexOf('+');

    final skylink = hash.substring(0, sep);
    final key = hash.substring(sep + 1);
/* 
    print(skylink);
    print(key); */
    print(skylink);

    querySelector('.upload-section').style.display = 'none';
    querySelector('#instructions-upload').style.display = 'none';
    querySelector('.download-section').style.display = '';
    querySelector('#instructions-download').style.display = '';

    final dlTask = DownloadTask();

    dlTask.progress.stream.listen((event) {
      setDLState(event);
    });

    await dlTask.downloadAndDecryptMetadata(
      skylink,
    );

    querySelector('#download-filename')
        .setInnerHtml('${dlTask.metadata["filename"]}');

    querySelector('#download-btn-filename').setInnerHtml(
        '${dlTask.metadata["filename"]} (${filesize(dlTask.metadata['filesize'])})');

    bool clicked = false;
    querySelector('.download-file').onClick.listen((event) async {
      if (!clicked) {
        clicked = true;

        List<Uint8List> chunks = [];

        dlTask.chunkCtrl.stream.listen((event) {
          if (event == null) {
            final blob = Blob(chunks, dlTask.metadata['type']);

            downloadBlob(blob, dlTask.metadata['filename']);
          } else {
            chunks.add(event);
          }
        });

        dlTask.downloadAndDecryptFile();
      }
    });
  }
  //var input = window.document.querySelector('#upload');

  FileUploadInputElement fileselect =
      window.document.querySelector('#fileselect');

  querySelector('.upload-section').onDrop.listen((event) {
    event.preventDefault();

    final item = event.dataTransfer.items[0];

    if (item.kind != 'file') return;

    encryptAndUpload(
      item.getAsFile(),
    );
  });

  querySelector('.upload-section').onDragOver.listen((event) {
    event.preventDefault();
  });

  querySelector('#upload-btn').onClick.listen((event) {
    fileselect.click();
  });

  fileselect.addEventListener("change", (e) {
    FileList files = fileselect.files;
    if (files.length < 1) throw Exception(); // TODO

    setState('Loading file...');

    File file = files.first;

    // file.slice()
    encryptAndUpload(
      file,
    );
  });
}

Stream<List<int>> getStreamOfFile(File file) async* {
  final reader = FileReader();

  int start = 0;
  while (start < file.size) {
    final end = start + chunkSize > file.size ? file.size : start + chunkSize;
    final blob = file.slice(start, end);
    reader.readAsArrayBuffer(blob);
    await reader.onLoad.first;
    yield reader.result;
    start += chunkSize;
  }
}

void setDLState(String s) {
  querySelector('#download-status').setInnerHtml(
      '<span><img src="resources/images/icon-download-link.svg" alt="Download link icon">$s</span>',
      validator: TrustedNodeValidator());
}

void setState(String s) {
  querySelector('.uploading-span')
      .setInnerHtml('<span>$s</span>', validator: TrustedNodeValidator());
}

class TrustedNodeValidator implements NodeValidator {
  bool allowsElement(Element element) => true;
  bool allowsAttribute(element, attributeName, value) => true;
}

void downloadBlob(Blob blob, String filename) {
  setDLState('Saving file...');

  window.document.querySelector("#downloadLink")
    ..setAttribute('href', Url.createObjectUrlFromBlob(blob))
    ..setAttribute('download', filename);

  window.document.querySelector("#downloadLink").click();
}

void encryptAndUpload(
  File file,
) async {
  querySelector('.upload-section').style.display = 'none';
  querySelector('.upload-section-active').style.display = '';

  setState('Uploading file...');
  // print(file.type);

  final totalChunks = (file.size / (chunkSize + 32)).abs().toInt() + 1;

  final metadata = {
    'filename': file.name,
    'type': file.type,
    'chunksize': chunkSize,
    'totalchunks': totalChunks,
    'filesize': file.size,
  };

/*   final md = json.encode(metadata);

  final mdBytes = utf8.encode(md); */

  //int mdL = mdBytes.length;

  // Metadata start (mdL + 32)

  final task = EncryptionUploadTask();

  task.progress.stream.listen((event) {
    setState(event);
  });

  final stream = getStreamOfFile(file);

  final chunkSkylinks = await task.uploadChunkedStreamToSkynet(
      file.size, stream /* .asBroadcastStream() */

      );

  print(chunkSkylinks);

  setState('Uploading chunk index...');

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

  final link =
      '${window.location.protocol}//${window.location.host}${window.location.pathname}#b-$skylink+';

  querySelector('.upload-section-active').style.display = 'none';
  querySelector('#upload-instruction').style.display = 'none';

  querySelector('.upload-section-done').style.display = '';

  querySelector('#upload-filename').setInnerHtml('${file.name}');

  querySelector('#upload-link').setInnerHtml('${link}');

  querySelector('#copy-btn').onClick.listen((event) {
    InputElement tempInput = document.createElement("input");
    tempInput.value = link;
    document.body.append(tempInput);
    tempInput.select();
    document.execCommand("copy");
    tempInput.remove();

    return;

    print('copy');
    final InputElement copyText = document.getElementById('copy-input');

    copyText.value = link;

    copyText.select();
    copyText.setSelectionRange(0, 99999);

    document.execCommand('copy');
  });

  setState('Secure Download Link for ${file.name}: <a href="$link">$link</a>');
}
