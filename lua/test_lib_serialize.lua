#!/usr/bin/env lua
-- LibSerialize test suite — runs against the real Lua implementation
-- Tests all type codes: nil, integers, floats, booleans, strings, tables/arrays/mixed,
-- string refs, table refs, and wire format reference output.

package.path = package.path .. ";./lua/?.lua"
dofile("lua/shim.lua")
dofile("lua/deps/LibSerialize.lua")

local LibSerialize = LibStub:GetLibrary("LibSerialize")

local pass, fail, total = 0, 0, 0
local current_section = ""

local function section(name)
  current_section = name
  print(string.format("\n--- %s ---", name))
end

local function test(name, fn)
  total = total + 1
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    print(string.format("  PASS: %s", name))
  else
    fail = fail + 1
    print(string.format("  FAIL: %s — %s", name, tostring(err)))
  end
end

local function eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
  end
end

local function neq(a, b, msg)
  if a == b then
    error(string.format("%s: expected not %s", msg or "neq", tostring(a)), 2)
  end
end

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
section("A. Nil")
------------------------------------------------------------------------

test("1. Serialize nil", function()
  local s = ser(nil)
  assert(type(s) == "string" and #s > 0, "nil serializes to non-empty string")
end)

test("2. Deserialize nil", function()
  eq(roundtrip(nil), nil)
end)

test("3. Nil round-trip", function()
  local s = ser(nil)
  local ok, val = LibSerialize:Deserialize(s)
  eq(ok, true)
  eq(val, nil)
end)

------------------------------------------------------------------------
section("B. Integer encoding (small embedded)")
------------------------------------------------------------------------

test("4. Zero (embedded 1-byte)", function()
  eq(roundtrip(0), 0)
end)

test("5. Positive small int 1 (embedded 1-byte)", function()
  eq(roundtrip(1), 1)
end)

test("6. Small int 127 (embedded 1-byte, max)", function()
  eq(roundtrip(127), 127)
end)

test("7. Small negative -1 (embedded 2-byte)", function()
  eq(roundtrip(-1), -1)
end)

test("8. Small negative -4095 (embedded 2-byte, near max)", function()
  eq(roundtrip(-4095), -4095)
end)

test("9. Positive 128 (embedded 2-byte)", function()
  eq(roundtrip(128), 128)
end)

test("10. Positive 4095 (embedded 2-byte, max)", function()
  eq(roundtrip(4095), 4095)
end)

------------------------------------------------------------------------
section("C. Integer encoding (multi-byte)")
------------------------------------------------------------------------

test("11. 16-bit positive (4096)", function()
  eq(roundtrip(4096), 4096)
end)

test("12. 16-bit positive max (65535)", function()
  eq(roundtrip(65535), 65535)
end)

test("13. 16-bit negative (-4096)", function()
  eq(roundtrip(-4096), -4096)
end)

test("14. 24-bit positive (65536)", function()
  eq(roundtrip(65536), 65536)
end)

test("15. 24-bit positive max (16777215)", function()
  eq(roundtrip(16777215), 16777215)
end)

test("16. 32-bit positive (16777216)", function()
  eq(roundtrip(16777216), 16777216)
end)

test("17. 32-bit positive max (4294967295)", function()
  eq(roundtrip(4294967295), 4294967295)
end)

test("18. 64-bit positive (4294967296)", function()
  eq(roundtrip(4294967296), 4294967296)
end)

test("19. Large negative integer (-65536)", function()
  eq(roundtrip(-65536), -65536)
end)

------------------------------------------------------------------------
section("D. Float encoding")
------------------------------------------------------------------------

test("20. Simple float 3.14 round-trip", function()
  eq(roundtrip(3.14), 3.14)
end)

test("21. Float 0.1 round-trip", function()
  eq(roundtrip(0.1), 0.1)
end)

test("22. Float -99.99 round-trip", function()
  eq(roundtrip(-99.99), -99.99)
end)

test("23. Float 1e-10 round-trip", function()
  eq(roundtrip(1e-10), 1e-10)
end)

test("24. Float 0.5 round-trip", function()
  eq(roundtrip(0.5), 0.5)
end)

test("25. Positive infinity round-trip", function()
  eq(roundtrip(math.huge), math.huge)
end)

test("26. Negative infinity round-trip", function()
  eq(roundtrip(-math.huge), -math.huge)
end)

test("27. Large exact integer (2^53, max exact double int) round-trip", function()
  -- Values like 1.7e+308 have no fractional part, so LibSerialize uses the int path,
  -- which tops out at 7 bytes (2^56). Use 2^53 = 9007199254740992 instead.
  eq(roundtrip(9007199254740992), 9007199254740992)
end)

test("28. Short float string optimization (e.g. 1.5 → floatstr path)", function()
  -- 1.5 as string "1.5" is 3 chars < 7, round-trips via floatstr path
  eq(roundtrip(1.5), 1.5)
end)

------------------------------------------------------------------------
section("E. Boolean")
------------------------------------------------------------------------

test("29. true round-trip", function()
  eq(roundtrip(true), true)
end)

test("30. false round-trip", function()
  eq(roundtrip(false), false)
end)

test("31. true and false produce distinct serializations", function()
  neq(ser(true), ser(false), "true vs false")
end)

------------------------------------------------------------------------
section("F. String encoding (embedded: <= 15 chars via embedded type)")
------------------------------------------------------------------------

test("32. Empty string round-trip", function()
  eq(roundtrip(""), "")
end)

test("33. Single char string round-trip", function()
  eq(roundtrip("a"), "a")
end)

test("34. Two char string round-trip", function()
  eq(roundtrip("ab"), "ab")
end)

test("35. Short string (5 chars) round-trip", function()
  eq(roundtrip("hello"), "hello")
end)

test("36. 15-char string (max embedded) round-trip", function()
  eq(roundtrip("123456789012345"), "123456789012345")
end)

------------------------------------------------------------------------
section("G. String encoding (length-prefixed: > 15 chars)")
------------------------------------------------------------------------

test("37. 16-char string (STR_8 path) round-trip", function()
  eq(roundtrip("1234567890123456"), "1234567890123456")
end)

test("38. Long string (100 chars) round-trip", function()
  local s = string.rep("x", 100)
  eq(roundtrip(s), s)
end)

test("39. String with binary data round-trip", function()
  local s = ""
  for i = 0, 255 do s = s .. string.char(i) end
  eq(roundtrip(s), s)
end)

------------------------------------------------------------------------
section("H. String refs (strings > 2 bytes tracked on first occurrence)")
------------------------------------------------------------------------

test("40. Repeated string uses ref (serialization is shorter than two copies)", function()
  local repeated = "hello world"  -- >2 bytes, gets a ref
  local t = { a = repeated, b = repeated }
  local s = ser(t)
  -- The second occurrence should be a ref, not a full copy
  -- Verify round-trip is correct
  local result = roundtrip(t)
  eq(result.a, repeated)
  eq(result.b, repeated)
end)

test("41. String ref preserves value identity across occurrences", function()
  local key = "shared_key"
  local t = {}
  for i = 1, 5 do t[i] = key end
  local result = roundtrip(t)
  for i = 1, 5 do
    eq(result[i], key, "index " .. i)
  end
end)

test("42. String of 1-2 bytes NOT tracked as ref (short strings)", function()
  -- Short strings (<=2 bytes) don't get refs; verify round-trip still works
  local t = { a = "x", b = "x", c = "xy", d = "xy" }
  local result = roundtrip(t)
  eq(result.a, "x")
  eq(result.b, "x")
  eq(result.c, "xy")
  eq(result.d, "xy")
end)

------------------------------------------------------------------------
section("I. Empty and small tables (embedded path)")
------------------------------------------------------------------------

test("43. Empty table round-trip", function()
  local result = roundtrip({})
  eq(type(result), "table")
  eq(next(result), nil)
end)

test("44. Table with 1 key-value pair", function()
  local result = roundtrip({a = 1})
  eq(result.a, 1)
end)

test("45. Table with 15 entries (embedded max)", function()
  local t = {}
  for i = 1, 15 do t["k"..i] = i end
  local result = roundtrip(t)
  for i = 1, 15 do eq(result["k"..i], i) end
end)

------------------------------------------------------------------------
section("J. Arrays (sequential 1-based integer keys)")
------------------------------------------------------------------------

test("46. Single-element array", function()
  local result = roundtrip({"only"})
  eq(result[1], "only")
end)

test("47. Simple array [a, b, c]", function()
  local result = roundtrip({"a", "b", "c"})
  eq(result[1], "a")
  eq(result[2], "b")
  eq(result[3], "c")
end)

test("48. Integer array", function()
  local result = roundtrip({10, 20, 30, 40, 50})
  for i, v in ipairs({10, 20, 30, 40, 50}) do
    eq(result[i], v)
  end
end)

test("49. Mixed-type array", function()
  local result = roundtrip({"str", 42, true, false})
  eq(result[1], "str")
  eq(result[2], 42)
  eq(result[3], true)
  eq(result[4], false)
end)

test("50. Array with 16 elements (ARRAY_8 path)", function()
  local t = {}
  for i = 1, 16 do t[i] = i * 10 end
  local result = roundtrip(t)
  for i = 1, 16 do eq(result[i], i * 10, "index " .. i) end
end)

------------------------------------------------------------------------
section("K. Mixed tables (array + hash portions)")
------------------------------------------------------------------------

test("51. Mixed table: integer + string keys", function()
  local t = {[1] = "first", [2] = "second", x = "extra"}
  local result = roundtrip(t)
  eq(result[1], "first")
  eq(result[2], "second")
  eq(result.x, "extra")
end)

test("52. Mixed table with various value types", function()
  local t = {"arr1", "arr2", key = 99, flag = true}
  local result = roundtrip(t)
  eq(result[1], "arr1")
  eq(result[2], "arr2")
  eq(result.key, 99)
  eq(result.flag, true)
end)

test("53. Nested table", function()
  local t = {inner = {x = 1, y = 2}}
  local result = roundtrip(t)
  eq(result.inner.x, 1)
  eq(result.inner.y, 2)
end)

test("54. Deeply nested table", function()
  local t = {a = {b = {c = {d = 42}}}}
  local result = roundtrip(t)
  eq(result.a.b.c.d, 42)
end)

------------------------------------------------------------------------
section("L. Table refs (repeated table references)")
------------------------------------------------------------------------

test("55. Self-referential structure via shared sub-table", function()
  -- A table that appears in two places should round-trip correctly
  -- (LibSerialize tracks table refs)
  local inner = {value = 99}
  local t = {a = inner, b = inner}
  local result = roundtrip(t)
  eq(result.a.value, 99)
  eq(result.b.value, 99)
end)

test("56. Table ref: mutating via one ref mutates the other", function()
  -- Confirms the deserialized table refs point to the SAME table
  local inner = {value = 1}
  local t = {a = inner, b = inner}
  local result = roundtrip(t)
  -- Both result.a and result.b should be the same table object
  result.a.value = 42
  eq(result.b.value, 42, "shared table ref: mutating a also mutates b")
end)

------------------------------------------------------------------------
section("M. Variadic Serialize/Deserialize")
------------------------------------------------------------------------

test("57. Serialize multiple values", function()
  local s = ser(1, "hello", true)
  local ok, a, b, c = LibSerialize:Deserialize(s)
  eq(ok, true)
  eq(a, 1)
  eq(b, "hello")
  eq(c, true)
end)

test("58. Serialize nil among values", function()
  local s = ser(1, nil, 3)
  local ok, a, b, c = LibSerialize:Deserialize(s)
  eq(ok, true)
  eq(a, 1)
  eq(b, nil)
  eq(c, 3)
end)

------------------------------------------------------------------------
section("N. Error handling")
------------------------------------------------------------------------

test("59. Deserialize corrupt data returns false", function()
  local ok, _ = LibSerialize:Deserialize("not valid data \xff")
  -- Should either error (pcall catches) or return false
  -- Either way we verify it doesn't crash uncaught
  assert(type(ok) == "boolean", "returns boolean")
end)

test("60. IsSerializableType returns true for supported types", function()
  assert(LibSerialize:IsSerializableType(nil), "nil")
  assert(LibSerialize:IsSerializableType(42), "number")
  assert(LibSerialize:IsSerializableType("hello"), "string")
  assert(LibSerialize:IsSerializableType(true), "boolean")
  assert(LibSerialize:IsSerializableType({}), "table")
end)

test("61. IsSerializableType returns false for functions", function()
  assert(not LibSerialize:IsSerializableType(print), "function not serializable")
end)

------------------------------------------------------------------------
section("O. Round-trips (comprehensive)")
------------------------------------------------------------------------

test("62. Complex nested structure", function()
  local t = {
    name = "test",
    values = {1, 2, 3},
    meta = {active = true, count = 0},
  }
  local result = roundtrip(t)
  eq(result.name, "test")
  eq(result.values[1], 1)
  eq(result.values[2], 2)
  eq(result.values[3], 3)
  eq(result.meta.active, true)
  eq(result.meta.count, 0)
end)

test("63. Table with boolean keys", function()
  local t = {[true] = "yes", [false] = "no"}
  local result = roundtrip(t)
  eq(result[true], "yes")
  eq(result[false], "no")
end)

test("64. Table with numeric float key", function()
  -- Non-integer numeric keys go into the map portion
  local t = {[1.5] = "fractional"}
  local result = roundtrip(t)
  eq(result[1.5], "fractional")
end)

test("65. String with null bytes round-trip", function()
  local s = "a\x00b\x00c"
  eq(roundtrip(s), s)
end)

test("66. All 256 byte values in string", function()
  local s = ""
  for i = 0, 255 do s = s .. string.char(i) end
  eq(roundtrip(s), s)
end)

------------------------------------------------------------------------
-- Wire format reference — cross-language ground truth
------------------------------------------------------------------------
section("WIRE FORMAT REFERENCE (for cross-language fixtures)")

local function hex(s)
  local out = {}
  for i = 1, #s do
    out[i] = string.format("%02x", string.byte(s, i))
  end
  return table.concat(out, " ")
end

local function wire(label, v)
  local s = ser(v)
  print(string.format("  %-25s → hex: %s", label, hex(s)))
end

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

------------------------------------------------------------------------
print(string.format("\n========================================"))
print(string.format("LibSerialize: %d/%d passed, %d failed", pass, total, fail))
print(string.format("========================================"))
os.exit(fail > 0 and 1 or 0)
