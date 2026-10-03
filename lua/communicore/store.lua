---In-session store of named request/response pairs, keyed by the
---request's @name. Pure Lua.

local M = {
  _named = {},
}

---@param name string
---@param entry { request: communicore.Request, response: communicore.Response }
function M.save(name, entry)
  M._named[name] = entry
end

---@param name string
---@return { request: communicore.Request, response: communicore.Response }|nil
function M.get(name)
  return M._named[name]
end

function M.clear()
  M._named = {}
end

return M
