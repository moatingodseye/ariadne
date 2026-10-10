#!/usr/bin/env bash
# Ariadne client installer (Linux x64): ariadne_cli (the command line) and
# ariadne_mcp (the MCP server) - two executables, one per job.
#
#   ./install-client.sh http://ariadne-host:8193 [install-dir]
#
# The URL is REQUIRED and that is deliberate. Unconfigured, the binary tries
# http://localhost:8193, which is right only on the server box itself; a client
# installed without being pointed somewhere would talk to whatever answers
# there. This script never leaves that to chance.
set -euo pipefail

URL="${1:-}"
TARGET="${2:-$HOME/tool}"
if [ -z "$URL" ]; then
  echo "Usage: $0 <server-url> [install-dir]" >&2
  echo "  e.g. $0 http://ariadne:8193" >&2
  exit 1
fi
cd "$(dirname "$0")"

echo
echo "Installing the Ariadne client"
echo "  server : $URL"
echo "  folder : $TARGET"
echo

mkdir -p "$TARGET"
install -m 0755 ariadne_cli-linux-x64 "$TARGET/ariadne_cli"
install -m 0755 ariadne_mcp-linux-x64 "$TARGET/ariadne_mcp"
echo "  copied ariadne_cli, ariadne_mcp"

# Written to the shell profile rather than exported here, which would last
# exactly as long as this script.
PROFILE="${ARIADNE_PROFILE:-$HOME/.profile}"
if grep -q '^export ARIADNE_API_URL=' "$PROFILE" 2>/dev/null; then
  sed -i "s|^export ARIADNE_API_URL=.*|export ARIADNE_API_URL=$URL|" "$PROFILE"
else
  printf '\nexport ARIADNE_API_URL=%s\n' "$URL" >> "$PROFILE"
fi
echo "  set ARIADNE_API_URL in $PROFILE (new shells only)"
echo

# The flag goes AFTER the command: `ariadne --url=... listprojects` is read as
# an op called "--url=..." and refused - found by running it, not by reading it.
if "$TARGET/ariadne_cli" listprojects --url="$URL"; then
  echo
  echo "  >> the server answered, so the client is working."
else
  echo
  echo "  >> the server did not answer. Check the URL and that the port is reachable." >&2
fi

cat <<TXT

Register it with Claude as an MCP server:

  claude mcp add ariadne -- $TARGET/ariadne_mcp --url=$URL

The --url is repeated there on purpose: an MCP server is started by another
process, which may not have inherited ARIADNE_API_URL.
TXT
