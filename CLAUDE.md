# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ports WoW (World of Warcraft) addon serialization formats from Lua to JavaScript, Ruby, and Python. Decodes and re-encodes export strings from 11+ addons (WeakAuras, ElvUI, Plater, MDT, VuhDo, Cell, BigWigs, GSE, TotalRP3, DBM, etc.).

## Commands

```bash
make install          # install deps for all languages
make test             # run all test suites (JS + Ruby + Python + Lua)
make test-js          # node --test js/test/**/*.test.js
make test-ruby        # cd ruby && bundle exec rspec spec/
make test-python      # cd python && uv run --extra test pytest tests/ -v
make test-lua         # cd lua && busted test/ --verbose
make generate-tests   # cd testing && uv run generate-tests.py
```

Single test by language:
- **JS**: `node --test js/test/pipeline.test.js`
- **Ruby**: `cd ruby && bundle exec rspec spec/pipeline_spec.rb -e "WA v1"`
- **Python**: `cd python && uv run pytest tests/test_pipeline.py -k "A1" -v`
- **Lua**: `cd lua && busted test/ace_serializer_spec.lua --filter "A1"`

## Architecture

### Pipeline

The central abstraction. Each addon format is a sequence of **steps** (prefix, encoding, compression, serialization). Decode runs steps left-to-right; encode runs them right-to-left.

Key structures in each language's Pipeline:
- **STEPS** registry: maps step names to `[decode_method, encode_method]` pairs
- **AUTO_FORMATS**: ordered array of `{addon, version, prefix, steps}` for prefix-based auto-detection (longest prefix first)
- **FORMATS**: addon-keyed lookup for explicit `Pipeline.decode(str, addon: 'mdt')`
- **ExportResult**: carries `addon`, `version`, `data`, `metadata`, `steps` — steps enable context-free re-encoding

Heuristic detection (`detect_steps`) probes four layers: prefix match, character set analysis (encoding), first-byte probe (compression), content analysis (serializer).

### Test Code Generation

Tests are generated from `testing/tests.yaml` (single source of truth) via Jinja2 templates in `testing/templates/`. The Lua reference implementation is ground truth. Run `make generate-tests` after changing the YAML manifest or templates. Generated test files have a "DO NOT EDIT" header.

### LuaDeflate: Reference vs Native

Two implementations exist per language:
- **Reference** (`lua_deflate.*`): manual bit-shifting, faithful port of the Lua source
- **Native** (`lua_deflate_native.*`): wraps stdlib base64 with alphabet translation and byte-group reversal

Both produce identical output. **Pipeline and all tests use the native variant.** The reference exists for standalone use and as a readable specification.

### LibCompress

Clean-room implementation of Huffman + LZW decompression. **Not derived from GPL-licensed LibCompress.lua** — reverse-engineered from wire format analysis. Decode only; encode is not implemented. Safe to redistribute.

## Language-Specific Notes

- **JS**: CommonJS throughout (`require`/`module.exports`). No ES6 imports. Depends on `cbor-x` (npm).
- **Ruby**: Flat `ruby/*.rb` files with `require_relative`. Uses `Struct.new` for ExportResult. Depends on `cbor` gem.
- **Python**: `wow_serialization` package. Uses dataclasses. Managed with `uv` and `pyproject.toml`. Test extras: `uv run --extra test`.
- **Lua**: Reference implementations only (not ports). Lives in `lua/` with busted test framework. Dependencies fetched via `lua/fetch-deps.sh`.

## Key Documentation

- [PROTOCOL.md](PROTOCOL.md) — AceSerializer and LuaDeflate wire format specification
- [FORMATS.md](FORMATS.md) — Per-addon export format matrix with source verification
