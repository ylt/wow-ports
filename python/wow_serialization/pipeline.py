"""
Pipeline — encode/decode WoW addon export strings.

Each format declares its prefix and an ordered list of processing steps.
Decode runs the steps left→right; encode runs them right→left.
Heuristic detection probes each layer to auto-detect unknown formats.
"""

import base64
import re
import zlib
from dataclasses import dataclass, field
from typing import Any, Optional

from .lua_deflate import decode_for_print, encode_for_print
from .ace_serializer import WowAce as _WowAce
from .lib_serialize import deserialize as lib_deserialize, serialize as lib_serialize
from .lib_compress import decompress as lib_compress_decompress
from .vuhdo_serializer import deserialize as vuhdo_deserialize, serialize as vuhdo_serialize

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
    steps: Optional[list] = field(default=None)


# ── Step registry ────────────────────────────────────────────────────────────

STEPS = {
    'prefix':          ('strip_prefix',              'prepend_prefix'),
    'metadata':        ('extract_metadata',          'append_metadata'),
    'encode_for_print': ('do_decode_for_print',      'do_encode_for_print'),
    'base64':          ('base64_decode',             'base64_encode'),
    'zlib':            ('decompress',                'compress'),
    'lib_compress':    ('lib_compress_decode',       'lib_compress_encode'),
    'ace_serializer':  ('deserialize_ace',           'serialize_ace'),
    'lib_serialize':   ('deserialize_lib_serialize', 'serialize_lib_serialize'),
    'cbor':            ('deserialize_cbor',          'serialize_cbor'),
    'vuhdo':           ('deserialize_vuhdo',         'serialize_vuhdo'),
}

# ── Format definitions ───────────────────────────────────────────────────────

AUTO_FORMATS = [
    {'addon': 'plater',    'version': 2, 'prefix': '!PLATER:2!',
     'steps': [{'prefix': '!PLATER:2!'}, 'base64', 'zlib', 'cbor']},
    {'addon': 'weakauras', 'version': 2, 'prefix': '!WA:2!',
     'steps': [{'prefix': '!WA:2!'}, 'encode_for_print', 'zlib', 'lib_serialize']},
    {'addon': 'elvui',     'version': 1, 'prefix': '!E1!',
     'steps': [{'prefix': '!E1!'}, 'encode_for_print', 'zlib', 'metadata', 'ace_serializer']},
    {'addon': 'weakauras', 'version': 1, 'prefix': '!',
     'steps': [{'prefix': '!'}, 'encode_for_print', 'zlib', 'ace_serializer']},
    {'addon': 'weakauras', 'version': 0, 'prefix': '',
     'steps': ['encode_for_print', 'zlib', 'ace_serializer']},
]

FORMATS = {
    'plater':    AUTO_FORMATS[0]['steps'],
    'weakauras': AUTO_FORMATS[1]['steps'],
    'elvui':     AUTO_FORMATS[2]['steps'],
    'cell':      [{'prefix': re.compile(r'^!CELL:\d+:\w+!')}, 'encode_for_print', 'zlib', 'lib_serialize'],
    'dbm':       ['encode_for_print', 'zlib', 'lib_serialize'],
    'mdt':       ['encode_for_print', 'lib_compress', 'ace_serializer'],
    'totalrp3':  [{'prefix': '!'}, 'encode_for_print', 'zlib', 'ace_serializer'],
    'vuhdo':     ['base64', 'lib_compress', 'vuhdo'],
}


def _resolve(step: str, direction: str) -> str:
    pair = STEPS.get(step)
    if not pair:
        raise ValueError(f"Unknown step: {step}")
    return pair[0] if direction == 'decode' else pair[1]


def find_format(addon: str, version: int) -> dict | None:
    return next((f for f in AUTO_FORMATS if f['addon'] == addon and f['version'] == version), None)


def _run_steps(pipeline, steps, direction: str):
    for step in steps:
        if isinstance(step, dict):
            name, arg = next(iter(step.items()))
            getattr(pipeline, _resolve(name, direction))(arg)
        else:
            getattr(pipeline, _resolve(step, direction))()


# ── Heuristic detection ──────────────────────────────────────────────────────

def detect_steps(export_str: str) -> list:
    raw = export_str.strip()
    steps = []

    # Layer 1: prefix
    bang_match = re.match(r'^![A-Z][\w:]*!', raw)
    colon_match = re.match(r'^[A-Z]+\d*:', raw)
    if bang_match:
        steps.append({'prefix': bang_match.group(0)})
        raw = raw[bang_match.end():]
    elif colon_match:
        steps.append({'prefix': colon_match.group(0)})
        raw = raw[colon_match.end():]
    elif raw.startswith('!'):
        steps.append({'prefix': '!'})
        raw = raw[1:]

    # Layer 2: encoding (character set)
    if re.fullmatch(r'[a-zA-Z0-9()]+', raw):
        steps.append('encode_for_print')
        raw = decode_for_print(raw)
    elif re.fullmatch(r'[A-Za-z0-9+/=]+', raw):
        steps.append('base64')
        raw = base64.b64decode(raw)
    elif raw.startswith(('{', '[')):
        return steps
    else:
        return steps

    if not raw or len(raw) == 0:
        return steps

    # Layer 3: compression
    first_byte = raw[0] if isinstance(raw, (bytes, bytearray)) else ord(raw[0])
    if first_byte in (1, 2, 3):
        steps.append('lib_compress')
        raw = lib_compress_decompress(raw)
    else:
        try:
            raw = zlib.decompress(raw, wbits=-zlib.MAX_WBITS)
            steps.append('zlib')
        except zlib.error:
            return steps

    # Layer 4: serializer
    text = raw.decode('latin-1') if isinstance(raw, bytes) else raw
    first = raw[0] if isinstance(raw, (bytes, bytearray)) else ord(raw[0])
    if text.startswith('^1'):
        if '^^::' in text:
            steps.append('metadata')
        steps.append('ace_serializer')
    elif first == 1:
        steps.append('lib_serialize')
    elif (first >> 5) in (4, 5):
        steps.append('cbor')

    return steps


class Pipeline:
    def __init__(self):
        self.raw: str = ''
        self.addon: str = ''
        self.version: int = 0
        self.prefix: str = ''
        self.metadata: Optional[dict] = None
        self.compressed: bytes = b''
        self.serialized: bytes = b''
        self.data: Any = None
        self.format: dict = {}
        self._steps: list = []

    # ── Public API ────────────────────────────────────────────────────────────

    @classmethod
    def decode(cls, export_str: str, addon: str | None = None, steps: list | None = None) -> ExportResult:
        p = cls()
        p.raw = export_str.strip()
        if steps is None:
            if addon:
                steps = FORMATS.get(addon)
                if not steps:
                    raise ValueError(f"Unknown addon: {addon}")
                p.addon = addon
            else:
                steps = detect_steps(export_str)
                if not steps:
                    raise ValueError('Could not detect format')
                pfx_step = next((s for s in steps if isinstance(s, dict) and 'prefix' in s), None)
                if pfx_step:
                    match = next((f for f in AUTO_FORMATS if f['prefix'] == pfx_step['prefix']), None)
                    if match:
                        p.addon = match['addon']
                        p.version = match['version']
                else:
                    p.addon = 'weakauras'
                    p.version = 0
        p._steps = steps
        _run_steps(p, steps, 'decode')
        return p.result()

    @classmethod
    def encode(cls, export_result: ExportResult, addon: str | None = None, steps: list | None = None) -> str:
        p = cls()
        p.addon = export_result.addon
        p.version = export_result.version
        p.data = export_result.data
        p.metadata = export_result.metadata
        if steps is None:
            if addon:
                steps = FORMATS.get(addon)
                if not steps:
                    raise ValueError(f"Unknown addon: {addon}")
            elif export_result.steps:
                steps = export_result.steps
            else:
                fmt = find_format(export_result.addon, export_result.version)
                if not fmt:
                    raise ValueError(f"Unknown format: {export_result.addon} v{export_result.version}")
                steps = fmt['steps']
        _run_steps(p, list(reversed(steps)), 'encode')
        return p.to_string()

    # ── Format detection (legacy) ─────────────────────────────────────────────

    def detect_format(self) -> 'Pipeline':
        self.format = next(
            (f for f in AUTO_FORMATS if f['prefix'] and self.raw.startswith(f['prefix'])),
            AUTO_FORMATS[-1],
        )
        self.addon = self.format['addon']
        self.version = self.format['version']
        self.prefix = self.format['prefix']
        return self

    # ── Decode step implementations ───────────────────────────────────────────

    def strip_prefix(self, pfx) -> 'Pipeline':
        if isinstance(pfx, re.Pattern):
            m = pfx.match(self.raw)
            if not m:
                raise ValueError(f"Prefix pattern {pfx.pattern} not found")
            self.prefix = m.group(0)
            self.raw = self.raw[len(self.prefix):]
        else:
            self.prefix = pfx
            self.raw = self.raw[len(pfx):]
        return self

    def extract_metadata(self) -> 'Pipeline':
        text = self.serialized.decode('latin-1') if isinstance(self.serialized, bytes) else self.serialized
        meta_idx = text.find('^^::')
        if meta_idx != -1:
            meta_part = text[meta_idx + 4:]
            parts = meta_part.split('::')
            self.metadata = {
                'profile_type': parts[0] if len(parts) > 0 else None,
                'profile_key': parts[1] if len(parts) > 1 else None,
            }
            self.serialized = text[:meta_idx + 2].encode('latin-1')
        return self

    def do_decode_for_print(self) -> 'Pipeline':
        result = decode_for_print(self.raw)
        if not result:
            raise ValueError('LuaDeflate decode failed')
        self.compressed = result
        return self

    def base64_decode(self) -> 'Pipeline':
        self.compressed = base64.b64decode(self.raw)
        return self

    def decompress(self) -> 'Pipeline':
        self.serialized = zlib.decompress(self.compressed, wbits=-zlib.MAX_WBITS)
        return self

    def lib_compress_decode(self) -> 'Pipeline':
        self.serialized = lib_compress_decompress(self.compressed)
        return self

    def deserialize_cbor(self) -> 'Pipeline':
        if _WowCbor is None:
            raise ValueError('WowCbor not available')
        self.data = _WowCbor.decode(self.serialized)
        return self

    def deserialize_lib_serialize(self) -> 'Pipeline':
        self.data = lib_deserialize(self.serialized)
        return self

    def deserialize_ace(self) -> 'Pipeline':
        self.data = _ace.deserialize(self.serialized.decode('latin-1'))
        return self

    def deserialize_vuhdo(self) -> 'Pipeline':
        text = self.serialized.decode('latin-1') if isinstance(self.serialized, bytes) else self.serialized
        self.data = vuhdo_deserialize(text)
        return self

    def result(self) -> ExportResult:
        return ExportResult(addon=self.addon, version=self.version,
                            data=self.data, metadata=self.metadata,
                            steps=self._steps)

    # ── Encode step implementations ───────────────────────────────────────────

    def serialize_cbor(self) -> 'Pipeline':
        if _WowCbor is None:
            raise ValueError('WowCbor not available')
        self.serialized = _WowCbor.encode(self.data)
        return self

    def serialize_lib_serialize(self) -> 'Pipeline':
        self.serialized = lib_serialize(self.data)
        return self

    def serialize_ace(self) -> 'Pipeline':
        self.serialized = _ace.serialize(self.data).encode('latin-1')
        return self

    def serialize_vuhdo(self) -> 'Pipeline':
        self.serialized = vuhdo_serialize(self.data).encode('latin-1')
        return self

    def compress(self) -> 'Pipeline':
        c = zlib.compressobj(wbits=-zlib.MAX_WBITS)
        self.compressed = c.compress(self.serialized) + c.flush()
        return self

    def lib_compress_encode(self) -> 'Pipeline':
        raise NotImplementedError('LibCompress encode not implemented')

    def do_encode_for_print(self) -> 'Pipeline':
        self.raw = encode_for_print(self.compressed)
        return self

    def base64_encode(self) -> 'Pipeline':
        self.raw = base64.b64encode(self.compressed).decode('ascii')
        return self

    def prepend_prefix(self, pfx) -> 'Pipeline':
        if isinstance(pfx, re.Pattern):
            self.raw = self.prefix + self.raw
        else:
            self.raw = pfx + self.raw
        return self

    def append_metadata(self) -> 'Pipeline':
        if self.metadata:
            profile_type = self.metadata.get('profile_type') or ''
            profile_key = self.metadata.get('profile_key') or ''
            self.serialized += f'::{profile_type}::{profile_key}'.encode('latin-1')
        return self

    def to_string(self) -> str:
        return self.raw
