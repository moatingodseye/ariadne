# Ariadne

A code-graph service for Claude. Ariadne indexes a codebase into a graph of its
symbols and how they connect — who calls what, where a type is used, what is
unreachable, what touches a database table — and answers those questions over
MCP, a command line and a web UI.

Languages: **Dart, Delphi / Object Pascal (including `.dfm` forms), Java, C# and
Rust.**

This repository holds **compiled releases only** — no source. Each release has
the server images and the client executables attached; the scripts and the
documentation to run them are here.

## What you get

| piece | what it is |
|---|---|
| `ariadne-api` image | the service: REST, MCP, and the indexer |
| `ariadne-web` image | the web UI, and the proxy clients talk to on `:8193` |
| `ariadne_cli` | the command line — index a repository, ask the graph questions |
| `ariadne_mcp` | the MCP server Claude talks to |

The server runs as three podman (or docker) containers on one Linux box, with a
stock PostgreSQL. The clients are single self-contained executables for Windows
x64 and Linux x64.

## Quick start

1. Download the latest **release** assets.
2. On the server box, put the two image tarballs in `server/` and run:

   ```bash
   cd server
   cp ariadne.env.example ariadne.env     # edit the data paths
   ./run-ariadne.sh                       # loads, starts, and checks it answered
   ```

   With docker instead of podman, use `compose.yaml` — see DEPLOYMENT.md.

3. On each client machine, put the executables in `client/` and run:

   ```
   Windows:  install-client.cmd http://<server>:8193
   Linux:    ./install-client.sh http://<server>:8193
   ```

4. Index something and ask it a question:

   ```bash
   ariadne_cli index C:/path/to/repo --project=myproject
   ariadne_cli searchgraph --project myproject --query Customer
   ```

5. Give it to Claude:

   ```
   claude mcp add ariadne -- D:\tool\ariadne_mcp.exe --url=http://<server>:8193
   ```

[**DEPLOYMENT.md**](DEPLOYMENT.md) is the full guide: requirements, settings, the
secret you must back up, upgrading, offline installs and troubleshooting.

## Uploads

`index` uploads the source tree to the server, which stores it and builds the
graph. It honours each repository's `.gitignore`, never uploads `.ssh/` or
`.claude/`, and skips build output and binaries. Point it only at code you are
happy to have stored on your Ariadne server.
