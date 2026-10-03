---Minimal pure-Lua JSON decoder (decode only).
---Returns `nil, err` instead of raising on invalid input.

local M = {}

---@param cp number codepoint
---@return string
local function utf8_encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(
    0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40,
    0x80 + cp % 0x40
  )
end

---@param str string
---@return any|nil value, string|nil err
function M.decode(str)
  if type(str) ~= "string" then
    return nil, "expected string input"
  end

  local pos = 1
  local len = #str

  local function fail(msg)
    error(("json decode error at byte %d: %s"):format(pos, msg), 0)
  end

  local function skip_ws()
    local _, e = str:find("^[ \t\n\r]+", pos)
    if e then
      pos = e + 1
    end
  end

  local parse_value -- forward declaration

  local ESCAPES = {
    ['"'] = '"',
    ["\\"] = "\\",
    ["/"] = "/",
    b = "\b",
    f = "\f",
    n = "\n",
    r = "\r",
    t = "\t",
  }

  local function parse_string()
    pos = pos + 1 -- consume opening quote
    local parts = {}
    local start = pos
    while pos <= len do
      local c = str:sub(pos, pos)
      if c == '"' then
        table.insert(parts, str:sub(start, pos - 1))
        pos = pos + 1
        return table.concat(parts)
      elseif c == "\\" then
        table.insert(parts, str:sub(start, pos - 1))
        pos = pos + 1
        local e = str:sub(pos, pos)
        if e == "u" then
          local hex = str:sub(pos + 1, pos + 4)
          local cp = tonumber(hex, 16)
          if not cp or #hex ~= 4 then
            fail("invalid \\u escape")
          end
          pos = pos + 5
          if cp >= 0xD800 and cp <= 0xDBFF and str:sub(pos, pos + 1) == "\\u" then
            local lo = tonumber(str:sub(pos + 2, pos + 5), 16)
            if lo and lo >= 0xDC00 and lo <= 0xDFFF then
              cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
              pos = pos + 6
            end
          end
          table.insert(parts, utf8_encode(cp))
        else
          local rep = ESCAPES[e]
          if not rep then
            fail("invalid escape \\" .. e)
          end
          table.insert(parts, rep)
          pos = pos + 1
        end
        start = pos
      else
        pos = pos + 1
      end
    end
    fail("unterminated string")
  end

  local function parse_number()
    local num = str:match("^%-?%d+%.?%d*[eE]?[+%-]?%d*", pos)
    local value = tonumber(num)
    if value == nil then
      fail("invalid number")
    end
    pos = pos + #num
    return value
  end

  local function parse_literal(literal, value)
    if str:sub(pos, pos + #literal - 1) ~= literal then
      fail("invalid literal")
    end
    pos = pos + #literal
    return value
  end

  local function parse_array()
    local arr = {}
    pos = pos + 1 -- consume '['
    skip_ws()
    if str:sub(pos, pos) == "]" then
      pos = pos + 1
      return arr
    end
    while true do
      table.insert(arr, parse_value())
      skip_ws()
      local c = str:sub(pos, pos)
      if c == "," then
        pos = pos + 1
      elseif c == "]" then
        pos = pos + 1
        return arr
      else
        fail("expected ',' or ']'")
      end
    end
  end

  local function parse_object()
    local obj = {}
    pos = pos + 1 -- consume '{'
    skip_ws()
    if str:sub(pos, pos) == "}" then
      pos = pos + 1
      return obj
    end
    while true do
      skip_ws()
      if str:sub(pos, pos) ~= '"' then
        fail("expected object key")
      end
      local key = parse_string()
      skip_ws()
      if str:sub(pos, pos) ~= ":" then
        fail("expected ':'")
      end
      pos = pos + 1
      obj[key] = parse_value()
      skip_ws()
      local c = str:sub(pos, pos)
      if c == "," then
        pos = pos + 1
      elseif c == "}" then
        pos = pos + 1
        return obj
      else
        fail("expected ',' or '}'")
      end
    end
  end

  parse_value = function()
    skip_ws()
    local c = str:sub(pos, pos)
    if c == "{" then
      return parse_object()
    elseif c == "[" then
      return parse_array()
    elseif c == '"' then
      return parse_string()
    elseif c == "t" then
      return parse_literal("true", true)
    elseif c == "f" then
      return parse_literal("false", false)
    elseif c == "n" then
      return parse_literal("null", nil)
    end
    return parse_number()
  end

  local ok, result = pcall(function()
    local value = parse_value()
    skip_ws()
    if pos <= len then
      fail("trailing characters")
    end
    return value
  end)

  if not ok then
    return nil, result
  end
  return result
end

return M
