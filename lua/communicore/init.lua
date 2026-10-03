---communicore.nvim — an HTTP client for Neovim speaking the .http file format.
---https://http-files.org/spec/basics/

local config = require("communicore.config")
local parser = require("communicore.parser")
local transport = require("communicore.transport")
local ui = require("communicore.ui")
local variables = require("communicore.variables")

local M = {}

---@param opts communicore.Config|nil
function M.setup(opts)
  config.setup(opts)
end

---@return communicore.Request[]
local function get_requests()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return parser.parse(table.concat(lines, "\n"))
end

---@param req communicore.Request
local function run_request(req)
  local resolved = variables.substitute_request(req)
  local impl = transport.get(config.options.transport)
  impl.execute(resolved, {}, function(resp, err)
    ui.show(resp, err)
  end)
end

---Runs the request under the cursor.
function M.run()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local req = parser.find_request_at(get_requests(), row)
  if not req then
    vim.notify("communicore: no request found at cursor", vim.log.levels.WARN)
    return
  end
  run_request(req)
end

---Runs all requests in the current buffer.
function M.run_all()
  local requests = get_requests()
  if #requests == 0 then
    vim.notify("communicore: no requests found in buffer", vim.log.levels.WARN)
    return
  end
  for _, req in ipairs(requests) do
    run_request(req)
  end
end

return M
