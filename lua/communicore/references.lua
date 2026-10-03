---Named request references (response chaining), per
---https://http-files.org/spec/variables/ (VS Code REST Client syntax):
---
---  {{name.response.body.$.json.path}}  -- jq-style path into a JSON body
---  {{name.response.body.path}}         -- bare jq-style path (no leading $)
---  {{name.response.body.*}}            -- entire raw body
---  {{name.response.headers.Header}}    -- response header (case-insensitive)
---  {{name.request.body.*}}             -- original request body
---  {{name.request.headers.Header}}     -- original request header
---
---Array indices in paths are 0-based (jq/JSONPath convention). Pure Lua.

local json = require("communicore.json")
local default_store = require("communicore.store")

local M = {}

---Parses a jq/JSONPath-style path into segments.
---Accepts "$.a.b[0].c", ".a.b[0]" and "a.b[0]".
---@param path string
---@return (string|number)[]|nil
local function parse_path(path)
  path = path:gsub("^%$", ""):gsub("^%.", "")
  if path == "" then
    return nil
  end
  local segments = {}
  local i = 1
  while i <= #path do
    local c = path:sub(i, i)
    if c == "." then
      i = i + 1
    elseif c == "[" then
      local j = path:find("]", i + 1, true)
      if not j then
        return nil
      end
      local index = tonumber(path:sub(i + 1, j - 1))
      if not index then
        return nil
      end
      table.insert(segments, index)
      i = j + 1
    else
      local j = path:find("[%.%[]", i) or (#path + 1)
      table.insert(segments, path:sub(i, j - 1))
      i = j
    end
  end
  return segments
end

---Evaluates parsed path segments against a decoded JSON value.
---Array indices are 0-based.
---@param value any
---@param segments (string|number)[]
---@return any|nil
local function eval_path(value, segments)
  for _, seg in ipairs(segments) do
    if type(value) ~= "table" then
      return nil
    end
    if type(seg) == "number" then
      value = value[seg + 1] -- jq/JSONPath are 0-based
    else
      value = value[seg]
    end
    if value == nil then
      return nil
    end
  end
  return value
end

---@param headers {name: string, value: string}[]|nil
---@param name string
---@return string|nil
local function find_header(headers, name)
  name = name:lower()
  for _, h in ipairs(headers or {}) do
    if h.name:lower() == name then
      return h.value
    end
  end
end

---@param body string|nil
---@param path string
---@return string|nil
local function resolve_body_path(body, path)
  if path == "*" then
    return body
  end
  local decoded = json.decode(body or "")
  if decoded == nil then
    return nil
  end
  local segments = parse_path(path)
  if not segments then
    return nil
  end
  local value = eval_path(decoded, segments)
  if type(value) == "table" then
    return nil -- objects/arrays have no string form (no encoder yet)
  end
  if value == nil then
    return nil
  end
  return tostring(value)
end

---Resolves one reference (the text inside {{...}}) to a string value.
---Returns nil when the reference cannot be resolved.
---@param ref string e.g. "login.response.body.$.token"
---@param store table|nil communicore.store-like table (defaults to the session store)
---@return string|nil
function M.resolve(ref, store)
  store = store or default_store
  local name, kind, rest = ref:match("^(.-)%.(response)%.(.+)$")
  if not name then
    name, kind, rest = ref:match("^(.-)%.(request)%.(.+)$")
  end
  if not name then
    return nil
  end

  local entry = store.get(name)
  if not entry then
    return nil
  end
  local target = entry[kind]
  if not target then
    return nil
  end

  if rest:sub(1, 5) == "body." then
    return resolve_body_path(target.body, rest:sub(6))
  elseif rest:sub(1, 8) == "headers." then
    return find_header(target.headers, rest:sub(9))
  end
  return nil
end

---@param text string|nil
---@param found table<string, boolean>
local function scan(text, found)
  if type(text) ~= "string" then
    return
  end
  for inner in text:gmatch("{{(.-)}}") do
    local ref = inner:gsub("^%s+", ""):gsub("%s+$", "")
    if ref:match("^.-%.response%.") or ref:match("^.-%.request%.") then
      found[ref] = true
    end
  end
end

---Collects all request references used by a request (url, headers, body).
---@param req communicore.Request
---@return table<string, boolean> set of reference texts
function M.collect(req)
  local found = {}
  scan(req.url, found)
  for _, h in ipairs(req.headers or {}) do
    scan(h.value, found)
  end
  scan(req.body, found)
  return found
end

return M
