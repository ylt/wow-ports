# frozen_string_literal: true

require 'benchmark'
require_relative 'lua_deflate'
require_relative 'lua_deflate_native'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def random_printable(size)
  Array.new(size) { rand(32..126).chr }.join
end

SIZES = {
  '32 B'   =>   32,
  '1 KB'   => 1_024,
  '64 KB'  => 65_536,
  '256 KB' => 262_144
}.freeze

# ---------------------------------------------------------------------------
# Correctness
# ---------------------------------------------------------------------------

puts "=== Correctness ==="
puts

SIZES.each do |label, size|
  data = random_printable(size)

  enc_ref    = LuaDeflate.encode_for_print(data)
  enc_native = LuaDeflateNative.encode_for_print(data)

  enc_match = enc_ref == enc_native

  dec_ref_from_ref       = LuaDeflate.decode_for_print(enc_ref)
  dec_native_from_native = LuaDeflateNative.decode_for_print(enc_native)
  dec_ref_from_native    = LuaDeflate.decode_for_print(enc_native)
  dec_native_from_ref    = LuaDeflateNative.decode_for_print(enc_ref)

  roundtrip_ref    = dec_ref_from_ref    == data
  roundtrip_native = dec_native_from_native == data
  cross_ref        = dec_ref_from_native == data
  cross_native     = dec_native_from_ref == data

  all_pass = enc_match && roundtrip_ref && roundtrip_native && cross_ref && cross_native
  status   = all_pass ? 'PASS' : 'FAIL'

  puts "#{label.rjust(7)}: #{status}"
  unless all_pass
    puts "  enc match:      #{enc_match}"
    puts "  roundtrip ref:  #{roundtrip_ref}"
    puts "  roundtrip nat:  #{roundtrip_native}"
    puts "  cross ref:      #{cross_ref}"
    puts "  cross native:   #{cross_native}"
  end
end

puts

# ---------------------------------------------------------------------------
# Benchmark
# ---------------------------------------------------------------------------

# Pick iteration counts so each cell takes ~0.5–2 s on typical hardware.
ITER_MAP = {
  '32 B'   => 20_000,
  '1 KB'   =>  2_000,
  '64 KB'  =>    50,
  '256 KB' =>    12
}.freeze

puts "=== Benchmark (encode + decode round-trip) ==="
puts

col_w = 8
printf "%-9s %#{col_w}s %#{col_w}s %#{col_w}s %#{col_w}s %#{col_w}s\n",
       'Size', 'Iters', 'Ref(ops/s)', 'Nat(ops/s)', 'Speedup', ''
puts '-' * 60

SIZES.each do |label, size|
  data   = random_printable(size)
  iters  = ITER_MAP[label]

  # Warm up
  3.times do
    LuaDeflate.encode_for_print(data)
    LuaDeflateNative.encode_for_print(data)
  end

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  iters.times do
    enc = LuaDeflate.encode_for_print(data)
    LuaDeflate.decode_for_print(enc)
  end
  ref_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  iters.times do
    enc = LuaDeflateNative.encode_for_print(data)
    LuaDeflateNative.decode_for_print(enc)
  end
  nat_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

  ref_ops = iters / ref_elapsed
  nat_ops = iters / nat_elapsed
  speedup = nat_ops / ref_ops

  flag = speedup >= 1.0 ? 'faster' : 'slower'
  printf "%-9s %#{col_w}d %#{col_w}.0f %#{col_w}.0f %#{col_w}.2fx %s\n",
         label, iters, ref_ops, nat_ops, speedup, flag
end

puts
