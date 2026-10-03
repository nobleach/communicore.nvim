---curl-based transport. Builds an argv list (no shell involved) and runs it
---with vim.system. `build_command` and `parse_response` are pure functions.

local M = {}

local VERSION_FLAGS = {
  ["HTTP/1.0"] = "--http1.0",
  ["HTTP/1.1"] = "--http1.1",
  ["HTTP/2"] = "--http2",
  ["HTTP/3"] = "--http3",
}

---Builds the curl argv for a request.
---@param req communicore.Request
---@param opts table|nil
---@return string[]
function M.build_command(req, opts)
  opts = opts or {}
  local argv = { "curl", "-sS", "-i", "-X", req.method }

  local version_flag = req.http_version and VERSION_FLAGS[req.http_version]
  if version_flag then
    table.insert(argv, version_flag)
  end

  for _, h in ipairs(req.headers or {}) do
    table.insert(argv, "-H")
    table.insert(argv, h.name .. ": " .. h.value)
  end

  if req.body and req.body ~= "" then
    table.insert(argv, "--data-raw")
    table.insert(argv, req.body)
  end

  table.insert(argv, req.url)
  return argv
end

---Splits a raw `curl -i` output into status line, headers and body.
---@param raw string
---@return communicore.Response
function M.parse_response(raw)
  local head, body
  local s, e = raw:find("\r\n\r\n", 1, true)
  if s then
    head, body = raw:sub(1, s - 1), raw:sub(e + 1)
  else
    s, e = raw:find("\n\n", 1, true)
    if s then
      head, body = raw:sub(1, s - 1), raw:sub(e + 1)
    else
      head, body = raw, ""
    end
  end

  local header_lines = {}
  for line in (head .. "\n"):gmatch("(.-)\n") do
    table.insert(header_lines, (line:gsub("\r$", "")))
  end

  local status_line = header_lines[1] or ""
  local headers = {}
  for i = 2, #header_lines do
    local name, value = header_lines[i]:match("^([^:]+):%s*(.-)%s*$")
    if name then
      table.insert(headers, { name = name, value = value })
    end
  end

  return {
    status = tonumber(status_line:match("^HTTP/%S+%s+(%d+)")),
    status_line = status_line,
    headers = headers,
    body = body,
  }
end

---Executes a request via curl.
---@param req communicore.Request
---@param opts table|nil
---@param callback fun(resp: communicore.Response|nil, err: string|nil)
function M.execute(req, opts, callback)
  local argv = M.build_command(req, opts)
  vim.system(argv, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local err = result.stderr
        if not err or err == "" then
          err = ("curl exited with code %d"):format(result.code)
        end
        callback(nil, vim.trim(err))
        return
      end
      local resp = M.parse_response(result.stdout or "")
      resp.request = req
      callback(resp, nil)
    end)
  end)
end

return M
