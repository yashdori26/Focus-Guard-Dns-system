import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/daemon/core/ring_buffer_pool.dart';
import 'package:focus_dns/engine/daemon/core/zero_battery_dns_processor.dart';

void main() {
  late RingBufferPool pool;
  late ZeroBatteryDnsProcessor processor;

  setUp(() {
    pool = RingBufferPool(capacity: 16);
    processor = ZeroBatteryDnsProcessor(
      bufferPool: pool,
      isDomainBlocked: (domain) =>
          domain == 'www.instagram.com' ||
          domain == 'tiktok.com' ||
          domain == 'pornhub.com',
    );
  });

  Uint8List buildQueryPacket(String domain, {int qType = DnsRecordType.a, bool recursionDesired = true}) {
    final buffer = Uint8List(512);
    final view = ByteData.sublistView(buffer);

    view.setUint16(0, 0xABCD); // Transaction ID
    int flags = 0x0000;
    if (recursionDesired) flags |= 0x0100;
    view.setUint16(2, flags);
    view.setUint16(4, 1); // QDCOUNT = 1
    view.setUint16(6, 0); // ANCOUNT = 0
    view.setUint16(8, 0);
    view.setUint16(10, 0);

    int offset = 12;
    for (final label in domain.split('.')) {
      buffer[offset++] = label.length;
      for (int i = 0; i < label.length; i++) {
        buffer[offset++] = label.codeUnitAt(i);
      }
    }
    buffer[offset++] = 0; // End of QNAME

    view.setUint16(offset, qType);
    offset += 2;
    view.setUint16(offset, 1); // QCLASS: IN
    offset += 2;

    return buffer.sublist(0, offset);
  }

  group('ZeroBatteryDnsProcessor Byte-Level Parsing Tests', () {
    test('Parses valid IPv4 DNS query correctly', () {
      final raw = buildQueryPacket('www.google.com');
      final payload = processor.parseQuery(raw, raw.length);

      expect(payload, isNotNull);
      expect(payload!.transactionId, equals(0xABCD));
      expect(payload.domain, equals('www.google.com'));
      expect(payload.queryType, equals(DnsRecordType.a));
      expect(payload.recursionDesired, isTrue);
      expect(payload.isStandardQuery, isTrue);
    });

    test('Parses HTTPS and AAAA DNS query types', () {
      final rawHttps = buildQueryPacket('cloudflare.com', qType: DnsRecordType.https);
      final payloadHttps = processor.parseQuery(rawHttps, rawHttps.length);
      expect(payloadHttps!.queryType, equals(DnsRecordType.https));

      final rawAaaa = buildQueryPacket('ipv6.google.com', qType: DnsRecordType.aaaa);
      final payloadAaaa = processor.parseQuery(rawAaaa, rawAaaa.length);
      expect(payloadAaaa!.queryType, equals(DnsRecordType.aaaa));
    });

    test('Rejects truncated packet (< 12 bytes) gracefully without exception', () {
      final truncated = Uint8List(8);
      final payload = processor.parseQuery(truncated, truncated.length);
      expect(payload, isNull);
      expect(processor.parsingErrors, equals(1));
    });

    test('Rejects packet with corrupted label length offset', () {
      final raw = Uint8List.fromList([
        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x50, // Claims 80 bytes follow, but only 2 remain!
        0x01, 0x02,
      ]);
      final payload = processor.parseQuery(raw, raw.length);
      expect(payload, isNull);
      expect(processor.parsingErrors, equals(1));
    });

    test('Payload toJson serialization round-trip', () {
      final raw = buildQueryPacket('subdomain.example.com');
      final payload = processor.parseQuery(raw, raw.length);
      final json = payload!.toJson();

      expect(json['domain'], equals('subdomain.example.com'));
      expect(json['transactionId'], equals(0xABCD));
    });
  });

  group('ZeroBatteryDnsProcessor Sinkhole & Synthesis Tests', () {
    test('Allowed domain query returns null (forwarded to upstream)', () {
      final raw = buildQueryPacket('wikipedia.org');
      final response = processor.processInboundPacket(raw, raw.length);

      expect(response, isNull);
      expect(processor.forwardedQueries, equals(1));
      expect(processor.blockedQueries, equals(0));
    });

    test('Blocked domain query synthesizes immediate RFC 1035 NXDOMAIN response', () {
      final raw = buildQueryPacket('www.instagram.com');
      final response = processor.processInboundPacket(raw, raw.length);

      expect(response, isNotNull);
      expect(processor.blockedQueries, equals(1));

      // Inspect synthesized response flags
      final view = ByteData.sublistView(response!.bytes, 0, response.length);
      final int txId = view.getUint16(0);
      final int flags = view.getUint16(2);
      final int qdCount = view.getUint16(4);
      final int anCount = view.getUint16(6);

      expect(txId, equals(0xABCD));
      // QR bit = 1 (response)
      expect((flags >> 15) & 0x01, equals(1));
      // RCODE = 3 (Name Error / NXDOMAIN)
      expect(flags & 0x0F, equals(DnsRcode.nameError));
      expect(qdCount, equals(1));
      expect(anCount, equals(0)); // 0 answers in NXDOMAIN

      response.release();
    });

    test('Synthesizes 0.0.0.0 A-record sinkhole response', () {
      final raw = buildQueryPacket('pornhub.com');
      final payload = processor.parseQuery(raw, raw.length)!;
      final response = processor.synthesizeZeroIpResponse(raw, raw.length, payload);

      final view = ByteData.sublistView(response.bytes, 0, response.length);
      final int flags = view.getUint16(2);
      final int anCount = view.getUint16(6);

      // NOERROR (0)
      expect(flags & 0x0F, equals(DnsRcode.noError));
      // 1 Answer Record
      expect(anCount, equals(1));

      // Verify last 4 bytes are 0.0.0.0
      final int len = response.length;
      expect(response.bytes[len - 4], equals(0));
      expect(response.bytes[len - 3], equals(0));
      expect(response.bytes[len - 2], equals(0));
      expect(response.bytes[len - 1], equals(0));

      response.release();
    });
  });
}
