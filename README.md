# wow-ports

Ports of WoW (World of Warcraft) addon serialization formats from Lua to JavaScript, Python, and Ruby.

Decode and re-encode export strings from WeakAuras, ElvUI, Plater, MDT, VuhDo, Cell, BigWigs, GSE, TotalRP3, DBM, and more.

## Quick start

```ruby
require_relative 'ruby/pipeline'

result = Pipeline.decode("!WA:2!nZ...)  # auto-detects addon format
result.data    # => deserialized Lua table as Ruby hash
result.addon   # => "weakauras"
result.steps   # => [:prefix, :encode_for_print, :zlib, :lib_serialize]

Pipeline.encode(result)  # => re-encoded export string
```

```javascript
const Pipeline = require('./js/lib/Pipeline');

const result = Pipeline.decode('!WA:2!nZ...');
result.data;   // deserialized object
result.steps;  // ['prefix', 'encode_for_print', 'zlib', 'lib_serialize']

Pipeline.encode(result); // re-encoded string
```

```python
from wow_serialization.pipeline import Pipeline

result = Pipeline.decode("!WA:2!nZ...")
result.data    # deserialized dict
result.steps   # ['prefix', 'encode_for_print', 'zlib', 'lib_serialize']

Pipeline.encode(result)  # re-encoded string
```

You can also specify an addon by name or provide explicit steps:

```ruby
Pipeline.decode(str, addon: 'elvui')
Pipeline.decode(str, steps: [:base64, :zlib, :cbor])
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

The pipeline auto-detects the addon format from the prefix and data characteristics. See [FORMATS.md](FORMATS.md) for full details.

## Libraries

Each language has parallel implementations of:

| Module | Description |
|--------|-------------|
| **Pipeline** | Orchestrates decode/encode with per-addon step sequences and heuristic auto-detection |
| **LuaDeflate** | WoW's custom 64-character encoding (not standard base64) |
| **AceSerializer** | Type-prefixed text serialization (`^S` string, `^N` number, `^T` table, etc.) |
| **LibSerialize** | Binary serialization with type codes and back-references |
| **LibCompress** | Huffman + LZW decompression (clean-room port) |
| **WowCbor** | CBOR wrapper for Plater/BigWigs/GSE |
| **VuhDoSerializer** | VuhDo's custom type-length-value format |

## Tests

```bash
make install  # install dependencies for all languages
make test     # run all test suites
```

Or individually:

```bash
make test-js      # Node.js (node --test)
make test-ruby    # RSpec
make test-python  # pytest
make test-lua     # busted (Lua reference tests)
```

Tests are generated from a shared YAML manifest (`testing/tests.yaml`) using Jinja2 templates, ensuring identical coverage across all languages.

```bash
make generate-tests  # regenerate test files from templates
```

## Project structure

```
js/lib/          JavaScript modules (CommonJS)
ruby/            Ruby modules
python/          Python package (wow_serialization)
lua/             Lua reference implementations + test suite
testing/         Test code generator, YAML manifest, and Jinja2 templates
```

## Protocol docs

- [PROTOCOL.md](PROTOCOL.md) -- AceSerializer and LuaDeflate wire format specification
- [FORMATS.md](FORMATS.md) -- Per-addon export format documentation

## License

MIT
