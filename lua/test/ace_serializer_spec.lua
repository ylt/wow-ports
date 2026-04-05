-- AceSerializer-3.0 test suite — busted spec
-- Runs against the real Lua implementation. CWD is lua/ when run via busted.

dofile("shim.lua")
dofile("deps/AceSerializer-3.0.lua")

local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")

local function ser(v)
  return AceSerializer:Serialize(v)
end

local function deser(s)
  local ok, val = AceSerializer:Deserialize(s)
  assert(ok, "Deserialize failed: " .. tostring(val))
  return val
end

local function roundtrip(v)
  return deser(ser(v))
end

local function contains(str, sub)
  return string.find(str, sub, 1, true) ~= nil
end

------------------------------------------------------------------------
describe("AceSerializer", function()
------------------------------------------------------------------------

  describe("A. String Escaping (Serialize)", function()
    it("1. NUL (0x00) → ~@", function()
      assert.truthy(contains(ser("\0"), "~@"))
    end)

    it("2. Control char 0x01 → ~A", function()
      assert.truthy(contains(ser("\1"), "~A"))
    end)

    it("3. Control char 0x0A (newline) → ~J", function()
      assert.truthy(contains(ser("\10"), "~J"))
    end)

    it("4. Control char 0x1D → ~]", function()
      assert.truthy(contains(ser("\29"), "~]"))
    end)

    it("5. Byte 30 (0x1E) → ~z (special case)", function()
      assert.truthy(contains(ser("\30"), "~z"))
    end)

    it("6. Byte 31 (0x1F) → ~_", function()
      assert.truthy(contains(ser("\31"), "~_"))
    end)

    it("7. Space (0x20) → ~`", function()
      assert.truthy(contains(ser(" "), "~`"))
    end)

    it("8. Caret ^ (0x5E) → ~}", function()
      assert.truthy(contains(ser("^"), "~}"))
    end)

    it("9. Tilde ~ (0x7E) → ~|", function()
      assert.truthy(contains(ser("~"), "~|"))
    end)

    it("10. DEL (0x7F) → ~{", function()
      assert.truthy(contains(ser("\127"), "~{"))
    end)

    it("11. Single-pass: no double-escaping", function()
      local s = ser("^~\127")
      assert.truthy(contains(s, "~}"))
      assert.truthy(contains(s, "~|"))
      assert.truthy(contains(s, "~{"))
    end)

    it("12. Printable ASCII passes through unescaped", function()
      assert.truthy(contains(ser("hello"), "^Shello"))
    end)
  end)

  describe("B. String Unescaping (Deserialize)", function()
    it("13. ~@ → NUL", function()
      assert.are.equal(deser("^1^S~@^^"), "\0")
    end)

    it("14. Generic ~X where X < z → chr(ord(X)-64)", function()
      assert.are.equal(deser("^1^S~A^^"), "\1")
      assert.are.equal(deser("^1^S~J^^"), "\10")
    end)

    it("15. ~z → byte 30", function()
      assert.are.equal(deser("^1^S~z^^"), "\30")
    end)

    it("16. ~{ → DEL (127)", function()
      assert.are.equal(deser("^1^S~{^^"), "\127")
    end)

    it("17. ~| → tilde (126)", function()
      assert.are.equal(deser("^1^S~|^^"), "~")
    end)

    it("18. ~} → caret (94)", function()
      assert.are.equal(deser("^1^S~}^^"), "^")
    end)

    it("19. Round-trip: string with ALL escapable bytes", function()
      local special = "\0\1\10\29\30\31 ^\127~"
      assert.are.equal(roundtrip(special), special)
    end)
  end)

  describe("C. Number Serialization", function()
    it("20. Positive integer → ^N42", function()
      assert.truthy(contains(ser(42), "^N42"))
    end)

    it("21. Negative integer → ^N-42", function()
      assert.truthy(contains(ser(-42), "^N-42"))
    end)

    it("22. Zero → ^N0", function()
      assert.truthy(contains(ser(0), "^N0"))
    end)

    it("23. Large integer", function()
      assert.truthy(contains(ser(1000000), "^N1000000"))
    end)

    it("24. Float 3.14 → ^N3.14", function()
      assert.truthy(contains(ser(3.14), "^N3.14"))
    end)

    it("25. Float needing ^F or ^N decomposition", function()
      local v = 1/3
      local s = ser(v)
      assert.truthy(
        string.find(s, "^N", 1, true) or string.find(s, "^F", 1, true),
        "Expected ^N or ^F for 1/3"
      )
    end)

    it("26. Positive infinity", function()
      local s = ser(math.huge)
      assert.truthy(
        string.find(s, "1.#INF", 1, true) or string.find(s, "inf", 1, true),
        "Expected infinity representation"
      )
    end)

    it("27. Negative infinity", function()
      local s = ser(-math.huge)
      assert.truthy(
        string.find(s, "-1.#INF", 1, true) or string.find(s, "-inf", 1, true),
        "Expected negative infinity representation"
      )
    end)
  end)

  describe("D. Number Deserialization", function()
    it("28. ^N42 → 42", function()
      assert.are.equal(deser("^1^N42^^"), 42)
    end)

    it("29. ^N-42 → -42", function()
      assert.are.equal(deser("^1^N-42^^"), -42)
    end)

    it("30. ^N3.14 → 3.14", function()
      assert.are.equal(deser("^1^N3.14^^"), 3.14)
    end)

    it("31. ^N1.#INF → Infinity", function()
      assert.are.equal(deser("^1^N1.#INF^^"), math.huge)
    end)

    it("32. ^N-1.#INF → -Infinity", function()
      assert.are.equal(deser("^1^N-1.#INF^^"), -math.huge)
    end)

    it("33. ^Ninf → Infinity", function()
      assert.are.equal(deser("^1^Ninf^^"), math.huge)
    end)

    it("34. ^N-inf → -Infinity", function()
      assert.are.equal(deser("^1^N-inf^^"), -math.huge)
    end)

    it("35. ^F<m>^f<e> → correct float", function()
      assert.are.equal(deser("^1^F4503599627370496^f-53^^"), 0.5)
    end)
  end)

  describe("E. Float frexp Round-trips", function()
    local float_cases = {3.14, 0.1, 123.456, -99.99, 1e-10}
    for _, v in ipairs(float_cases) do
      it(string.format("36-40. Round-trip %s", tostring(v)), function()
        assert.are.equal(roundtrip(v), v)
      end)
    end

    it("41. Round-trip very large float", function()
      assert.are.equal(roundtrip(1.7976931348623157e+308), 1.7976931348623157e+308)
    end)
  end)

  describe("F. Boolean", function()
    it("42. true → ^B", function()
      assert.truthy(contains(ser(true), "^B"))
    end)

    it("43. false → ^b", function()
      assert.truthy(contains(ser(false), "^b"))
    end)

    it("44. ^B → true", function()
      assert.are.equal(deser("^1^B^^"), true)
    end)

    it("45. ^b → false", function()
      assert.are.equal(deser("^1^b^^"), false)
    end)
  end)

  describe("G. Nil", function()
    it("46. nil → ^Z", function()
      assert.truthy(contains(ser(nil), "^Z"))
    end)

    it("47. ^Z → nil", function()
      assert.is_nil(deser("^1^Z^^"))
    end)
  end)

  describe("H. Table Serialization", function()
    it("48. Empty table → ^T^t", function()
      assert.truthy(contains(ser({}), "^T^t"))
    end)

    it("49. Single key-value pair", function()
      local s = ser({a = 1})
      assert.truthy(contains(s, "^T"))
      assert.truthy(contains(s, "^Sa"))
      assert.truthy(contains(s, "^N1"))
      assert.truthy(contains(s, "^t"))
    end)

    it("50. Multiple key-value pairs", function()
      local s = ser({a = 1, b = 2})
      assert.truthy(contains(s, "^T"))
      assert.truthy(contains(s, "^t"))
    end)

    it("51. Nested table", function()
      local s = ser({inner = {x = 1}})
      local _, count_open = string.gsub(s, "%^T", "")
      local _, count_close = string.gsub(s, "%^t", "")
      assert.are.equal(count_open, 2)
      assert.are.equal(count_close, 2)
    end)

    it("52. Array with 1-based integer keys", function()
      local s = ser({"a", "b", "c"})
      assert.truthy(contains(s, "^N1"))
      assert.truthy(contains(s, "^Sa"))
      assert.truthy(contains(s, "^N2"))
      assert.truthy(contains(s, "^Sb"))
      assert.truthy(contains(s, "^N3"))
      assert.truthy(contains(s, "^Sc"))
    end)

    it("53. Mixed table (integer + string keys)", function()
      local s = ser({[1] = "a", x = "b"})
      assert.truthy(contains(s, "^T"))
      assert.truthy(contains(s, "^t"))
    end)
  end)

  describe("I. Array Detection (Deserialize)", function()
    it("54. Sequential 1-based keys round-trip as table", function()
      local t = {[1] = "a", [2] = "b", [3] = "c"}
      local result = roundtrip(t)
      assert.are.equal(result[1], "a")
      assert.are.equal(result[2], "b")
      assert.are.equal(result[3], "c")
    end)

    it("55. Non-sequential keys round-trip", function()
      local t = {[1] = "a", [3] = "c"}
      local result = roundtrip(t)
      assert.are.equal(result[1], "a")
      assert.are.equal(result[3], "c")
    end)

    it("56. String keys round-trip", function()
      local t = {x = 1, y = 2}
      local result = roundtrip(t)
      assert.are.equal(result.x, 1)
      assert.are.equal(result.y, 2)
    end)

    it("57. Single element table", function()
      local result = roundtrip({[1] = "only"})
      assert.are.equal(result[1], "only")
    end)

    it("58. Empty table round-trip", function()
      local result = roundtrip({})
      assert.is_nil(next(result))
    end)
  end)

  describe("J. Framing", function()
    it("59. Serialize wraps with ^1 and ^^", function()
      local s = ser("hello")
      assert.are.equal(string.sub(s, 1, 2), "^1")
      assert.are.equal(string.sub(s, -2), "^^")
    end)

    it("60. Deserialize requires ^1 prefix", function()
      local ok, _ = AceSerializer:Deserialize("^2^Shello^^")
      assert.are.equal(ok, false)
    end)

    it("61. Deserialize requires ^^ terminator", function()
      local ok, _ = AceSerializer:Deserialize("^1^Shello")
      assert.are.equal(ok, false)
    end)

    it("62. Deserialize strips control chars", function()
      local ok, val = AceSerializer:Deserialize("^1\t\n^Shello\r\n^^")
      assert.are.equal(ok, true)
      assert.are.equal(val, "hello")
    end)
  end)

  describe("K. Error Handling", function()
    it("63. Missing ^1 prefix → error", function()
      local ok, _ = AceSerializer:Deserialize("^Shello^^")
      assert.are.equal(ok, false)
    end)

    it("64. Empty string → error", function()
      local ok, _ = AceSerializer:Deserialize("")
      assert.are.equal(ok, false)
    end)

    it("65. Missing ^^ terminator → error", function()
      local ok, _ = AceSerializer:Deserialize("^1^Shello")
      assert.are.equal(ok, false)
    end)
  end)

  describe("L. Round-trips", function()
    it("66. String with plain ASCII", function()
      assert.are.equal(roundtrip("hello world test"), "hello world test")
    end)

    it("67. String with all special chars", function()
      local s = "\0\1\30\31 ^~\127"
      assert.are.equal(roundtrip(s), s)
    end)

    it("68. Integer", function()
      assert.are.equal(roundtrip(12345), 12345)
    end)

    it("69. Float", function()
      assert.are.equal(roundtrip(3.14), 3.14)
    end)

    it("70. Boolean", function()
      assert.are.equal(roundtrip(true), true)
      assert.are.equal(roundtrip(false), false)
    end)

    it("71. Nil", function()
      assert.is_nil(roundtrip(nil))
    end)

    it("72. Nested table", function()
      local t = {a = {b = {c = 1}}}
      local r = roundtrip(t)
      assert.are.equal(r.a.b.c, 1)
    end)

    it("73. Mixed-type table", function()
      local t = {[1] = "str", [2] = 42, [3] = true, [4] = false}
      local r = roundtrip(t)
      assert.are.equal(r[1], "str")
      assert.are.equal(r[2], 42)
      assert.are.equal(r[3], true)
      assert.are.equal(r[4], false)
    end)
  end)

  describe("WIRE FORMAT REFERENCE", function()
    it("prints cross-language fixtures", function()
      local function wire(label, v)
        print(string.format("  %-12s → %s", label, ser(v)))
      end
      print("\n  -- AceSerializer wire format --")
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
      assert.truthy(true) -- wire format printing always passes
    end)
  end)

end)
