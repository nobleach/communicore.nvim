local M = {}

---@class communicore.Config
---@field transport string|table transport name or custom transport implementation
---@field split "right"|"left"|"above"|"below" where to open the response window
---@field env string|nil selected environment name (reads .env and .env.<env>)
M.defaults = {
  transport = "curl",
  split = "right",
  ---@type string|nil selected environment name, e.g. "qa" (reads .env.qa)
  env = nil,
}

---@type communicore.Config
M.options = vim.deepcopy(M.defaults)

---@param opts communicore.Config|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
