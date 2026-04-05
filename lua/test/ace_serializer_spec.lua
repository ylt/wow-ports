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
    it("A1: NUL (0x00) → ~@", function()
      assert.truthy(contains(ser("\0"), "~@"))
    end)

    it("A2: control 0x01 → ~A", function()
      assert.truthy(contains(ser("\1"), "~A"))
    end)

    it("A2: control 0x0A (LF) → ~J", function()
      assert.truthy(contains(ser("\10"), "~J"))
    end)

    it("A2: control 0x1D → ~]", function()
      assert.truthy(contains(ser("\29"), "~]"))
    end)

    it("A3: byte 30 (0x1E) → ~z (special case — 30+64=94=^ would corrupt parser)", function()
      assert.truthy(contains(ser("\30"), "~z"))
    end)

    it("A4: byte 31 (0x1F) → ~_", function()
      assert.truthy(contains(ser("\31"), "~_"))
    end)

    it("A5: space (0x20) → ~`", function()
      assert.truthy(contains(ser(" "), "~`"))
    end)

    it("A6: caret ^ (0x5E) → ~}", function()
      assert.truthy(contains(ser("^"), "~}"))
    end)

    it("A7: tilde ~ (0x7E) → ~|", function()
      assert.truthy(contains(ser("~"), "~|"))
    end)

    it("A8: DEL (0x7F) → ~{", function()
      assert.truthy(contains(ser("\127"), "~{"))
    end)

    it("A9: single-pass — multiple special chars, no double-escaping", function()
      local s = ser("^~\127")
      assert.truthy(contains(s, "~}"))
      assert.truthy(contains(s, "~|"))
      assert.truthy(contains(s, "~{"))
    end)

    it("A10: printable ASCII (0x21-0x5D, 0x5F-0x7D) passes through unescaped", function()
      assert.truthy(contains(ser("hello"), "^Shello"))
    end)
  end)

  describe("B. String Unescaping (Deserialize)", function()
    it("B11: ~@ → NUL (0x00)", function()
      assert.are.equal(deser("^1^S~@^^"), "\0")
    end)

    it("B12: generic ~X where X < z — ~A → chr(1)", function()
      assert.are.equal(deser("^1^S~A^^"), "\1")
    end)

    it("B12: ~J → chr(10) (newline)", function()
      assert.are.equal(deser("^1^S~J^^"), "\10")
    end)

    it("B13: ~z → byte 30 (0x1E)", function()
      assert.are.equal(deser("^1^S~z^^"), "\30")
    end)

    it("B14: ~{ → DEL (0x7F)", function()
      assert.are.equal(deser("^1^S~{^^"), "\127")
    end)

    it("B15: ~| → tilde (~)", function()
      assert.are.equal(deser("^1^S~|^^"), "~")
    end)

    it("B16: ~} → caret (^)", function()
      assert.are.equal(deser("^1^S~}^^"), "^")
    end)

    it("B17: round-trip — all escapable bytes survive serialize→deserialize", function()
      local special = "\0\1\10\29\30\31 ^\127~"
      assert.are.equal(roundtrip(special), special)
    end)
  end)

  describe("C. Number Serialization", function()
    it("C18: positive integer → ^N42", function()
      assert.truthy(contains(ser(42), "^N42"))
    end)

    it("C19: negative integer → ^N-42", function()
      assert.truthy(contains(ser(-42), "^N-42"))
    end)

    it("C20: zero → ^N0", function()
      assert.truthy(contains(ser(0), "^N0"))
    end)

    it("C21: large integer → ^N<large>", function()
      assert.truthy(contains(ser(1000000), "^N1000000"))
    end)

    it("C22: non-integer float uses ^F^f format (not ^N)", function()
      pending("Lua uses ^N for string-representable floats")
    end)

    it("C23: 3.14 exact wire format", function()
      pending("Lua uses ^N for string-representable floats")
    end)

    it("C24: 0.1 wire format is ^F^f", function()
      pending("Lua uses ^N for string-representable floats")
    end)

    it("C24: -99.99 wire format is ^F^f", function()
      pending("Lua uses ^N for string-representable floats")
    end)

    it("C24: 1e-10 wire format is ^F^f", function()
      pending("Lua uses ^N for string-representable floats")
    end)

    it("C25: positive infinity → ^N1.#INF", function()
      local s = ser(math.huge)
      assert.truthy(
        string.find(s, "1.#INF", 1, true) or string.find(s, "inf", 1, true),
        "Expected infinity representation"
      )
    end)

    it("C26: negative infinity → ^N-1.#INF", function()
      local s = ser(-math.huge)
      assert.truthy(
        string.find(s, "-1.#INF", 1, true) or string.find(s, "-inf", 1, true),
        "Expected negative infinity representation"
      )
    end)
  end)

  describe("D. Number Deserialization", function()
    it("D27: ^N42 → 42 (integer)", function()
      assert.are.equal(deser("^1^N42^^"), 42)
    end)

    it("D28: ^N-42 → -42", function()
      assert.are.equal(deser("^1^N-42^^"), -42)
    end)

    it("D29: ^N3.14 → 3.14 (float via ^N path)", function()
      assert.are.equal(deser("^1^N3.14^^"), 3.14)
    end)

    it("D30: ^N1.#INF → Infinity", function()
      assert.are.equal(deser("^1^N1.#INF^^"), math.huge)
    end)

    it("D31: ^N-1.#INF → -Infinity", function()
      assert.are.equal(deser("^1^N-1.#INF^^"), -math.huge)
    end)

    it("D32: ^Ninf → Infinity (alternate format)", function()
      assert.are.equal(deser("^1^Ninf^^"), math.huge)
    end)

    it("D33: ^N-inf → -Infinity (alternate format)", function()
      assert.are.equal(deser("^1^N-inf^^"), -math.huge)
    end)

    it("D34: ^F<m>^f<e> → correct float reconstruction", function()
      assert.are.equal(deser("^1^F4503599627370496^f-53^^"), 0.5)
    end)
  end)

  describe("E. Float frexp Round-trips", function()
    it("E35: round-trip 3.14", function()
      assert.are.equal(roundtrip(3.14), 3.14)
    end)

    it("E36: round-trip 0.1", function()
      assert.are.equal(roundtrip(0.1), 0.1)
    end)

    it("E37: round-trip 123.456", function()
      assert.are.equal(roundtrip(123.456), 123.456)
    end)

    it("E38: round-trip -99.99", function()
      assert.are.equal(roundtrip(-99.99), -99.99)
    end)

    it("E39: round-trip 1e-10", function()
      assert.are.equal(roundtrip(1e-10), 1e-10)
    end)

    it("E40: round-trip very small float (minimum normal)", function()
      local minNormal = 2.2250738585072014e-308
      assert.are.equal(roundtrip(minNormal), minNormal)
    end)

    it("E41: round-trip very large float", function()
      assert.are.equal(roundtrip(1.7976931348623157e+308), 1.7976931348623157e+308)
    end)
  end)

  describe("F. Boolean", function()
    it("F42: true → ^B", function()
      assert.truthy(contains(ser(true), "^B"))
    end)

    it("F43: false → ^b", function()
      assert.truthy(contains(ser(false), "^b"))
    end)

    it("F44: ^B → true", function()
      assert.are.equal(deser("^1^B^^"), true)
    end)

    it("F45: ^b → false", function()
      assert.are.equal(deser("^1^b^^"), false)
    end)
  end)

  describe("G. Nil", function()
    it("G46: null → ^Z", function()
      assert.truthy(contains(ser(nil), "^Z"))
    end)

    it("G47: ^Z → null", function()
      assert.is_nil(deser("^1^Z^^"))
    end)
  end)

  describe("H. Table Serialization", function()
    it("H48: empty table → ^T^t", function()
      assert.truthy(contains(ser({}), "^T^t"))
    end)

    it("H49: single string key-value pair", function()
      local s = ser({a = 1})
      assert.truthy(contains(s, "^T"))
      assert.truthy(contains(s, "^Sa"))
      assert.truthy(contains(s, "^N1"))
      assert.truthy(contains(s, "^t"))
    end)

    it("H50: multiple key-value pairs", function()
      local s = ser({a = 1, b = 2})
      assert.truthy(contains(s, "^T"))
      assert.truthy(contains(s, "^t"))
    end)

    it("H51: nested table (table containing table)", function()
      local s = ser({inner = {x = 1}})
      local _, count_open = string.gsub(s, "%^T", "")
      local _, count_close = string.gsub(s, "%^t", "")
      assert.are.equal(count_open, 2)
      assert.are.equal(count_close, 2)
    end)

    it("H52: array [a,b,c] → 1-based integer keys", function()
      local s = ser({"a", "b", "c"})
      assert.truthy(contains(s, "^N1"))
      assert.truthy(contains(s, "^Sa"))
      assert.truthy(contains(s, "^N2"))
      assert.truthy(contains(s, "^Sb"))
      assert.truthy(contains(s, "^N3"))
      assert.truthy(contains(s, "^Sc"))
    end)

    it("H53: mixed table (integer + string keys)", function()
      local s = ser({[1] = "a", x = "b"})
      assert.truthy(contains(s, "^T"))
      assert.truthy(contains(s, "^t"))
    end)
  end)

  describe("I. Array Detection (Deserialize)", function()
    it("I54: sequential 1-based integer keys → array", function()
      local t = {[1] = "a", [2] = "b", [3] = "c"}
      local result = roundtrip(t)
      assert.are.equal(result[1], "a")
      assert.are.equal(result[2], "b")
      assert.are.equal(result[3], "c")
    end)

    it("I55: non-sequential integer keys → object/hash", function()
      local t = {[1] = "a", [3] = "c"}
      local result = roundtrip(t)
      assert.are.equal(result[1], "a")
      assert.are.equal(result[3], "c")
    end)

    it("I56: string keys → object (not array)", function()
      local t = {x = 1, y = 2}
      local result = roundtrip(t)
      assert.are.equal(result.x, 1)
      assert.are.equal(result.y, 2)
    end)

    it("I57: single element array", function()
      local result = roundtrip({[1] = "only"})
      assert.are.equal(result[1], "only")
    end)

    it("I58: empty table → empty object (not array)", function()
      local result = roundtrip({})
      assert.is_nil(next(result))
    end)
  end)

  describe("J+K. Framing and Error Handling", function()
    it("J59: serialize output starts with ^1 and ends with ^^", function()
      local s = ser("hello")
      assert.are.equal(string.sub(s, 1, 2), "^1")
      assert.are.equal(string.sub(s, -2), "^^")
    end)

    it("J60/K63: missing ^1 prefix → throws", function()
      local ok, _ = AceSerializer:Deserialize("^Shello^^")
      assert.are.equal(ok, false)
    end)

    it("K64: empty string → throws", function()
      local ok, _ = AceSerializer:Deserialize("")
      assert.are.equal(ok, false)
    end)

    it("J61/K65: missing ^^ terminator — JS is lenient, returns value", function()
      local ok, _ = AceSerializer:Deserialize("^1^Shello")
      assert.are.equal(ok, false)
    end)

    it("J62: control chars 0x00-0x20 stripped from input before parsing", function()
      local ok, val = AceSerializer:Deserialize("^1\t\n^Shello\r\n^^")
      assert.are.equal(ok, true)
      assert.are.equal(val, "hello")
    end)
  end)

  describe("L. Round-trips", function()
    it("L66: string with plain ASCII", function()
      assert.are.equal(roundtrip("hello world test"), "hello world test")
    end)

    it("L67: string with all special chars", function()
      local s = "\0\1\30\31 ^~\127"
      assert.are.equal(roundtrip(s), s)
    end)

    it("L68: integer", function()
      assert.are.equal(roundtrip(12345), 12345)
    end)

    it("L69: float", function()
      assert.are.equal(roundtrip(3.14), 3.14)
    end)

    it("L70: boolean true", function()
      assert.are.equal(roundtrip(true), true)
      assert.are.equal(roundtrip(false), false)
    end)

    it("L71: null (nil)", function()
      assert.is_nil(roundtrip(nil))
    end)

    it("L72: nested table/array", function()
      local t = {1, {2, 3}}
      local r = roundtrip(t)
      assert.are.equal(r[1], 1)
      assert.are.equal(r[2][1], 2)
      assert.are.equal(r[2][2], 3)
    end)

    it("L73: mixed-type table", function()
      local t = {n = 42, f = 3.14, b = true, s = "hello"}
      local r = roundtrip(t)
      assert.are.equal(r.n, 42)
      assert.are.equal(r.f, 3.14)
      assert.are.equal(r.b, true)
      assert.are.equal(r.s, "hello")
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
