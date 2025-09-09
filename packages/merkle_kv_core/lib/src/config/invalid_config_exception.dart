/// Exception thrown when a MerkleKVConfig has invalid parameters.
/// 
/// This exception implements [FormatException] to align with Dart's standard
/// exception hierarchy for configuration and parsing errors.
class InvalidConfigException implements FormatException {
  /// Creates an InvalidConfigException with a message and optional parameter name.
  const InvalidConfigException(this.message, [this.parameter]);

  @override
  final String message;

  /// The name of the invalid parameter, if applicable.
  final String? parameter;

  @override
  int? get offset => null;

  @override
  dynamic get source => null;

  @override
  String toString() {
    if (parameter != null) {
      return 'InvalidConfigException: $message (parameter: $parameter)';
    }
    return 'InvalidConfigException: $message';
  }
}
