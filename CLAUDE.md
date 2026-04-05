# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A library that ports WoW (World of Warcraft) AddOn serialization formats from Lua to JavaScript and Ruby. Implements two protocols:

- **LuaDeflate** — Custom base64 encoding/decoding using WoW's specific 62-character set (`a-zA-Z0-9()`)
- **WowAceSerializer** — Serialization/deserialization for WoW Ace library data structures (type-prefixed format: `^S` string, `^N`/`^F` number/float, `^T` table, `^B`/`^b` boolean, `^Z` null)

## Commands

No build system, package manager, test runner, or linter is configured. The JS and Ruby implementations are standalone library files.

The JS `WowAceDeserializer` depends on the `streader` npm package (not declared in a package.json).

Ruby `wowace.rb` has inline demo/test code at the bottom of the file (lines 153-167) that runs on `ruby ruby/wowace.rb`.

## Architecture

Parallel implementations in JS (`js/lib/`) and Ruby (`ruby/`) with identical serialization logic:

- **JS**: CommonJS modules (`LuaDeflate.js`, `WowAceSerializer.js`), except `WowAceDeserializer.js` which uses ES6 `export default` (inconsistency)
- **Ruby**: `LuaDeflate` class with singleton methods; `WowAceSerialization`/`WowAceDeserialization` modules mixed into `WowAceSerializer` class

Key design details:
- Escape mechanism uses `~` prefix in a single-pass regex substitution (see PROTOCOL.md for full mapping)
- **WARNING:** Current JS/Ruby AceSerializer implementations have incorrect escape characters (`~U`/`~T`/`~S` instead of the correct `~}`/`~|`/`~{`), are missing the byte 30 special case, and use sequential replacements instead of single-pass. See plans.md Section 2 for the full bug list. These must be fixed before the code can interoperate with real WoW addons.
- Ruby deserializer converts tables back to arrays when keys are sequential 1..n
- JS `LuaDeflate` offers both string (`decodeForPrint`) and `Uint8Array` (`decodeForPrint2`) output
