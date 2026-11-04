import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

String workKeyForPath(String path, String workId) => sha256
    .convert(utf8.encode('${p.normalize(p.absolute(path))}|$workId'))
    .toString();
