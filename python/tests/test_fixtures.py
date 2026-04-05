"""Fixture-based tests — reads testdata/fixtures.json and tests all languages' outputs."""

import json
import math
import os
import pytest
from wow_serialization.ace_serializer import WowAce
from wow_serialization.lua_deflate import decode_for_print, encode_for_print

FIXTURES_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'testdata', 'fixtures.json')

with open(FIXTURES_PATH, 'r', encoding='utf-8') as _f:
    _FIXTURES = json.load(_f)


def to_native(v):
    """Convert a fixture input value (which may contain __type__ wrappers) to a native Python value."""
    if v is None or isinstance(v, (bool, int, float, str)):
        return v
    if isinstance(v, list):
        return [to_native(el) for el in v]
    if isinstance(v, dict):
        t = v.get('__type__')
        if t == 'infinity':
            return math.inf
        if t == 'neg_infinity':
            return -math.inf
        if t == 'float':
            return float(v['value'])
        if t == 'bytes':
            return bytes.fromhex(v['hex']).decode('latin-1')
        return {k: to_native(val) for k, val in v.items()}
    return v


# ── AceSerializer fixtures — deserialize ──────────────────────────────────────

class TestAceDeserialize:
    @pytest.fixture(autouse=True)
    def _ace(self):
        self.ace = WowAce()

    @pytest.mark.parametrize('fixture', _FIXTURES['ace_serializer'],
                             ids=[f['name'] for f in _FIXTURES['ace_serializer']])
    def test_deserialize(self, fixture):
        result = self.ace.deserialize(fixture['ace_serialized'])
        assert result == to_native(fixture['input'])


# ── AceSerializer fixtures — serialize ───────────────────────────────────────

class TestAceSerialize:
    @pytest.fixture(autouse=True)
    def _ace(self):
        self.ace = WowAce()

    @pytest.mark.parametrize(
        'fixture',
        [f for f in _FIXTURES['ace_serializer'] if f.get('serialize_deterministic') is not False],
        ids=[f['name'] for f in _FIXTURES['ace_serializer']
             if f.get('serialize_deterministic') is not False],
    )
    def test_serialize(self, fixture):
        result = self.ace.serialize(to_native(fixture['input']))
        assert result == fixture['ace_serialized']


# ── AceSerializer fixtures — round-trip ──────────────────────────────────────
# deserialize(wire) → value1 → serialize → deserialize → value2
# Assert value2 deeply equals value1 (internal consistency).

class TestAceRoundTrip:
    @pytest.fixture(autouse=True)
    def _ace(self):
        self.ace = WowAce()

    @pytest.mark.parametrize('fixture', _FIXTURES['ace_serializer'],
                             ids=[f['name'] for f in _FIXTURES['ace_serializer']])
    def test_roundtrip(self, fixture):
        value1 = self.ace.deserialize(fixture['ace_serialized'])
        wire2 = self.ace.serialize(value1)
        value2 = self.ace.deserialize(wire2)
        assert value2 == value1


# ── LuaDeflate fixtures — encode ─────────────────────────────────────────────

class TestLuaDeflateEncode:
    @pytest.mark.parametrize('fixture', _FIXTURES['lua_deflate'],
                             ids=[f['name'] for f in _FIXTURES['lua_deflate']])
    def test_encode(self, fixture):
        input_bytes = bytes.fromhex(fixture['input_hex'])
        assert encode_for_print(input_bytes) == fixture['encoded']


# ── LuaDeflate fixtures — decode ─────────────────────────────────────────────

class TestLuaDeflateDecode:
    @pytest.mark.parametrize('fixture', _FIXTURES['lua_deflate'],
                             ids=[f['name'] for f in _FIXTURES['lua_deflate']])
    def test_decode(self, fixture):
        decoded = decode_for_print(fixture['encoded'])
        assert decoded.hex() == fixture['input_hex']
