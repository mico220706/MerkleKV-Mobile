/// Storage interface for MerkleKV Mobile
abstract class StorageInterface {
  /// Initialize the storage backend
  Future<void> initialize();
  
  /// Get a value by key
  Future<String?> get(String key);
  
  /// Set a key-value pair
  Future<void> set(String key, String value);
  
  /// Delete a key
  Future<bool> delete(String key);
  
  /// Check if a key exists
  Future<bool> exists(String key);
  
  /// Get all keys
  Future<List<String>> keys();
  
  /// Get all key-value pairs
  Future<Map<String, String>> getAll();
  
  /// Clear all data
  Future<void> clear();
  
  /// Get storage size in bytes
  Future<int> size();
  
  /// Dispose of resources
  Future<void> dispose();
  
  /// Increment a numeric value
  Future<int> increment(String key, int amount);
  
  /// Decrement a numeric value
  Future<int> decrement(String key, int amount);
  
  /// Append to a string value
  Future<String> append(String key, String value);
  
  /// Prepend to a string value
  Future<String> prepend(String key, String value);
  
  /// Get multiple keys at once
  Future<Map<String, String?>> multiGet(List<String> keys);
  
  /// Set multiple key-value pairs at once
  Future<void> multiSet(Map<String, String> keyValues);
  
  /// Delete multiple keys at once
  Future<int> multiDelete(List<String> keys);
}
