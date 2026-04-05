"""
Pipeline — encode/decode WoW addon export strings.

Supports:
  WA v0  (legacy WeakAuras, no prefix, AceSerializer)
  WA v1  (WeakAuras + AceSerializer, prefix '!')
  WA v2  (WeakAuras + LibSerialize, prefix '!WA:2!')
  ElvUI  (prefix '!E1!', AceSerializer + optional metadata trailer)

Decode: LuaDeflate → zlib raw inflate → AceSerializer / LibSerialize
Encode: AceSerializer / LibSerialize → zlib raw deflate → LuaDeflate
"""

import zlib
from dataclasses import dataclass
from typing import Any, Optional

from .lua_deflate import decode_for_print, encode_for_print
from .ace_serializer import WowAce as _WowAce
from .lib_serialize import deserialize as lib_deserialize, serialize as lib_serialize

_ace = _WowAce()


@dataclass
class ExportResult:
    addon: str
    version: int
    data: Any
    metadata: Optional[dict]


def _detect_addon(s: str) -> dict:
    if s.startswith('!WA:2!'):
        return {'addon': 'weakauras', 'version': 2, 'prefix': '!WA:2!'}
    if s.startswith('!E1!'):
        return {'addon': 'elvui', 'version': 1, 'prefix': '!E1!'}
    if s.startswith('!'):
        return {'addon': 'weakauras', 'version': 1, 'prefix': '!'}
    return {'addon': 'weakauras', 'version': 0, 'prefix': ''}


def _prefix_for(addon: str, version: int) -> str:
    if version == 2:
        return '!WA:2!'
    if addon == 'elvui':
        return '!E1!'
    if version >= 1:
        return '!'
    return ''


def _inflate_raw(data: bytes) -> bytes:
    return zlib.decompress(data, wbits=-zlib.MAX_WBITS)


def _deflate_raw(data: bytes) -> bytes:
    c = zlib.compressobj(wbits=-zlib.MAX_WBITS)
    return c.compress(data) + c.flush()


class Pipeline:
    @staticmethod
    def decode(export_str: str) -> ExportResult:
        export_str = export_str.strip()
        detected = _detect_addon(export_str)
        addon = detected['addon']
        version = detected['version']
        encoded = export_str[len(detected['prefix']):]

        # ElvUI: strip ^^:: metadata trailer before LuaDeflate decode
        metadata = None
        if addon == 'elvui':
            meta_idx = encoded.find('^^::')
            if meta_idx != -1:
                meta_part = encoded[meta_idx + 4:]
                parts = meta_part.split('::')
                metadata = {
                    'profile_type': parts[0] if len(parts) > 0 else None,
                    'profile_key': parts[1] if len(parts) > 1 else None,
                }
                encoded = encoded[:meta_idx]

        # LuaDeflate decode → bytes
        compressed = decode_for_print(encoded)
        if not compressed:
            raise ValueError('LuaDeflate decode failed')

        # zlib raw inflate
        inflated = _inflate_raw(compressed)

        # Deserialize
        if version == 2:
            data = lib_deserialize(inflated)
        else:
            data = _ace.deserialize(inflated.decode('latin-1'))

        return ExportResult(addon=addon, version=version, data=data, metadata=metadata)

    @staticmethod
    def encode(export_result: ExportResult) -> str:
        addon = export_result.addon
        version = export_result.version
        data = export_result.data
        metadata = export_result.metadata

        # Serialize
        if version == 2:
            serialized: bytes = lib_serialize(data)
        else:
            serialized = _ace.serialize(data).encode('latin-1')

        # zlib raw deflate
        compressed = _deflate_raw(serialized)

        # LuaDeflate encode
        encoded = encode_for_print(compressed)

        # ElvUI: append metadata trailer
        if addon == 'elvui' and metadata:
            profile_type = metadata.get('profile_type') or ''
            profile_key = metadata.get('profile_key') or ''
            encoded += f'^^::{profile_type}::{profile_key}'

        return _prefix_for(addon, version) + encoded
