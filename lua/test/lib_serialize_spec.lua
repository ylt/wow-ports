-- LibSerialize test suite — busted spec
-- CWD is lua/ when run via busted.

dofile("shim.lua")
dofile("deps/LibSerialize.lua")

local LibSerialize = LibStub:GetLibrary("LibSerialize")

local function ser(...)
  return LibSerialize:Serialize(...)
end

local function deser(s)
  local ok, val = LibSerialize:Deserialize(s)
  assert(ok, "Deserialize failed: " .. tostring(val))
  return val
end

local function roundtrip(v)
  return deser(ser(v))
end

------------------------------------------------------------------------
describe("LibSerialize", function()
------------------------------------------------------------------------

  describe("A. Nil", function()
    it("A01: Serialize nil produces non-empty string", function()
      local s = ser(nil)
      assert.are.equal(type(s), "string")
      assert.truthy(#s > 0)
    end)

    it("A02: Deserialize nil", function()
      assert.is_nil(roundtrip(nil))
    end)

    it("A03: Nil round-trip via Deserialize API", function()
      local s = ser(nil)
      local ok, val = LibSerialize:Deserialize(s)
      assert.are.equal(ok, true)
      assert.is_nil(val)
    end)
  end)

  describe("B. Integer encoding (small embedded)", function()
    it("B01: Zero (embedded 1-byte)", function()
      assert.are.equal(roundtrip(0), 0)
    end)

    it("B02: Positive small int 1", function()
      assert.are.equal(roundtrip(1), 1)
    end)

    it("B03: Small int 127 (embedded 1-byte, max)", function()
      assert.are.equal(roundtrip(127), 127)
    end)

    it("B04: Small negative -1 (embedded 2-byte)", function()
      assert.are.equal(roundtrip(-1), -1)
    end)

    it("B05: Small negative -4095 (embedded 2-byte, near max)", function()
      assert.are.equal(roundtrip(-4095), -4095)
    end)

    it("B06: Positive 128 (embedded 2-byte)", function()
      assert.are.equal(roundtrip(128), 128)
    end)

    it("B07: Positive 4095 (embedded 2-byte, max)", function()
      assert.are.equal(roundtrip(4095), 4095)
    end)
  end)

  describe("C. Integer encoding (multi-byte)", function()
    it("C01: 16-bit positive (4096)", function()
      assert.are.equal(roundtrip(4096), 4096)
    end)

    it("C02: 16-bit positive max (65535)", function()
      assert.are.equal(roundtrip(65535), 65535)
    end)

    it("C03: 16-bit negative (-4096)", function()
      assert.are.equal(roundtrip(-4096), -4096)
    end)

    it("C04: 24-bit positive (65536)", function()
      assert.are.equal(roundtrip(65536), 65536)
    end)

    it("C05: 24-bit positive max (16777215)", function()
      assert.are.equal(roundtrip(16777215), 16777215)
    end)

    it("C06: 32-bit positive (16777216)", function()
      assert.are.equal(roundtrip(16777216), 16777216)
    end)

    it("C07: 32-bit positive max (4294967295)", function()
      assert.are.equal(roundtrip(4294967295), 4294967295)
    end)

    it("C08: 64-bit positive (4294967296)", function()
      assert.are.equal(roundtrip(4294967296), 4294967296)
    end)

    it("C09: Large negative integer (-65536)", function()
      assert.are.equal(roundtrip(-65536), -65536)
    end)
  end)

  describe("D. Float encoding", function()
    it("D01: Float 3.14 round-trip", function()
      assert.are.equal(roundtrip(3.14), 3.14)
    end)

    it("D02: Float 0.1 round-trip", function()
      assert.are.equal(roundtrip(0.1), 0.1)
    end)

    it("D03: Float -99.99 round-trip", function()
      assert.are.equal(roundtrip(-99.99), -99.99)
    end)

    it("D04: Float 1e-10 round-trip", function()
      assert.are.equal(roundtrip(1e-10), 1e-10)
    end)

    it("D05: Float 0.5 round-trip", function()
      assert.are.equal(roundtrip(0.5), 0.5)
    end)

    it("D06: Positive infinity round-trip", function()
      assert.are.equal(roundtrip(math.huge), math.huge)
    end)

    it("D07: Negative infinity round-trip", function()
      assert.are.equal(roundtrip(-math.huge), -math.huge)
    end)

    it("D08: Max exact double integer (2^53) round-trip", function()
      -- 1.7e+308 has no fractional part, overflows 7-byte int path.
      -- 2^53 = 9007199254740992 is the largest exact integer in a double.
      assert.are.equal(roundtrip(9007199254740992), 9007199254740992)
    end)

    it("D09: Short float string optimization (1.5 → floatstr path)", function()
      assert.are.equal(roundtrip(1.5), 1.5)
    end)
  end)

  describe("E. Boolean", function()
    it("E01: true round-trip", function()
      assert.are.equal(roundtrip(true), true)
    end)

    it("E02: false round-trip", function()
      assert.are.equal(roundtrip(false), false)
    end)

    it("E03: true and false produce distinct serializations", function()
      assert.are_not.equal(ser(true), ser(false))
    end)
  end)

  describe("F. String encoding (embedded ≤15 chars)", function()
    it("F01: Empty string round-trip", function()
      assert.are.equal(roundtrip(""), "")
    end)

    it("F02: Single char string round-trip", function()
      assert.are.equal(roundtrip("a"), "a")
    end)

    it("F03: Two char string round-trip", function()
      assert.are.equal(roundtrip("ab"), "ab")
    end)

    it("F04: Short string (5 chars) round-trip", function()
      assert.are.equal(roundtrip("hello"), "hello")
    end)

    it("F05: 15-char string (max embedded) round-trip", function()
      assert.are.equal(roundtrip("123456789012345"), "123456789012345")
    end)
  end)

  describe("G. String encoding (length-prefixed >15 chars)", function()
    it("G01: 16-char string (STR_8 path) round-trip", function()
      assert.are.equal(roundtrip("1234567890123456"), "1234567890123456")
    end)

    it("G02: Long string (100 chars) round-trip", function()
      local s = string.rep("x", 100)
      assert.are.equal(roundtrip(s), s)
    end)

    it("G03: String with all 256 byte values round-trip", function()
      local s = ""
      for i = 0, 255 do s = s .. string.char(i) end
      assert.are.equal(roundtrip(s), s)
    end)
  end)

  describe("H. String refs (strings >2 bytes tracked on first use)", function()
    it("H01: Repeated string uses ref — values preserved", function()
      local repeated = "hello world"
      local t = {a = repeated, b = repeated}
      local result = roundtrip(t)
      assert.are.equal(result.a, repeated)
      assert.are.equal(result.b, repeated)
    end)

    it("H02: String ref preserves value across 5 occurrences", function()
      local key = "shared_key"
      local t = {}
      for i = 1, 5 do t[i] = key end
      local result = roundtrip(t)
      for i = 1, 5 do
        assert.are.equal(result[i], key)
      end
    end)

    it("H03: Short strings (≤2 bytes) not tracked as ref — still round-trip", function()
      local t = {a = "x", b = "x", c = "xy", d = "xy"}
      local result = roundtrip(t)
      assert.are.equal(result.a, "x")
      assert.are.equal(result.b, "x")
      assert.are.equal(result.c, "xy")
      assert.are.equal(result.d, "xy")
    end)
  end)

  describe("I. Empty and small tables (embedded path)", function()
    it("I01: Empty table round-trip", function()
      local result = roundtrip({})
      assert.are.equal(type(result), "table")
      assert.is_nil(next(result))
    end)

    it("I02: Table with 1 key-value pair", function()
      assert.are.equal(roundtrip({a = 1}).a, 1)
    end)

    it("I03: Table with 15 entries (embedded max)", function()
      local t = {}
      for i = 1, 15 do t["k"..i] = i end
      local result = roundtrip(t)
      for i = 1, 15 do
        assert.are.equal(result["k"..i], i)
      end
    end)
  end)

  describe("J. Arrays (sequential 1-based integer keys)", function()
    it("J01: Single-element array", function()
      assert.are.equal(roundtrip({"only"})[1], "only")
    end)

    it("J02: Simple array [a, b, c]", function()
      local result = roundtrip({"a", "b", "c"})
      assert.are.equal(result[1], "a")
      assert.are.equal(result[2], "b")
      assert.are.equal(result[3], "c")
    end)

    it("J03: Integer array", function()
      local result = roundtrip({10, 20, 30, 40, 50})
      for i, v in ipairs({10, 20, 30, 40, 50}) do
        assert.are.equal(result[i], v)
      end
    end)

    it("J04: Mixed-type array", function()
      local result = roundtrip({"str", 42, true, false})
      assert.are.equal(result[1], "str")
      assert.are.equal(result[2], 42)
      assert.are.equal(result[3], true)
      assert.are.equal(result[4], false)
    end)

    it("J05: Array with 16 elements (ARRAY_8 path)", function()
      local t = {}
      for i = 1, 16 do t[i] = i * 10 end
      local result = roundtrip(t)
      for i = 1, 16 do
        assert.are.equal(result[i], i * 10)
      end
    end)
  end)

  describe("K. Mixed tables (array + hash portions)", function()
    it("K01: Mixed table: integer + string keys", function()
      local result = roundtrip({[1] = "first", [2] = "second", x = "extra"})
      assert.are.equal(result[1], "first")
      assert.are.equal(result[2], "second")
      assert.are.equal(result.x, "extra")
    end)

    it("K02: Mixed table with various value types", function()
      local result = roundtrip({"arr1", "arr2", key = 99, flag = true})
      assert.are.equal(result[1], "arr1")
      assert.are.equal(result[2], "arr2")
      assert.are.equal(result.key, 99)
      assert.are.equal(result.flag, true)
    end)

    it("K03: Nested table", function()
      local result = roundtrip({inner = {x = 1, y = 2}})
      assert.are.equal(result.inner.x, 1)
      assert.are.equal(result.inner.y, 2)
    end)

    it("K04: Deeply nested table", function()
      local result = roundtrip({a = {b = {c = {d = 42}}}})
      assert.are.equal(result.a.b.c.d, 42)
    end)
  end)

  describe("L. Table refs (repeated table references)", function()
    it("L01: Shared sub-table round-trips correctly", function()
      local inner = {value = 99}
      local result = roundtrip({a = inner, b = inner})
      assert.are.equal(result.a.value, 99)
      assert.are.equal(result.b.value, 99)
    end)

    it("L02: Deserialized table refs point to the same table object", function()
      local inner = {value = 1}
      local result = roundtrip({a = inner, b = inner})
      result.a.value = 42
      assert.are.equal(result.b.value, 42)
    end)
  end)

  describe("M. Variadic Serialize/Deserialize", function()
    it("M01: Serialize multiple values", function()
      local s = ser(1, "hello", true)
      local ok, a, b, c = LibSerialize:Deserialize(s)
      assert.are.equal(ok, true)
      assert.are.equal(a, 1)
      assert.are.equal(b, "hello")
      assert.are.equal(c, true)
    end)

    it("M02: Serialize nil among values", function()
      local s = ser(1, nil, 3)
      local ok, a, b, c = LibSerialize:Deserialize(s)
      assert.are.equal(ok, true)
      assert.are.equal(a, 1)
      assert.is_nil(b)
      assert.are.equal(c, 3)
    end)
  end)

  describe("N. Error handling", function()
    it("N01: Deserialize corrupt data returns boolean result", function()
      local ok, _ = LibSerialize:Deserialize("not valid data \xff")
      assert.are.equal(type(ok), "boolean")
    end)

    it("N02: IsSerializableType returns true for supported types", function()
      assert.truthy(LibSerialize:IsSerializableType(nil))
      assert.truthy(LibSerialize:IsSerializableType(42))
      assert.truthy(LibSerialize:IsSerializableType("hello"))
      assert.truthy(LibSerialize:IsSerializableType(true))
      assert.truthy(LibSerialize:IsSerializableType({}))
    end)

    it("N03: IsSerializableType returns false for functions", function()
      assert.falsy(LibSerialize:IsSerializableType(print))
    end)
  end)

  describe("O. Round-trips (comprehensive)", function()
    it("O01: Complex nested structure", function()
      local t = {name = "test", values = {1, 2, 3}, meta = {active = true, count = 0}}
      local result = roundtrip(t)
      assert.are.equal(result.name, "test")
      assert.are.equal(result.values[1], 1)
      assert.are.equal(result.values[2], 2)
      assert.are.equal(result.values[3], 3)
      assert.are.equal(result.meta.active, true)
      assert.are.equal(result.meta.count, 0)
    end)

    it("O02: Table with boolean keys", function()
      local result = roundtrip({[true] = "yes", [false] = "no"})
      assert.are.equal(result[true], "yes")
      assert.are.equal(result[false], "no")
    end)

    it("O03: Table with float key (non-integer → map portion)", function()
      local result = roundtrip({[1.5] = "fractional"})
      assert.are.equal(result[1.5], "fractional")
    end)

    it("O04: String with null bytes round-trip", function()
      local s = "a\x00b\x00c"
      assert.are.equal(roundtrip(s), s)
    end)

    it("O05: All 256 byte values in string", function()
      local s = ""
      for i = 0, 255 do s = s .. string.char(i) end
      assert.are.equal(roundtrip(s), s)
    end)
  end)

  describe("WIRE FORMAT REFERENCE", function()
    it("prints cross-language fixtures (hex)", function()
      local function hex(s)
        local out = {}
        for i = 1, #s do out[i] = string.format("%02x", string.byte(s, i)) end
        return table.concat(out, " ")
      end
      local function wire(label, v)
        print(string.format("  %-25s → hex: %s", label, hex(ser(v))))
      end
      print("\n  -- LibSerialize wire format (hex) --")
      wire("nil", nil)
      wire("false", false)
      wire("true", true)
      wire("0", 0)
      wire("1", 1)
      wire("127", 127)
      wire("128", 128)
      wire("4095", 4095)
      wire("4096", 4096)
      wire("-1", -1)
      wire("-4096", -4096)
      wire("65535", 65535)
      wire("65536", 65536)
      wire("3.14", 3.14)
      wire("0.1", 0.1)
      wire("0.5", 0.5)
      wire('""', "")
      wire('"a"', "a")
      wire('"hello"', "hello")
      wire('"hello world"', "hello world")
      wire("{}", {})
      wire("{1,2,3}", {1,2,3})
      wire('{a=1}', {a=1})
      assert.truthy(true)
    end)
  end)

end)
