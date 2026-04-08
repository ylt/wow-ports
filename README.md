# azerite

Ports of WoW (World of Warcraft) addon serialization formats from Lua to JavaScript, Python, and Ruby.

Decode and re-encode export strings from WeakAuras, ElvUI, Plater, MDT, VuhDo, Cell, BigWigs, GSE, TotalRP3, DBM, and more.

## Packages

| Language | Package | Install | Docs |
|----------|---------|---------|------|
| JavaScript | [azerite](https://www.npmjs.com/package/azerite) | `npm install azerite` | [js/README.md](js/README.md) |
| Ruby | [azerite](https://rubygems.org/gems/azerite) | `gem install azerite` | [ruby/README.md](ruby/README.md) |
| Python | [azerite](https://pypi.org/project/azerite/) | `pip install azerite` | [python/README.md](python/README.md) |

## Quick start

```javascript
const { Pipeline } = require('azerite');
const result = Pipeline.decode('!WA:2!nZ...');
// result.data, result.addon, result.steps
Pipeline.encode(result);
```

```ruby
require "azerite"
result = Pipeline.decode("!WA:2!nZ...")
Pipeline.encode(result)
```

```python
from azerite import Pipeline
result = Pipeline.decode("!WA:2!nZ...")
Pipeline.encode(result)
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
js/              JavaScript package (CommonJS)
ruby/            Ruby gem (lib/azerite/)
python/          Python package (azerite/)
lua/             Lua reference implementations + test suite
testing/         Test code generator, YAML manifest, and Jinja2 templates
```

## Protocol docs

- [PROTOCOL.md](PROTOCOL.md) -- AceSerializer and LuaDeflate wire format specification
- [FORMATS.md](FORMATS.md) -- Per-addon export format documentation

## Credits

From-scratch implementations of the wire formats used by these WoW Lua libraries:

- [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) by Haoqian He — EncodeForPrint encoding ([zlib](https://github.com/SafeteeWoW/LibDeflate/blob/main/LICENSE.txt))
- [AceSerializer-3.0](https://github.com/hurricup/WoW-Ace3) (Ace3) — type-prefixed text serialization ([BSD](https://github.com/hurricup/WoW-Ace3/blob/master/LICENSE.txt))
- [LibSerialize](https://github.com/rossnichols/LibSerialize) by Ross Nichols — binary serialization with back-references ([MIT](https://github.com/rossnichols/LibSerialize/blob/main/LICENSE))
- [LibCompress](https://github.com/WoWAddonMirrors/LibCompress) by jjsheets and Galmok — Huffman + LZW compression ([GPL v2](https://github.com/WoWAddonMirrors/LibCompress/blob/main/LibCompress.lua#L7))
- [VuhDo](https://gitlab.vuhdo.io/vuhdo/vuhdo) — custom type-length-value serialization ([All Rights Reserved](https://gitlab.vuhdo.io/vuhdo/vuhdo/-/blob/master/LICENSE))

## License

ISC
