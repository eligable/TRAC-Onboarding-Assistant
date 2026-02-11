#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

usage() {
  cat <<'USAGE'
rfq-live-fast-restart.sh

Fast helper for live remote RFQ runs:
1) pull latest RFQ from remote channel
2) post QUOTE from local opposite peer
3) wait for matching QUOTE_ACCEPT from remote
4) post SWAP_INVITE immediately
5) verify SWAP_INVITE is visible on remote stream

Usage:
  scripts/rfq-live-fast-restart.sh [options]

Options:
  --channel <name>         RFQ channel (default: 0000intercomswapbtcusdt)
  --trade-id <id>          Optional: force a specific trade_id
  --welcome-text <text>    Invite welcome text (default: swap invite)
  --ttl-sec <n>            Invite ttl seconds (default: 1800)
  --accept-polls <n>       Poll rounds for QUOTE_ACCEPT (default: 10)
  --remote-user <name>     SSH user (default: muffin)
  --remote-host <host>     SSH host (default: 2.tcp.eu.ngrok.io)
  --remote-port <port>     SSH port (default: 10067)
  --remote-url <url>       Remote promptd URL (default: http://127.0.0.1:9334)
  --pass-file <path>       File with password on line 2 (default: /Users/muffin/lol)
  --local-setup <path>     Local prompt setup json (default: onchain/prompt/setup.json)
  --help                   Show this help
USAGE
}

CHANNEL="0000intercomswapbtcusdt"
TARGET_TRADE_ID=""
WELCOME_TEXT="swap invite"
TTL_SEC=1800
ACCEPT_POLLS=10

REMOTE_USER="muffin"
REMOTE_HOST="2.tcp.eu.ngrok.io"
REMOTE_PORT="10067"
REMOTE_URL="http://127.0.0.1:9334"
PASS_FILE="/Users/muffin/lol"
LOCAL_SETUP="onchain/prompt/setup.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="${2:-}"; shift 2 ;;
    --trade-id) TARGET_TRADE_ID="${2:-}"; shift 2 ;;
    --welcome-text) WELCOME_TEXT="${2:-}"; shift 2 ;;
    --ttl-sec) TTL_SEC="${2:-}"; shift 2 ;;
    --accept-polls) ACCEPT_POLLS="${2:-}"; shift 2 ;;
    --remote-user) REMOTE_USER="${2:-}"; shift 2 ;;
    --remote-host) REMOTE_HOST="${2:-}"; shift 2 ;;
    --remote-port) REMOTE_PORT="${2:-}"; shift 2 ;;
    --remote-url) REMOTE_URL="${2:-}"; shift 2 ;;
    --pass-file) PASS_FILE="${2:-}"; shift 2 ;;
    --local-setup) LOCAL_SETUP="${2:-}"; shift 2 ;;
    --help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

for cmd in expect node; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

if [[ ! -f "$PASS_FILE" ]]; then
  echo "Password file not found: $PASS_FILE" >&2
  exit 1
fi
if [[ ! -f "$LOCAL_SETUP" ]]; then
  echo "Local setup json not found: $LOCAL_SETUP" >&2
  exit 1
fi

PASS="$(sed -n '2p' "$PASS_FILE" | tr -d '\r\n')"
if [[ -z "$PASS" ]]; then
  echo "Password missing (expected on line 2): $PASS_FILE" >&2
  exit 1
fi
export PASS REMOTE_USER REMOTE_HOST REMOTE_PORT

tmpdir="$(mktemp -d /tmp/rfq-live-fast.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

ssh_expect_exec() {
  local remote_cmd="$1"
  export REMOTE_CMD="$remote_cmd"
  expect <<'EOF'
set timeout 60
set pass $env(PASS)
set user $env(REMOTE_USER)
set host $env(REMOTE_HOST)
set port $env(REMOTE_PORT)
set cmd  $env(REMOTE_CMD)
spawn ssh -o StrictHostKeyChecking=no -p $port $user@$host $cmd
expect {
  -re {(?i)password:} { send "$pass\r"; exp_continue }
  eof
}
EOF
}

fetch_remote_stream() {
  local channels="$1"
  local outfile="$2"
  ssh_expect_exec "curl -sN --max-time 12 '$REMOTE_URL/v1/sc/stream?limit=3000&channels=$channels'" \
    | sed -n '/^{"type":"sc_/,$p' \
    | tr -d '\r' \
    > "$outfile"
}

rfq_stream_file="$tmpdir/remote_rfq_stream.ndjson"
fetch_remote_stream "$CHANNEL" "$rfq_stream_file"

rfq_event_file="$tmpdir/latest_rfq_event.json"
node --input-type=module - <<'EOF'
import fs from 'node:fs';

const streamPath = process.env.RFQ_STREAM_FILE;
const outPath = process.env.RFQ_EVENT_FILE;
const targetTradeId = String(process.env.TARGET_TRADE_ID || '').trim();
const lines = fs.readFileSync(streamPath, 'utf8').split(/\n+/).filter(Boolean);
let best = null;
for (const line of lines) {
  let evt;
  try {
    evt = JSON.parse(line);
  } catch {
    continue;
  }
  const msg = evt?.message;
  if (!msg || msg.kind !== 'swap.rfq') continue;
  const tid = String(msg.trade_id || '').trim();
  if (!tid) continue;
  if (targetTradeId && tid !== targetTradeId) continue;
  best = evt;
}
if (!best) {
  const suffix = targetTradeId ? ` for trade_id=${targetTradeId}` : '';
  throw new Error(`No RFQ event found${suffix}`);
}
fs.writeFileSync(outPath, `${JSON.stringify(best)}\n`);
process.stdout.write(`${best.message.trade_id}\n`);
EOF
RFQ_STREAM_FILE="$rfq_stream_file" RFQ_EVENT_FILE="$rfq_event_file" TARGET_TRADE_ID="$TARGET_TRADE_ID" \
  | tee "$tmpdir/trade_id.txt"

TRADE_ID="$(tr -d '\r\n' < "$tmpdir/trade_id.txt")"
if [[ -z "$TRADE_ID" ]]; then
  echo "Failed to resolve trade id" >&2
  exit 1
fi
echo "RFQ trade_id=$TRADE_ID"

node --input-type=module - <<'EOF'
import fs from 'node:fs';
import { Keypair } from '@solana/web3.js';
import { ToolExecutor } from './src/prompt/executor.js';

const setupPath = process.env.LOCAL_SETUP;
const rfqEventPath = process.env.RFQ_EVENT_FILE;
const channel = process.env.CHANNEL;

const setup = JSON.parse(fs.readFileSync(setupPath, 'utf8'));
const rfqEvent = JSON.parse(fs.readFileSync(rfqEventPath, 'utf8').trim());
const rfqEnvelope = rfqEvent?.message;
if (!rfqEnvelope || rfqEnvelope.kind !== 'swap.rfq') throw new Error('Invalid RFQ envelope');

const tokenFile = String(setup?.sc_bridge?.token_file || '').trim();
const token = tokenFile ? fs.readFileSync(tokenFile, 'utf8').trim() : String(setup?.sc_bridge?.token || '').trim();
if (!token) throw new Error('Missing SC-Bridge token');

const makerSol = JSON.parse(fs.readFileSync('onchain/solana/mainnet/maker-keypair.json', 'utf8'));
const makerPub = Keypair.fromSecretKey(Uint8Array.from(makerSol)).publicKey.toBase58();

const ex = new ToolExecutor({
  scBridge: { url: setup.sc_bridge.url, token },
  peer: { keypairPath: setup.peer.keypair },
  ln: {
    impl: setup.ln.impl,
    backend: setup.ln.backend,
    network: setup.ln.network,
    composeFile: setup.ln.compose_file,
    service: setup.ln.service,
    cliBin: setup.ln.cli_bin,
    lnd: setup.ln.lnd,
  },
  solana: {
    rpcUrls: setup.solana.rpc_url,
    commitment: setup.solana.commitment || 'confirmed',
    programId: setup.solana.program_id,
    keypairPath: setup.solana.keypair,
    cuLimit: setup.solana.cu_limit ?? null,
    cuPrice: setup.solana.cu_price ?? null,
  },
  receipts: { dbPath: setup.receipts.db },
});

const out = await ex.execute(
  'intercomswap_quote_post_from_rfq',
  {
    channel,
    rfq_envelope: rfqEnvelope,
    trade_fee_collector: makerPub,
    valid_for_sec: 900,
  },
  { autoApprove: true, dryRun: false }
);

process.stdout.write(`${JSON.stringify({
  step: 'quote_posted',
  trade_id: out?.envelope?.trade_id,
  quote_id: out?.quote_id,
}, null, 2)}\n`);
EOF
LOCAL_SETUP="$LOCAL_SETUP" RFQ_EVENT_FILE="$rfq_event_file" CHANNEL="$CHANNEL"

accept_event_file="$tmpdir/latest_accept_event.json"
rm -f "$accept_event_file"

for _ in $(seq 1 "$ACCEPT_POLLS"); do
  accept_stream_file="$tmpdir/remote_accept_stream.ndjson"
  fetch_remote_stream "$CHANNEL" "$accept_stream_file"
  if ACCEPT_STREAM_FILE="$accept_stream_file" ACCEPT_EVENT_FILE="$accept_event_file" TRADE_ID="$TRADE_ID" node --input-type=module - <<'EOF'
import fs from 'node:fs';

const streamPath = process.env.ACCEPT_STREAM_FILE;
const outPath = process.env.ACCEPT_EVENT_FILE;
const tradeId = String(process.env.TRADE_ID || '').trim();
const lines = fs.readFileSync(streamPath, 'utf8').split(/\n+/).filter(Boolean);
let best = null;
for (const line of lines) {
  let evt;
  try {
    evt = JSON.parse(line);
  } catch {
    continue;
  }
  const msg = evt?.message;
  if (!msg || msg.kind !== 'swap.quote_accept') continue;
  if (String(msg.trade_id || '').trim() !== tradeId) continue;
  best = evt;
}
if (!best) process.exit(1);
fs.writeFileSync(outPath, `${JSON.stringify(best)}\n`);
process.exit(0);
EOF
  then
    echo "accept_found trade_id=$TRADE_ID"
    break
  fi
  sleep 1
done

if [[ ! -s "$accept_event_file" ]]; then
  echo "No matching swap.quote_accept found for trade_id=$TRADE_ID" >&2
  exit 1
fi

node --input-type=module - <<'EOF'
import fs from 'node:fs';
import { ToolExecutor } from './src/prompt/executor.js';

const setupPath = process.env.LOCAL_SETUP;
const acceptEventPath = process.env.ACCEPT_EVENT_FILE;
const channel = process.env.CHANNEL;
const welcomeText = process.env.WELCOME_TEXT;
const ttlSec = Number.parseInt(String(process.env.TTL_SEC || '1800'), 10);

const setup = JSON.parse(fs.readFileSync(setupPath, 'utf8'));
const acceptEvent = JSON.parse(fs.readFileSync(acceptEventPath, 'utf8').trim());
const acceptEnvelope = acceptEvent?.message;
if (!acceptEnvelope || acceptEnvelope.kind !== 'swap.quote_accept') throw new Error('Invalid quote_accept envelope');

const tokenFile = String(setup?.sc_bridge?.token_file || '').trim();
const token = tokenFile ? fs.readFileSync(tokenFile, 'utf8').trim() : String(setup?.sc_bridge?.token || '').trim();
if (!token) throw new Error('Missing SC-Bridge token');

const ex = new ToolExecutor({
  scBridge: { url: setup.sc_bridge.url, token },
  peer: { keypairPath: setup.peer.keypair },
  ln: {
    impl: setup.ln.impl,
    backend: setup.ln.backend,
    network: setup.ln.network,
    composeFile: setup.ln.compose_file,
    service: setup.ln.service,
    cliBin: setup.ln.cli_bin,
    lnd: setup.ln.lnd,
  },
  solana: {
    rpcUrls: setup.solana.rpc_url,
    commitment: setup.solana.commitment || 'confirmed',
    programId: setup.solana.program_id,
    keypairPath: setup.solana.keypair,
    cuLimit: setup.solana.cu_limit ?? null,
    cuPrice: setup.solana.cu_price ?? null,
  },
  receipts: { dbPath: setup.receipts.db },
});

const out = await ex.execute(
  'intercomswap_swap_invite_from_accept',
  {
    channel,
    accept_envelope: acceptEnvelope,
    welcome_text: welcomeText,
    ttl_sec: Number.isFinite(ttlSec) && ttlSec > 0 ? ttlSec : 1800,
  },
  { autoApprove: true, dryRun: false }
);

process.stdout.write(`${JSON.stringify({
  step: 'invite_posted',
  trade_id: out?.envelope?.trade_id,
  swap_channel: out?.swap_channel,
}, null, 2)}\n`);
EOF
LOCAL_SETUP="$LOCAL_SETUP" ACCEPT_EVENT_FILE="$accept_event_file" CHANNEL="$CHANNEL" WELCOME_TEXT="$WELCOME_TEXT" TTL_SEC="$TTL_SEC"

invite_stream_file="$tmpdir/remote_invite_stream.ndjson"
fetch_remote_stream "$CHANNEL" "$invite_stream_file"

INVITE_STREAM_FILE="$invite_stream_file" TRADE_ID="$TRADE_ID" node --input-type=module - <<'EOF'
import fs from 'node:fs';

const streamPath = process.env.INVITE_STREAM_FILE;
const tradeId = String(process.env.TRADE_ID || '').trim();
const lines = fs.readFileSync(streamPath, 'utf8').split(/\n+/).filter(Boolean);
let best = null;
for (const line of lines) {
  let evt;
  try {
    evt = JSON.parse(line);
  } catch {
    continue;
  }
  const msg = evt?.message;
  if (!msg || msg.kind !== 'swap.swap_invite') continue;
  if (String(msg.trade_id || '').trim() !== tradeId) continue;
  best = evt;
}
if (!best) throw new Error(`Invite not found on remote for trade_id=${tradeId}`);
process.stdout.write(`${JSON.stringify({
  step: 'invite_confirmed_remote',
  trade_id: tradeId,
  swap_channel: best?.message?.body?.swap_channel || null,
  seq: best?.seq ?? null,
}, null, 2)}\n`);
EOF
