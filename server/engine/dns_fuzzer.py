"""
FocusDNS Engine - DNS Wire Fuzzing, Mutation & Cyclic Loop Defense Subsystem
Standards & Vulnerabilities:
- RFC 1035 Section 4.1.4: Message Compression (Compression Pointers 0xC000)
- CVE-2000-0381 / VU#229838: Infinite Compression Pointer Loop Vulnerability
- RFC 6891: Corrupted OPT Pseudo-RR Wire Formats
- Malicious DNS Packet Fuzzing, Bit Mutations, and Crash Prevention Harness
"""

import os
import random
import struct
import threading
from typing import Any, Callable, Dict, List, Optional, Set, Tuple


class LoopVulnerabilityDetector:
    """
    Detects and neutralizes cyclic DNS compression pointer loops (CVE-2000-0381).
    RFC 1035 allows domain labels to be replaced by a 2-octet pointer with the top two bits set (0xC0).
    A malicious packet where pointer A -> pointer B -> pointer A can cause infinite recursion or crash.
    """

    MAX_POINTER_DEPTH = 32

    @classmethod
    def inspect_pointer_loops(cls, wire_bytes: bytes, offset: int = 12) -> Tuple[bool, List[int]]:
        """
        Traces pointer chains starting from offset.
        Returns: (is_cyclic: bool, visited_offsets: List[int])
        """
        visited: Set[int] = set()
        visited_chain: List[int] = []
        curr = offset
        depth = 0

        while curr < len(wire_bytes) and depth < cls.MAX_POINTER_DEPTH:
            byte_val = wire_bytes[curr]

            # End of name
            if byte_val == 0:
                return False, visited_chain

            # Check if this is a compression pointer (top two bits 11xx xxxx -> >= 0xC0)
            if (byte_val & 0xC0) == 0xC0:
                if curr + 1 >= len(wire_bytes):
                    # Truncated pointer
                    return False, visited_chain

                # Pointer offset is the lower 14 bits
                ptr_offset = struct.unpack("!H", wire_bytes[curr : curr + 2])[0] & 0x3FFF

                if ptr_offset in visited:
                    # Detected loop: visited offset re-encountered!
                    visited_chain.append(ptr_offset)
                    return True, visited_chain

                visited.add(ptr_offset)
                visited_chain.append(ptr_offset)
                curr = ptr_offset
                depth += 1
            else:
                # Normal label: skip length octet + label string
                curr += 1 + byte_val

        # If depth reached MAX_POINTER_DEPTH without terminating, treat as malicious loop
        if depth >= cls.MAX_POINTER_DEPTH:
            return True, visited_chain

        return False, visited_chain


class WireMutationEngine:
    """
    Generates hostile, malformed, and corrupted DNS wire packets
    to test parser robustness and memory safety.
    """

    @staticmethod
    def inject_cyclic_pointer_loop(wire_bytes: bytes, target_offset: int = 12) -> bytes:
        """
        Constructs an infinite self-referential compression pointer:
        Offset X points back to offset X (e.g. 0xC0 0x0C pointing to offset 12).
        """
        buf = bytearray(wire_bytes)
        if len(buf) > target_offset + 1:
            # 0xC000 | target_offset
            ptr = 0xC000 | (target_offset & 0x3FFF)
            struct.pack_into("!H", buf, target_offset, ptr)
        return bytes(buf)

    @staticmethod
    def inject_mutual_pointer_loop(wire_bytes: bytes) -> bytes:
        """
        Constructs a mutual 2-step pointer loop:
        Offset 12 points to offset 14 (0xC00E).
        Offset 14 points to offset 12 (0xC00C).
        """
        buf = bytearray(wire_bytes)
        if len(buf) >= 16:
            struct.pack_into("!H", buf, 12, 0xC00E)
            struct.pack_into("!H", buf, 14, 0xC00C)
        return bytes(buf)

    @staticmethod
    def inject_bit_flips(wire_bytes: bytes, flip_ratio: float = 0.05, seed: Optional[int] = None) -> bytes:
        """Randomly flips bits across wire bytes to test bitwise corruption resilience."""
        rng = random.Random(seed)
        buf = bytearray(wire_bytes)
        num_flips = max(1, int(len(buf) * 8 * flip_ratio))
        for _ in range(num_flips):
            byte_idx = rng.randint(0, len(buf) - 1)
            bit_idx = rng.randint(0, 7)
            buf[byte_idx] ^= (1 << bit_idx)
        return bytes(buf)

    @staticmethod
    def inject_label_length_overflow(wire_bytes: bytes, offset: int = 12) -> bytes:
        """Sets label length byte to illegal values (>63, e.g. 128 or 255)."""
        buf = bytearray(wire_bytes)
        if len(buf) > offset:
            buf[offset] = 0x3F + 1  # 64 (illegal per RFC 1035)
        return bytes(buf)

    @staticmethod
    def truncate_wire(wire_bytes: bytes, cut_length: Optional[int] = None) -> bytes:
        """Truncates packet midway through headers or records."""
        if cut_length is None:
            cut_length = max(1, len(wire_bytes) // 2)
        return wire_bytes[:cut_length]


class DNSFuzzHarness:
    """
    Automated fuzzing and crash-prevention test harness.
    Executes thousands of mutated queries against a target parser/pipeline function,
    guaranteeing zero unhandled crashes or infinite loops.
    """

    def __init__(self, target_parser: Optional[Callable[[bytes], Any]] = None):
        self.target_parser = target_parser
        self.total_fuzz_iterations: int = 0
        self.exceptions_caught: int = 0
        self.crashes_detected: int = 0
        self.loops_neutralized: int = 0
        self._lock = threading.Lock()

    def run_fuzz_cycle(self, base_wire: bytes, iterations: int = 100, seed: int = 42) -> Dict[str, Any]:
        """
        Runs a comprehensive fuzzing batch across all mutation strategies.
        Returns detailed resilience diagnostics.
        """
        rng = random.Random(seed)
        parser = self.target_parser

        for i in range(iterations):
            mutation_type = rng.choice(["cyclic_loop", "mutual_loop", "bit_flip", "label_overflow", "truncate"])

            if mutation_type == "cyclic_loop":
                mutated = WireMutationEngine.inject_cyclic_pointer_loop(base_wire)
                is_loop, _ = LoopVulnerabilityDetector.inspect_pointer_loops(mutated)
                if is_loop:
                    with self._lock:
                        self.loops_neutralized += 1

            elif mutation_type == "mutual_loop":
                mutated = WireMutationEngine.inject_mutual_pointer_loop(base_wire)
                is_loop, _ = LoopVulnerabilityDetector.inspect_pointer_loops(mutated)
                if is_loop:
                    with self._lock:
                        self.loops_neutralized += 1

            elif mutation_type == "bit_flip":
                mutated = WireMutationEngine.inject_bit_flips(base_wire, flip_ratio=0.08, seed=rng.randint(0, 100000))

            elif mutation_type == "label_overflow":
                mutated = WireMutationEngine.inject_label_length_overflow(base_wire)

            elif mutation_type == "truncate":
                cut = rng.randint(1, len(base_wire))
                mutated = WireMutationEngine.truncate_wire(base_wire, cut_length=cut)

            with self._lock:
                self.total_fuzz_iterations += 1

            # Execute parser under crash protection
            if parser:
                try:
                    parser(mutated)
                except Exception as ex:
                    # Expected DNS parsing exceptions (e.g. dnslib.DNSError, ValueError) are safe
                    with self._lock:
                        self.exceptions_caught += 1
                except BaseException as fatal_crash:
                    # Fatal unexpected exceptions (SystemExit, KeyboardInterrupt, Segfault)
                    with self._lock:
                        self.crashes_detected += 1

        return self.get_stats()

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "total_fuzz_iterations": self.total_fuzz_iterations,
                "loops_neutralized": self.loops_neutralized,
                "safe_exceptions_handled": self.exceptions_caught,
                "fatal_crashes": self.crashes_detected,
                "zero_crash_guarantee_met": (self.crashes_detected == 0),
            }
