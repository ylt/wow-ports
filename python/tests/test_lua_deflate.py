"""Tests for LuaDeflate encode/decode."""

import pytest
from wow_serialization.lua_deflate import decode_for_print, encode_for_print
from wow_serialization.lua_deflate_native import (
    decode_for_print as decode_for_print_native,
    encode_for_print as encode_for_print_native,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def roundtrip(data: bytes) -> None:
    """Assert encode → decode returns original data."""
    assert decode_for_print(encode_for_print(data)) == data


def roundtrip_native(data: bytes) -> None:
    """Assert native encode → native decode returns original data."""
    assert decode_for_print_native(encode_for_print_native(data)) == data


# ---------------------------------------------------------------------------
# Encode → decode round-trips
# ---------------------------------------------------------------------------


class TestRoundTrip:
    def test_simple_ascii(self):
        roundtrip(b"Hello, World!")

    def test_empty_bytes(self):
        # encode of empty → "" → decode returns b"" (length <= 1 path)
        assert encode_for_print(b"") == ""
        assert decode_for_print("") == b""

    def test_one_byte(self):
        roundtrip(b"A")

    def test_two_bytes(self):
        roundtrip(b"AB")

    def test_three_bytes(self):
        # Exactly one full group
        roundtrip(b"ABC")

    def test_four_bytes(self):
        # One full group + one partial (1 byte)
        roundtrip(b"ABCD")

    def test_five_bytes(self):
        roundtrip(b"ABCDE")

    def test_six_bytes(self):
        roundtrip(b"ABCDEF")

    def test_long_ascii(self):
        roundtrip(b"The quick brown fox jumps over the lazy dog")

    def test_binary_all_byte_values(self):
        data = bytes(range(256))
        roundtrip(data)

    def test_binary_zeros(self):
        roundtrip(bytes(100))

    def test_binary_all_0xff(self):
        roundtrip(bytes([0xFF] * 100))

    def test_large_payload(self):
        import os
        data = os.urandom(4096)
        roundtrip(data)


# ---------------------------------------------------------------------------
# Known encode outputs (cross-language verification)
# ---------------------------------------------------------------------------


class TestKnownOutputs:
    """
    Expected values derived from running the JS / Ruby reference implementations.

    Character set: abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()
    Indices:       0                         26                52        62 63
    """

    def test_single_a(self):
        # b"a" = 0x61 = 97
        # 1 byte → 2 chars.  value = 97.
        # char0 = 97 & 0x3F = 33 → 'H'   (26+7)
        # char1 = (97 >> 6) & 0x3F = 1 → 'b'
        assert encode_for_print(b"a") == "Hb"

    def test_single_null(self):
        # b"\x00" → value = 0 → "aa"
        assert encode_for_print(b"\x00") == "aa"

    def test_three_nulls(self):
        # b"\x00\x00\x00" → value = 0 → "aaaa"
        assert encode_for_print(b"\x00\x00\x00") == "aaaa"

    def test_decode_aa(self):
        # "aa" → 2 chars → 1 byte.  value = 0 + 0*64 = 0 → b"\x00"
        assert decode_for_print("aa") == b"\x00"

    def test_decode_aaaa(self):
        assert decode_for_print("aaaa") == b"\x00\x00\x00"

    def test_encode_decode_hello(self):
        encoded = encode_for_print(b"Hello")
        assert decode_for_print(encoded) == b"Hello"

    def test_charset_boundary_62(self):
        # Index 62 → '(' character
        # Encode b"\xf8" = 248.  1 byte → 2 chars.
        # value = 248. char0 = 248 & 0x3F = 56 → '4' (52+4). char1 = 248>>6 = 3 → 'd'
        assert encode_for_print(b"\xf8") == "4d"

    def test_charset_boundary_63(self):
        # Index 63 → ')' character.  Ensure it round-trips.
        # Build a byte that produces index 63 as first char: value & 0x3F = 63
        # b"\xff" = 255. 1 byte → 2 chars. char0 = 255 & 63 = 63 → ')'. char1 = 3 → 'd'
        assert encode_for_print(b"\xff") == ")d"
        assert decode_for_print(")d") == b"\xff"

    def test_whitespace_stripped_on_decode(self):
        encoded = encode_for_print(b"test")
        assert decode_for_print("  " + encoded + "\n") == b"test"


# ---------------------------------------------------------------------------
# Edge / error cases
# ---------------------------------------------------------------------------


class TestEdgeCases:
    def test_decode_length_one_returns_empty(self):
        # A single char is ambiguous — implementation returns b""
        assert decode_for_print("a") == b""

    def test_decode_invalid_char_raises(self):
        with pytest.raises((ValueError, KeyError, TypeError)):
            decode_for_print("!!")

    def test_encode_wrong_type_raises(self):
        with pytest.raises(TypeError):
            encode_for_print("not bytes")

    def test_decode_wrong_type_raises(self):
        with pytest.raises(TypeError):
            decode_for_print(12345)


# ---------------------------------------------------------------------------
# Native variant produces identical output
# ---------------------------------------------------------------------------


class TestNativeVariant:
    def test_roundtrip_empty(self):
        assert encode_for_print_native(b"") == ""
        assert decode_for_print_native("") == b""

    def test_matches_reference_one_byte(self):
        data = b"x"
        assert encode_for_print_native(data) == encode_for_print(data)
        assert decode_for_print_native(encode_for_print(data)) == data

    def test_matches_reference_three_bytes(self):
        data = b"ABC"
        assert encode_for_print_native(data) == encode_for_print(data)

    def test_matches_reference_all_bytes(self):
        data = bytes(range(256))
        assert encode_for_print_native(data) == encode_for_print(data)
        assert decode_for_print_native(encode_for_print_native(data)) == data

    def test_roundtrip_native(self):
        roundtrip_native(b"Hello, World!")
        roundtrip_native(bytes(range(256)))
