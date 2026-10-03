---Response display: a reusable buffer shown in a split window.

local config = require("communicore.config")

local M = {}

local bufnr = nil ---@type number|nil

local FILETYPES = {
  json = "json",
  html = "html",
  xml = "xml",
  javascript = "javascript",
  text = "text",
}

---@param resp communicore.Response|nil
---@return string filetype
local function detect_filetype(resp)
  if not resp then
    return "text"
  end
  for _, h in ipairs(resp.headers) do
    if h.name:lower() == "content-type" then
      for key, ft in pairs(FILETYPES) do
        if h.value:lower():find(key, 1, true) then
          return ft
        end
      end
    end
  end
  return "text"
end

---@param resp communicore.Response|nil
---@param err string|nil
---@return string[] lines, string filetype
local function render(resp, err)
  if err then
    return { "Error:", "", err }, "text"
  end
  local lines = { resp.status_line }
  for _, h in ipairs(resp.headers) do
    table.insert(lines, h.name .. ": " .. h.value)
  end
  table.insert(lines, "")
  for line in (resp.body .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, (line:gsub("\r$", "")))
  end
  -- Remove the extra line produced by the trailing newline above.
  if resp.body == "" or resp.body:sub(-1) == "\n" then
    table.remove(lines)
  end
  return lines, detect_filetype(resp)
end

local function open_window()
  local split = config.options.split
  local cmds = {
    right = "botright vsplit",
    left = "topleft vsplit",
    above = "topleft split",
    below = "botright split",
  }
  vim.cmd(cmds[split] or cmds.right)
end

---Shows a response (or error) in the output window.
---@param resp communicore.Response|nil
---@param err string|nil
function M.show(resp, err)
  local lines, filetype = render(resp, err)

  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "communicore://response")
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = filetype
  vim.bo[bufnr].modifiable = false

  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    open_window()
    vim.api.nvim_win_set_buf(0, bufnr)
  end
end

return M
