import 'dart:typed_data';

import 'package:meta/meta.dart';

/// How a command was answered.
enum CommandOutcome {
  /// The scanner acknowledged the command with `[LEN, 0x0B]`.
  ack,

  /// The scanner echoed the frame back (some parameterized commands).
  echo,

  /// The scanner answered with a reply; see [CommandResult.reply].
  reply,

  /// A raw (unframed) command was written and nothing came back. Raw
  /// commands are never acknowledged.
  sentRaw,

  /// The link dropped right after the write, as expected for commands such
  /// as `setName` or `powerOff`. This is success.
  disconnected,
}

/// The result of sending a command.
@immutable
class CommandResult {
  /// Creates a result.
  const CommandResult(this.outcome, {this.reply, this.rawReply});

  /// How the command was answered.
  final CommandOutcome outcome;

  /// The decoded reply text, for [CommandOutcome.reply].
  final String? reply;

  /// The reply bytes as received, for [CommandOutcome.reply].
  final Uint8List? rawReply;

  @override
  String toString() => reply == null
      ? 'CommandResult(${outcome.name})'
      : 'CommandResult(${outcome.name}: $reply)';
}
