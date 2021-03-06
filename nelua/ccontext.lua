local AnalyzerContext = require 'nelua.analyzercontext'
local class = require 'nelua.utils.class'
local cdefs = require 'nelua.cdefs'
local traits = require 'nelua.utils.traits'
local cbuiltins = require 'nelua.cbuiltins'
local config = require 'nelua.configer'.get()

local CContext = class(AnalyzerContext)

function CContext:init(visitors, typevisitors)
  self:set_visitors(visitors)
  self.typevisitors = typevisitors
  self.declarations = {}
  self.definitions = {}
  self.compileopts = {
    cflags = {},
    ldflags = {},
    linklibs = {}
  }
  self.stringliterals = {}
  self.uniquecounters = {}
  self.builtins = cbuiltins.builtins
end

function CContext.promote_context(self, visitors, typevisitors)
  setmetatable(self, CContext)
  self:init(visitors, typevisitors)
  return self
end

function CContext:declname(attr)
  assert(traits.is_attr(attr))
  if attr.declname then
    return attr.declname
  end
  local declname = attr.codename
  assert(attr.codename)
  if not attr.nodecl then
    if not attr.cimport then
      declname = cdefs.quotename(declname)
    end
    if attr.shadows or (attr.funcdef and not attr.staticstorage) then
      declname = self:genuniquename(declname, '%s__%d')
    end
  end
  attr.declname = declname
  return declname
end

function CContext:genuniquename(kind, fmt)
  local count = self.uniquecounters[kind] or 0
  count = count + 1
  self.uniquecounters[kind] = count
  if not fmt then
    fmt = '__%s%d'
  end
  return string.format(fmt, kind, count)
end

function CContext:typename(type)
  assert(traits.is_type(type))
  local visitor

  -- search visitor for any inherited type class
  local mt = getmetatable(type)
  repeat
    local mtindex = rawget(mt, '__index')
    if not mtindex then break end
    visitor = self.typevisitors[mtindex]
    mt = getmetatable(mtindex)
    if not mt then break end
  until visitor

  if visitor then
    if config.check_ast_shape then
      assert(type:shape())
    end
    visitor(self, type)
  end
  return type.codename
end

function CContext:ctype(type)
  local codename = self:typename(type)
  local ctype = cdefs.primitive_ctypes[type.codename]
  if ctype then
    return ctype
  end
  return codename
end

function CContext:runctype(type)
  local typename = self:typename(type)
  self:ensure_runtime_builtin('nlruntype_', typename)
  return 'nlruntype_' .. typename
end

function CContext:funcretctype(functype)
  if functype:has_multiple_returns() then
    return functype.codename .. '_ret'
  else
    return self:ctype(functype:get_return_type(1))
  end
end

function CContext:add_declaration(code, name)
  if name then
    assert(not self.declarations[name])
    self.declarations[name] = true
  end
  table.insert(self.declarations, code)
end

function CContext:add_definition(code, name)
  if name then
    assert(not self.definitions[name])
    self.definitions[name] = true
  end
  table.insert(self.definitions, code)
end

function CContext:is_declared(name)
  return self.declarations[name] == true
end

function CContext:add_include(name)
  if self.declarations[name] then return end
  self:add_declaration(string.format('#include %s\n', name), name)
end

local function eval_late_templates(templates)
  for i,v in ipairs(templates) do
    if type(v) == 'function' then
      templates[i] = v()
    end
  end
end

function CContext:evaluate_templates()
  eval_late_templates(self.declarations)
  eval_late_templates(self.definitions)
end

return CContext
