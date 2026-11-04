import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final class _CFRange extends Struct {
  @IntPtr()
  external int location;
  @IntPtr()
  external int length;
}

String decodeGb18030(List<int> bytes) {
  if (bytes.isEmpty) return '';
  final input = calloc<Uint8>(bytes.length);
  input.asTypedList(bytes.length).setAll(0, bytes);
  try {
    if (Platform.isMacOS) {
      final cf = DynamicLibrary.open(
        '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
      );
      final create = cf
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Uint8>,
              IntPtr,
              Uint32,
              Uint8,
            ),
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int)
          >('CFStringCreateWithBytes');
      final string = create(nullptr, input, bytes.length, 0x0632, 0);
      if (string == nullptr) {
        throw const FormatException('无法按 GB18030 解码，请检查原文件编码');
      }
      final length = cf
          .lookupFunction<
            IntPtr Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('CFStringGetLength')(string);
      final output = calloc<Uint16>(length + 1);
      final range = calloc<_CFRange>()..ref.location = 0;
      range.ref.length = length;
      try {
        cf.lookupFunction<
          Void Function(Pointer<Void>, _CFRange, Pointer<Uint16>),
          void Function(Pointer<Void>, _CFRange, Pointer<Uint16>)
        >('CFStringGetCharacters')(string, range.ref, output);
        return String.fromCharCodes(output.asTypedList(length));
      } finally {
        cf.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CFRelease')(string);
        calloc.free(output);
        calloc.free(range);
      }
    }
    if (Platform.isWindows) {
      final kernel = DynamicLibrary.open('kernel32.dll');
      final convert = kernel
          .lookupFunction<
            Int32 Function(
              Uint32,
              Uint32,
              Pointer<Uint8>,
              Int32,
              Pointer<Uint16>,
              Int32,
            ),
            int Function(int, int, Pointer<Uint8>, int, Pointer<Uint16>, int)
          >('MultiByteToWideChar');
      final length = convert(54936, 8, input, bytes.length, nullptr, 0);
      if (length == 0) throw const FormatException('无法按 GB18030 解码，请检查原文件编码');
      final output = calloc<Uint16>(length);
      try {
        final written = convert(54936, 8, input, bytes.length, output, length);
        if (written == 0) throw const FormatException('GB18030 文件内容不完整');
        return String.fromCharCodes(output.asTypedList(written));
      } finally {
        calloc.free(output);
      }
    }
    throw UnsupportedError('GB18030 导入仅支持 Windows 和 macOS');
  } finally {
    calloc.free(input);
  }
}
