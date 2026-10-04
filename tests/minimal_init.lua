local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  vim.fn.system({"git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir})
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

-- Optional: build the tree-sitter http grammar so the navigate specs can
-- exercise the tree-sitter backend. Silently skipped without git/cc.
local ts_src = os.getenv("TREE_SITTER_HTTP_DIR") or "/tmp/tree-sitter-http"
local ts_parsers = os.getenv("COMMUNICORE_TS_PARSER_DIR") or "/tmp/communicore-ts-parsers"
local ts_so = ts_parsers .. "/parser/http.so"
if vim.fn.filereadable(ts_so) == 0 and vim.fn.executable("git") == 1 and vim.fn.executable("cc") == 1 then
  if vim.fn.isdirectory(ts_src) == 0 then
    vim.fn.system({ "git", "clone", "--depth", "1", "https://github.com/rest-nvim/tree-sitter-http", ts_src })
  end
  if vim.fn.filereadable(ts_src .. "/src/parser.c") == 1 then
    vim.fn.mkdir(ts_parsers .. "/parser", "p")
    local cmd = { "cc", "-o", ts_so, "-shared", "-fPIC", "-I", ts_src .. "/src", "-O2", ts_src .. "/src/parser.c" }
    if vim.fn.filereadable(ts_src .. "/src/scanner.c") == 1 then
      table.insert(cmd, ts_src .. "/src/scanner.c")
    end
    vim.fn.system(cmd)
  end
end
if vim.fn.filereadable(ts_so) == 1 then
  vim.opt.rtp:prepend(ts_parsers)
end

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
