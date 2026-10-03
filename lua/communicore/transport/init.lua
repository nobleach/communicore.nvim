---Pluggable transport registry.
---
---A transport executes a parsed request and reports the result
---asynchronously through a callback:
---
---  ---@class communicore.Transport
---  ---@field execute fun(req: communicore.Request, opts: table|nil, callback: fun(resp: communicore.Response|nil, err: string|nil))

---@class communicore.Response
---@field status number|nil HTTP status code.
---@field status_line string e.g. "HTTP/1.1 200 OK".
---@field headers {name: string, value: string}[]
---@field body string
---@field request communicore.Request|nil the request that produced this response

local M = {
  _registry = {},
}

---@param name string
---@param impl table
function M.register(name, impl)
  M._registry[name] = impl
end

---Resolves a transport by name, or passes through a transport table.
---@param transport string|table|nil transport name (defaults to "curl") or implementation
---@return table
function M.get(transport)
  if type(transport) == "table" then
    return transport
  end
  local impl = M._registry[transport or "curl"]
  if not impl then
    error(("communicore: unknown transport %q"):format(tostring(transport)))
  end
  return impl
end

M.register("curl", require("communicore.transport.curl"))

return M
