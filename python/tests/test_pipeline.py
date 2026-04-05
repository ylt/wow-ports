"""Tests for Pipeline encode/decode."""

import pytest
from wow_serialization.pipeline import Pipeline, ExportResult


def roundtrip(addon, version, data, metadata=None):
    enc = Pipeline.encode(ExportResult(addon=addon, version=version, data=data, metadata=metadata))
    return Pipeline.decode(enc)


# ---------------------------------------------------------------------------
# Prefix encoding
# ---------------------------------------------------------------------------

class TestPrefixEncoding:
    def test_wa_v1_uses_bang_prefix(self):
        enc = Pipeline.encode(ExportResult('weakauras', 1, 'x', None))
        assert enc.startswith('!')
        assert not enc.startswith('!WA:2!')
        assert not enc.startswith('!E1!')

    def test_elvui_uses_e1_prefix(self):
        enc = Pipeline.encode(ExportResult('elvui', 1, 'x', None))
        assert enc.startswith('!E1!')

    def test_legacy_v0_uses_no_prefix(self):
        enc = Pipeline.encode(ExportResult('weakauras', 0, 'x', None))
        assert not enc.startswith('!')

    def test_wa_v2_uses_wa2_prefix(self):
        enc = Pipeline.encode(ExportResult('weakauras', 2, {'a': 1}, None))
        assert enc.startswith('!WA:2!')


# ---------------------------------------------------------------------------
# Prefix detection (via decode)
# ---------------------------------------------------------------------------

class TestPrefixDetection:
    def test_e1_detects_elvui_v1(self):
        dec = roundtrip('elvui', 1, {'a': 1})
        assert dec.addon == 'elvui'
        assert dec.version == 1

    def test_bang_detects_weakauras_v1(self):
        dec = roundtrip('weakauras', 1, {'a': 1})
        assert dec.addon == 'weakauras'
        assert dec.version == 1

    def test_no_prefix_detects_legacy_v0(self):
        dec = roundtrip('weakauras', 0, {'a': 1})
        assert dec.addon == 'weakauras'
        assert dec.version == 0

    def test_wa2_detects_weakauras_v2(self):
        dec = roundtrip('weakauras', 2, {'a': 1})
        assert dec.addon == 'weakauras'
        assert dec.version == 2


# ---------------------------------------------------------------------------
# ExportResult structure
# ---------------------------------------------------------------------------

class TestExportResultStructure:
    def test_decode_returns_all_four_fields(self):
        dec = roundtrip('weakauras', 1, {'x': 1})
        assert hasattr(dec, 'addon')
        assert hasattr(dec, 'version')
        assert hasattr(dec, 'data')
        assert hasattr(dec, 'metadata')


# ---------------------------------------------------------------------------
# Encode→decode round-trips
# ---------------------------------------------------------------------------

class TestRoundTrip:
    def test_wa_v1_string(self):
        dec = roundtrip('weakauras', 1, 'hello')
        assert dec.data == 'hello'
        assert dec.addon == 'weakauras'
        assert dec.version == 1
        assert dec.metadata is None

    def test_wa_v1_dict(self):
        data = {'key': 'value', 'num': 42}
        dec = roundtrip('weakauras', 1, data)
        assert dec.data['key'] == 'value'
        assert dec.data['num'] == 42

    def test_wa_v1_array(self):
        data = ['a', 'b', 'c']
        dec = roundtrip('weakauras', 1, data)
        assert dec.data == data

    def test_wa_v1_nested(self):
        data = {'outer': {'inner': 99}, 'list': [1, 2]}
        dec = roundtrip('weakauras', 1, data)
        assert dec.data['outer']['inner'] == 99
        assert dec.data['list'] == [1, 2]

    def test_legacy_v0_roundtrip(self):
        data = {'flag': True, 'n': -5}
        dec = roundtrip('weakauras', 0, data)
        assert dec.data['flag'] is True
        assert dec.data['n'] == -5

    def test_wa_v2_roundtrip(self):
        data = {'key': 'v2data', 'num': 7}
        dec = roundtrip('weakauras', 2, data)
        assert dec.data['key'] == 'v2data'
        assert dec.data['num'] == 7


# ---------------------------------------------------------------------------
# ElvUI metadata
# ---------------------------------------------------------------------------

class TestElvUIMetadata:
    def test_roundtrip_preserves_profile_type_and_key(self):
        metadata = {'profile_type': 'profile', 'profile_key': 'Default'}
        dec = roundtrip('elvui', 1, {'setting': 1}, metadata)
        assert dec.addon == 'elvui'
        assert dec.metadata['profile_type'] == 'profile'
        assert dec.metadata['profile_key'] == 'Default'
        assert dec.data['setting'] == 1

    def test_elvui_without_metadata_gives_none(self):
        dec = roundtrip('elvui', 1, {'a': 1}, None)
        assert dec.metadata is None
