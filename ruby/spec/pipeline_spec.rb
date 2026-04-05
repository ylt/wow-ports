# frozen_string_literal: true

require 'spec_helper'
require_relative '../pipeline'

RSpec.describe 'Pipeline' do
  # ── Prefix encoding ────────────────────────────────────────────────────────

  describe 'prefix encoding' do
    it 'WA v1 uses ! prefix' do
      enc = Pipeline.encode(ExportResult.new('weakauras', 1, 'x', nil))
      expect(enc).to start_with('!')
      expect(enc).not_to start_with('!WA:2!')
      expect(enc).not_to start_with('!E1!')
    end

    it 'ElvUI uses !E1! prefix' do
      enc = Pipeline.encode(ExportResult.new('elvui', 1, 'x', nil))
      expect(enc).to start_with('!E1!')
    end

    it 'legacy (v0) uses no prefix' do
      enc = Pipeline.encode(ExportResult.new('weakauras', 0, 'x', nil))
      expect(enc).not_to start_with('!')
    end

    it 'WA v2 uses !WA:2! prefix' do
      enc = Pipeline.encode(ExportResult.new('weakauras', 2, { 'a' => 1 }, nil))
      expect(enc).to start_with('!WA:2!')
    end
  end

  # ── Prefix detection (via decode) ─────────────────────────────────────────

  describe 'decode prefix detection' do
    it '!E1! → elvui v1' do
      enc = Pipeline.encode(ExportResult.new('elvui', 1, { 'a' => 1 }, nil))
      dec = Pipeline.decode(enc)
      expect(dec.addon).to eq('elvui')
      expect(dec.version).to eq(1)
    end

    it '! → weakauras v1' do
      enc = Pipeline.encode(ExportResult.new('weakauras', 1, { 'a' => 1 }, nil))
      dec = Pipeline.decode(enc)
      expect(dec.addon).to eq('weakauras')
      expect(dec.version).to eq(1)
    end

    it 'no prefix → weakauras v0 (legacy)' do
      enc = Pipeline.encode(ExportResult.new('weakauras', 0, { 'a' => 1 }, nil))
      dec = Pipeline.decode(enc)
      expect(dec.addon).to eq('weakauras')
      expect(dec.version).to eq(0)
    end

    it '!WA:2! → weakauras v2' do
      enc = Pipeline.encode(ExportResult.new('weakauras', 2, { 'a' => 1 }, nil))
      dec = Pipeline.decode(enc)
      expect(dec.addon).to eq('weakauras')
      expect(dec.version).to eq(2)
    end
  end

  # ── ExportResult wrapper shape ─────────────────────────────────────────────

  describe 'ExportResult structure' do
    it 'decode returns all four fields' do
      enc = Pipeline.encode(ExportResult.new('weakauras', 1, { 'x' => 1 }, nil))
      dec = Pipeline.decode(enc)
      expect(dec).to respond_to(:addon)
      expect(dec).to respond_to(:version)
      expect(dec).to respond_to(:data)
      expect(dec).to respond_to(:metadata)
    end
  end

  # ── Encode→decode round-trips ──────────────────────────────────────────────

  describe 'encode→decode round-trip' do
    it 'WA v1 — string' do
      orig = ExportResult.new('weakauras', 1, 'hello', nil)
      dec  = Pipeline.decode(Pipeline.encode(orig))
      expect(dec.data).to eq('hello')
      expect(dec.addon).to eq('weakauras')
      expect(dec.version).to eq(1)
      expect(dec.metadata).to be_nil
    end

    it 'WA v1 — hash' do
      data = { 'key' => 'value', 'num' => 42 }
      dec  = Pipeline.decode(Pipeline.encode(ExportResult.new('weakauras', 1, data, nil)))
      expect(dec.data['key']).to eq('value')
      expect(dec.data['num']).to eq(42)
    end

    it 'WA v1 — array' do
      data = ['a', 'b', 'c']
      dec  = Pipeline.decode(Pipeline.encode(ExportResult.new('weakauras', 1, data, nil)))
      expect(dec.data).to eq(data)
    end

    it 'WA v1 — nested hash' do
      data = { 'outer' => { 'inner' => 99 }, 'list' => [1, 2] }
      dec  = Pipeline.decode(Pipeline.encode(ExportResult.new('weakauras', 1, data, nil)))
      expect(dec.data['outer']['inner']).to eq(99)
      expect(dec.data['list']).to eq([1, 2])
    end

    it 'legacy v0 — round-trip' do
      data = { 'flag' => true, 'n' => -5 }
      dec  = Pipeline.decode(Pipeline.encode(ExportResult.new('weakauras', 0, data, nil)))
      expect(dec.data['flag']).to eq(true)
      expect(dec.data['n']).to eq(-5)
    end

    it 'WA v2 — round-trip' do
      data = { 'key' => 'v2data', 'num' => 7 }
      dec  = Pipeline.decode(Pipeline.encode(ExportResult.new('weakauras', 2, data, nil)))
      expect(dec.data['key']).to eq('v2data')
      expect(dec.data['num']).to eq(7)
    end
  end

  # ── ElvUI metadata ─────────────────────────────────────────────────────────

  describe 'ElvUI metadata' do
    it 'round-trip preserves profileType and profileKey' do
      metadata = { profile_type: 'profile', profile_key: 'Default' }
      orig = ExportResult.new('elvui', 1, { 'setting' => 1 }, metadata)
      dec  = Pipeline.decode(Pipeline.encode(orig))
      expect(dec.addon).to eq('elvui')
      expect(dec.metadata[:profile_type]).to eq('profile')
      expect(dec.metadata[:profile_key]).to eq('Default')
      expect(dec.data['setting']).to eq(1)
    end

    it 'ElvUI without metadata → nil metadata after decode' do
      orig = ExportResult.new('elvui', 1, { 'a' => 1 }, nil)
      dec  = Pipeline.decode(Pipeline.encode(orig))
      expect(dec.metadata).to be_nil
    end
  end
end
