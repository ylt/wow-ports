"""Tests for WowCbor wrapper."""

import pytest
import cbor2
from wow_serialization.wow_cbor import WowCbor


# ── encode/decode round-trip ───────────────────────────────────────────────


class TestRoundTrip:
    def test_string(self):
        assert WowCbor.decode(WowCbor.encode("hello")) == "hello"

    def test_integer(self):
        assert WowCbor.decode(WowCbor.encode(42)) == 42

    def test_boolean(self):
        assert WowCbor.decode(WowCbor.encode(True)) is True

    def test_none(self):
        assert WowCbor.decode(WowCbor.encode(None)) is None

    def test_string_keyed_dict(self):
        data = {"key": "value", "num": 7}
        result = WowCbor.decode(WowCbor.encode(data))
        assert result["key"] == "value"
        assert result["num"] == 7

    def test_list(self):
        data = ["a", "b", "c"]
        assert WowCbor.decode(WowCbor.encode(data)) == data


# ── byte string conversion ─────────────────────────────────────────────────


class TestByteStringConversion:
    def test_bytes_converted_to_utf8_string(self):
        # CBOR encode bytes directly (cbor2 encodes Python bytes as CBOR type 2)
        raw = cbor2.dumps(b"hello")
        result = WowCbor.decode(raw)
        assert result == "hello"
        assert isinstance(result, str)

    def test_nested_bytes_in_dict_converted(self):
        raw = cbor2.dumps({"key": b"world"})
        result = WowCbor.decode(raw)
        assert result["key"] == "world"
        assert isinstance(result["key"], str)

    def test_bytes_in_list_converted(self):
        raw = cbor2.dumps([b"a", b"b"])
        result = WowCbor.decode(raw)
        assert result == ["a", "b"]


# ── array detection ────────────────────────────────────────────────────────


class TestArrayDetection:
    def test_sequential_1based_int_keys_to_list(self):
        # cbor2 preserves integer keys in dicts
        raw = cbor2.dumps({1: "a", 2: "b", 3: "c"})
        result = WowCbor.decode(raw)
        assert result == ["a", "b", "c"]

    def test_non_sequential_int_keys_stay_as_dict(self):
        raw = cbor2.dumps({1: "a", 3: "c"})
        result = WowCbor.decode(raw)
        assert isinstance(result, dict)
        assert result[1] == "a"
        assert result[3] == "c"

    def test_zero_based_int_keys_stay_as_dict(self):
        raw = cbor2.dumps({0: "a", 1: "b", 2: "c"})
        result = WowCbor.decode(raw)
        assert isinstance(result, dict)

    def test_string_keyed_dict_stays_as_dict(self):
        data = {"a": 1, "b": 2}
        result = WowCbor.decode(WowCbor.encode(data))
        assert isinstance(result, dict)
        assert result["a"] == 1

    def test_non_string_keys_preserved(self):
        # Keys that are not sequential 1-based ints stay as-is
        raw = cbor2.dumps({10: "x", 20: "y"})
        result = WowCbor.decode(raw)
        assert isinstance(result, dict)
        assert result[10] == "x"
        assert result[20] == "y"
