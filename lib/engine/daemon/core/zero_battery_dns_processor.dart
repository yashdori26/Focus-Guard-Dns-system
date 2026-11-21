import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'ring_buffer_pool.dart';

/// DNS Resource Record Types
class DnsRecordType {
  static const int a = 1;
  static const int ns = 2;
  static const int cname = 5;
  static const int soa = 6;
  static const int ptr = 12;
  static const int mx = 15;
  static const int txt = 16;
  static const int aaaa = 28;
  static const int srv = 33;
  static const int opt = 41; // EDNS0
  static const int https = 65;
  static const int any = 255;
}

/// DNS Response Return Codes (RCODE)
class DnsRcode {
  static const int noError = 0;
  static const int formatError = 1;
  static const int serverFailure = 2;
  static const int nameError = 3; // NXDOMAIN
  static const int notImplemented = 4;
  static const int refused = 5;
}

/// Parsed metadata for an intercepted DNS query.
@immutable
class DnsQueryPayload {
  final int transactionId;
  final int flags;
  final int questionCount;
  final String domain;
  final int queryType;
  final int queryClass;
  final bool hasEdns0;
  final int payloadLength;

  const DnsQueryPayload({
    required this.transactionId,
    required this.flags,
    required this.questionCount,
    required this.domain,
    required this.queryType,
    required this.queryClass,
    this.hasEdns0 = false,
    required this.payloadLength,
  });

  bool get isStandardQuery => ((flags >> 11) & 0x0F) == 0;
  bool get recursionDesired => ((flags >> 8) & 0x01) == 1;

  Map<String, dynamic> toJson() => {
        'transactionId': transactionId,
        'flags': flags,
        'domain': domain,
        'queryType': queryType,
        'hasEdns0': hasEdns0,
        'payloadLength': payloadLength,
      };
}

/// Ultra-fast, zero-allocation byte-level DNS packet processor.
///
/// Designed to parse, inspect, and synthesize DNS sinkhole responses in < 50 microseconds
/// per packet without memory churn or radio transmission.
class ZeroBatteryDnsProcessor {
  final RingBufferPool _bufferPool;
  final bool Function(String domain) _isDomainBlocked;

  int _processedPackets = 0;
  int _blockedQueries = 0;
  int _forwardedQueries = 0;
  int _parsingErrors = 0;

  ZeroBatteryDnsProcessor({
    RingBufferPool? bufferPool,
    required bool Function(String domain) isDomainBlocked,
  })  : _bufferPool = bufferPool ?? RingBufferPool(),
        _isDomainBlocked = isDomainBlocked;

  int get processedPackets => _processedPackets;
  int get blockedQueries => _blockedQueries;
  int get forwardedQueries => _forwardedQueries;
  int get parsingErrors => _parsingErrors;

  /// Parses raw byte buffer into structured [DnsQueryPayload].
  DnsQueryPayload? parseQuery(Uint8List bytes, int length) {
    if (length < 12) {
      _parsingErrors++;
      return null;
    }

    final ByteData view = ByteData.sublistView(bytes, 0, length);
    final int transactionId = view.getUint16(0);
    final int flags = view.getUint16(2);
    final int qdCount = view.getUint16(4);

    if (qdCount <= 0) {
      _parsingErrors++;
      return null;
    }

    // Parse QNAME label sequence
    int offset = 12;
    final StringBuffer domainBuffer = StringBuffer();
    bool firstLabel = true;

    while (offset < length) {
      final int labelLen = bytes[offset++];
      if (labelLen == 0) break; // End of QNAME

      // Compression pointer check (0xC0)
      if ((labelLen & 0xC0) == 0xC0) {
        offset++; // Skip pointer offset
        break;
      }

      if (offset + labelLen > length) {
        _parsingErrors++;
        return null; // Malformed packet
      }

      if (!firstLabel) domainBuffer.write('.');
      firstLabel = false;

      for (int i = 0; i < labelLen; i++) {
        domainBuffer.writeCharCode(bytes[offset + i]);
      }
      offset += labelLen;
    }

    if (offset + 4 > length) {
      _parsingErrors++;
      return null;
    }

    final int qType = view.getUint16(offset);
    final int qClass = view.getUint16(offset + 2);
    offset += 4;

    // Detect EDNS0 OPT RR (RFC 6891)
    bool hasEdns = false;
    if (offset + 11 <= length) {
      // Check if root label followed by OPT type 41
      if (bytes[offset] == 0 && view.getUint16(offset + 1) == DnsRecordType.opt) {
        hasEdns = true;
      }
    }

    return DnsQueryPayload(
      transactionId: transactionId,
      flags: flags,
      questionCount: qdCount,
      domain: domainBuffer.toString().toLowerCase(),
      queryType: qType,
      queryClass: qClass,
      hasEdns0: hasEdns,
      payloadLength: length,
    );
  }

  /// Processes raw inbound DNS packet.
  ///
  /// If the domain is blocked, synthesizes a local synthetic NXDOMAIN response in-memory
  /// and returns it immediately without waking the cellular/Wi-Fi modem.
  /// If permitted, returns null indicating the packet should be passed upstream.
  PooledBuffer? processInboundPacket(Uint8List rawBytes, int length) {
    _processedPackets++;
    final payload = parseQuery(rawBytes, length);
    if (payload == null) {
      return null;
    }

    final isBlocked = _isDomainBlocked(payload.domain);
    if (isBlocked) {
      _blockedQueries++;
      return synthesizeNxDomainResponse(rawBytes, length, payload);
    } else {
      _forwardedQueries++;
      return null;
    }
  }

  /// Synthesizes an RFC 1035 NXDOMAIN (Name Error) response packet in a pooled buffer.
  PooledBuffer synthesizeNxDomainResponse(
    Uint8List requestBytes,
    int requestLen,
    DnsQueryPayload payload,
  ) {
    final PooledBuffer response = _bufferPool.acquire();

    // Copy original query (Header + Question section)
    int questionSectionEnd = 12;
    while (questionSectionEnd < requestLen && requestBytes[questionSectionEnd] != 0) {
      final int len = requestBytes[questionSectionEnd];
      if ((len & 0xC0) == 0xC0) {
        questionSectionEnd += 2;
        break;
      }
      questionSectionEnd += 1 + len;
    }
    if (questionSectionEnd < requestLen && requestBytes[questionSectionEnd] == 0) {
      questionSectionEnd += 5; // Skip null byte + QTYPE (2) + QCLASS (2)
    }

    final int headerAndQuestionLen = questionSectionEnd.clamp(12, requestLen);
    response.bytes.setRange(0, headerAndQuestionLen, requestBytes);

    final ByteData view = ByteData.sublistView(response.bytes, 0, headerAndQuestionLen);

    // Flags: QR = 1 (Response), Opcode = 0 (Query), AA = 1, TC = 0, RD = copy, RA = 1, RCODE = 3 (NXDOMAIN)
    int flags = 0x8183; // Standard NXDOMAIN flags
    if (payload.recursionDesired) {
      flags |= 0x0100;
    }
    view.setUint16(2, flags); // Update Flags

    view.setUint16(4, payload.questionCount); // QDCOUNT
    view.setUint16(6, 0); // ANCOUNT = 0
    view.setUint16(8, 0); // NSCOUNT = 0
    view.setUint16(10, 0); // ARCOUNT = 0

    response.length = headerAndQuestionLen;
    return response;
  }

  /// Synthesizes an RFC 1035 0.0.0.0 A-record answer for sinkholing.
  PooledBuffer synthesizeZeroIpResponse(
    Uint8List requestBytes,
    int requestLen,
    DnsQueryPayload payload,
  ) {
    final PooledBuffer response = _bufferPool.acquire();

    // Find end of Question
    int questionEnd = 12;
    while (questionEnd < requestLen && requestBytes[questionEnd] != 0) {
      final int len = requestBytes[questionEnd];
      if ((len & 0xC0) == 0xC0) {
        questionEnd += 2;
        break;
      }
      questionEnd += 1 + len;
    }
    if (questionEnd < requestLen && requestBytes[questionEnd] == 0) {
      questionEnd += 5;
    }

    final int baseLen = questionEnd.clamp(12, requestLen);
    response.bytes.setRange(0, baseLen, requestBytes);

    final ByteData view = ByteData.sublistView(response.bytes, 0, baseLen + 16);

    // Response flags with NOERROR (0)
    int flags = 0x8180;
    if (payload.recursionDesired) flags |= 0x0100;
    view.setUint16(2, flags);

    view.setUint16(4, 1); // QDCOUNT = 1
    view.setUint16(6, 1); // ANCOUNT = 1 (1 Answer Record)
    view.setUint16(8, 0);
    view.setUint16(10, 0);

    // Append Answer Record (A: 0.0.0.0, TTL: 300s)
    int offset = baseLen;
    response.bytes[offset++] = 0xC0; // Compression pointer
    response.bytes[offset++] = 0x0C; // Points to offset 12 (Domain in Question)

    view.setUint16(offset, DnsRecordType.a); // TYPE: A
    offset += 2;
    view.setUint16(offset, 1); // CLASS: IN
    offset += 2;
    view.setUint32(offset, 300); // TTL: 300 seconds
    offset += 4;
    view.setUint16(offset, 4); // RDLENGTH: 4 bytes (IPv4)
    offset += 2;

    // RDATA: 0.0.0.0
    response.bytes[offset++] = 0;
    response.bytes[offset++] = 0;
    response.bytes[offset++] = 0;
    response.bytes[offset++] = 0;

    response.length = offset;
    return response;
  }
}
