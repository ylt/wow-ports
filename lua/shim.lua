-- Minimal LibStub shim for loading AceSerializer-3.0 outside WoW
local libs = {}
LibStub = {
  NewLibrary = function(self, major, minor)
    if not libs[major] then libs[major] = {} end
    return libs[major], nil
  end,
  GetLibrary = function(self, major, silent)
    return libs[major], nil
  end,
}
