-- Fixture-based tests for AceSerializer and LuaDeflate — busted spec
-- Reads testdata/fixtures.json and runs identical tests to JS/Ruby fixture suites.
-- CWD is lua/ when run via busted.

dofile("shim.lua")
dofile("deps/AceSerializer-3.0.lua")
local LibDeflate = dofile("deps/LibDeflate.lua")
local json = require("dkjson")

local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")

-- ── Load fixtures ──────────────────────────────────────────────────────────

local fixtures_path = "../testdata/fixtures.json"
local fh = assert(io.open(fixtures_path, "r"), "Cannot open " .. fixtures_path)
local fixtures_raw = fh:read("*a")
fh:close()
local fixtures = json.decode(fixtures_raw)
assert(fixtures, "Failed to parse fixtures.json")

-- ── __type__ wrapper handling ──────────────────────────────────────────────
-- Mirrors JS toNativeValue(): converts JSON __type__ wrappers to native values.

local function toNative(v)
  if v == nil or v == json.null then return nil end
  if type(v) ~= "table" then return v end

  local t = v["__type__"]
  if t == "infinity"     then return math.huge end
  if t == "neg_infinity" then return -math.huge end
  if t == "float"        then return v.value end
  if t == "bytes" then
    local hex = v.hex
    return (hex:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
  end

  -- Recurse into plain tables/arrays.
  local result = {}
  for k, val in pairs(v) do
    result[k] = toNative(val)
  end
  return result
end

-- ── Helpers ────────────────────────────────────────────────────────────────

local function ace_deser(s)
  local ok, val = AceSerializer:Deserialize(s)
  assert(ok, "AceSerializer:Deserialize failed: " .. tostring(val))
  return val
end

local function ace_ser(v)
  return AceSerializer:Serialize(v)
end

local function hex_to_bytes(hex)
  return (hex:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
end

local function bytes_to_hex(s)
  local out = {}
  for i = 1, #s do
    out[i] = string.format("%02x", string.byte(s, i))
  end
  return table.concat(out)
end

-- Returns true if the fixture input contains a __type__: "float" wrapper
-- (string-representable floats that Lua serializes as ^N, not ^F^f).
local function is_float_type(input)
  return type(input) == "table" and input["__type__"] == "float"
end

-- Returns true if the wire format contains null (^Z) inside a table (^Z followed
-- by another type marker like ^N/^S/^T/^B/^b). The real Lua AceSerializer-3.0
-- does not store nil values in tables, so it cannot deserialize or produce these.
local function has_null_in_table(wire)
  return wire:find("%^Z%^[NSTBbFfT]") ~= nil
end

-- ── AceSerializer: deserialize ─────────────────────────────────────────────

describe("AceSerializer fixtures — deserialize", function()
  for _, fixture in ipairs(fixtures.ace_serializer) do
    it(fixture.name, function()
      if has_null_in_table(fixture.ace_serialized) then
        pending("Lua AceSerializer-3.0 does not store nil in tables; ^Z inside ^T unsupported")
        return
      end
      local result = ace_deser(fixture.ace_serialized)
      assert.same(toNative(fixture.input), result)
    end)
  end
end)

-- ── AceSerializer: serialize ───────────────────────────────────────────────
-- Skip fixtures where serialize_deterministic is false (non-deterministic key order).
-- Skip fixtures where input is a __type__: "float" (Lua uses ^N, not ^F^f).
-- Skip fixtures whose wire format contains null inside a table (Lua skips nil values).

describe("AceSerializer fixtures — serialize", function()
  for _, fixture in ipairs(fixtures.ace_serializer) do
    if fixture.serialize_deterministic == false then
      -- skip: non-deterministic table key order
    elseif is_float_type(fixture.input) then
      it(fixture.name, function()
        pending("Lua uses ^N for string-representable floats")
      end)
    elseif has_null_in_table(fixture.ace_serialized) then
      it(fixture.name, function()
        pending("Lua AceSerializer-3.0 skips nil values in tables; wire format differs")
      end)
    else
      it(fixture.name, function()
        local result = ace_ser(toNative(fixture.input))
        assert.are.equal(fixture.ace_serialized, result)
      end)
    end
  end
end)

-- ── AceSerializer: round-trip ──────────────────────────────────────────────
-- deserialize(ace_serialized) → value1 → serialize(value1) → deserialize → value2
-- Assert value2 deeply equals value1 (internal consistency).

describe("AceSerializer fixtures — round-trip", function()
  for _, fixture in ipairs(fixtures.ace_serializer) do
    it(fixture.name, function()
      if has_null_in_table(fixture.ace_serialized) then
        pending("Lua AceSerializer-3.0 does not store nil in tables; ^Z inside ^T unsupported")
        return
      end
      local value1 = ace_deser(fixture.ace_serialized)
      local wire2  = ace_ser(value1)
      local value2 = ace_deser(wire2)
      assert.same(value1, value2)
    end)
  end
end)

-- ── LuaDeflate: encode ─────────────────────────────────────────────────────

describe("LuaDeflate fixtures — encode", function()
  for _, fixture in ipairs(fixtures.lua_deflate) do
    it(fixture.name, function()
      local input = hex_to_bytes(fixture.input_hex)
      local encoded = LibDeflate:EncodeForPrint(input)
      assert.are.equal(fixture.encoded, encoded)
    end)
  end
end)

-- ── LuaDeflate: decode ─────────────────────────────────────────────────────

describe("LuaDeflate fixtures — decode", function()
  for _, fixture in ipairs(fixtures.lua_deflate) do
    it(fixture.name, function()
      local decoded = LibDeflate:DecodeForPrint(fixture.encoded)
      assert.are.equal(fixture.input_hex, bytes_to_hex(decoded))
    end)
  end
end)
