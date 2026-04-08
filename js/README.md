# azerite

Decode and encode World of Warcraft addon export strings in Node.js.

Supports WeakAuras, ElvUI, Plater, MDT, VuhDo, Cell, BigWigs, GSE, TotalRP3, DBM, and more.

## Install

```bash
npm install azerite
```

## Usage

```javascript
const { Pipeline } = require('azerite');

// Auto-detect addon format and decode
const result = Pipeline.decode('!WA:2!nZ...');
console.log(result.data);   // deserialized object
console.log(result.addon);  // 'weakauras'
console.log(result.steps);  // ['prefix', 'encode_for_print', 'zlib', 'lib_serialize']

// Re-encode from a previous result
Pipeline.encode(result);

// Decode with explicit addon
Pipeline.decode(str, { addon: 'elvui' });

// Decode with explicit steps
Pipeline.decode(str, { steps: ['base64', 'zlib', 'cbor'] });
```

## Supported addons

| Addon | Prefix | Encoding | Compression | Serializer |
|-------|--------|----------|-------------|------------|
| WeakAuras v2 | `!WA:2!` | EncodeForPrint | zlib | LibSerialize |
| WeakAuras v1 | `!` | EncodeForPrint | zlib | AceSerializer |
| ElvUI | `!E1!` | EncodeForPrint | zlib | AceSerializer |
| Plater v2 | `!PLATER:2!` | base64 | zlib | CBOR |
| Cell | `!CELL:*:*!` | EncodeForPrint | zlib | LibSerialize |
| MDT | `!` or none | EncodeForPrint | zlib or LibCompress | AceSerializer |
| TotalRP3 | `!` | EncodeForPrint | zlib | AceSerializer |
| BigWigs | `BW2:` | base64 | zlib | CBOR |
| GSE | `!GSE3!` | base64 | zlib | CBOR |
| VuhDo | none | base64 | LibCompress | VuhDo custom |
| DBM | none | EncodeForPrint | zlib | LibSerialize |

## Individual modules

```javascript
const {
  Pipeline,
  LuaDeflate,
  LuaDeflateNative,
  WowAceSerializer,
  WowAceDeserializer,
  LibSerialize,
  LibCompress,
  WowCbor,
  VuhDoSerializer,
} = require('azerite');
```

## License

ISC
