if vim.g.loaded_communicore == 1 then
  return
end
vim.g.loaded_communicore = 1

vim.api.nvim_create_user_command("CommunicoreRun", function()
  require("communicore").run()
end, { desc = "Run the .http request under the cursor" })

vim.api.nvim_create_user_command("CommunicoreRunAll", function()
  require("communicore").run_all()
end, { desc = "Run all .http requests in the current buffer" })

vim.api.nvim_create_user_command("CommunicoreEnv", function(opts)
  local communicore = require("communicore")
  if opts.args == "" then
    local current = communicore.get_env()
    vim.notify("communicore: environment is " .. (current and ("%q"):format(current) or "unset"))
    return
  end
  communicore.set_env(opts.args)
  vim.notify(("communicore: environment set to %q"):format(opts.args))
end, { nargs = "?", desc = "Set or show the active .env environment" })
