# Test Index — Ground Truth from Lua Reference Implementations

Lua is the reference. Every other language must have identical tests asserting the same expected output.
If a language's implementation diverges from Lua, the test is **skipped** with a reason — never adapted.

---

## AceSerializer (73 tests)

### A. String Escaping (Serialize)

| ID | Description | Lua | JS | Ruby | Python | Deviation |
|---|---|---|---|---|---|---|
| A1 | NUL (0x00) → ~@ | ✓ | ✓ | ✓ | ✓ | |
| A2 | control 0x01 → ~A | ✓ | ✓ | ✓ | ✓ | |
| A2 | control 0x0A (LF) → ~J | ✓ | ✓ | ✓ | ✓ | |
| A2 | control 0x1D → ~] | ✓ | ✓ | ✓ | ✓ | |
| A3 | byte 30 (0x1E) → ~z (special case) | ✓ | ✓ | ✓ | ✓ | |
| A4 | byte 31 (0x1F) → ~_ | ✓ | ✓ | ✓ | ✓ | |
| A5 | space (0x20) → ~` | ✓ | ✓ | ✓ | ✓ | |
| A6 | caret ^ (0x5E) → ~} | ✓ | ✓ | ✓ | ✓ | |
| A7 | tilde ~ (0x7E) → ~\| | ✓ | ✓ | ✓ | ✓ | |
| A8 | DEL (0x7F) → ~{ | ✓ | ✓ | ✓ | ✓ | |
| A9 | single-pass — no double-escaping | ✓ | ✓ | ✓ | ✓ | |
| A10 | printable ASCII passes through | ✓ | ✓ | ✓ | ✓ | |

### B. String Unescaping (Deserialize)

| ID | Description | Lua | JS | Ruby | Python | Deviation |
|---|---|---|---|---|---|---|
| B11 | ~@ → NUL (0x00) | ✓ | ✓ | ✓ | ✓ | |
| B12 | ~A → chr(1) | ✓ | ✓ | ✓ | ✓ | |
| B12 | ~J → chr(10) | ✓ | ✓ | ✓ | ✓ | |
| B13 | ~z → byte 30 | ✓ | ✓ | ✓ | ✓ | |
| B14 | ~{ → DEL | ✓ | ✓ | ✓ | ✓ | |
| B15 | ~\| → tilde | ✓ | ✓ | ✓ | ✓ | |
| B16 | ~} → caret | ✓ | ✓ | ✓ | ✓ | |
| B17 | round-trip all escapable bytes | ✓ | ✓ | ✓ | ✓ | |

### C. Number Serialization

| ID | Description | Lua | JS | Ruby | Python | Deviation |
|---|---|---|---|---|---|---|
| C18 | positive integer → ^N42 | ✓ | ✓ | ✓ | ✓ | |
| C19 | negative integer → ^N-42 | ✓ | ✓ | ✓ | ✓ | |
| C20 | zero → ^N0 | ✓ | ✓ | ✓ | ✓ | |
| C21 | large integer | ✓ | ✓ | ✓ | ✓ | |
| C22 | non-integer float wire format | skip | skip | skip | skip | Lua: ^N (tonumber/tostring); JS/Ruby/Python: always ^F |
| C23 | 3.14 exact wire format | skip | skip | skip | skip | Lua: ^N3.14; others: ^F7070651414971679^f-51 |
| C24 | 0.1 wire format | skip | skip | skip | skip | ^N vs ^F divergence |
| C24 | -99.99 wire format | skip | skip | skip | skip | ^N vs ^F divergence |
| C24 | 1e-10 wire format | skip | skip | skip | skip | ^N vs ^F divergence |
| C25 | positive infinity → ^N1.#INF | ✓ | ✓ | ✓ | ✓ | |
| C26 | negative infinity → ^N-1.#INF | ✓ | ✓ | ✓ | ✓ | |

### D. Number Deserialization

| ID | Description | Lua | JS | Ruby | Python | Deviation |
|---|---|---|---|---|---|---|
| D27 | ^N42 → 42 | ✓ | ✓ | ✓ | ✓ | |
| D28 | ^N-42 → -42 | ✓ | ✓ | ✓ | ✓ | |
| D29 | ^N3.14 → 3.14 | ✓ | ✓ | ✓ | ✓ | |
| D30 | ^N1.#INF → Infinity | ✓ | ✓ | ✓ | ✓ | |
| D31 | ^N-1.#INF → -Infinity | ✓ | ✓ | ✓ | ✓ | |
| D32 | ^Ninf → Infinity | ✓ | ✓ | ✓ | ✓ | |
| D33 | ^N-inf → -Infinity | ✓ | ✓ | ✓ | ✓ | |
| D34 | ^F\<m\>^f\<e\> → correct float | ✓ | ✓ | ✓ | ✓ | |

### E. Float frexp Round-trips

| ID | Description | Lua | JS | Ruby | Python | Deviation |
|---|---|---|---|---|---|---|
| E35 | round-trip 3.14 | ✓ | ✓ | ✓ | ✓ | |
| E36 | round-trip 0.1 | ✓ | ✓ | ✓ | ✓ | |
| E37 | round-trip 123.456 | ✓ | ✓ | ✓ | ✓ | |
| E38 | round-trip -99.99 | ✓ | ✓ | ✓ | ✓ | |
| E39 | round-trip 1e-10 | ✓ | ✓ | ✓ | ✓ | |
| E40 | round-trip very small float | ✓ | ✓ | ✓ | ✓ | JS uses min normal 2^-1022 (subnormals can't round-trip) |
| E41 | round-trip very large float | ✓ | ✓ | ✓ | ✓ | |

### F. Boolean

| ID | Description | Lua | JS | Ruby | Python |
|---|---|---|---|---|---|
| F42 | true → ^B | ✓ | ✓ | ✓ | ✓ |
| F43 | false → ^b | ✓ | ✓ | ✓ | ✓ |
| F44 | ^B → true | ✓ | ✓ | ✓ | ✓ |
| F45 | ^b → false | ✓ | ✓ | ✓ | ✓ |

### G. Nil

| ID | Description | Lua | JS | Ruby | Python |
|---|---|---|---|---|---|
| G46 | nil → ^Z | ✓ | ✓ | ✓ | ✓ |
| G47 | ^Z → nil | ✓ | ✓ | ✓ | ✓ |

### H. Table Serialization

| ID | Description | Lua | JS | Ruby | Python |
|---|---|---|---|---|---|
| H48 | empty table → ^T^t | ✓ | ✓ | ✓ | ✓ |
| H49 | single key-value pair | ✓ | ✓ | ✓ | ✓ |
| H50 | multiple key-value pairs | ✓ | ✓ | ✓ | ✓ |
| H51 | nested table | ✓ | ✓ | ✓ | ✓ |
| H52 | array → 1-based integer keys | ✓ | ✓ | ✓ | ✓ |
| H53 | mixed table | ✓ | ✓ | ✓ | ✓ |

### I. Array Detection (Deserialize)

| ID | Description | Lua | JS | Ruby | Python | Deviation |
|---|---|---|---|---|---|---|
| I54 | sequential 1-based keys → array | ✓ | ✓ | ✓ | ✓ | Lua: table; others: native array |
| I55 | non-sequential → object | ✓ | ✓ | ✓ | ✓ | |
| I56 | string keys → object | ✓ | ✓ | ✓ | ✓ | |
| I57 | single element array | ✓ | ✓ | ✓ | ✓ | |
| I58 | empty table → empty object | ✓ | ✓ | ✓ | ✓ | |

### J/K. Framing and Error Handling

| ID | Description | Lua | JS | Ruby | Python | Deviation |
|---|---|---|---|---|---|---|
| J59 | ^1 prefix + ^^ terminator | ✓ | ✓ | ✓ | ✓ | |
| J60/K63 | missing ^1 → error | ✓ | ✓ | ✓ | ✓ | |
| K64 | empty string → error | ✓ | ✓ | ✓ | ✓ | |
| J61/K65 | missing ^^ → error | ✓ | **skip** | ✓ | ✓ | JS lenient — doesn't throw |
| J62 | control chars stripped | ✓ | ✓ | ✓ | ✓ | |

### L. Round-trips

| ID | Description | Lua | JS | Ruby | Python |
|---|---|---|---|---|---|
| L66 | plain ASCII string | ✓ | ✓ | ✓ | ✓ |
| L67 | all special chars | ✓ | ✓ | ✓ | ✓ |
| L68 | integer | ✓ | ✓ | ✓ | ✓ |
| L69 | float | ✓ | ✓ | ✓ | ✓ |
| L70 | boolean | ✓ | ✓ | ✓ | ✓ |
| L71 | nil | ✓ | ✓ | ✓ | ✓ |
| L72 | nested table/array | ✓ | ✓ | ✓ | ✓ |
| L73 | mixed-type table | ✓ | ✓ | ✓ | ✓ |

---

## LuaDeflate (23 tests) — FULL PARITY ✓

| ID | Description | Lua | JS | Ruby | Python |
|---|---|---|---|---|---|
| M74 | 3-byte → 4 chars | ✓ | ✓ | ✓ | ✓ |
| M75 | 1-byte → 2 chars | ✓ | ✓ | ✓ | ✓ |
| M76 | 2-byte → 3 chars | ✓ | ✓ | ✓ | ✓ |
| M77 | 6-byte → 8 chars | ✓ | ✓ | ✓ | ✓ |
| M78 | empty → empty | ✓ | ✓ | ✓ | ✓ |
| M79 | only alphabet chars | ✓ | ✓ | ✓ | ✓ |
| N80 | 4-char → 3 bytes | ✓ | ✓ | ✓ | ✓ |
| N81 | 2-char → 1 byte | ✓ | ✓ | ✓ | ✓ |
| N82 | 3-char → 2 bytes | ✓ | ✓ | ✓ | ✓ |
| N83 | whitespace stripped | ✓ | ✓ | ✓ | ✓ |
| N84 | length-1 → nil | ✓ | ✓ | ✓ | ✓ |
| N85 | empty → nil | ✓ | ✓ | ✓ | ✓ |
| N86 | invalid char → nil | ✓ | ✓ | ✓ | ✓ |
| O87 | ASCII round-trip | ✓ | ✓ | ✓ | ✓ |
| O88 | all 256 bytes | ✓ | ✓ | ✓ | ✓ |
| O89 | large payload | ✓ | ✓ | ✓ | ✓ |
| O90 | single byte | ✓ | ✓ | ✓ | ✓ |
| O91 | two bytes | ✓ | ✓ | ✓ | ✓ |
| O92 | three bytes | ✓ | ✓ | ✓ | ✓ |
| O93 | null bytes | ✓ | ✓ | ✓ | ✓ |
| P94 | encode deterministic | ✓ | ✓ | ✓ | ✓ |
| P95 | decode is inverse | ✓ | ✓ | ✓ | ✓ |
| P96 | structured round-trip | ✓ | ✓ | ✓ | ✓ |

---

## LibSerialize (67 tests) — MAJOR GAPS

Lua has 67 tests with IDs A01-O05. JS has 58, Ruby 18, Python ~39 — but NONE use the Lua IDs.

| ID | Description | Lua | JS | Ruby | Python |
|---|---|---|---|---|---|
| **A. Nil** |
| A01 | Serialize nil produces non-empty string | ✓ | ✗ | ✗ | ✗ |
| A02 | Deserialize nil | ✓ | ✗ | ✗ | ✗ |
| A03 | Nil round-trip | ✓ | ✗ | ✗ | ✗ |
| **B. Integers (Embedded)** |
| B01 | Zero (1-byte) | ✓ | ✗ | ✗ | ✗ |
| B02 | Positive small int 1 | ✓ | ✗ | ✗ | ✗ |
| B03 | 127 (max 1-byte) | ✓ | ✗ | ✗ | ✗ |
| B04 | -1 (embedded 2-byte) | ✓ | ✗ | ✗ | ✗ |
| B05 | -4095 (near max 2-byte) | ✓ | ✗ | ✗ | ✗ |
| B06 | 128 (embedded 2-byte) | ✓ | ✗ | ✗ | ✗ |
| B07 | 4095 (max 2-byte) | ✓ | ✗ | ✗ | ✗ |
| **C. Integers (Multi-byte)** |
| C01 | 16-bit 4096 | ✓ | ✗ | ✗ | ✗ |
| C02 | 16-bit max 65535 | ✓ | ✗ | ✗ | ✗ |
| C03 | 16-bit negative -4096 | ✓ | ✗ | ✗ | ✗ |
| C04 | 24-bit 65536 | ✓ | ✗ | ✗ | ✗ |
| C05 | 24-bit max 16777215 | ✓ | ✗ | ✗ | ✗ |
| C06 | 32-bit 16777216 | ✓ | ✗ | ✗ | ✗ |
| C07 | 32-bit max 4294967295 | ✓ | ✗ | ✗ | ✗ |
| C08 | 64-bit 4294967296 | ✓ | ✗ | ✗ | ✗ |
| C09 | Large negative -65536 | ✓ | ✗ | ✗ | ✗ |
| **D. Floats** |
| D01 | 3.14 round-trip | ✓ | ✗ | ✗ | ✗ |
| D02 | 0.1 round-trip | ✓ | ✗ | ✗ | ✗ |
| D03 | -99.99 round-trip | ✓ | ✗ | ✗ | ✗ |
| D04 | 1e-10 round-trip | ✓ | ✗ | ✗ | ✗ |
| D05 | 0.5 round-trip | ✓ | ✗ | ✗ | ✗ |
| D06 | +infinity round-trip | ✓ | ✗ | ✗ | ✗ |
| D07 | -infinity round-trip | ✓ | ✗ | ✗ | ✗ |
| D08 | 2^53 (max exact double int) | ✓ | ✗ | ✗ | ✗ |
| D09 | Short float string optimization | ✓ | ✗ | ✗ | ✗ |
| **E. Booleans** |
| E01 | true round-trip | ✓ | ✗ | ✗ | ✗ |
| E02 | false round-trip | ✓ | ✗ | ✗ | ✗ |
| E03 | true/false produce distinct bytes | ✓ | ✗ | ✗ | ✗ |
| **F. Strings (Embedded)** |
| F01 | Empty string | ✓ | ✗ | ✗ | ✗ |
| F02 | Single char | ✓ | ✗ | ✗ | ✗ |
| F03 | Two chars | ✓ | ✗ | ✗ | ✗ |
| F04 | Short (5 chars) | ✓ | ✗ | ✗ | ✗ |
| F05 | 15 chars (max embedded) | ✓ | ✗ | ✗ | ✗ |
| **G. Strings (Length-prefixed)** |
| G01 | 16 chars (STR_8) | ✓ | ✗ | ✗ | ✗ |
| G02 | 100 chars | ✓ | ✗ | ✗ | ✗ |
| G03 | All 256 byte values | ✓ | ✗ | ✗ | ✗ |
| **H. String Refs** |
| H01 | Repeated string uses ref | ✓ | ✗ | ✗ | ✗ |
| H02 | 5 occurrences all use refs | ✓ | ✗ | ✗ | ✗ |
| H03 | Short strings (≤2) not tracked | ✓ | ✗ | ✗ | ✗ |
| **I. Tables (Hash)** |
| I01 | Empty table | ✓ | ✗ | ✗ | ✗ |
| I02 | 1 key-value pair | ✓ | ✗ | ✗ | ✗ |
| I03 | 15 entries (max embedded) | ✓ | ✗ | ✗ | ✗ |
| **J. Arrays** |
| J01 | Single element | ✓ | ✗ | ✗ | ✗ |
| J02 | [a, b, c] | ✓ | ✗ | ✗ | ✗ |
| J03 | Integer array | ✓ | ✗ | ✗ | ✗ |
| J04 | Mixed-type array | ✓ | ✗ | ✗ | ✗ |
| J05 | 16 elements (ARRAY_8) | ✓ | ✗ | ✗ | ✗ |
| **K. Mixed Tables + Nesting** |
| K01 | integer + string keys | ✓ | ✗ | ✗ | ✗ |
| K02 | various value types | ✓ | ✗ | ✗ | ✗ |
| K03 | Nested table | ✓ | ✗ | ✗ | ✗ |
| K04 | Deeply nested | ✓ | ✗ | ✗ | ✗ |
| **L. Table Refs** |
| L01 | Shared sub-table round-trips | ✓ | ✗ | ✗ | ✗ |
| L02 | Refs point to same object | ✓ | ✗ | ✗ | ✗ |
| **M. Variadic** |
| M01 | Serialize multiple values | ✓ | skip | skip | skip | Not implemented in ports |
| M02 | Nil among values | ✓ | skip | skip | skip | Not implemented in ports |
| **N. Error Handling** |
| N01 | Corrupt data → boolean result | ✓ | ✗ | ✗ | ✗ |
| N02 | IsSerializableType true | ✓ | skip | skip | skip | API not ported |
| N03 | IsSerializableType false | ✓ | skip | skip | skip | API not ported |
| **O. Complex Round-trips** |
| O01 | Complex nested structure | ✓ | ✗ | ✗ | ✗ |
| O02 | Boolean keys | ✓ | ✗ | ✗ | ✗ |
| O03 | Float key | ✓ | ✗ | ✗ | ✗ |
| O04 | Null bytes in string | ✓ | ✗ | ✗ | ✗ |
| O05 | All 256 byte values | ✓ | ✗ | ✗ | ✗ |

---

## Known Deviations (skip, don't adapt)

| Tests | Lua behavior | JS/Ruby/Python behavior | Action |
|---|---|---|---|
| C22-C24 | ^N for string-representable floats | Always ^F | skip with reason |
| J61/K65 | Error on missing ^^ | JS lenient | skip in JS |
| E40 | Subnormal float round-trip | JS frexp underflows | skip in JS, use min normal |
| I54 | Returns table (no array type) | Returns native array | Adapt assertion to type system |
| M01-M02 | Variadic serialize | Not ported | skip in JS/Ruby/Python |
| N02-N03 | IsSerializableType API | Not ported | skip in JS/Ruby/Python |

---

## Counts

| Module | Lua | JS | Ruby | Python | Target |
|---|---|---|---|---|---|
| AceSerializer | 73 | 73 | 78 (5 dupes) | 73 | 73 |
| LuaDeflate | 23 | 23 | 23 | 23 | 23 |
| LibSerialize | **67** | 58 (wrong IDs) | 18 (massive gap) | ~39 (wrong IDs) | **67** |
| Pipeline | n/a | 17 | 17 | 17 | 17 |
| CBOR | n/a | 15 | 15 | 14 | 15 |
| Fixtures | 0 | 102 | 102 | ? | 102+ |
