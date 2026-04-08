# Azerite — Serialization Protocol Specification

This document describes the two serialization protocols implemented in this repository: the **WoW Ace Serialization** format and the **LuaDeflate Encoding** scheme. Both originate from World of Warcraft AddOn Lua libraries.

---

## WoW Ace Serialization

A type-length-value style format used by the WoW Ace library (`AceSerializer-3.0`) to serialize Lua values into printable strings for addon-to-addon communication.

### Message Framing

Every serialized message is wrapped with a version prefix and a terminator:

```
^1<payload>^^
```

- `^1` — version prefix (always version 1)
- `^^` — end-of-message terminator

The payload is one or more concatenated typed values.

### Type Prefixes

Each value in the payload begins with a two-character prefix `^X` where `X` identifies the type:

| Prefix | Type | Description |
|--------|------|-------------|
| `^S` | String | Escaped string data (see below) |
| `^N` | Number | Integer or special float literal |
| `^F` | Float | IEEE 754 double via mantissa + exponent |
| `^T` | Table open | Start of a key-value table |
| `^t` | Table close | End of a key-value table |
| `^B` | Boolean true | No payload |
| `^b` | Boolean false | No payload |
| `^Z` | Null/nil | No payload |

### String Serialization (`^S`)

Format: `^S<escaped-data>`

The string body continues until the next `^` that begins a type prefix. The `~` character (0x7E) is the escape prefix. All escaping is done in a **single pass** over the string using a character-class regex, not sequential replacements.

**Escaped character class:** `[\x00-\x20 \x5E \x7E \x7F]` — control characters, space, `^`, `~`, and DEL.

**Escape mapping (reference: AceSerializer-3.0.lua `SerializeStringHelper`):**

| Input byte | Escape sequence | Notes |
|-----------|-----------------|-------|
| 0x00–0x1D (0–29) | `~` + `chr(byte + 64)` | Generic control char formula |
| 0x1E (30) | `~z` (0x7E 0x7A) | **Special case:** 30+64=94=`^`, would corrupt parser |
| 0x1F (31) | `~_` (0x7E 0x5F) | Generic formula: 31+64=95=`_` |
| 0x20 (space) | `` ~` `` (0x7E 0x60) | Generic formula: 32+64=96=`` ` `` |
| 0x5E (`^`) | `~}` (0x7E 0x7D) | Value separator; 94+64=158 is outside ASCII, so special-cased to 125 |
| 0x7E (`~`) | `~\|` (0x7E 0x7C) | Escape char itself; 126+64=190 is outside ASCII, so special-cased to 124 |
| 0x7F (DEL) | `~{` (0x7E 0x7B) | 127+64=191 is outside ASCII, so special-cased to 123 |

**Key insight:** The generic `chr(byte + 64)` formula only works for bytes 0–57 (producing chars 64–121). Bytes 30, 94, 126, and 127 are all special-cased. Byte 30 is special-cased because `30+64=94=^` which would break parsing.

**Encoding** must be a single-pass regex substitution (not sequential string replacements, which cause double-escaping bugs).

**Decoding** matches `~(.)` globally. The dispatch logic (from `DeserializeStringHelper`):
- If the char after `~` is `<` `z` (byte < 122): generic decode via `chr(byte - 64)`
- `~z` (122) → byte 30 (0x1E) — special case
- `~{` (123) → byte 127 (DEL)
- `~|` (124) → byte 126 (`~`)
- `~}` (125) → byte 94 (`^`)

### Number Serialization (`^N`)

Format: `^N<number-literal>`

The number literal continues until the next `^` character. Supported forms:

| Literal | Value |
|---------|-------|
| `^N123` | Integer 123 |
| `^N-42` | Integer -42 |
| `^N3.14` | Floating-point 3.14 |
| `^N1.#INF` | Positive infinity |
| `^N-1.#INF` | Negative infinity |

When decoding, also accept `inf` / `-inf` as infinity representations.

Integer detection: a number string matching `/^-?\d+$/` is parsed as integer; otherwise as float.

### Float Serialization (`^F` / `^f`)

Format: `^F<mantissa>^f<exponent>`

Used for floating-point numbers that are not integers and not infinity. The encoding decomposes an IEEE 754 double-precision float:

**Encoding** (reference: AceSerializer-3.0.lua `SerializeValue`):
1. Extract mantissa and exponent using `frexp`: `m, e = frexp(value)` — `m` is in range [0.5, 1.0)
2. Scale mantissa to integer: `int_mantissa = floor(m * 2^53)`
3. Adjust exponent: `adj_exponent = e - 53`
4. Emit: `^F<int_mantissa>^f<adj_exponent>`

**Decoding** (reference: AceSerializer-3.0.lua `DeserializeValue`):
1. Parse the integer mantissa `m` after `^F`
2. Skip the `^f` separator
3. Parse the integer exponent `e`
4. Reconstruct: `value = m * 2^e`

Note: The exponent on the wire is already adjusted (`e - 53`), so decoding is simply `m * 2^e`. The Lua reference does NOT subtract 53 during decode.

### Boolean Serialization

- `^B` — true (no additional payload)
- `^b` — false (no additional payload)

### Null Serialization

- `^Z` — null/nil (no additional payload)

### Table Serialization (`^T` / `^t`)

Format: `^T<key1><value1><key2><value2>...^t`

Tables are the Lua equivalent of maps/dictionaries. Key-value pairs are concatenated between `^T` (open) and `^t` (close). Each key and value is a fully typed serialized value (recursive).

**Arrays** are serialized as tables with 1-based integer keys:

```
Array: ["a", "b", "c"]
  → Table: {1: "a", 2: "b", 3: "c"}
  → ^T^N1^Sa^N2^Sb^N3^Sc^t
```

**Decoding heuristic (Ruby implementation):** After deserializing a table, if the sorted keys are exactly the sequence `1, 2, 3, ..., N`, convert it back to an array of values. The JS implementation does not perform this conversion — it returns a plain object with string keys.

### Complete Examples

**Simple string:**
```
serialize("hello") → ^1^Shello^^
```

**Integer:**
```
serialize(42) → ^1^N42^^
```

**Boolean:**
```
serialize(true) → ^1^B^^
```

**Null:**
```
serialize(null) → ^1^Z^^
```

**Nested structure:**
```
serialize({"hello": "world", "test": 123, "nested": [null, null, null, "test"]})
→ ^1^T^Shello^Sworld^Stest^N123^Snested^T^N1^Z^N2^Z^N3^Z^N4^Stest^t^t^^
```

**Infinity:**
```
serialize(Infinity)  → ^1^N1.#INF^^
serialize(-Infinity) → ^1^N-1.#INF^^
```

---

## LuaDeflate Encoding

A custom base64-like encoding used by the WoW `LibDeflate` library. It maps binary data to a 64-character alphabet that is safe for WoW's chat and addon communication channels.

### Character Set

The 64-character alphabet (index 0–63):

```
abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()
```

| Index | Characters |
|-------|-----------|
| 0–25 | `a` through `z` |
| 26–51 | `A` through `Z` |
| 52–61 | `0` through `9` |
| 62 | `(` |
| 63 | `)` |

This differs from standard base64 (`A-Za-z0-9+/`) in both alphabet and ordering.

### Encoding Algorithm

Input is processed in 3-byte groups, producing 4 encoded characters per group.

**For each 3-byte group:**

1. Read up to 3 bytes from input.
2. Pack into a 24-bit integer using **little-endian** byte order:
   ```
   value = byte[0] + byte[1] * 256 + byte[2] * 65536
   ```
3. Extract four 6-bit indices in **little-endian** order:
   ```
   index[0] = (value >>  0) & 0x3F
   index[1] = (value >>  6) & 0x3F
   index[2] = (value >> 12) & 0x3F
   index[3] = (value >> 18) & 0x3F
   ```
4. Map each index to the character set.

**Padding:** If the final group has fewer than 3 bytes, emit only `N + 1` characters (where N is the number of remaining bytes). There is no padding character — the output length implicitly encodes the original data length.

| Input bytes in final group | Output characters |
|---------------------------|-------------------|
| 3 | 4 |
| 2 | 3 |
| 1 | 2 |

### Decoding Algorithm

Input is processed in 4-character groups, producing 3 bytes per group.

**For each 4-character group:**

1. Read up to 4 characters from input.
2. Map each character to its index in the alphabet. If any character is not in the alphabet, decoding fails (returns null).
3. Pack into a 24-bit integer using **little-endian** index order:
   ```
   value = index[0] * 64^0 + index[1] * 64^1 + index[2] * 64^2 + index[3] * 64^3
   ```
4. Extract bytes in **little-endian** order:
   ```
   byte[0] = (value >>  0) & 0xFF
   byte[1] = (value >>  8) & 0xFF
   byte[2] = (value >> 16) & 0xFF
   ```

**Final group handling:** If the final group has fewer than 4 characters, extract only `N - 1` bytes (where N is the number of characters).

| Input characters in final group | Output bytes |
|--------------------------------|-------------|
| 4 | 3 |
| 3 | 2 |
| 2 | 1 |

**Pre-processing:** Leading and trailing whitespace is stripped before decoding. Inputs of length 0 or 1 are rejected.

### Output Modes (JS only)

The JavaScript implementation offers two decode methods:
- `decodeForPrint(str)` — returns a decoded string
- `decodeForPrint2(str)` — returns a `Uint8Array` buffer (useful for binary data)

### Size Ratio

Encoded output is approximately 4/3 the size of the input (same as standard base64), minus padding overhead.
