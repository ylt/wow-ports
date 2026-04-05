"""
Pipeline — encode/decode WoW addon export strings.

Supports:
  WA v0     (legacy WeakAuras, no prefix, AceSerializer)
  WA v1     (WeakAuras + AceSerializer, prefix '!')
  WA v2     (WeakAuras + LibSerialize, prefix '!WA:2!')
  ElvUI     (prefix '!E1!', AceSerializer + optional metadata trailer)
  Plater v2 (prefix '!PLATER:2!', CBOR)

Decode: LuaDeflate → zlib raw inflate → AceSerializer / LibSerialize / CBOR
Encode: AceSerializer / LibSerialize / CBOR → zlib raw deflate → LuaDeflate
"""

import zlib
from dataclasses import dataclass
from typing import Any, Optional

from .lua_deflate import decode_for_print, encode_for_print
from .ace_serializer import WowAce as _WowAce
from .lib_serialize import deserialize as lib_deserialize, serialize as lib_serialize

_ace = _WowAce()

try:
    from .wow_cbor import WowCbor as _WowCbor
except ImportError:
    _WowCbor = None


@dataclass
class ExportResult:
    addon: str
    version: int
    data: Any
    metadata: Optional[dict]


def _prefix_for(addon: str, version: int) -> str:
    if addon == 'plater' and version == 2:
        return '!PLATER:2!'
    if version == 2:
        return '!WA:2!'
    if addon == 'elvui':
        return '!E1!'
    if version >= 1:
        return '!'
    return ''


class Pipeline:
    """Instance-based pipeline carrying state through encode/decode steps.

    Convenience class methods Pipeline.decode() and Pipeline.encode() remain
    as wrappers so existing call-sites continue to work unchanged.
    """

    def __init__(self):
        self.raw: str = ''
        self.addon: str = ''
        self.version: int = 0
        self.prefix: str = ''
        self.metadata: Optional[dict] = None
        self.compressed: bytes = b''
        self.serialized: bytes = b''
        self.data: Any = None
        self.encoded: str = ''

    # ── Decode steps ──────────────────────────────────────────────────────────

    def detect_format(self) -> 'Pipeline':
        """Inspect raw string and set addon, version, prefix."""
        s = self.raw
        if s.startswith('!PLATER:2!'):
            self.addon, self.version, self.prefix = 'plater', 2, '!PLATER:2!'
        elif s.startswith('!WA:2!'):
            self.addon, self.version, self.prefix = 'weakauras', 2, '!WA:2!'
        elif s.startswith('!E1!'):
            self.addon, self.version, self.prefix = 'elvui', 1, '!E1!'
        elif s.startswith('!'):
            self.addon, self.version, self.prefix = 'weakauras', 1, '!'
        else:
            self.addon, self.version, self.prefix = 'weakauras', 0, ''
        return self

    def strip_prefix(self) -> 'Pipeline':
        """Remove the addon prefix from raw, storing the rest in encoded."""
        self.encoded = self.raw[len(self.prefix):]
        return self

    def extract_metadata(self) -> 'Pipeline':
        """ElvUI: extract ^^:: metadata trailer from encoded, set self.metadata."""
        if self.addon == 'elvui':
            meta_idx = self.encoded.find('^^::')
            if meta_idx != -1:
                meta_part = self.encoded[meta_idx + 4:]
                parts = meta_part.split('::')
                self.metadata = {
                    'profile_type': parts[0] if len(parts) > 0 else None,
                    'profile_key': parts[1] if len(parts) > 1 else None,
                }
                self.encoded = self.encoded[:meta_idx]
        return self

    def base64_decode(self) -> 'Pipeline':
        """LuaDeflate-decode encoded string into compressed bytes."""
        result = decode_for_print(self.encoded)
        if not result:
            raise ValueError('LuaDeflate decode failed')
        self.compressed = result
        return self

    def decompress(self) -> 'Pipeline':
        """zlib raw-inflate compressed bytes into serialized bytes."""
        self.serialized = zlib.decompress(self.compressed, wbits=-zlib.MAX_WBITS)
        return self

    def deserialize(self) -> 'Pipeline':
        """Dispatch to the correct deserializer based on addon/version."""
        if self.addon == 'plater' and self.version == 2:
            if _WowCbor is None:
                raise ValueError('WowCbor not available for Plater v2 decode')
            self.data = _WowCbor.decode(self.serialized)
        elif self.version == 2:
            self.data = lib_deserialize(self.serialized)
        else:
            self.data = _ace.deserialize(self.serialized.decode('latin-1'))
        return self

    def result(self) -> ExportResult:
        """Return the decoded ExportResult."""
        return ExportResult(addon=self.addon, version=self.version,
                            data=self.data, metadata=self.metadata)

    # ── Encode steps ──────────────────────────────────────────────────────────

    def serialize(self) -> 'Pipeline':
        """Dispatch to the correct serializer based on addon/version."""
        if self.addon == 'plater' and self.version == 2:
            if _WowCbor is None:
                raise ValueError('WowCbor not available for Plater v2 encode')
            self.serialized = _WowCbor.encode(self.data)
        elif self.version == 2:
            self.serialized = lib_serialize(self.data)
        else:
            self.serialized = _ace.serialize(self.data).encode('latin-1')
        return self

    def compress(self) -> 'Pipeline':
        """zlib raw-deflate serialized bytes into compressed bytes."""
        c = zlib.compressobj(wbits=-zlib.MAX_WBITS)
        self.compressed = c.compress(self.serialized) + c.flush()
        return self

    def base64_encode(self) -> 'Pipeline':
        """LuaDeflate-encode compressed bytes into the encoded string."""
        self.encoded = encode_for_print(self.compressed)
        return self

    def prepend_prefix(self) -> 'Pipeline':
        """Prepend the addon prefix to produce raw."""
        self.prefix = _prefix_for(self.addon, self.version)
        self.raw = self.prefix + self.encoded
        return self

    def append_metadata(self) -> 'Pipeline':
        """ElvUI: append ^^:: metadata trailer to raw."""
        if self.addon == 'elvui' and self.metadata:
            profile_type = self.metadata.get('profile_type') or ''
            profile_key = self.metadata.get('profile_key') or ''
            self.raw += f'^^::{profile_type}::{profile_key}'
        return self

    def to_string(self) -> str:
        """Return the final encoded export string."""
        return self.raw

    # ── Convenience class-method wrappers ─────────────────────────────────────

    @classmethod
    def decode(cls, export_str: str) -> ExportResult:
        """Decode a WoW addon export string → ExportResult."""
        p = cls()
        p.raw = export_str.strip()
        p.detect_format()
        p.strip_prefix()
        p.extract_metadata()
        p.base64_decode()
        p.decompress()
        p.deserialize()
        return p.result()

    @classmethod
    def encode(cls, export_result: ExportResult) -> str:
        """Encode an ExportResult → WoW addon export string."""
        p = cls()
        p.addon = export_result.addon
        p.version = export_result.version
        p.data = export_result.data
        p.metadata = export_result.metadata
        p.serialize()
        p.compress()
        p.base64_encode()
        p.prepend_prefix()
        p.append_metadata()
        return p.to_string()
