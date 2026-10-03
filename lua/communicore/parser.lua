---Parser for .http files, following https://http-files.org/spec/basics/.
---Pure Lua: no Neovim API dependencies, so it can run under plain busted.

---@class communicore.Request
---@field method string HTTP method (uppercase), defaults to "GET".
---@field url string Request URL, may contain {{variables}}.
---@field http_version string|nil e.g. "HTTP/1.1" or "HTTP/2".
---@field headers {name: string, value: string}[] Ordered header list.
---@field body string|nil Request body.
---@field name string|nil Title taken from the preceding ### separator.
---@field line number 1-based line number of the request line.
---@field end_line number 1-based line number of the last line of the request block.
---@field variables table<string, string> File variables in scope for this request.

local M = {}

---@param str string
---@return string
local function trim(str)
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param t table<string, string>
---@return table<string, string>
local function shallow_copy(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end

---@param line string
---@return boolean
local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

---@param line string
---@return boolean
local function is_separator(line)
  return line:match("^%s*###+") ~= nil
end

---@param line string
---@return string|nil title text after the separator, if any
local function separator_title(line)
  local title = line:match("^%s*###+%s*(.-)%s*$")
  if title and title ~= "" then
    return title
  end
end

---@param line string
---@return boolean
local function is_comment(line)
  if is_separator(line) then
    return false
  end
  return line:match("^%s*#") ~= nil or line:match("^%s*//") ~= nil
end

---@param line string
---@return string|nil name, string|nil value
local function parse_variable(line)
  local name, value = line:match("^%s*@([%w_.%-]+)%s*=%s*(.-)%s*$")
  return name, value
end

---@param line string
---@return boolean
local function is_indented(line)
  return line:match("^[ \t]") ~= nil and not is_blank(line)
end

---@param line string
---@return boolean
local function is_query_continuation(line)
  return line:match("^%s*[?&]%S") ~= nil
end

---@param line string
---@return string|nil name, string|nil value
local function parse_header(line)
  local name, value = line:match("^([%w_%-]+)%s*:%s*(.-)%s*$")
  return name, value
end

---Parses a request line of the form `[Method] Request-URL [HTTP-Version]`.
---@param line string trimmed, non-empty line
---@return string method, string url, string|nil http_version
local function parse_request_line(line)
  local method, url, http_version
  local first, rest = line:match("^(%S+)%s+(.+)$")

  if first and first:match("^%u[%u%d_%-]*$") then
    method = first
    -- An optional HTTP version is the last token when it looks like HTTP/x.
    local u, v = rest:match("^(.-)%s+(HTTP/[%d.]+)%s*$")
    if u then
      url, http_version = u, v
    else
      url = rest
    end
  else
    method = "GET"
    url = line
  end

  return method, trim(url), http_version
end

---Joins a urlencoded form body spread over multiple lines into a single
---`a=1&b=2` string, per https://http-files.org/spec/requests/.
---@param body string
---@return string
local function join_form_body(body)
  local parts = {}
  for line in (body .. "\n"):gmatch("(.-)\n") do
    line = trim(line):gsub("^[?&]", "")
    if line ~= "" then
      table.insert(parts, line)
    end
  end
  return table.concat(parts, "&")
end

---@param headers {name: string, value: string}[]
---@return boolean
local function is_form_urlencoded(headers)
  for _, h in ipairs(headers) do
    if h.name:lower() == "content-type" and h.value:lower():find("application/x-www-form-urlencoded", 1, true) then
      return true
    end
  end
  return false
end

---Parses .http file content into a list of requests.
---@param content string
---@return communicore.Request[]
function M.parse(content)
  local lines = {}
  for line in (content .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, (line:gsub("\r$", "")))
  end

  local requests = {}
  local variables = {}
  local current = nil ---@type communicore.Request|nil
  local state = nil ---@type "headers"|"body"|"handler"|nil
  local pending_name = nil ---@type string|nil
  local has_headers = false
  local body_lines = {} ---@type string[]

  local function finalize(end_line)
    if not current then
      return
    end
    -- Drop trailing blank lines from the body.
    while #body_lines > 0 and is_blank(body_lines[#body_lines]) do
      table.remove(body_lines)
    end
    if #body_lines > 0 then
      current.body = table.concat(body_lines, "\n")
      if is_form_urlencoded(current.headers) then
        current.body = join_form_body(current.body)
      end
    end
    current.end_line = end_line
    table.insert(requests, current)
    current = nil
    state = nil
    body_lines = {}
  end

  for i, line in ipairs(lines) do
    if is_separator(line) then
      finalize(i - 1)
      pending_name = separator_title(line)
    elseif current and state == "body" then
      -- Everything inside the body is literal, except that a response
      -- handler (`>`) terminates it.
      if line:match("^%s*>") then
        state = "handler"
      else
        table.insert(body_lines, line)
      end
    elseif current and state == "handler" then
      -- Response handlers are not supported yet; ignore their content.
    elseif is_comment(line) or is_blank(line) then
      -- # @name / // @name metadata names the next request.
      local meta = line:match("^%s*#%s*@name%s+(%S+)") or line:match("^%s*//%s*@name%s+(%S+)")
      if meta and not current then
        pending_name = meta
      end
      if current and state == "headers" and is_blank(line) then
        state = "body"
      end
      -- Comments and stray blank lines between requests are ignored.
    elseif not current then
      local name, value = parse_variable(line)
      if name then
        variables[name] = value
      else
        current = {
          method = "GET",
          url = "",
          headers = {},
          name = pending_name,
          line = i,
          variables = shallow_copy(variables),
        }
        pending_name = nil
        local method, url, http_version = parse_request_line(trim(line))
        current.method = method
        current.url = url
        current.http_version = http_version
        state = "headers"
        has_headers = false
      end
    elseif state == "headers" then
      if (is_indented(line) or is_query_continuation(line)) and not has_headers then
        -- Multi-line URL: continuation lines are concatenated to the URL.
        current.url = current.url .. trim(line)
      elseif is_indented(line) and has_headers then
        -- Multi-line header value.
        local last = current.headers[#current.headers]
        last.value = last.value .. " " .. trim(line)
      else
        local name, value = parse_header(line)
        if name then
          table.insert(current.headers, { name = name, value = value })
          has_headers = true
        end
        -- Non-conforming lines in the header section are ignored.
      end
    end
  end

  finalize(#lines)
  return requests
end

---Finds the request that should run for a given 1-based cursor line.
---Lines between requests map to the next request in the file.
---@param requests communicore.Request[]
---@param linenr number
---@return communicore.Request|nil
function M.find_request_at(requests, linenr)
  for _, req in ipairs(requests) do
    if linenr <= req.end_line then
      return req
    end
  end
end

return M
