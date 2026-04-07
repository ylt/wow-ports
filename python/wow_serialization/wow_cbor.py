"""WowCbor: CBOR wrapper with WoW-specific post-processing.

Post-processing applied after decode:
- CBOR byte strings (bytes) → UTF-8 text strings
- Sequential 1-based integer-keyed dicts → lists (Lua table convention)
"""

import cbor2


class WowCbor:
    @staticmethod
    def decode(data: bytes):
        """Decode CBOR bytes to a Python value with WoW-specific post-processing."""
        raw = cbor2.loads(data)
        return WowCbor._post_process(raw)

    @staticmethod
    def encode(data) -> bytes:
        """Encode a Python value to CBOR bytes."""
        return cbor2.dumps(data)

    @classmethod
    def _post_process(cls, val):
        if isinstance(val, bytes):
            return val.decode("utf-8", errors="replace")
        if isinstance(val, list):
            return [cls._post_process(v) for v in val]
        if isinstance(val, dict):
            result = {k: cls._post_process(v) for k, v in val.items()}
            return cls._apply_array_detection(result)
        return val

    @staticmethod
    def _apply_array_detection(d: dict):
        """Convert sequential 1-based integer-keyed dict to list."""
        if not d:
            return d
        keys = list(d.keys())
        if not all(isinstance(k, int) and k > 0 for k in keys):
            return d
        sorted_keys = sorted(keys)
        if sorted_keys != list(range(1, len(keys) + 1)):
            return d
        return [d[k] for k in sorted_keys]
