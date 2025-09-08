/// MerkleKV Core Library
/// 
/// A distributed key-value store designed for mobile and edge environments.
/// Uses MQTT for communication and Merkle trees for efficient synchronization.
library merkle_kv_core;

// Core client interface
export 'src/merkle_kv_mobile.dart';

// Configuration
export 'src/config/merkle_kv_config.dart';
export 'src/config/default_config.dart';

// Models
export 'src/models/response_models.dart';
export 'src/models/event_models.dart';
export 'src/models/error_models.dart';

// Commands
export 'src/commands/command_models.dart';

// Storage interface
export 'src/storage/storage_interface.dart';

// Utilities
export 'src/utils/logger.dart';
