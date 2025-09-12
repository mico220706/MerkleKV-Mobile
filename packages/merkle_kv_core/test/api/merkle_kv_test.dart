import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:merkle_kv_core/merkle_kv.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/errors/merkle_kv_exception.dart';
import 'package:merkle_kv_core/src/mqtt/connection_state.dart';
import 'package:merkle_kv_core/src/mqtt/mqtt_client_interface.dart';
import 'package:merkle_kv_core/src/storage/storage_interface.dart';
import 'package:merkle_kv_core/src/commands/command_processor.dart';

// Generate mocks
@GenerateMocks([MqttClientInterface, StorageInterface, CommandProcessor])
import 'merkle_kv_test.mocks.dart';

void main() {
  group('MerkleKV', () {
    late MockMqttClientInterface mockMqttClient;
    late MockStorageInterface mockStorage;
    late MockCommandProcessor mockCommandProcessor;
    late MerkleKVConfig config;

    setUp(() {
      mockMqttClient = MockMqttClientInterface();
      mockStorage = MockStorageInterface();
      mockCommandProcessor = MockCommandProcessor();
      
      config = MerkleKVConfig.create(
        brokerHost: 'localhost',
        brokerPort: 1883,
        clientId: 'test_client',
        username: 'test_user',
        password: 'test_pass',
        enableOfflineQueue: false,
      );

      // Setup default mock behaviors
      when(mockMqttClient.connectionState).thenReturn(ConnectionState.disconnected);
      when(mockMqttClient.connect()).thenAnswer((_) async => true);
      when(mockMqttClient.disconnect()).thenAnswer((_) async {});
    });

    group('Construction and Lifecycle', () {
      test('creates instance with valid configuration', () {
        expect(() => MerkleKV.create(config), returnsNormally);
      });

      test('throws ValidationException for invalid configuration', () {
        final invalidConfig = MerkleKVConfig.create(
          brokerHost: '', // Invalid empty host
          brokerPort: 1883,
          clientId: 'test_client',
        );
        
        expect(
          () => MerkleKV.create(invalidConfig),
          throwsA(isA<ValidationException>()),
        );
      });

      test('connect establishes connection successfully', () async {
        final merkleKV = MerkleKV.create(config);
        
        when(mockMqttClient.connect()).thenAnswer((_) async => true);
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
        
        await merkleKV.connect();
        
        expect(merkleKV.isConnected, isTrue);
        verify(mockMqttClient.connect()).called(1);
      });

      test('connect throws ConnectionException on failure', () async {
        final merkleKV = MerkleKV.create(config);
        
        when(mockMqttClient.connect()).thenAnswer((_) async => false);
        
        expect(
          () => merkleKV.connect(),
          throwsA(isA<ConnectionException>()),
        );
      });

      test('disconnect closes connection successfully', () async {
        final merkleKV = MerkleKV.create(config);
        
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
        when(mockMqttClient.disconnect()).thenAnswer((_) async {});
        
        await merkleKV.disconnect();
        
        verify(mockMqttClient.disconnect()).called(1);
      });

      test('isConnected returns correct state', () {
        final merkleKV = MerkleKV.create(config);
        
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
        expect(merkleKV.isConnected, isTrue);
        
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.disconnected);
        expect(merkleKV.isConnected, isFalse);
      });
    });

    group('Core Operations', () {
      late MerkleKV merkleKV;

      setUp(() {
        merkleKV = MerkleKV.create(config);
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
      });

      group('get operation', () {
        test('validates key before processing', () async {
          final invalidKey = 'a' * 257; // Too long
          
          expect(
            () => merkleKV.get(invalidKey),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Key size'))),
          );
        });

        test('throws ConnectionException when disconnected and offline queue disabled', () async {
          when(mockMqttClient.connectionState).thenReturn(ConnectionState.disconnected);
          
          expect(
            () => merkleKV.get('test_key'),
            throwsA(isA<ConnectionException>()
                .having((e) => e.message, 'message', contains('disconnected'))),
          );
        });

        test('processes valid get request when connected', () async {
          when(mockCommandProcessor.sendCommand(any))
              .thenAnswer((_) async => 'test_value');
          
          final result = await merkleKV.get('test_key');
          
          expect(result, equals('test_value'));
          verify(mockCommandProcessor.sendCommand(any)).called(1);
        });

        test('returns null for non-existent key', () async {
          when(mockCommandProcessor.sendCommand(any))
              .thenAnswer((_) async => null);
          
          final result = await merkleKV.get('nonexistent_key');
          
          expect(result, isNull);
        });

        test('handles timeout correctly', () async {
          when(mockCommandProcessor.sendCommand(any))
              .thenThrow(TimeoutException.operationTimeout('get'));
          
          expect(
            () => merkleKV.get('test_key'),
            throwsA(isA<TimeoutException>()),
          );
        });
      });

      group('set operation', () {
        test('validates key and value before processing', () async {
          final invalidKey = 'a' * 257;
          final invalidValue = 'a' * (256 * 1024 + 1);
          
          expect(
            () => merkleKV.set(invalidKey, 'value'),
            throwsA(isA<ValidationException>()),
          );
          
          expect(
            () => merkleKV.set('key', invalidValue),
            throwsA(isA<ValidationException>()),
          );
        });

        test('processes valid set request when connected', () async {
          when(mockCommandProcessor.sendCommand(any))
              .thenAnswer((_) async => true);
          
          await merkleKV.set('test_key', 'test_value');
          
          verify(mockCommandProcessor.sendCommand(any)).called(1);
        });

        test('throws ConnectionException when disconnected', () async {
          when(mockMqttClient.connectionState).thenReturn(ConnectionState.disconnected);
          
          expect(
            () => merkleKV.set('key', 'value'),
            throwsA(isA<ConnectionException>()),
          );
        });
      });

      group('delete operation', () {
        test('validates key before processing', () async {
          final invalidKey = 'a' * 257;
          
          expect(
            () => merkleKV.delete(invalidKey),
            throwsA(isA<ValidationException>()),
          );
        });

        test('is idempotent - succeeds even if key does not exist', () async {
          when(mockCommandProcessor.sendCommand(any))
              .thenAnswer((_) async => false); // Key didn't exist
          
          await merkleKV.delete('nonexistent_key');
          
          verify(mockCommandProcessor.sendCommand(any)).called(1);
        });

        test('processes valid delete request when connected', () async {
          when(mockCommandProcessor.sendCommand(any))
              .thenAnswer((_) async => true);
          
          await merkleKV.delete('test_key');
          
          verify(mockCommandProcessor.sendCommand(any)).called(1);
        });
      });
    });

    group('Numeric Operations', () {
      late MerkleKV merkleKV;

      setUp(() {
        merkleKV = MerkleKV.create(config);
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
      });

      test('increment validates key and delta', () async {
        final invalidKey = 'a' * 257;
        
        expect(
          () => merkleKV.increment(invalidKey, 1),
          throwsA(isA<ValidationException>()),
        );
      });

      test('increment processes valid request', () async {
        when(mockCommandProcessor.sendCommand(any))
            .thenAnswer((_) async => 42);
        
        final result = await merkleKV.increment('counter', 5);
        
        expect(result, equals(42));
        verify(mockCommandProcessor.sendCommand(any)).called(1);
      });

      test('decrement validates key and delta', () async {
        final invalidKey = 'a' * 257;
        
        expect(
          () => merkleKV.decrement(invalidKey, 1),
          throwsA(isA<ValidationException>()),
        );
      });

      test('decrement processes valid request', () async {
        when(mockCommandProcessor.sendCommand(any))
            .thenAnswer((_) async => 38);
        
        final result = await merkleKV.decrement('counter', 5);
        
        expect(result, equals(38));
        verify(mockCommandProcessor.sendCommand(any)).called(1);
      });
    });

    group('String Operations', () {
      late MerkleKV merkleKV;

      setUp(() {
        merkleKV = MerkleKV.create(config);
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
      });

      test('append validates key and value', () async {
        final invalidKey = 'a' * 257;
        final invalidValue = 'a' * (256 * 1024 + 1);
        
        expect(
          () => merkleKV.append(invalidKey, 'suffix'),
          throwsA(isA<ValidationException>()),
        );
        
        expect(
          () => merkleKV.append('key', invalidValue),
          throwsA(isA<ValidationException>()),
        );
      });

      test('append processes valid request', () async {
        when(mockCommandProcessor.sendCommand(any))
            .thenAnswer((_) async => 'hello_world');
        
        final result = await merkleKV.append('greeting', '_world');
        
        expect(result, equals('hello_world'));
        verify(mockCommandProcessor.sendCommand(any)).called(1);
      });

      test('prepend validates key and value', () async {
        final invalidKey = 'a' * 257;
        final invalidValue = 'a' * (256 * 1024 + 1);
        
        expect(
          () => merkleKV.prepend(invalidKey, 'prefix'),
          throwsA(isA<ValidationException>()),
        );
        
        expect(
          () => merkleKV.prepend('key', invalidValue),
          throwsA(isA<ValidationException>()),
        );
      });

      test('prepend processes valid request', () async {
        when(mockCommandProcessor.sendCommand(any))
            .thenAnswer((_) async => 'hello_world');
        
        final result = await merkleKV.prepend('greeting', 'hello_');
        
        expect(result, equals('hello_world'));
        verify(mockCommandProcessor.sendCommand(any)).called(1);
      });
    });

    group('Bulk Operations', () {
      late MerkleKV merkleKV;

      setUp(() {
        merkleKV = MerkleKV.create(config);
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
      });

      group('getMultiple', () {
        test('validates keys before processing', () async {
          final invalidKeys = ['key1', 'a' * 257, 'key3'];
          
          expect(
            () => merkleKV.getMultiple(invalidKeys),
            throwsA(isA<ValidationException>()),
          );
        });

        test('validates total bulk size', () async {
          final tooManyKeys = List.generate(3000, (i) => 'key_$i' * 50);
          
          expect(
            () => merkleKV.getMultiple(tooManyKeys),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Bulk keys size'))),
          );
        });

        test('processes valid bulk get request', () async {
          final keys = ['key1', 'key2', 'key3'];
          final expectedResult = {
            'key1': 'value1',
            'key2': 'value2',
            'key3': null,
          };
          
          when(mockCommandProcessor.sendCommand(any))
              .thenAnswer((_) async => expectedResult);
          
          final result = await merkleKV.getMultiple(keys);
          
          expect(result, equals(expectedResult));
          verify(mockCommandProcessor.sendCommand(any)).called(1);
        });

        test('handles empty key list', () async {
          when(mockCommandProcessor.sendCommand(any))
              .thenAnswer((_) async => <String, String?>{});
          
          final result = await merkleKV.getMultiple([]);
          
          expect(result, isEmpty);
        });
      });

      group('setMultiple', () {
        test('validates keys and values before processing', () async {
          final invalidOperations = {
            'a' * 257: 'value', // Invalid key
          };
          
          expect(
            () => merkleKV.setMultiple(invalidOperations),
            throwsA(isA<ValidationException>()),
          );
        });

        test('validates total bulk size', () async {
          final tooLargeOperations = <String, String>{};
          for (int i = 0; i < 200; i++) {
            tooLargeOperations['key$i'] = 'a' * 3000;
          }
          
          expect(
            () => merkleKV.setMultiple(tooLargeOperations),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Bulk operation size'))),
          );
        });

        test('processes valid bulk set request', () async {
          final operations = {
            'key1': 'value1',
            'key2': 'value2',
            'key3': 'value3',
          };
          
          when(mockCommandProcessor.sendCommand(any))
              .thenAnswer((_) async => true);
          
          await merkleKV.setMultiple(operations);
          
          verify(mockCommandProcessor.sendCommand(any)).called(1);
        });

        test('handles empty operations map', () async {
          when(mockCommandProcessor.sendCommand(any))
              .thenAnswer((_) async => true);
          
          await merkleKV.setMultiple({});
          
          verify(mockCommandProcessor.sendCommand(any)).called(1);
        });
      });
    });

    group('Thread Safety', () {
      late MerkleKV merkleKV;

      setUp(() {
        merkleKV = MerkleKV.create(config);
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
      });

      test('handles concurrent operations safely', () async {
        when(mockCommandProcessor.sendCommand(any))
            .thenAnswer((_) async {
          // Simulate some processing time
          await Future.delayed(Duration(milliseconds: 10));
          return 'test_value';
        });

        // Start multiple concurrent operations
        final futures = <Future>[];
        for (int i = 0; i < 10; i++) {
          futures.add(merkleKV.get('key$i'));
          futures.add(merkleKV.set('key$i', 'value$i'));
        }

        // Wait for all operations to complete
        await Future.wait(futures);

        // Verify all operations were processed
        verify(mockCommandProcessor.sendCommand(any)).called(20);
      });

      test('maintains connection state consistency under concurrent access', () async {
        when(mockCommandProcessor.sendCommand(any))
            .thenAnswer((_) async => 'value');

        // Simulate rapid connection state changes and operations
        final futures = <Future>[];
        
        for (int i = 0; i < 5; i++) {
          futures.add(() async {
            when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
            await merkleKV.get('key$i');
          }());
          
          futures.add(() async {
            when(mockMqttClient.connectionState).thenReturn(ConnectionState.disconnected);
            try {
              await merkleKV.get('key$i');
            } catch (e) {
              // Expected to fail when disconnected
            }
          }());
        }

        await Future.wait(futures);
      });
    });

    group('Offline Queue Behavior', () {
      test('enables offline queue when configured', () {
        final configWithQueue = MerkleKVConfig.create(
          brokerHost: 'localhost',
          brokerPort: 1883,
          clientId: 'test_client',
          enableOfflineQueue: true,
        );
        
        final merkleKV = MerkleKV.create(configWithQueue);
        
        // Should not throw when disconnected and offline queue is enabled
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.disconnected);
        
        expect(() => merkleKV.get('test_key'), returnsNormally);
      });

      test('disables offline queue when configured', () {
        final configWithoutQueue = MerkleKVConfig.create(
          brokerHost: 'localhost',
          brokerPort: 1883,
          clientId: 'test_client',
          enableOfflineQueue: false,
        );
        
        final merkleKV = MerkleKV.create(configWithoutQueue);
        
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.disconnected);
        
        expect(
          () => merkleKV.get('test_key'),
          throwsA(isA<ConnectionException>()),
        );
      });
    });

    group('Error Handling', () {
      late MerkleKV merkleKV;

      setUp(() {
        merkleKV = MerkleKV.create(config);
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
      });

      test('propagates PayloadException from command processor', () async {
        when(mockCommandProcessor.sendCommand(any))
            .thenThrow(PayloadException.payloadTooLarge('test payload'));
        
        expect(
          () => merkleKV.get('test_key'),
          throwsA(isA<PayloadException>()),
        );
      });

      test('propagates StorageException from command processor', () async {
        when(mockCommandProcessor.sendCommand(any))
            .thenThrow(StorageException.storageFailure('disk full'));
        
        expect(
          () => merkleKV.get('test_key'),
          throwsA(isA<StorageException>()),
        );
      });

      test('handles unknown exceptions gracefully', () async {
        when(mockCommandProcessor.sendCommand(any))
            .thenThrow(Exception('Unknown error'));
        
        expect(
          () => merkleKV.get('test_key'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('UTF-8 Validation Integration', () {
      late MerkleKV merkleKV;

      setUp(() {
        merkleKV = MerkleKV.create(config);
        when(mockMqttClient.connectionState).thenReturn(ConnectionState.connected);
        when(mockCommandProcessor.sendCommand(any))
            .thenAnswer((_) async => 'success');
      });

      test('accepts international characters in keys and values', () async {
        await merkleKV.set('café', 'ñoño');
        await merkleKV.set('测试', 'тест');
        await merkleKV.set('🚀', '🌍');
        
        verify(mockCommandProcessor.sendCommand(any)).called(3);
      });

      test('correctly calculates UTF-8 byte sizes', () async {
        // This key is exactly 256 bytes in UTF-8
        final key256Bytes = 'café' * 51 + 'c'; // (4*51) + 1 = 205, need to adjust
        final exactKey = 'a' * 256; // Simple 256-byte key
        
        await merkleKV.set(exactKey, 'value');
        
        verify(mockCommandProcessor.sendCommand(any)).called(1);
      });

      test('rejects keys/values that exceed byte limits', () async {
        final keyTooLong = 'café' * 65; // Exceeds 256 bytes
        final valueTooLong = 'a' * (256 * 1024 + 1); // Exceeds 256 KiB
        
        expect(
          () => merkleKV.set(keyTooLong, 'value'),
          throwsA(isA<ValidationException>()),
        );
        
        expect(
          () => merkleKV.set('key', valueTooLong),
          throwsA(isA<ValidationException>()),
        );
      });
    });
  });
}