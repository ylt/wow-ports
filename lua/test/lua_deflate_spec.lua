-- LibDeflate EncodeForPrint/DecodeForPrint test suite — busted spec
-- CWD is lua/ when run via busted.

local LibDeflate = dofile("deps/LibDeflate.lua")

local alphabet = {}
for b = string.byte('a'), string.byte('z') do alphabet[string.char(b)] = true end
for b = string.byte('A'), string.byte('Z') do alphabet[string.char(b)] = true end
for b = string.byte('0'), string.byte('9') do alphabet[string.char(b)] = true end
alphabet['('] = true
alphabet[')'] = true

local function only_alphabet(s)
  for i = 1, #s do
    local c = string.sub(s, i, i)
    if not alphabet[c] then
      error(string.format("char '%s' (byte %d) at pos %d not in alphabet", c, string.byte(c), i), 2)
    end
  end
  return true
end

local function enc(s) return LibDeflate:EncodeForPrint(s) end
local function dec(s) return LibDeflate:DecodeForPrint(s) end

------------------------------------------------------------------------
describe("LibDeflate", function()
------------------------------------------------------------------------

  describe("M. Encode", function()
    it("M74: 3-byte input → 4 chars (full group)", function()
      local r = enc("abc")
      assert.are.equal(#r, 4)
      assert.truthy(only_alphabet(r))
    end)

    it("M75: 1-byte input → 2 chars (tail)", function()
      local r = enc("a")
      assert.are.equal(#r, 2)
      assert.truthy(only_alphabet(r))
    end)

    it("M76: 2-byte input → 3 chars (tail)", function()
      local r = enc("ab")
      assert.are.equal(#r, 3)
      assert.truthy(only_alphabet(r))
    end)

    it("M77: 6-byte input → 8 chars (two full groups)", function()
      local r = enc("abcdef")
      assert.are.equal(#r, 8)
      assert.truthy(only_alphabet(r))
    end)

    it("M78: empty input → empty string", function()
      assert.are.equal(enc(""), "")
    end)

    it("M79: output uses only alphabet chars a-zA-Z0-9()", function()
      local bin = ""
      for i = 0, 255 do bin = bin .. string.char(i) end
      assert.truthy(only_alphabet(enc(bin)))
    end)
  end)

  describe("N. Decode", function()
    it("N80: 4-char input → 3 bytes (full group)", function()
      local encoded = enc("abc")
      assert.are.equal(#encoded, 4)
      assert.are.equal(dec(encoded), "abc")
    end)

    it("N81: 2-char input → 1 byte (tail)", function()
      local encoded = enc("a")
      assert.are.equal(#encoded, 2)
      assert.are.equal(dec(encoded), "a")
    end)

    it("N82: 3-char input → 2 bytes (tail)", function()
      local encoded = enc("ab")
      assert.are.equal(#encoded, 3)
      assert.are.equal(dec(encoded), "ab")
    end)

    it("N83: whitespace stripped from start/end before decode", function()
      local encoded = enc("hello")
      assert.are.equal(dec("  \t" .. encoded .. "\n  "), "hello")
    end)

    it("N84: length-1 input → nil", function()
      assert.is_nil(dec("a"))
    end)

    it("N85: empty string → nil", function()
      -- Lua DecodeForPrint returns "" for empty input (JS returns undefined).
      pending("Lua LibDeflate returns empty string for empty input, not nil")
    end)

    it("N86: invalid character → nil", function()
      assert.is_nil(dec("abc!"))
      assert.is_nil(dec("!@#$"))
    end)
  end)

  describe("O. Round-trips", function()
    it("O87: simple ASCII string", function()
      local s = "Hello, World!"
      assert.are.equal(dec(enc(s)), s)
    end)

    it("O88: binary data — all 256 byte values", function()
      local bin = ""
      for i = 0, 255 do bin = bin .. string.char(i) end
      assert.are.equal(dec(enc(bin)), bin)
    end)

    it("O89: large payload (1000+ bytes)", function()
      local large = string.rep("The quick brown fox jumps over the lazy dog. ", 25)
      assert.are.equal(dec(enc(large)), large)
    end)

    it("O90: single byte", function()
      assert.are.equal(dec(enc("\x42")), "\x42")
    end)

    it("O91: two bytes", function()
      assert.are.equal(dec(enc("\x01\x02")), "\x01\x02")
    end)

    it("O92: three bytes (boundary)", function()
      assert.are.equal(dec(enc("\xAA\xBB\xCC")), "\xAA\xBB\xCC")
    end)

    it("O93: null bytes (0x00) round-trip correctly", function()
      assert.are.equal(dec(enc("\x00\x00\x00")), "\x00\x00\x00")
      assert.are.equal(dec(enc("a\x00b\x00c")), "a\x00b\x00c")
    end)
  end)

  describe("P. Native Variant", function()
    it("P94: encode output is deterministic", function()
      local s = "deterministic test"
      assert.are.equal(enc(s), enc(s))
    end)

    it("P95: decode is inverse of encode", function()
      local s = "inverse test \x00\xFF"
      assert.are.equal(dec(enc(s)), s)
    end)

    it("P96: round-trip preserves all byte values in structured payload", function()
      local payload = ""
      for i = 0, 255 do payload = payload .. string.char(i) end
      payload = payload .. payload
      assert.are.equal(dec(enc(payload)), payload)
    end)
  end)

  describe("WIRE FORMAT REFERENCE", function()
    it("prints cross-language fixtures", function()
      local function wire(label, input)
        print(string.format("  %-30s → %s", label, enc(input)))
      end
      print("\n  -- LibDeflate EncodeForPrint wire format --")
      wire('""', "")
      wire('"a"', "a")
      wire('"ab"', "ab")
      wire('"abc"', "abc")
      wire('"Hello, World!"', "Hello, World!")
      wire("NUL byte (\\x00)", "\x00")
      wire("bytes 0x00-0x02", "\x00\x01\x02")
      wire("bytes 0xFF 0xFE 0xFD", "\xFF\xFE\xFD")
      wire('"hello world"', "hello world")
      assert.truthy(true)
    end)
  end)

end)
