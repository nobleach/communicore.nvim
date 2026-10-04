---Cursor navigation between the requests of an .http buffer.
---Request starts are located via tree-sitter when the http grammar is
---installed, falling back to the built-in line-based parser otherwise.

local parser = require("communicore.parser")

local M = {}

---Request start lines (1-based, ascending) via tree-sitter, or nil when the
---http grammar is not installed.
---@param bufnr number
---@return number[]|nil
local function ts_request_lines(bufnr)
  local ok, ts_parser = pcall(vim.treesitter.get_parser, bufnr, "http")
  if not ok or not ts_parser then
    return nil
  end
  local tree = ts_parser:parse()[1]
  if not tree then
    return nil
  end
  local query = vim.treesitter.query.parse("http", "(request) @request")
  local lines = {}
  for _, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
    table.insert(lines, node:start() + 1)
  end
  table.sort(lines)
  return lines
end

---@param bufnr number
---@return number[] request start lines, 1-based and ascending
local function request_lines(bufnr)
  local lines = ts_request_lines(bufnr)
  if lines then
    return lines
  end
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  lines = {}
  for _, req in ipairs(parser.parse(content)) do
    table.insert(lines, req.line)
  end
  return lines
end

---Finds the jump target: the first line strictly after `row` (direction 1)
---or the last line strictly before `row` (direction -1).
---@param lines number[] ascending
---@param row number 1-based cursor line
---@param direction 1|-1
---@return number|nil
function M._target_line(lines, row, direction)
  local target = nil
  for _, line in ipairs(lines) do
    if direction > 0 and line > row and (not target or line < target) then
      target = line
    elseif direction < 0 and line < row and (not target or line > target) then
      target = line
    end
  end
  return target
end

---@param direction 1|-1
local function jump(direction)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local target = M._target_line(request_lines(0), row, direction)
  if not target then
    local which = direction > 0 and "next" or "previous"
    vim.notify(("communicore: no %s request"):format(which), vim.log.levels.INFO)
    return
  end
  vim.api.nvim_win_set_cursor(0, { target, 0 })
end

---Jumps to the first request starting after the cursor.
function M.next_request()
  jump(1)
end

---Jumps to the request starting before the cursor; when the cursor is inside
---a request block, jumps to that request's start.
function M.prev_request()
  jump(-1)
end

return M
