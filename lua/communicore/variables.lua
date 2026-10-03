---File variable substitution ({{name}}), per https://http-files.org/spec/variables/.
---Pure Lua: no Neovim API dependencies.

local M = {}

local MAX_DEPTH = 10

---@param str string
---@return string
local function trim(str)
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param str string
---@param vars table<string, string>
---@param depth number
---@return string
local function expand(str, vars, depth)
  if depth > MAX_DEPTH then
    return str
  end
  local expanded = false
  local out = str:gsub("{{(.-)}}", function(name)
    local value = vars[trim(name)]
    if value == nil then
      return nil -- leave unknown variables untouched
    end
    expanded = true
    return value
  end)
  -- Values may themselves reference other variables; keep expanding.
  if expanded and out:find("{{", 1, true) then
    return expand(out, vars, depth + 1)
  end
  return out
end

---Substitutes {{name}} placeholders in `str` using `vars`.
---Unknown variables are left as-is. Cyclic references terminate unresolved.
---@param str string|nil
---@param vars table<string, string>
---@return string|nil
function M.substitute(str, vars)
  if type(str) ~= "string" then
    return str
  end
  return expand(str, vars, 1)
end

---Returns a copy of the request with all {{variables}} resolved against
---the request's own variable scope. The original request is not modified.
---@param req communicore.Request
---@return communicore.Request
function M.substitute_request(req)
  local vars = req.variables or {}
  local resolved = {
    method = req.method,
    url = M.substitute(req.url, vars),
    http_version = req.http_version,
    headers = {},
    name = req.name,
    line = req.line,
    end_line = req.end_line,
    variables = vars,
  }
  for i, h in ipairs(req.headers or {}) do
    resolved.headers[i] = { name = h.name, value = M.substitute(h.value, vars) }
  end
  resolved.body = M.substitute(req.body, vars)
  return resolved
end

return M
