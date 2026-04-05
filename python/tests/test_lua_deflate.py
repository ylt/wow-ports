"""Tests for LuaDeflate encode/decode — canonical 23-case spec (sections M-P)."""

import os
import re
import pytest
from wow_serialization.lua_deflate import decode_for_print, encode_for_print
from wow_serialization.lua_deflate_native import (
    decode_for_print as decode_for_print_native,
    encode_for_print as encode_for_print_native,
)


def roundtrip(data: bytes) -> None:
    assert decode_for_print(encode_for_print(data)) == data


def roundtrip_native(data: bytes) -> None:
    assert decode_for_print_native(encode_for_print_native(data)) == data


# ---------------------------------------------------------------------------
# M. Encode — tests 74-79
# ---------------------------------------------------------------------------

class TestM_Encode:
    def test_M74_three_byte_input_gives_4_chars(self):
        """M74: 3-byte input → 4 encoded chars (full group)"""
        encoded = encode_for_print(b"ABC")
        assert len(encoded) == 4

    def test_M75_one_byte_input_gives_2_chars(self):
        """M75: 1-byte input → 2 encoded chars (tail)"""
        encoded = encode_for_print(b"A")
        assert len(encoded) == 2

    def test_M76_two_byte_input_gives_3_chars(self):
        """M76: 2-byte input → 3 encoded chars (tail)"""
        encoded = encode_for_print(b"AB")
        assert len(encoded) == 3

    def test_M77_six_byte_input_gives_8_chars(self):
        """M77: 6-byte input → 8 encoded chars (two full groups)"""
        # 6 bytes = 2 full groups of 3 → 8 chars
        encoded = encode_for_print(b"ABCDEF")
        assert len(encoded) == 8

    def test_M78_empty_input_gives_empty_string(self):
        """M78: empty input → empty string"""
        assert encode_for_print(b"") == ""

    def test_M79_output_uses_only_alphabet_chars(self):
        """M79: output uses only alphabet chars a-zA-Z0-9()"""
        # Alphabet: a-zA-Z0-9()
        encoded = encode_for_print(bytes(range(256)))
        assert re.fullmatch(r'[a-zA-Z0-9()]+', encoded)


# ---------------------------------------------------------------------------
# N. Decode — tests 80-86
# ---------------------------------------------------------------------------

class TestN_Decode:
    def test_N80_four_char_input_gives_3_bytes(self):
        """N80: 4-char input → 3 bytes (full group)"""
        # "aaaa" → 3 bytes (full group)
        result = decode_for_print("aaaa")
        assert len(result) == 3

    def test_N81_two_char_input_gives_1_byte(self):
        """N81: 2-char input → 1 byte (tail)"""
        # "aa" → 1 byte (tail: 2 chars → 1 byte)
        result = decode_for_print("aa")
        assert len(result) == 1

    def test_N82_three_char_input_gives_2_bytes(self):
        """N82: 3-char input → 2 bytes (tail)"""
        # Encode 2 bytes to get a 3-char string, then verify decode gives 2 bytes
        encoded = encode_for_print(b"AB")
        assert len(encoded) == 3
        result = decode_for_print(encoded)
        assert len(result) == 2

    def test_N83_whitespace_stripped_before_decode(self):
        """N83: whitespace stripped from start/end before decode"""
        encoded = encode_for_print(b"test")
        assert decode_for_print("  " + encoded + "\n") == b"test"

    def test_N84_length_1_input_returns_none_or_empty(self):
        """N84: length-1 input → None or empty"""
        # Single char is ambiguous — Lua spec returns nil
        result = decode_for_print("a")
        assert result is None or result == b""

    def test_N85_empty_string_returns_none_or_empty(self):
        """N85: empty string → None or empty"""
        # After whitespace strip, if strlen <= 1 → nil/empty
        result = decode_for_print("")
        assert result is None or result == b""

    def test_N86_invalid_character_raises(self):
        """N86: invalid character raises"""
        with pytest.raises((ValueError, KeyError, TypeError)):
            decode_for_print("!!")


# ---------------------------------------------------------------------------
# O. Round-trips — tests 87-93
# ---------------------------------------------------------------------------

class TestO_RoundTrips:
    def test_O87_simple_ascii_string(self):
        """O87: simple ASCII string"""
        roundtrip(b"Hello, World!")

    def test_O88_binary_all_256_byte_values(self):
        """O88: binary data — all 256 byte values"""
        roundtrip(bytes(range(256)))

    def test_O89_large_payload(self):
        """O89: large payload (1000+ bytes)"""
        roundtrip(os.urandom(1024))

    def test_O90_single_byte(self):
        """O90: single byte"""
        roundtrip(b"A")

    def test_O91_two_bytes(self):
        """O91: two bytes"""
        roundtrip(b"AB")

    def test_O92_three_bytes_boundary(self):
        """O92: three bytes (boundary)"""
        roundtrip(b"ABC")

    def test_O93_null_bytes_roundtrip(self):
        """O93: null bytes (0x00) round-trip correctly"""
        roundtrip(b"\x00" * 10)


# ---------------------------------------------------------------------------
# P. Native Variant — tests 94-96
# ---------------------------------------------------------------------------

class TestP_NativeVariant:
    def test_P94_native_encode_byte_identical_to_reference(self):
        """P94: native encode output byte-identical to reference encode"""
        for data in [b"hello", b"ABC", b"The quick brown fox", b"x" * 99]:
            assert encode_for_print_native(data) == encode_for_print(data), \
                f"Mismatch for: {data[:20]}"

    def test_P95_native_decode_byte_identical_to_reference(self):
        """P95: native decode output byte-identical to reference decode"""
        data = b"round trip test string 123"
        encoded = encode_for_print(data)
        assert decode_for_print_native(encoded) == decode_for_print(encoded)

    def test_P96_native_roundtrip(self):
        """P96: native round-trip"""
        roundtrip_native(b"Hello, World!")
        roundtrip_native(bytes(range(256)))
