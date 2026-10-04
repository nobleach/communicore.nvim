# AGENTS.md

## What this is

communicore.nvim — a Neovim HTTP client for the [.http file format](https://http-files.org/spec/basics/), conceptually a clone of [kulala.nvim](https://github.com/dont-be-evil-company/kulala.nvim) but 100% Lua with no external core binary. The only runtime dependency is `curl`.

## Conventions

- **Pure Lua where possible**: `lua/communicore/parser.lua`, `lua/communicore/variables.lua`, `lua/communicore/environment.lua`, `lua/communicore/json.lua`, `lua/communicore/format.lua`, `lua/communicore/store.lua` and `lua/communicore/references.lua` must not use the `vim` API (`io` is fine), so they stay testable under plain busted and portable outside Neovim.
- **Pluggable transport**: request execution goes through `communicore.transport` (`register`/`get`). New transports implement `execute(req, opts, callback)` where callback receives `(resp, err)`.
- **Tests first**: new spec features get a failing spec in `tests/communicore/` before implementation.
- Formatting: `.stylua.toml` (2-space indent, double quotes, 120 columns).

## Commands

- Run tests: `make test` (uses plenary busted; set `PLENARY_DIR` to override the plenary checkout location, default `/tmp/plenary.nvim`).
- Format check: `stylua --check lua tests plugin ftdetect`.

## Scope notes

- Deferred to later iterations: gRPC, GraphQL, `http-client.env.json` (JetBrains env format), dynamic variables (`$timestamp` etc.), response handler scripts (`> {% ... %}` — the parser already terminates the body at `>`), pre-request scripts, cookies/proxy/SSL options, `{{%var}}` percent-encoding substitution, XPath references (`{{name.response.body.//xpath}}`), JSON encoding (references into non-scalar JSON values resolve to nil).
- File variables follow JetBrains semantics: an `@var = value` line only applies to requests declared after it.
- Environments follow the dotenv-flow convention: `.env` (shared) + `.env.<name>` (selected env overrides). Precedence: in-file `@var` > `.env.<name>` > `.env`. Env files are resolved relative to the `.http` file's directory, falling back to cwd.
- Response chaining: `# @name` names a request; its request/response pair is stored in-memory after it runs. References follow VS Code syntax (`{{name.response.body.$.path}}`) with jq-style paths (0-based arrays); the `$` is optional.

## Structure

```
lua/communicore/
  init.lua            -- public API: setup, run, run_all
  config.lua          -- defaults + user config merge
  parser.lua          -- .http file parser (pure Lua)
  variables.lua       -- {{variable}} substitution (pure Lua)
  environment.lua     -- dotenv loading + env/file var precedence (pure Lua)
  json.lua            -- minimal JSON decoder (pure Lua, decode only)
  format.lua          -- JSON pretty printer, re-indents raw text (pure Lua)
  store.lua           -- in-session named request/response store (pure Lua)
  references.lua      -- {{name.response.body.$.path}} resolution (pure Lua)
  transport/init.lua  -- transport registry
  transport/curl.lua  -- curl transport (build_command/parse_response are pure)
  ui.lua              -- response split window
plugin/communicore.lua -- :CommunicoreRun, :CommunicoreRunAll
ftdetect/http.lua      -- .http/.rest filetype detection
tests/communicore/     -- plenary busted specs mirroring lua/ layout
```
