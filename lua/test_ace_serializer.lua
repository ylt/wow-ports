#!/usr/bin/env lua
-- AceSerializer-3.0 test suite — runs against the real Lua implementation
-- Grounded in the 96-case canonical spec (sections A-L)

package.path = package.path .. ";./lua/?.lua"
dofile("lua/shim.lua")
dofile("lua/deps/AceSerializer-3.0.lua")

local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")

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
    error(string.format("%s: expected %s, got %s", msg or "assertion", tostring(b), tostring(a)), 2)
  end
end

local function contains(str, sub, msg)
  if not string.find(str, sub, 1, true) then
    error(string.format("%s: expected '%s' to contain '%s'", msg or "assertion", str, sub), 2)
  end
end

-- Helper: serialize single value
local function ser(v)
  return AceSerializer:Serialize(v)
end

-- Helper: deserialize and return first value
local function deser(s)
  local ok, val = AceSerializer:Deserialize(s)
  assert(ok, "Deserialize failed: " .. tostring(val))
  return val
end

-- Helper: round-trip
local function roundtrip(v)
  return deser(ser(v))
end

------------------------------------------------------------------------
section("A. String Escaping (Serialize)")
------------------------------------------------------------------------

test("1. NUL (0x00) → ~@ (chr 64)", function()
  local s = ser("\0")
  contains(s, "~@", "NUL escape")
end)

test("2. Control char 0x01 → ~A", function()
  contains(ser("\1"), "~A")
end)

test("3. Control char 0x0A (newline) → ~J", function()
  contains(ser("\10"), "~J")
end)

test("4. Control char 0x1D → ~]", function()
  contains(ser("\29"), "~]")
end)

test("5. Byte 30 (0x1E) → ~z (special case)", function()
  contains(ser("\30"), "~z")
end)

test("6. Byte 31 (0x1F) → ~_", function()
  contains(ser("\31"), "~_")
end)

test("7. Space (0x20) → ~`", function()
  contains(ser(" "), "~`")
end)

test("8. Caret ^ (0x5E) → ~}", function()
  contains(ser("^"), "~}")
end)

test("9. Tilde ~ (0x7E) → ~|", function()
  contains(ser("~"), "~|")
end)

test("10. DEL (0x7F) → ~{", function()
  contains(ser("\127"), "~{")
end)

test("11. Single-pass: no double-escaping", function()
  local s = ser("^~\127")
  -- Should contain ~} ~| ~{ but NOT double-escaped versions
  contains(s, "~}")
  contains(s, "~|")
  contains(s, "~{")
end)

test("12. Printable ASCII passes through unescaped", function()
  local s = ser("hello")
  contains(s, "^Shello")
end)

------------------------------------------------------------------------
section("B. String Unescaping (Deserialize)")
------------------------------------------------------------------------

test("13. ~@ → NUL", function()
  eq(deser("^1^S~@^^"), "\0")
end)

test("14. Generic ~X where X < z → chr(ord(X)-64)", function()
  eq(deser("^1^S~A^^"), "\1")  -- ~A → 0x01
  eq(deser("^1^S~J^^"), "\10") -- ~J → 0x0A
end)

test("15. ~z → byte 30", function()
  eq(deser("^1^S~z^^"), "\30")
end)

test("16. ~{ → DEL (127)", function()
  eq(deser("^1^S~{^^"), "\127")
end)

test("17. ~| → tilde (126)", function()
  eq(deser("^1^S~|^^"), "~")
end)

test("18. ~} → caret (94)", function()
  eq(deser("^1^S~}^^"), "^")
end)

test("19. Round-trip: string with ALL escapable bytes", function()
  local special = "\0\1\10\29\30\31 ^\127~"
  eq(roundtrip(special), special)
end)

------------------------------------------------------------------------
section("C. Number Serialization")
------------------------------------------------------------------------

test("20. Positive integer → ^N42", function()
  contains(ser(42), "^N42")
end)

test("21. Negative integer → ^N-42", function()
  contains(ser(-42), "^N-42")
end)

test("22. Zero → ^N0", function()
  contains(ser(0), "^N0")
end)

test("23. Large integer", function()
  contains(ser(1000000), "^N1000000")
end)

test("24. Float serialization (tonumber(tostring(v))==v check)", function()
  -- In Lua, 3.14's tostring round-trips, so it uses ^N
  local s = ser(3.14)
  -- The Lua impl uses ^N if tonumber(tostring(v))==v
  -- For 3.14 in Lua: tostring(3.14) = "3.14", tonumber("3.14") == 3.14 → true → ^N
  contains(s, "^N3.14")
end)

test("25. Float needing ^F decomposition", function()
  -- Find a value where tonumber(tostring(v)) ~= v
  -- In Lua 5.3+, most floats round-trip via tostring, but let's check frexp path
  -- 1/3 might not round-trip perfectly
  local v = 1/3
  local s = ser(v)
  -- Should use either ^N or ^F — both are valid
  assert(string.find(s, "^N", 1, true) or string.find(s, "^F", 1, true),
    "Expected ^N or ^F for 1/3")
end)

test("26. Positive infinity → ^N1.#INF", function()
  contains(ser(math.huge), "^N")
  local s = ser(math.huge)
  assert(string.find(s, "1.#INF", 1, true) or string.find(s, "inf", 1, true),
    "Expected infinity representation")
end)

test("27. Negative infinity → ^N-1.#INF", function()
  local s = ser(-math.huge)
  assert(string.find(s, "-1.#INF", 1, true) or string.find(s, "-inf", 1, true),
    "Expected negative infinity representation")
end)

------------------------------------------------------------------------
section("D. Number Deserialization")
------------------------------------------------------------------------

test("28. ^N42 → 42", function()
  eq(deser("^1^N42^^"), 42)
end)

test("29. ^N-42 → -42", function()
  eq(deser("^1^N-42^^"), -42)
end)

test("30. ^N3.14 → 3.14", function()
  eq(deser("^1^N3.14^^"), 3.14)
end)

test("31. ^N1.#INF → Infinity", function()
  eq(deser("^1^N1.#INF^^"), math.huge)
end)

test("32. ^N-1.#INF → -Infinity", function()
  eq(deser("^1^N-1.#INF^^"), -math.huge)
end)

test("33. ^Ninf → Infinity", function()
  eq(deser("^1^Ninf^^"), math.huge)
end)

test("34. ^N-inf → -Infinity", function()
  eq(deser("^1^N-inf^^"), -math.huge)
end)

test("35. ^F<m>^f<e> → correct float", function()
  -- 0.5: frexp(0.5) = 0.5, 0 → m=0.5*2^53=4503599627370496, e=0-53=-53
  eq(deser("^1^F4503599627370496^f-53^^"), 0.5)
end)

------------------------------------------------------------------------
section("E. Float frexp Round-trips")
------------------------------------------------------------------------

local float_cases = {3.14, 0.1, 123.456, -99.99, 1e-10}
for _, v in ipairs(float_cases) do
  test(string.format("36-40. Round-trip %s", tostring(v)), function()
    eq(roundtrip(v), v)
  end)
end

test("41. Round-trip very large float", function()
  eq(roundtrip(1.7976931348623157e+308), 1.7976931348623157e+308)
end)

------------------------------------------------------------------------
section("F. Boolean")
------------------------------------------------------------------------

test("42. true → ^B", function()
  contains(ser(true), "^B")
end)

test("43. false → ^b", function()
  contains(ser(false), "^b")
end)

test("44. ^B → true", function()
  eq(deser("^1^B^^"), true)
end)

test("45. ^b → false", function()
  eq(deser("^1^b^^"), false)
end)

------------------------------------------------------------------------
section("G. Nil")
------------------------------------------------------------------------

test("46. nil → ^Z", function()
  contains(ser(nil), "^Z")
end)

test("47. ^Z → nil", function()
  eq(deser("^1^Z^^"), nil)
end)

------------------------------------------------------------------------
section("H. Table Serialization")
------------------------------------------------------------------------

test("48. Empty table → ^T^t", function()
  local s = ser({})
  contains(s, "^T^t")
end)

test("49. Single key-value pair", function()
  local s = ser({a = 1})
  contains(s, "^T")
  contains(s, "^Sa")
  contains(s, "^N1")
  contains(s, "^t")
end)

test("50. Multiple key-value pairs", function()
  local s = ser({a = 1, b = 2})
  contains(s, "^T")
  contains(s, "^t")
end)

test("51. Nested table", function()
  local s = ser({inner = {x = 1}})
  -- Should have two ^T and two ^t
  local _, count_open = string.gsub(s, "%^T", "")
  local _, count_close = string.gsub(s, "%^t", "")
  eq(count_open, 2, "nested ^T count")
  eq(count_close, 2, "nested ^t count")
end)

test("52. Array with 1-based integer keys", function()
  local s = ser({"a", "b", "c"})
  contains(s, "^N1")
  contains(s, "^Sa")
  contains(s, "^N2")
  contains(s, "^Sb")
  contains(s, "^N3")
  contains(s, "^Sc")
end)

test("53. Mixed table (integer + string keys)", function()
  local t = {[1] = "a", x = "b"}
  local s = ser(t)
  contains(s, "^T")
  contains(s, "^t")
end)

------------------------------------------------------------------------
section("I. Array Detection (Deserialize)")
------------------------------------------------------------------------

-- Note: Lua deserializer returns tables, not arrays.
-- Array detection is a JS/Ruby/Python feature. We just verify tables round-trip.

test("54. Sequential 1-based keys round-trip as table", function()
  local t = {[1] = "a", [2] = "b", [3] = "c"}
  local result = roundtrip(t)
  eq(result[1], "a")
  eq(result[2], "b")
  eq(result[3], "c")
end)

test("55. Non-sequential keys round-trip", function()
  local t = {[1] = "a", [3] = "c"}
  local result = roundtrip(t)
  eq(result[1], "a")
  eq(result[3], "c")
end)

test("56. String keys round-trip", function()
  local t = {x = 1, y = 2}
  local result = roundtrip(t)
  eq(result.x, 1)
  eq(result.y, 2)
end)

test("57. Single element table", function()
  local t = {[1] = "only"}
  local result = roundtrip(t)
  eq(result[1], "only")
end)

test("58. Empty table round-trip", function()
  local result = roundtrip({})
  eq(next(result), nil, "empty table")
end)

------------------------------------------------------------------------
section("J. Framing")
------------------------------------------------------------------------

test("59. Serialize wraps with ^1 and ^^", function()
  local s = ser("hello")
  eq(string.sub(s, 1, 2), "^1", "starts with ^1")
  eq(string.sub(s, -2), "^^", "ends with ^^")
end)

test("60. Deserialize requires ^1 prefix", function()
  local ok, err = AceSerializer:Deserialize("^2^Shello^^")
  eq(ok, false, "should fail without ^1")
end)

test("61. Deserialize requires ^^ terminator", function()
  local ok, err = AceSerializer:Deserialize("^1^Shello")
  eq(ok, false, "should fail without ^^")
end)

test("62. Deserialize strips control chars", function()
  -- Tabs and newlines should be stripped before parsing
  local ok, val = AceSerializer:Deserialize("^1\t\n^Shello\r\n^^")
  eq(ok, true)
  eq(val, "hello")
end)

------------------------------------------------------------------------
section("K. Error Handling")
------------------------------------------------------------------------

test("63. Missing ^1 prefix → error", function()
  local ok, _ = AceSerializer:Deserialize("^Shello^^")
  eq(ok, false)
end)

test("64. Empty string → error", function()
  local ok, _ = AceSerializer:Deserialize("")
  eq(ok, false)
end)

test("65. Missing ^^ terminator → error", function()
  local ok, _ = AceSerializer:Deserialize("^1^Shello")
  eq(ok, false)
end)

------------------------------------------------------------------------
section("L. Round-trips")
------------------------------------------------------------------------

test("66. String with plain ASCII", function()
  eq(roundtrip("hello world test"), "hello world test")
end)

test("67. String with all special chars", function()
  local s = "\0\1\30\31 ^~\127"
  eq(roundtrip(s), s)
end)

test("68. Integer", function()
  eq(roundtrip(12345), 12345)
end)

test("69. Float", function()
  eq(roundtrip(3.14), 3.14)
end)

test("70. Boolean", function()
  eq(roundtrip(true), true)
  eq(roundtrip(false), false)
end)

test("71. Nil", function()
  eq(roundtrip(nil), nil)
end)

test("72. Nested table", function()
  local t = {a = {b = {c = 1}}}
  local r = roundtrip(t)
  eq(r.a.b.c, 1)
end)

test("73. Mixed-type table", function()
  local t = {[1] = "str", [2] = 42, [3] = true, [4] = false}
  local r = roundtrip(t)
  eq(r[1], "str")
  eq(r[2], 42)
  eq(r[3], true)
  eq(r[4], false)
end)

------------------------------------------------------------------------
-- Report wire format values for cross-language reference
------------------------------------------------------------------------
section("WIRE FORMAT REFERENCE (for cross-language fixtures)")

local function wire(label, v)
  print(string.format("  %s → %s", label, ser(v)))
end

wire("3.14", 3.14)
wire("0.1", 0.1)
wire("-99.99", -99.99)
wire("1e-10", 1e-10)
wire("0.5", 0.5)
wire("42", 42)
wire("true", true)
wire("false", false)
wire('""', "")
wire('"hello"', "hello")
wire('"^"', "^")
wire('"~"', "~")
wire("byte30", "\30")
wire("DEL", "\127")
wire("space", " ")
wire("Inf", math.huge)
wire("-Inf", -math.huge)

------------------------------------------------------------------------
print(string.format("\n========================================"))
print(string.format("AceSerializer: %d/%d passed, %d failed", pass, total, fail))
print(string.format("========================================"))
os.exit(fail > 0 and 1 or 0)
