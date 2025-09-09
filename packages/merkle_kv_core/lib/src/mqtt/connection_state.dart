/// Connection state for MQTT client.
enum ConnectionState {
  /// Client is disconnected.
  disconnected,

  /// Client is attempting to connect.
  connecting,

  /// Client is connected and ready.
  connected,

  /// Client is disconnecting.
  disconnecting,
}
