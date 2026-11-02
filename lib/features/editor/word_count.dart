import 'package:characters/characters.dart';

final _whitespace = RegExp(r'^\s+$', unicode: true);

int countWords(String text) => text.characters
    .where((character) => !_whitespace.hasMatch(character))
    .length;
