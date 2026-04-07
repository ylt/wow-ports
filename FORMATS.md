# WoW Addon Export Formats

WoW addons share configuration via export strings — opaque text blobs that users copy/paste between clients or share on the web. Each addon uses a layered encoding pipeline.

## Pipeline

Most addons follow a common layered structure, though the specific layers vary:

```
Encode:  Data → Serialize → Compress → Encode → Prefix + text
Decode:  Text → Strip prefix → Decode → Decompress → Deserialize
```

The layers are mix-and-match:

| Layer | Options |
|-------|---------|
| **Prefix** | `!WA:2!`, `!E1!`, `!PLATER:2!`, `!CELL:*!`, `!GSE3!`, `BW2:`, `!`, or none |
| **Encoding** | LuaDeflate EncodeForPrint, standard base64, plaintext, or raw JSON |
| **Compression** | zlib raw deflate, LibCompress (Huffman+LZW), or none |
| **Serializer** | AceSerializer-3.0, LibSerialize, CBOR, MessagePack, or none |

## Format Matrix

Determined by experimentation against real export strings from [wago.io](https://wago.io).

| Addon | Prefix | Encoding | Compression | Serializer | Status |
|-------|--------|----------|-------------|------------|--------|
| WeakAuras v0 | *(none)* | LuaDeflate | zlib | AceSerializer | Implemented |
| WeakAuras v1 | `!` | LuaDeflate | zlib | AceSerializer | Implemented |
| WeakAuras v2 | `!WA:2!` | LuaDeflate | zlib | LibSerialize | Implemented |
| ElvUI | `!E1!` | LuaDeflate | zlib | AceSerializer | Implemented |
| Plater v2 | `!PLATER:2!` | base64 | zlib | CBOR | Implemented |
| TotalRP3 | `!` | LuaDeflate | zlib | AceSerializer | Supported (same as WA v1) |
| Cell | `!CELL:*:*!` | LuaDeflate | zlib | LibSerialize | Needs prefix support |
| DBM | *(none)* | LuaDeflate | zlib | LibSerialize | Needs format entry |
| BigWigs | `BW2:` | base64 | zlib (Blizzard) | CBOR (Blizzard) | Needs CBOR decoder |
| GSE | `!GSE3!` | base64 | zlib (Blizzard) | CBOR (Blizzard) | Needs CBOR decoder |
| MDT | *(none)* or `!` | LuaDeflate | LibCompress or zlib | AceSerializer | Implemented |
| VuhDo | *(none)* | base64 | LibCompress | unknown | Needs base64 + LibCompress |
| OPie | *(none)* | plaintext | none | custom | Out of scope |
| Baganator | *(none)* | none | none | raw JSON | Trivial |
| BlizzHUD | *(none)* | plaintext | none | custom | Out of scope |

## Notes on Discovery

### Encoding detection

The encoding layer can be identified by character set analysis:
- **LuaDeflate**: exactly `a-zA-Z0-9()` — 64 chars
- **Standard base64**: `A-Za-z0-9+/=` — 65 chars (with padding)
- **Plaintext**: includes spaces, punctuation, or other characters outside both sets
- **JSON**: starts with `{` or `[`

### LibCompress

MDT and VuhDo use **LibCompress** instead of zlib. After decoding (LuaDeflate or base64), the first byte is `0x03`, indicating Huffman+LZW compression. This is a custom Lua compression format (not zlib-compatible) that would need to be ported from the [LibCompress](https://www.curseforge.com/wow/addons/libcompress) Lua source.

LibCompress method markers:
- `0x01` — Huffman only
- `0x02` — LZW only
- `0x03` — Huffman + LZW

### Blizzard C_EncodingUtil (BigWigs, GSE)

BigWigs and GSE use WoW's built-in `C_EncodingUtil` API (added in 11.0):

```lua
-- Encode
C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(data)))
-- Decode
C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(str)))
```

The serialization is CBOR (same as Plater v2), but the compression and base64 encoding use Blizzard's implementations rather than LibDeflate. The compression is standard deflate; the base64 is standard base64.

Source: [BigWigs/Options/Sharing.lua](https://github.com/BigWigsMods/BigWigs), [GSE/API/Serialisation.lua](https://github.com/TimothyLuke/GSE-Advanced-Macro-Compiler)

### Cell

Cell uses LibSerialize + LibDeflate (same as WeakAuras v2) with a versioned prefix: `!CELL:<version>:<scope>!` (e.g., `!CELL:259:ALL!`). The version and scope are variable, so prefix detection needs pattern matching.

```lua
local prefix = "!CELL:"..Cell.versionNum..":ALL!"
local str = LibSerialize:Serialize(data)
str = LibDeflate:CompressDeflate(str)
str = LibDeflate:EncodeForPrint(str)
return prefix..str
```

Source: [enderneko/Cell](https://github.com/enderneko/Cell)

### MDT (Mythic Dungeon Tools)

MDT has two export formats:
- **Current**: `!` prefix + LuaDeflate + zlib + AceSerializer (same pipeline as WeakAuras v1)
- **Legacy**: no prefix + LuaDeflate + LibCompress(Huffman) + AceSerializer

---

## Implemented Addons

### WeakAuras

**Version 0 (legacy):** No prefix. Rare — predates the `!` prefix convention.
```
<LuaDeflate(zlib(AceSerializer(data)))>
```

**Version 1:** Prefix `!`. Common for exports prior to ~2023.
```
!<LuaDeflate(zlib(AceSerializer(data)))>
```

**Version 2:** Prefix `!WA:2!`. Current format.
```
!WA:2!<LuaDeflate(zlib(LibSerialize(data)))>
```

### ElvUI

Prefix `!E1!`. Uses AceSerializer-3.0 with an optional metadata trailer.

```
!E1!<LuaDeflate(zlib(AceSerializer(data)))>^^::<profileType>::<profileKey>
```

The `^^::` delimiter separates the encoded data from the metadata. Both `profileType` and `profileKey` are plain text (not encoded). If no metadata is present, the trailer is omitted.

### Plater v2

Prefix `!PLATER:2!`. Uses standard base64 (not LuaDeflate) and CBOR serialization.

```
!PLATER:2!<base64(zlib(CBOR(data)))>
```

---

## Serializer Reference

| Serializer | Type | Spec |
|------------|------|------|
| AceSerializer-3.0 | Text (`^T^Skey^Nvalue^t^^`) | [PROTOCOL.md](PROTOCOL.md#wow-ace-serialization) |
| LibSerialize | Binary (type codes + refs) | [PROTOCOL.md](PROTOCOL.md) *(planned)* |
| CBOR | Binary (RFC 8949) | [cbor.io](https://cbor.io) |
| LuaDeflate EncodeForPrint | Encoding layer (not a serializer) | [PROTOCOL.md](PROTOCOL.md#luadeflate-encoding) |
