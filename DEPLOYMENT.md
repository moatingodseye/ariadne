# Ariadne 0.33.1 — deployment

Everything needed to run Ariadne on one box and point clients at it. **No source,
no Dart SDK and no build step** are required anywhere: the two application images
are AOT binaries on `debian-slim`, and the CLI is a single self-contained
executable.

The scripts are in this repository; the binaries are attached to the matching
**GitHub release**. Put each release file beside the script that uses it:

```
ariadne/
  DEPLOYMENT.md                  this file
  server/
    ariadne-api-0.33.1.tar.gz    release asset - the API + MCP service   (~66 MB)
    ariadne-web-0.33.1.tar.gz    release asset - the UI and /api proxy   (~40 MB)
    init.sql                     runs once, on first database creation
    ariadne.env.example          copy to ariadne.env and edit
    run-ariadne.sh               loads, starts, and PROVES it answered
    compose.yaml                 the same, for docker compose
  client/
    ariadne_cli.exe              release asset - the CLI, Windows x64
    ariadne_mcp.exe              release asset - the MCP server, Windows x64
    ariadne_cli-linux-x64        release asset - the CLI, Linux x64
    ariadne_mcp-linux-x64        release asset - the MCP server, Linux x64
    install-client.cmd           Windows installer
    install-client.sh            Linux installer
```

`SHA256SUMS` on the release lists a checksum for every asset:
`sha256sum -c SHA256SUMS --ignore-missing` after downloading.

Version **0.33.1+0**. The exact commit is baked into the images — ask the running
server with `curl http://<box>:8193/api/version`, and the release notes it was
built from are in `/app/changes.log` inside `ariadne-api`.

---

## What you are deploying

Three containers on one podman network:

| container | what it is | port |
|---|---|---|
| `ariadne-db` | stock `pgvector/pgvector:pg16`, data bind-mounted to the host | none published |
| `ariadne-api` | the service: REST + MCP, and a live feed on 8091 | 8192 → 8090 |
| `ariadne-web` | nginx serving the UI and proxying `/api` and `/ws` | **8193** → 8080 |

**`:8193` is the only port clients need.** `:8192` is the API direct; firewall it
off if you like, nothing depends on it being reachable from elsewhere.

---

## 1. The box

Ubuntu or any distro with podman. Rootless is fine and is what this is built for.

```bash
sudo apt update && sudo apt install -y podman
loginctl enable-linger "$USER"     # REQUIRED — rootless containers die on logout without it
podman info >/dev/null && echo "podman OK"
```

It needs outbound access to `docker.io` **once**, to pull Postgres (~450 MB).
Everything else comes out of the tarballs. For a fully offline box see
[Offline](#offline) at the end.

## 2. Settings

```bash
cd server
cp ariadne.env.example ariadne.env
$EDITOR ariadne.env
```

The two that matter:

- **`ARIADNE_DB_DATA` and `ARIADNE_SOURCE`** — where the database and the source
  store live on the host. The defaults are under `/var/lib/ariadne`. Both must be
  outside anything you would delete to "start clean", and both must survive a
  redeploy. The source store holds one git repository per indexed project; losing
  it leaves every graph describing code nobody can reproduce.
- **`ARIADNE_SECRET`** — leave it blank. `run-ariadne.sh` generates one on the
  first run and writes it back into `ariadne.env`, 0600.

> ⚠ **Back `ariadne.env` up, and never regenerate the secret.** It seals the
> database passwords Ariadne stores for the projects it reads schemas from.
> Change it and every one of them becomes undecryptable — which shows up later
> as a schema import failing to authenticate, and reads like a database problem
> rather than like this.
>
> Without it the server runs perfectly well. The one thing it refuses is
> *storing* a password, and it says so. It never falls back to plaintext.

## 3. Run it

```bash
chmod +x run-ariadne.sh
./run-ariadne.sh
```

It loads the images, starts the three containers, and then **asks the running
server whether it is alive** before saying so — `curl /api/health` through the web
port, up to 60 s. A deploy that printed "up" because `podman run` returned would
have proved only that podman liked the arguments.

**Nothing autostarts.** `ARIADNE_RESTART` is `no` unless you set it to
`unless-stopped` in `ariadne.env`, and the script never enables lingering or
podman's restart unit — starting something at boot is a decision for whoever
owns the box, not a side effect of deploying.

Re-running it is how you **upgrade**: the app containers are recreated, the
database and the source store are untouched.

Check it from anywhere:

```bash
curl http://<box>:8193/api/version
```

### Or with docker compose

On a box with docker rather than podman, `server/compose.yaml` starts the same
three containers from the same `ariadne.env`:

```bash
cd server
docker load -i ariadne-api-0.33.1.tar.gz
docker load -i ariadne-web-0.33.1.tar.gz
cp ariadne.env.example ariadne.env
openssl rand -hex 32          # paste into ARIADNE_SECRET - once, and back it up
$EDITOR ariadne.env
docker compose --env-file ariadne.env up -d
curl http://localhost:8193/api/health
```

The one difference: compose cannot generate `ARIADNE_SECRET` for you, so it
refuses to start until you have set one. `podman-compose` works with the same
file.

## 4. The clients

On each machine that will use the CLI or drive Ariadne from Claude:

```
Windows:  install-client.cmd http://<box>:8193
Linux:    ./install-client.sh http://<box>:8193
```

The URL is **required**, and that is the single most important line in this
document. Unconfigured, the executable tries `http://localhost:8193`, which is
right only on the server box itself; a client installed without being pointed at
your server would talk to whatever answers there. The installer sets
`ARIADNE_API_URL` and then proves the server answered.

Default install folder is `D:\tool` (or `C:\tool` without a D: drive) on Windows
and `~/tool` on Linux; pass a second argument to change it.

### Driving it from Claude

```
claude mcp add ariadne -- D:\tool\ariadne_mcp.exe --url=http://<box>:8193
```

`--url` is repeated on purpose: an MCP server is launched by another process,
which may not have inherited the environment variable.

### First use

```bash
ariadne_cli listprojects                                 # answers, empty at first
ariadne_cli index C:/path/to/a/repo --project=myproject  # uploads AND indexes
ariadne_cli searchgraph --project myproject --query Customer
```

The server needs no access to your source control and no mounted checkout — the
tree is uploaded and stored server-side, one git repository per project.
`index` waits for the run and prints what it built; `reindex --project=<key>`
rebuilds later without re-uploading. `--project=x` and `--project x` both work,
everywhere.

**What `index` uploads.** Source, including vendored code (the server resolves
against it), minus build output and binaries. It honours each repository's
`.gitignore` — asked of git itself, so nested ignore files and global excludes
count — and it **never** uploads `.ssh/` or `.claude/`, whatever git says. The
upload line reports how many files were ignored. Write paths with forward
slashes: some shells eat a backslash, and the CLI says so when one has.

---

## Reading a project's DATABASE

Optional, and only if you want schema and *what touches this table*.

- **PostgreSQL, SQL Server, MySQL and SQLite** work directly from the server.
- **Oracle** needs an adapter container, which is **not published**: its base
  image carries the Oracle Instant Client, and redistributing that is a licensing
  question rather than a technical one.

Connections are configured with `dbconnect`, which stores the password sealed
under `ARIADNE_SECRET` — see section 2.

---

## Troubleshooting

| what you see | what it is |
|---|---|
| `run-ariadne.sh` fails at `health` | `podman logs ariadne-api` and `podman logs ariadne-web`. Usually the database not ready or a port already bound. |
| containers vanish after you log out | `loginctl enable-linger $USER` was not run. |
| a client cannot connect, or answers about projects you do not recognise | it is talking to the default, `localhost:8193`. `ariadne_cli listprojects --url=http://<box>:8193` to confirm, then re-run the installer. |
| schema import fails to authenticate | `ARIADNE_SECRET` changed. The stored password cannot be decrypted; re-enter it with `dbconnect`. |
| `curl :8192` times out | expected if you firewalled it. Clients use `:8193`. |

## Offline

`run-ariadne.sh` pulls Postgres from `docker.io` if it is not already present.
On a box with no outbound access, bring it in from one that has:

```bash
# on a connected machine
podman pull docker.io/pgvector/pgvector:pg16
podman save docker.io/pgvector/pgvector:pg16 | gzip -6 > pgvector-pg16.tar.gz

# on the target, before ./run-ariadne.sh
podman load -i pgvector-pg16.tar.gz
```

The script finds it already present and skips the pull.
