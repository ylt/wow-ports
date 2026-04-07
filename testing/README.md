# Test Fixtures

This directory contains shared test fixtures used by all language implementations (JS, Ruby, Python) to validate cross-language interoperability.

## fixtures.json

Contains known input/output pairs for both protocols. Structure:

```json
{
  "ace_serializer": [ ... ],
  "lua_deflate": [ ... ]
}
```

### AceSerializer fixture fields

| Field | Description |
|-------|-------------|
| `name` | Human-readable fixture name |
| `input` | The value to serialize (see type conventions below) |
| `ace_serialized` | Expected wire format string |
| `serialize_deterministic` | `true` if `serialize(input)` must exactly match `ace_serialized`. `false` for string-keyed tables where key ordering is non-deterministic — test deserialization only. |
| `note` | Optional annotation |

### LuaDeflate fixture fields

| Field | Description |
|-------|-------------|
| `name` | Human-readable fixture name |
| `input_hex` | Input bytes as a lowercase hex string |
| `encoded` | Expected LuaDeflate-encoded output string |

### Non-JSON-native type conventions

Some values cannot be represented natively in JSON. Use `__type__` wrappers:

| Wrapper | Language value |
|---------|---------------|
| `{ "__type__": "infinity" }` | `Infinity` / `Float::INFINITY` |
| `{ "__type__": "neg_infinity" }` | `-Infinity` / `-Float::INFINITY` |
| `{ "__type__": "float", "value": 3.14 }` | `3.14` as a float (not integer) |
| `{ "__type__": "bytes", "hex": "deadbeef" }` | Raw binary bytes |
| `null` (JSON) | `null` / `nil` |

### How to test

For each AceSerializer fixture:

1. **Serialize test** (only when `serialize_deterministic` is `true` or absent):
   - Convert `input` to the native language type (handle `__type__` wrappers)
   - Call `serialize(input)`
   - Assert output equals `ace_serialized`

2. **Deserialize test**:
   - Call `deserialize(ace_serialized)`
   - Assert output equals `input` (with appropriate `__type__` unwrapping)

3. **Round-trip test**:
   - Call `deserialize(ace_serialized)` → `value`
   - Call `serialize(value)` → `wire`
   - Call `deserialize(wire)` → `value2`
   - Assert `value2` equals `value`

For each LuaDeflate fixture:

1. **Encode test**: decode `input_hex` to bytes, call `encode(bytes)`, assert equals `encoded`
2. **Decode test**: call `decode(encoded)`, assert hex of result equals `input_hex`

## Real addon export strings

Real WoW addon export strings are large compressed blobs that require a running WoW client to generate. They cannot easily be created from scratch.

To capture real export strings for regression testing:

1. Install the addon in WoW (WeakAuras, ElvUI, etc.)
2. Export a simple profile/aura
3. Copy the entire export string
4. Save it to `testdata/real/` with a descriptive filename (e.g., `weakauras_v1_simple.txt`)

Real export strings should be short/simple profiles to keep the files small. The pipeline tests in `js/test/pipeline.test.js` and `ruby/spec/pipeline_spec.rb` will load them if present.
