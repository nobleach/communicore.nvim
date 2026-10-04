---Pure-Lua JSON pretty printer.
---Re-indents the raw text instead of decoding and re-encoding, so key
---order, string contents and number lexemes are preserved exactly.

local json = require("communicore.json")

local M = {}

---@param text string
---@param indent string|nil indent unit, defaults to two spaces
---@return string|nil formatted, string|nil err
function M.json(text, indent)
  indent = indent or "  "

  -- Validate first: fall back to the raw text on invalid JSON.
  local _, err = json.decode(text)
  if err then
    return nil, err
  end

  local out = {}
  local depth = 0
  local in_string = false
  local escaped = false

  local function newline()
    table.insert(out, "\n" .. indent:rep(depth))
  end

  local i = 1
  local len = #text
  while i <= len do
    local c = text:sub(i, i)
    if in_string then
      table.insert(out, c)
      if escaped then
        escaped = false
      elseif c == "\\" then
        escaped = true
      elseif c == '"' then
        in_string = false
      end
    elseif c == '"' then
      in_string = true
      table.insert(out, c)
    elseif c == "{" or c == "[" then
      local close = c == "{" and "}" or "]"
      -- Keep empty containers on one line: {} and []
      local j = i + 1
      while text:sub(j, j):match("%s") do
        j = j + 1
      end
      if text:sub(j, j) == close then
        table.insert(out, c .. close)
        i = j
      else
        depth = depth + 1
        table.insert(out, c)
        newline()
      end
    elseif c == "}" or c == "]" then
      depth = depth - 1
      newline()
      table.insert(out, c)
    elseif c == "," then
      table.insert(out, c)
      newline()
    elseif c == ":" then
      table.insert(out, ": ")
    elseif not c:match("%s") then
      table.insert(out, c)
    end
    i = i + 1
  end

  return table.concat(out)
end

return M
