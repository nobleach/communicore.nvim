<p align="center">
  <img src="logo.svg" alt="communicore.nvim" width="220">
</p>

# communicore.nvim

An HTTP client for Neovim built on the [.http file format](https://http-files.org/spec/basics/) — in the spirit of [kulala.nvim](https://github.com/dont-be-evil-company/kulala.nvim), but 100% Lua with no external core binary. The only runtime dependency is `curl`.

## Rationale

I enjoyed using Kulala until it went private. I needed a simple REST client for NeoVim. After trying a couple of the others, nothing really hit.

This repo is complete donationware. You're free to do whatever you want with it. Use it. Make fun of it. Fork it and make it 100x better. It suits me. If you have problems with it, fixes are welcome. If you have feature requests, PRs are welcome. If you need support, read the source and figure out how it works. It shells out to `curl`. I did build it with the plan to allow pluggable backends but, `curl` is fairly ubiquitous.

## Features

- Run HTTP requests (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, `OPTIONS`, ...) directly from `.http` / `.rest` buffers
- Multiple requests per file, separated by `###` (with optional titles)
- `#` and `//` comments
- File variables: `@name = value` definitions and `{{name}}` substitution in URLs, headers and bodies
- Named environments via dotenv files: `.env` for shared defaults, `.env.<name>` per environment
- Named requests and response chaining: `# @name login`, then reference the stored response with
  `{{login.response.body.$.token}}` (jq-style paths), `{{login.response.headers.X}}` or
  `{{login.response.body.*}}`
- Multi-line URLs and query parameters, multi-line header values
- URL-encoded form bodies spread over multiple lines (`a=1` / `&b=2`)
- Pluggable transport layer (ships with a `curl` transport)
- Response shown in a split with status line, headers and pretty-printed, syntax-highlighted body
- Jump between requests (`next_request()` / `prev_request()`) via tree-sitter, with a built-in fallback

Planned for later iterations: `http-client.env.json` (JetBrains format), dynamic variables, request metadata (`@name`, `@no-redirect`), response handlers and pre-request scripts, GraphQL and gRPC. And maybe a cooler UI. Kulala got really cool there at the end!

## Requirements

- Neovim >= 0.10
- `curl` in `$PATH`
- Optional: the `http` tree-sitter grammar (`:TSInstall http`) for request navigation — without it, jumping falls back to the built-in parser

## Installation

Via [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
require("lazy").setup({
  {
    "nobleach/communicore.nvim",
    ft = { "http", "rest" },
    opts = {},
    keys = {
      { "<leader>hh", function() require("communicore").run() end, ft = "http", desc = "Run request" },
      { "<leader>ha", function() require("communicore").run_all() end, ft = "http", desc = "Run all requests" },
      { "]r", function() require("communicore").next_request() end, ft = "http", desc = "Next request" },
      { "[r", function() require("communicore").prev_request() end, ft = "http", desc = "Previous request" },
    },
  },
})
```

## Usage

Given a file `requests.http`:

```http
@host = api.example.com

### Get a user
GET https://{{host}}/users/1
Accept: application/json

### Create a user
POST https://{{host}}/users
Content-Type: application/json

{
  "name": "New User"
}
```

- `:CommunicoreRun` (or `require("communicore").run()`) runs the request under the cursor.
- `:CommunicoreRunAll` (or `require("communicore").run_all()`) runs every request in the buffer.
- `:CommunicoreEnv qa` (or `require("communicore").set_env("qa")`) selects the active environment; `:CommunicoreEnv` shows it.
- `require("communicore").next_request()` / `.prev_request()` jump to the next/previous request — map them yourself, e.g. `]r` / `[r`.

### Environments

Environment variables come from dotenv files next to the `.http` file (falling back to the current working directory), following the dotenv-flow / Next.js / Vite convention:

- `.env` — shared defaults, always loaded
- `.env.<name>` — loaded when environment `<name>` is active, overriding shared values

Variable precedence (highest first): in-file `@var` → `.env.<name>` → `.env`.

Values from these files are referenced with the same `{{name}}` syntax as file variables, and can be interpolated anywhere in the request — URL, headers and body:

```
# .env
HOST=api.example.com
SOME_PASS=foo
```

```http
GET https://{{HOST}}/users/1
Authorization: Basic {{SOME_PASS}}
```

With the files above, the request is sent as `GET https://api.example.com/users/1` with an `Authorization: Basic foo` header. Select a named environment with `:CommunicoreEnv qa` (loads `.env` plus `.env.qa`) or `require("communicore").set_env("qa")`.

### Response chaining

Name a request with `# @name` and later requests can reference its response (VS Code REST Client syntax,
with jq-style paths — dot-separated keys and 0-based array indices):

```http
# @name login
POST https://api.example.com/auth
Content-Type: application/json

{"user": "admin", "password": "secret"}

###
GET https://api.example.com/protected
Authorization: Bearer {{login.response.body.$.access_token}}
```

Supported reference forms:

- `{{name.response.body.$.path}}` / `{{name.response.body.path}}` — path into a JSON response body
- `{{name.response.body.*}}` — entire raw response body
- `{{name.response.headers.Header-Name}}` — response header (case-insensitive)
- `{{name.request.body.*}}` / `{{name.request.headers.Header-Name}}` — the original request

Responses are stored in memory for the Neovim session after a named request runs.

## Configuration

```lua
require("communicore").setup({
  -- Transport: "curl" or a custom implementation table:
  -- { execute = function(req, opts, callback) ... callback(resp, err) end }
  transport = "curl",
  -- Where to open the response window: "right", "left", "above", "below"
  split = "right",
  -- Active environment name; reads .env and .env.<name>
  env = nil,
})
```

## Project layout

```
lua/communicore/
  init.lua            -- public API: setup, run, run_all
  config.lua          -- defaults + user config merge
  parser.lua            -- .http file parser (pure Lua)
  variables.lua         -- {{variable}} substitution (pure Lua)
  environment.lua       -- dotenv loading + env/file var precedence (pure Lua)
  json.lua              -- minimal JSON decoder (pure Lua, decode only)
  store.lua             -- in-session named request/response store (pure Lua)
  references.lua        -- {{name.response.body.$.path}} resolution (pure Lua)
  transport/init.lua  -- pluggable transport registry
  transport/curl.lua  -- curl transport
  ui.lua              -- response split window
plugin/communicore.lua -- user commands
ftdetect/http.lua      -- .http/.rest filetype detection
tests/                 -- plenary busted specs
```

## Development

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) busted-style specs:

```
make test
```

Formatting follows `.stylua.toml` (`stylua lua tests`).

## License

MIT
