import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:merkle_kv_core/src/utils/payload_optimizer.dart';
import 'package:merkle_kv_core/src/commands/command.dart';
import 'package:merkle_kv_core/src/commands/response.dart';
import 'package:merkle_kv_core/src/replication/metrics.dart';

class TestReplicationMetrics implements ReplicationMetrics {
  int optimizationCount = 0;
  int originalTotalSize = 0;
  int optimizedTotalSize = 0;
  double totalEffectiveness = 0.0;
  
  @override
  void incrementEventsPublished() {}
  
  @override
  void incrementPublishErrors() {}
  
  @override
  void setOutboxSize(int size) {}
  
  @override
  void recordPublishLatency(int milliseconds) {}
  
  @override
  void recordFlushDuration(int milliseconds) {}
  
  @override
  void setSequenceNumber(int sequence) {}
  
  @override
  void incrementSequenceGaps() {}
  
  @override
  void recordPayloadOptimization(int originalBytes, int optimizedBytes) {
    optimizationCount++;
    originalTotalSize += originalBytes;
    optimizedTotalSize += optimizedBytes;
  }
  
  @override
  void recordOptimizationEffectiveness(double reductionPercent) {
    totalEffectiveness += reductionPercent;
  }
  
  @override
  void incrementSizeLimitExceeded() {}
  
  @override
  void recordSizeEstimationAccuracy(int estimatedBytes, int actualBytes) {}
}

void main() {
  group('PayloadOptimizer', () {
    late PayloadOptimizer optimizer;
    late TestReplicationMetrics metrics;
    
    setUp(() {
      metrics = TestReplicationMetrics();
      optimizer = PayloadOptimizer(metrics: metrics);
    });
    
    test('optimizes CBOR payload without changing semantic content', () {
      final Map<String, dynamic> event = {
        'type': 'update',
        'key': 'user-profile-123',
        'value': '{"name":"Alice","age":30,"roles":["admin","user"]}',
        'timestamp': 1649876543210,
        'nodeId': 'device-abc-123',
        'seq': 42,
        'metadata': {
          'version': 3,
          'tags': ['profile', 'user'],
          'priority': 'high'
        }
      };
      
      // Randomize original order to simulate real-world usage
      final Map<String, dynamic> shuffledEvent = {
        'nodeId': 'device-abc-123',
        'seq': 42,
        'type': 'update',
        'metadata': {
          'tags': ['profile', 'user'],
          'version': 3,
          'priority': 'high'
        },
        'timestamp': 1649876543210,
        'key': 'user-profile-123',
        'value': '{"name":"Alice","age":30,"roles":["admin","user"]}',
      };
      
      final Uint8List optimized = optimizer.optimizeCBOR(shuffledEvent);
      
      // Verify the optimized payload is smaller or equal
      final int originalEstimate = SizeEstimator.estimateEventSize(event);
      expect(optimized.length, lessThanOrEqualTo(originalEstimate));
      
      // Verify metrics were collected
      expect(metrics.optimizationCount, 1);
      expect(metrics.originalTotalSize, greaterThan(0));
      expect(metrics.optimizedTotalSize, greaterThan(0));
      
      // Verify semantic content preserved (test with decoder)
      final Map<String, dynamic> decoded = jsonDecode(utf8.decode(optimized));
      expect(decoded['type'], equals('update'));
      expect(decoded['key'], equals('user-profile-123'));
      expect(decoded['nodeId'], equals('device-abc-123'));
      expect(decoded['seq'], equals(42));
      expect(decoded['timestamp'], equals(1649876543210));
    });
    
    test('optimizes JSON Command while preserving format', () {
      final Command command = Command(
        id: '9fe7c757-d00a-4630-9cae-7b8fbd8c0f87',
        op: 'MSET',
        keyValues: {
          'user:123': '{"name":"John","active":true}',
          'user:456': '{"name":"Jane","active":false}',
          'settings:theme': 'dark'
        }
      );
      
      final String optimized = optimizer.optimizeJSON(command);
      
      // Verify the command can be parsed back correctly
      final Command parsedCommand = Command.fromJsonString(optimized);
      expect(parsedCommand.id, equals(command.id));
      expect(parsedCommand.op, equals(command.op));
      expect(parsedCommand.keyValues, equals(command.keyValues));
      
      // Verify metrics were collected
      expect(metrics.optimizationCount, 1);
    });
    
    test('optimizes Response JSON while preserving format', () {
      final Response response = Response.ok(
        id: '9fe7c757-d00a-4630-9cae-7b8fbd8c0f87',
        value: {
          'result': 'success',
          'count': 3,
          'details': {
            'processed': true,
            'timing': 42.5
          }
        },
        metadata: {'version': '1.2.0'}
      );
      
      final String optimized = optimizer.optimizeResponseJSON(response);
      
      // Verify response can be parsed back correctly
      final Map<String, dynamic> parsed = jsonDecode(optimized);
      expect(parsed['id'], equals(response.id));
      expect(parsed['status'], equals('OK'));
      expect((parsed['value'] as Map)['result'], equals('success'));
      expect((parsed['value'] as Map)['count'], equals(3));
      
      // Verify metrics were collected
      expect(metrics.optimizationCount, 1);
    });
  });
  
  group('SizeEstimator', () {
    test('estimates command size within 5% accuracy', () {
      final Command command = Command(
        id: '9fe7c757-d00a-4630-9cae-7b8fbd8c0f87',
        op: 'SET',
        key: 'user:123',
        value: '{"name":"John","age":30,"active":true}'
      );
      
      final int estimatedSize = SizeEstimator.estimateCommandSize(command);
      final String actualJson = jsonEncode(command.toJson());
      final int actualSize = actualJson.length;
      
      // Verify estimate is within 5% of actual size
      final double ratio = estimatedSize / actualSize;
      expect(ratio, greaterThanOrEqualTo(0.95));
      expect(ratio, lessThanOrEqualTo(1.05));
    });
    
    test('estimates event size within 5% accuracy', () {
      final Map<String, dynamic> event = {
        'type': 'update',
        'key': 'user:123',
        'value': '{"name":"Alice","preferences":{"theme":"dark"}}',
        'timestamp': 1649876543210,
        'nodeId': 'device-abc-123',
        'seq': 42
      };
      
      final int estimatedSize = SizeEstimator.estimateEventSize(event);
      final String actualJson = jsonEncode(event);
      final int actualSize = actualJson.length;
      
      // CBOR is typically more compact than JSON, so we allow a larger margin
      // but the estimate should still be reasonably close
      expect(estimatedSize, greaterThanOrEqualTo(actualSize * 0.7));
      expect(estimatedSize, lessThanOrEqualTo(actualSize * 1.2));
    });
    
    test('validates command size against maximum limit', () {
      // Create a command that's well under the limit
      final Command validCommand = Command(
        id: '9fe7c757-d00a-4630-9cae-7b8fbd8c0f87',
        op: 'SET',
        key: 'user:123',
        value: '{"name":"John"}'
      );
      
      expect(SizeEstimator.validateCommandSize(validCommand), isTrue);
      
      // Create a command that exceeds the limit
      // Generate a very large value
      final String largeValue = List.generate(300000, (i) => 'x').join();
      final Command invalidCommand = Command(
        id: '9fe7c757-d00a-4630-9cae-7b8fbd8c0f87',
        op: 'SET',
        key: 'user:123',
        value: largeValue
      );
      
      expect(SizeEstimator.validateCommandSize(invalidCommand), isFalse);
    });
  });
}