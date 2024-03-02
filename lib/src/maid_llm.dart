import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:maid_llm/src/gpt_params.dart';

import 'bindings.dart';

class MaidLLM {
  static SendPort? _sendPort;
  static maid_llm? _lib;
  static void Function(String)? _log;

  /// Getter for the Llama library.
  ///
  /// Loads the library based on the current platform.
  static maid_llm get lib {
    if (_lib == null) {
      if (Platform.isWindows) {
        _lib = maid_llm(DynamicLibrary.open('bin/llama.dll'));
      } else if (Platform.isLinux || Platform.isAndroid) {
        _lib = maid_llm(DynamicLibrary.open('libllama.so'));
      } else if (Platform.isMacOS || Platform.isIOS) {
        throw Exception('Unsupported platform');
        //_lib = maid_llm(DynamicLibrary.open('bin/llama.dylib'));
      } else {
        throw Exception('Unsupported platform');
      }
    }
    return _lib!;
  }

  MaidLLM(GptParams params, {void Function(String)? log}) {
    _log = log;
    lib.maid_llm_init(params.get(), Pointer.fromFunction(_logOutput));
  }

  static Stream<String> prompt(String input) async* {
    final receivePort = ReceivePort();
    _sendPort = receivePort.sendPort;

    final isolate  = await Isolate.spawn(_promptIsolate, (input, _sendPort!));
    
    await for (var data in receivePort) {
      if (data is (String, bool)) {
        final (message, done) = data;

        if (done) {
          receivePort.close();
          isolate.kill();
          return;
        }

        yield message;
      }
    }
  }

  static void _promptIsolate((String, SendPort) args) {
    final (input, sendPort) = args;
    _sendPort = sendPort;
    lib.maid_llm_prompt(input.toNativeUtf8().cast<Char>(), Pointer.fromFunction(_output));
  }

  static void _output(Pointer<Char> buffer, bool stop) {
    try {
      _sendPort!.send((buffer.cast<Utf8>().toDartString(), stop));
    } catch (e) {
      print(e);
    }
  }

  static void _logOutput(Pointer<Char> message) {
    if (_log != null) {
      _log!(message.cast<Utf8>().toDartString());
    }
  }
}