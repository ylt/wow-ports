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
    def test_74_three_byte_input_gives_4_chars(self):
        encoded = encode_for_print(b"ABC")
        assert len(encoded) == 4

    def test_75_one_byte_input_gives_2_chars(self):
        encoded = encode_for_print(b"A")
        assert len(encoded) == 2

    def test_76_two_byte_input_gives_3_chars(self):
        encoded = encode_for_print(b"AB")
        assert len(encoded) == 3

    def test_77_six_byte_input_gives_8_chars(self):
        # 6 bytes = 2 full groups of 3 → 8 chars
        encoded = encode_for_print(b"ABCDEF")
        assert len(encoded) == 8

    def test_78_empty_input_gives_empty_string(self):
        assert encode_for_print(b"") == ""

    def test_79_output_uses_only_alphabet_chars(self):
        # Alphabet: a-zA-Z0-9()
        encoded = encode_for_print(bytes(range(256)))
        assert re.fullmatch(r'[a-zA-Z0-9()]+', encoded)


# ---------------------------------------------------------------------------
# N. Decode — tests 80-86
# ---------------------------------------------------------------------------

class TestN_Decode:
    def test_80_four_char_input_gives_3_bytes(self):
        # "aaaa" → 3 bytes (full group)
        result = decode_for_print("aaaa")
        assert len(result) == 3

    def test_81_two_char_input_gives_1_byte(self):
        # "aa" → 1 byte (tail: 2 chars → 1 byte)
        result = decode_for_print("aa")
        assert len(result) == 1

    def test_82_three_char_input_gives_2_bytes(self):
        # Encode 2 bytes to get a 3-char string, then verify decode gives 2 bytes
        encoded = encode_for_print(b"AB")
        assert len(encoded) == 3
        result = decode_for_print(encoded)
        assert len(result) == 2

    def test_83_whitespace_stripped_before_decode(self):
        encoded = encode_for_print(b"test")
        assert decode_for_print("  " + encoded + "\n") == b"test"

    def test_84_length_1_input_returns_none_or_empty(self):
        # Single char is ambiguous — Lua spec returns nil
        result = decode_for_print("a")
        assert result is None or result == b""

    def test_85_empty_string_returns_none_or_empty(self):
        # After whitespace strip, if strlen <= 1 → nil/empty
        result = decode_for_print("")
        assert result is None or result == b""

    def test_86_invalid_character_raises(self):
        with pytest.raises((ValueError, KeyError, TypeError)):
            decode_for_print("!!")


# ---------------------------------------------------------------------------
# O. Round-trips — tests 87-93
# ---------------------------------------------------------------------------

class TestO_RoundTrips:
    def test_87_simple_ascii_string(self):
        roundtrip(b"Hello, World!")

    def test_88_binary_all_256_byte_values(self):
        roundtrip(bytes(range(256)))

    def test_89_large_payload(self):
        roundtrip(os.urandom(1024))

    def test_90_single_byte(self):
        roundtrip(b"A")

    def test_91_two_bytes(self):
        roundtrip(b"AB")

    def test_92_three_bytes_boundary(self):
        roundtrip(b"ABC")

    def test_93_null_bytes_roundtrip(self):
        roundtrip(b"\x00" * 10)


# ---------------------------------------------------------------------------
# P. Native Variant — tests 94-96
# ---------------------------------------------------------------------------

class TestP_NativeVariant:
    def test_94_native_encode_byte_identical_to_reference(self):
        for data in [b"hello", b"ABC", b"The quick brown fox", b"x" * 99]:
            assert encode_for_print_native(data) == encode_for_print(data), \
                f"Mismatch for: {data[:20]}"

    def test_95_native_decode_byte_identical_to_reference(self):
        data = b"round trip test string 123"
        encoded = encode_for_print(data)
        assert decode_for_print_native(encoded) == decode_for_print(encoded)

    def test_96_native_roundtrip(self):
        roundtrip_native(b"Hello, World!")
        roundtrip_native(bytes(range(256)))
