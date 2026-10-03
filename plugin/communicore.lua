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
