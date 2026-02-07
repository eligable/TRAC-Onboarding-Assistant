# Intercom Swap (Fork)

This repo is a fork of upstream **Intercom** and adds a non-custodial swap harness:

- Negotiate via **Intercom sidechannels** (P2P).
- Settle **BTC over Lightning** <> **USDT on Solana** using a shared Solana escrow program (HTLC-style).

Links:
- Upstream Intercom: `https://github.com/Trac-Systems/intercom`
- This fork: `https://github.com/TracSystems/intercom-swap`

---

## What Intercom Is (Upstream)

Intercom is a Trac stack for autonomous agents:
- **Sidechannels**: fast, ephemeral P2P messaging (Hyperswarm + Noise).
- **Features**: integrate non-agent services/tools into the same network.
- **Contracts (optional)**: deterministic state + optional chat.
- **MSB (optional)**: value-settled transactions.

This fork keeps Intercom intact and layers swap + ops tooling on top.

---

## Install And Operate From `SKILL.md`

`SKILL.md` is the canonical **installer + runbook** for this repo. If you are an agent, treat it as the source of truth for:
- installation steps
- runtime requirements (Pear, Node)
- first-run decisions (sidechannels, invites, PoW)
- operations (LN/Solana, recovery, tests)

### Recommended Models (For Install/Upgrades)

Installation and large merges are easiest with a top-tier coding model.

Recommended:
- OpenAI: **GPT-5.3+** (Codex, `xhigh`)
- Anthropic: **Claude Opus 4.6+**

Local/open-weight models can work too, but use a high-grade one (aim for at least an "M2-class" model or better, and always run the full test suite):
- Moonshot: **Kimi K2.5+**
- MiniMax: **MiniMax-M2.1+**
- Any comparable-or-stronger model is fine

Note: “M2” is a MiniMax model family name; Moonshot Kimi uses the K2/K2.5 naming.

---

## How To Use `SKILL.md` With An Agent

Example prompts (copy/paste):

1. Install
```text
Install this repo using SKILL.md. Run all tests (unit + e2e). Report what you ran and any failures.
```

2. Install + staging tests
```text
Install this repo using SKILL.md. Run unit + local e2e. Then run a smoke test on test networks (LN signet + Solana devnet) if supported. Report results.
```

3. Update workflow
```text
Pull the latest version of this fork, resolve merge conflicts, and run all tests (unit + e2e). If testnet smoke tests exist, run them too. Only then proceed to mainnet checks.
```

---

## Conceptual Flow (BTC(LN) <> USDT(Solana))

```text
Rendezvous (directory only)                      Trade negotiation
0000intercom                                     0000intercomswapbtcusdt
    |                                                   |
    | (svc_announce: "I swap BTC<->USDT")               |  RFQ -> QUOTE -> QUOTE_ACCEPT
    |                                                   v
    +----------------------------------------------> per-trade invite
                                                     swap:<trade_id> (invite-only)
                                                         |
                                                         |  TERMS (includes fees, mint, refund timeout)
                                                         |  ACCEPT
                                                         |  LN_INVOICE (payment_hash)
                                                         |  SOL_ESCROW_CREATED (escrow PDA + vault)
                                                         v
Settlement
  1) Maker creates LN invoice and Solana escrow keyed by payment_hash
  2) Taker verifies escrow on-chain (hard rule: no escrow, no pay)
  3) Taker pays LN invoice -> learns preimage
  4) Taker claims USDT on Solana using preimage
  5) Refund path after timeout if LN payment never happens
```

---

## Command Surface (Scripts = "Function Calls")

After installation, day-to-day operation should be done by invoking scripts (macOS/Linux `.sh`, Windows `.ps1`). The `.mjs` files are the canonical CLIs; wrappers exist to keep invocation stable and tool-call friendly.

### Script Index

| Area | macOS/Linux | Windows | Canonical | Purpose |
|---|---|---|---|---|
| Bootstrap | `scripts/bootstrap.sh` | n/a | bash | Install Pear runtime + deps |
| Start peer (maker/service) | `scripts/run-swap-maker.sh` | `scripts/run-swap-maker.ps1` | shell | Start a peer with SC-Bridge + price oracle and join an OTC channel |
| Start peer (taker/client) | `scripts/run-swap-taker.sh` | `scripts/run-swap-taker.ps1` | shell | Start a peer with SC-Bridge + price oracle and join an OTC channel; pins `SWAP_INVITER_KEYS` for `swap:*` |
| SC-Bridge control | `scripts/swapctl.sh` | `scripts/swapctl.ps1` | `scripts/swapctl.mjs` | Sidechannel ops + signed message helpers |
| SC-Bridge control (token auto) | `scripts/swapctl-peer.sh` | `scripts/swapctl-peer.ps1` | wrapper | Same as `swapctl`, but reads token from `onchain/sc-bridge/<store>.token` |
| OTC maker bot | `scripts/otc-maker-peer.sh` | `scripts/otc-maker-peer.ps1` | `scripts/otc-maker.mjs` | Quote RFQs; optionally run full swap state machine |
| OTC taker bot | `scripts/otc-taker-peer.sh` | `scripts/otc-taker-peer.ps1` | `scripts/otc-taker.mjs` | Send RFQ; accept quote; optionally run full swap state machine |
| Recovery | `scripts/swaprecover.sh` | `scripts/swaprecover.ps1` | `scripts/swaprecover.mjs` | List/show receipts; claim/refund escrows |
| Solana wallet ops | `scripts/solctl.sh` | `scripts/solctl.ps1` | `scripts/solctl.mjs` | Keypairs, balances, ATA, token transfers |
| Solana escrow ops | `scripts/escrowctl.sh` | `scripts/escrowctl.ps1` | `scripts/escrowctl.mjs` | Program config, fee vaults, escrow inspection |
| Solana program ops (maintainers) | `scripts/solprogctl.sh` | `scripts/solprogctl.ps1` | `scripts/solprogctl.mjs` | Build/deploy the Solana program |
| Lightning ops | `scripts/lnctl.sh` | `scripts/lnctl.ps1` | `scripts/lnctl.mjs` | Addresses, channels, invoices, payments |
| LND local lifecycle (optional) | `scripts/lndctl.sh` | `scripts/lndctl.ps1` | `scripts/lndctl.mjs` | Generate `lnd.conf`, start/stop, create/unlock wallet |
| LND password helper (optional) | `scripts/lndpw.sh` | `scripts/lndpw.ps1` | shell | Write an LND wallet password file (no trailing newline) |

---

### Start Intercom Peers (`run-swap-*`)

| Function call | What it does | Parameters |
|---|---|---|
| `scripts/run-swap-maker.sh [storeName] [scBridgePort] [otcChannel] [...extra peer flags]` | Starts a maker/service peer, enables SC-Bridge + price oracle, joins the OTC channel | Positional args; optional env: `SIDECHANNEL_POW` (default `1`), `SIDECHANNEL_POW_DIFFICULTY` (default `12`) |
| `SWAP_INVITER_KEYS="<makerPeerPubkeyHex[,more]>" scripts/run-swap-taker.sh [storeName] [scBridgePort] [otcChannel] [...extra peer flags]` | Starts a taker/client peer and pins inviter key(s) for `swap:*` invite-only channels | Requires `SWAP_INVITER_KEYS`; same optional env vars as maker |

Notes:
| Item | Details |
|---|---|
| Token files | Created under `onchain/sc-bridge/<storeName>.token` (gitignored). |
| OTC channel | Any channel works. Use a dedicated rendezvous like `0000intercomswapbtcusdt` for trading, and keep `0000intercom` for service presence only. |

---

### SC-Bridge Control (`swapctl`)

`swapctl` is the "tool RPC" interface into a running peer via SC-Bridge.

Global connection flags (required for `scripts/swapctl.sh ...` / `scripts/swapctl.ps1 ...`):
| Flag | Meaning |
|---|---|
| `--url ws://127.0.0.1:<scPort>` | SC-Bridge websocket URL |
| `--token <hex>` | SC-Bridge token (from `onchain/sc-bridge/<store>.token`) |

Token convenience wrapper:
| Wrapper | Parameters | What it does |
|---|---|---|
| `scripts/swapctl-peer.sh <storeName> <scPort> <swapctl command...>` | `storeName`, `scPort`, then any `swapctl` args | Reads token from `onchain/sc-bridge/<storeName>.token` and calls `swapctl` |

Introspection:
| Function call | What it does | Parameters |
|---|---|---|
| `info` | Peer info (pubkey, joined channels, SC-Bridge status) | none |
| `stats` | Peer runtime stats | none |
| `price-get` | Current price snapshot from the price feature | none |
| `watch` | Stream messages for debugging/observability | Optional: `--channels <a,b,c>`, `--kinds <k1,k2>`, `--trade-id <id>`, `--pretty 0|1`, `--raw 0|1` |

Sidechannel I/O:
| Function call | What it does | Parameters |
|---|---|---|
| `join` | Join a sidechannel | Required: `--channel <name>`; optional: `--invite <b64|json|@file>`, `--welcome <b64|json|@file>` |
| `leave` | Leave a sidechannel | Required: `--channel <name>` |
| `open` | Request others to open a channel (via the entry channel) | Required: `--channel <name>`, `--via <entryChannel>`; optional: `--invite <...>`, `--welcome <...>` |
| `send` | Send plaintext or JSON to a channel | Required: `--channel <name>` and either `--text <msg>` or `--json <obj|@file>`; optional: `--invite <b64|json|@file>`, `--welcome <b64|json|@file>` |

Service presence ("directory beacon"):
| Function call | What it does | Parameters |
|---|---|---|
| `svc-announce` | Broadcast a signed service announcement | Required: `--channels <a,b,c>`, `--name <label>`; optional: `--pairs <p1,p2>`, `--otc-channels <a,b,c>`, `--note <text>`, `--offers-json <json|@file>`, `--trade-id <id>`, `--ttl-sec <sec>`, `--join 0|1` |
| `svc-announce-loop` | Periodically re-broadcast announcements (sidechannels have no history) | Required: `--channels <a,b,c>`, `--config <json|@file>`; optional: `--interval-sec <sec>`, `--watch 0|1`, `--ttl-sec <sec>`, `--trade-id <id>`, `--join 0|1` |

Invite and welcome helpers (owner-signed):
| Function call | What it does | Parameters |
|---|---|---|
| `make-welcome` | Create a signed welcome payload | Required: `--channel <name>`, `--text <welcomeText>` |
| `make-invite` | Create a signed invite payload | Required: `--channel <name>`, `--invitee-pubkey <hex32>`; optional: `--ttl-sec <sec>`, `--welcome <b64|json|@file>` |

Swap message helpers (signed swap envelopes):
| Function call | What it does | Parameters |
|---|---|---|
| `rfq` | Send RFQ to an OTC channel | Required: `--channel <otcChannel>`, `--trade-id <id>`, `--btc-sats <n>`, `--usdt-amount <atomicStr>`; optional: `--valid-until-unix <sec>` |
| `quote` | Send quote | Required: `--channel <otcChannel>`, `--trade-id <id>`, `--rfq-id <id>`, `--btc-sats <n>`, `--usdt-amount <atomicStr>`, `--valid-until-unix <sec>` |
| `quote-from-rfq` | Build + send a quote from an RFQ envelope | Required: `--channel <otcChannel>`, `--rfq-json <envelope|@file>`; optional: `--btc-sats <n>`, `--usdt-amount <atomicStr>`, `--valid-until-unix <sec>` |
| `quote-accept` | Accept a quote | Required: `--channel <otcChannel>`, `--quote-json <envelope|@file>` |
| `swap-invite-from-accept` | Create and send a `swap:<trade_id>` invite after acceptance | Required: `--channel <otcChannel>`, `--accept-json <envelope|@file>`; optional: `--swap-channel <name>`, `--welcome-text <text>`, `--ttl-sec <sec>` |
| `join-from-swap-invite` | Join a swap channel using a swap-invite envelope | Required: `--swap-invite-json <envelope|@file>` |
| `terms` | Send swap terms into `swap:<id>` | Required: `--channel <swapChannel>`, `--trade-id <id>`, `--btc-sats <n>`, `--usdt-amount <atomicStr>`, `--sol-mint <base58>`, `--sol-recipient <base58>`, `--sol-refund <base58>`, `--sol-refund-after-unix <sec>`, `--ln-receiver-peer <hex32>`, `--ln-payer-peer <hex32>`, `--platform-fee-bps <n>`, `--trade-fee-bps <n>`, `--trade-fee-collector <base58>`; optional: `--platform-fee-collector <base58>`, `--terms-valid-until-unix <sec>` |
| `accept` | Accept swap terms | Required: `--channel <swapChannel>`, `--trade-id <id>`, and either `--terms-hash <hex>` or `--terms-json <envelope|body|@file>` |

Pre-pay verification helper:
| Function call | What it does | Parameters |
|---|---|---|
| `verify-prepay` | Validate terms/invoice/escrow match, and optionally validate escrow on-chain | Required: `--terms-json <envelope|body|@file>`, `--invoice-json <envelope|body|@file>`, `--escrow-json <envelope|body|@file>`; optional: `--now-unix <sec>`, `--solana-rpc-url <url[,url2,...]>`, `--solana-commitment <confirmed|finalized|processed>` |

---

### OTC Bots (`otc-maker` / `otc-taker`)

These are long-running bots that sit in an OTC channel and negotiate RFQ/quotes. With `--run-swap 1` they run the full swap state machine inside an invite-only `swap:<trade_id>` channel.

Maker bot wrapper:
| Function call | What it does | Parameters |
|---|---|---|
| `scripts/otc-maker-peer.sh <storeName> <scPort> [...flags]` | Runs the maker OTC bot against a running peer | Reads token from `onchain/sc-bridge/<storeName>.token`; forwards flags to `otc-maker.mjs` |

Taker bot wrapper:
| Function call | What it does | Parameters |
|---|---|---|
| `scripts/otc-taker-peer.sh <storeName> <scPort> [...flags]` | Runs the taker OTC bot against a running peer | Reads token from `onchain/sc-bridge/<storeName>.token`; forwards flags to `otc-taker.mjs` |

Maker bot flags (`scripts/otc-maker.mjs`):
| Flag | Meaning |
|---|---|
| `--otc-channel <name>` | OTC rendezvous channel (default `0000intercomswapbtcusdt`) |
| `--swap-channel-template <tmpl>` | Swap channel name template (default `swap:{trade_id}`) |
| `--quote-valid-sec <n>` | Quote validity window (default `60`) |
| `--invite-ttl-sec <n>` | Invite TTL (default `604800`) |
| `--once 0|1` | Exit after one completed swap (default `0`) |
| `--debug 0|1` | Verbose logs (default `0`) |
| `--receipts-db <path>` | Receipts DB path (recommended: `onchain/receipts/<name>.sqlite`) |
| `--price-guard 0|1` | Fail-closed quoting based on oracle (default `1`) |
| `--price-max-age-ms <n>` | Reject stale snapshots (default `15000`) |
| `--maker-spread-bps <n>` | Quote spread vs oracle (default `0`) |
| `--maker-max-overpay-bps <n>` | If RFQ requests a favorable price for maker, accept it up to this cap (default `0`) |
| `--run-swap 0|1` | Execute the full swap state machine (default `0`) |
| `--swap-timeout-sec <n>` | Per-swap timeout (default `300`) |
| `--swap-resend-ms <n>` | Proof resend interval (default `1200`) |
| `--terms-valid-sec <n>` | Terms validity window (default `300`) |
| `--solana-refund-after-sec <n>` | Solana refund timelock from terms send time (default `3600`) |
| `--solana-rpc-url <url[,url2,...]>` | Solana RPC pool (default `http://127.0.0.1:8899`) |
| `--solana-keypair <path>` | Maker Solana keypair (required when `--run-swap 1`) |
| `--solana-mint <pubkey>` | SPL mint for escrow (required when `--run-swap 1`) |
| `--solana-decimals <n>` | Mint decimals (default `6` for mainnet USDT) |
| `--solana-program-id <pubkey>` | Override program id (defaults to the compiled-in shared program id) |
| `--solana-cu-limit <units>` | Optional compute unit limit |
| `--solana-cu-price <microLamports>` | Optional priority fee |
| `--solana-trade-fee-collector <pubkey>` | Which trade-fee config PDA to use (defaults to platform fee collector) |
| `--ln-impl <cln|lnd>` | Lightning implementation (default `cln`) |
| `--ln-backend <docker|cli>` | Lightning backend (default `docker`) |
| `--ln-compose-file <path>` | Docker compose file (default `dev/ln-regtest/docker-compose.yml`) |
| `--ln-service <name>` | Docker service name (required when `--ln-backend docker`) |
| `--ln-network <regtest|signet|mainnet|...>` | Lightning network (default `regtest`) |
| `--ln-cli-bin <path>` | CLI binary override (for `--ln-backend cli`) |
| `--lnd-rpcserver <host:port>` | LND CLI backend (optional; for `--ln-impl lnd --ln-backend cli`) |
| `--lnd-tlscert <path>` | LND TLS cert (optional; for `--ln-backend cli`) |
| `--lnd-macaroon <path>` | LND macaroon (optional; for `--ln-backend cli`) |
| `--lnd-dir <path>` | LND dir (optional; for `--ln-backend cli`) |

Taker bot flags (`scripts/otc-taker.mjs`):
| Flag | Meaning |
|---|---|
| `--trade-id <id>` | Trade id (default random) |
| `--otc-channel <name>` | OTC rendezvous channel (default `0000intercomswapbtcusdt`) |
| `--btc-sats <n>` | Sats requested (default `50000`) |
| `--usdt-amount <atomicStr>` | USDT requested; `0` means "open RFQ" (maker will quote via oracle) |
| `--rfq-valid-sec <n>` | RFQ validity window (default `60`) |
| `--timeout-sec <n>` | RFQ/quote negotiation timeout (default `30`) |
| `--rfq-resend-ms <n>` | RFQ resend interval (default `1200`) |
| `--accept-resend-ms <n>` | Quote accept resend interval (default `1200`) |
| `--once 0|1` | Exit after one completed swap (default `0`) |
| `--debug 0|1` | Verbose logs (default `0`) |
| `--receipts-db <path>` | Receipts DB path (recommended: `onchain/receipts/<name>.sqlite`) |
| `--persist-preimage 0|1` | Persist `ln_preimage_hex` into receipts (default `1` when receipts enabled) |
| `--stop-after-ln-pay 0|1` | Testing/recovery hook: stop after paying LN (default `0`) |
| `--price-guard 0|1` | Fail-closed quoting based on oracle (default `1`) |
| `--price-max-age-ms <n>` | Reject stale snapshots (default `15000`) |
| `--taker-max-discount-bps <n>` | Reject quotes discounted beyond this vs oracle median (default `200`) |
| `--run-swap 0|1` | Execute the full swap state machine (default `0`) |
| `--swap-timeout-sec <n>` | Per-swap timeout (default `300`) |
| `--swap-resend-ms <n>` | Proof resend interval (default `1200`) |
| `--solana-rpc-url <url[,url2,...]>` | Solana RPC pool (default `http://127.0.0.1:8899`) |
| `--solana-keypair <path>` | Taker Solana keypair (required when `--run-swap 1`) |
| `--solana-mint <pubkey>` | SPL mint for escrow (required when `--run-swap 1`) |
| `--solana-decimals <n>` | Mint decimals (default `6`) |
| `--solana-cu-limit <units>` | Optional compute unit limit |
| `--solana-cu-price <microLamports>` | Optional priority fee |
| `--ln-impl <cln|lnd>` | Lightning implementation (default `cln`) |
| `--ln-backend <docker|cli>` | Lightning backend (default `docker`) |
| `--ln-compose-file <path>` | Docker compose file (default `dev/ln-regtest/docker-compose.yml`) |
| `--ln-service <name>` | Docker service name (required when `--ln-backend docker`) |
| `--ln-network <regtest|signet|mainnet|...>` | Lightning network (default `regtest`) |
| `--ln-cli-bin <path>` | CLI binary override (for `--ln-backend cli`) |
| `--lnd-rpcserver <host:port>` | LND CLI backend (optional; for `--ln-impl lnd --ln-backend cli`) |
| `--lnd-tlscert <path>` | LND TLS cert (optional; for `--ln-backend cli`) |
| `--lnd-macaroon <path>` | LND macaroon (optional; for `--ln-backend cli`) |
| `--lnd-dir <path>` | LND dir (optional; for `--ln-backend cli`) |

---

### Recovery (`swaprecover`)

Global flags:
| Flag | Meaning |
|---|---|
| `--receipts-db <path>` | Receipts DB (SQLite; should live under `onchain/`) |

Commands:
| Function call | What it does | Parameters |
|---|---|---|
| `list` | List trades in receipts | Optional: `--limit <n>` |
| `show` | Show one trade | Requires one of: `--trade-id <id>`, `--payment-hash <hex32>` |
| `claim` | Claim Solana escrow if LN was paid but agent crashed | Requires: `--solana-rpc-url <csv>`, `--solana-keypair <path>`, and one of: `--trade-id <id>`, `--payment-hash <hex32>` |
| `refund` | Refund Solana escrow after timeout | Requires: `--solana-rpc-url <csv>`, `--solana-keypair <path>`, and one of: `--trade-id <id>`, `--payment-hash <hex32>` |

---

### Solana Wallet Tooling (`solctl`)

Global flags:
| Flag | Meaning |
|---|---|
| `--rpc-url <url[,url2,...]>` | RPC pool (default `http://127.0.0.1:8899`) |
| `--commitment <processed|confirmed|finalized>` | Commitment (default `confirmed`) |

Commands:
| Function call | What it does | Parameters |
|---|---|---|
| `keygen` | Create a keypair | Required: `--out <path>`; optional: `--seed-hex <hex32>`, `--force 0|1` |
| `address` | Print pubkey | Required: `--keypair <path>` |
| `balance` | SOL balance | Required: `--keypair <path>` |
| `airdrop` | Devnet/testnet airdrop | Required: `--keypair <path>`, `--sol <n>` |
| `transfer-sol` | Send SOL | Required: `--keypair <path>`, `--to <pubkey>`, `--sol <n>` |
| `mint-create` | Create a test mint | Required: `--keypair <path>`, `--decimals <n>`; optional: `--out <path>` |
| `mint-info` | Inspect mint | Required: `--mint <pubkey>` |
| `token-ata` | Print or create ATA | Required: `--keypair <path>`, `--mint <pubkey>`; optional: `--owner <pubkey>`, `--create 0|1` |
| `token-balance` | SPL token balance | Required: `--keypair <path>`, `--mint <pubkey>`; optional: `--owner <pubkey>` |
| `token-transfer` | Transfer SPL tokens | Required: `--keypair <path>`, `--mint <pubkey>`, `--to <pubkey>`, `--amount <u64>`; optional: `--create-ata 0|1` |
| `mint-to` | Mint test tokens | Required: `--keypair <path>`, `--mint <pubkey>`, `--to <pubkey>`, `--amount <u64>`; optional: `--create-ata 0|1` |
| `inventory` | Print balances across mints | Required: `--keypair <path>`; optional: `--mints <csvPubkeys>` |

---

### Solana Escrow Program Tooling (`escrowctl`)

Global flags:
| Flag | Meaning |
|---|---|
| `--solana-rpc-url <url[,url2,...]>` | RPC pool (default `http://127.0.0.1:8899`) |
| `--commitment <processed|confirmed|finalized>` | Commitment (default `confirmed`) |
| `--program-id <base58>` | Override program id (default is the shared program id compiled into the client) |
| `--solana-cu-limit <units>` | Optional compute unit limit |
| `--solana-cu-price <microLamports>` | Optional priority fee |
| `--solana-keypair <path>` | Required for signing commands (`config-init`, `config-set`, withdrawals, trade config init/set) |

Commands:
| Function call | What it does | Parameters |
|---|---|---|
| `config-get` | Read platform config | none |
| `config-init` | Initialize platform fee config | Required: `--fee-bps <n>`; optional: `--fee-collector <pubkey>`, `--simulate 0|1` |
| `config-set` | Update platform fee config | Required: `--fee-bps <n>`; optional: `--fee-collector <pubkey>`, `--simulate 0|1` |
| `fees-balance` | Platform fee vault balance | Required: `--mint <pubkey>` |
| `fees-withdraw` | Withdraw platform fees | Required: `--mint <pubkey>`; optional: `--amount <u64>`, `--create-ata 0|1`, `--simulate 0|1` |
| `trade-config-get` | Read trade fee config | Required: `--fee-collector <pubkey>` |
| `trade-config-init` | Initialize trade fee config | Required: `--fee-bps <n>`; optional: `--fee-collector <pubkey>`, `--simulate 0|1` |
| `trade-config-set` | Update trade fee config | Required: `--fee-bps <n>`; optional: `--fee-collector <pubkey>`, `--simulate 0|1` |
| `trade-fees-balance` | Trade fee vault balance | Required: `--fee-collector <pubkey>`, `--mint <pubkey>` |
| `trade-fees-withdraw` | Withdraw trade fees (for the signer fee collector) | Required: `--mint <pubkey>`; optional: `--amount <u64>`, `--create-ata 0|1`, `--simulate 0|1` |
| `escrow-get` | Inspect escrow state | Required: `--payment-hash <hex32>` |

---

### Solana Program Build/Deploy (`solprogctl`) (Maintainers Only)

Commands:
| Function call | What it does | Parameters |
|---|---|---|
| `id` | Print the program id used by the codebase | none |
| `build` | Build the SBF program | none (requires Rust + Solana CLI toolchain) |
| `deploy` | Deploy/upgrade the program | Required: `--rpc-url <url>`, `--payer <keypair.json>`, `--program-keypair <keypair.json>`; optional: `--upgrade-authority <keypair.json>`, `--so <path>`, `--dry-run 0|1` |
| `keypair-pubkey` | Print a program pubkey from a keypair file | Required: `--program-keypair <keypair.json>` |

---

### Lightning Operator Tooling (`lnctl`)

Global flags:
| Flag | Meaning |
|---|---|
| `--impl <cln|lnd>` | Implementation (default `cln`) |
| `--backend <cli|docker>` | Backend (default `cli`) |
| `--network <bitcoin|mainnet|testnet|regtest|signet>` | Network (default `regtest`) |
| `--compose-file <path>` | Docker backend compose (default `dev/ln-regtest/docker-compose.yml`) |
| `--service <name>` | Docker service name (required for docker backend) |
| `--cli-bin <path>` | CLI binary override |
| `--lnd-rpcserver <host:port>` | LND CLI backend extra |
| `--lnd-tlscert <path>` | LND CLI backend extra |
| `--lnd-macaroon <path>` | LND CLI backend extra |
| `--lnd-dir <path>` | LND CLI backend extra |

Commands:
| Function call | What it does | Parameters |
|---|---|---|
| `info` | Node info | none |
| `newaddr` | New on-chain address | none |
| `listfunds` | Wallet + channel balances | none |
| `balance` | Alias of listfunds wallet balance | none |
| `connect` | Connect to a peer | Required: `--peer <nodeid@host:port>` |
| `fundchannel` | Open a channel | Required: `--node-id <hex>`, `--amount-sats <n>` |
| `invoice` | Create invoice | Required: `--msat <amountmsat>`, `--label <label>`, `--desc <text>`; optional: `--expiry <sec>` |
| `decodepay` | Decode a BOLT11 invoice | Required: `--bolt11 <invoice>` |
| `pay` | Pay invoice | Required: `--bolt11 <invoice>` |
| `pay-status` | Payment status | Required: `--payment-hash <hex32>` |
| `preimage-get` | Preimage lookup (for recovery) | Required: `--payment-hash <hex32>` |

---

### Optional LND Local Lifecycle (`lndctl` / `lndpw`)

This is only for running LND from a local directory under `onchain/` (not required if you use the docker deployments in `dev/`).

LND lifecycle (`lndctl`):
| Function call | What it does | Parameters |
|---|---|---|
| `init` | Generate an `lnd.conf` | Required: `--node <name>`; optional: `--network <mainnet|testnet|signet|regtest>`, `--lnd-dir <path>`, `--alias <str>`, `--p2p-port <n>`, `--rpc-port <n>`, `--rest-port <n>`, `--bitcoin-node <neutrino|bitcoind>`, `--neutrino-peers <host:port[,..]>`, `--wallet-password-file <path>` |
| `start` | Start `lnd` | Required: `--node <name>`; optional: `--network <...>`, `--lnd-dir <path>`, `--lnd-bin <path>` |
| `stop` | Stop `lnd` | Required: `--node <name>`; optional: `--network <...>`, `--lnd-dir <path>`, `--lncli-bin <path>` |
| `create-wallet` | Create wallet (interactive) | Required: `--node <name>`; optional: `--network <...>`, `--lnd-dir <path>`, `--lncli-bin <path>` |
| `unlock` | Unlock wallet (interactive) | Required: `--node <name>`; optional: `--network <...>`, `--lnd-dir <path>`, `--lncli-bin <path>` |
| `paths` | Print TLS/macaroon paths | Required: `--node <name>`; optional: `--network <...>`, `--lnd-dir <path>` |

Wallet password helper (`lndpw`):
| Function call | What it does | Parameters |
|---|---|---|
| `scripts/lndpw.sh <outFile>` | Writes a password file (no trailing newline) | Positional: `<outFile>` (example: `onchain/lnd/mainnet/maker/wallet.pw`) |

---

## Prompt Router (Planned)

Not implemented yet: a small “prompt router” layer that converts high-level prompts into the script invocations above (with full parameterization and guardrails). The intention is:
- Use a top-tier model to install/upgrade and generate safe scripts/configs.
- After install, run day-to-day operations via tool calls (scripts) so a smaller model (or humans/programs) can operate the system reliably.

---

## Tests (Mandatory)

Run all tests after changes:
```bash
npm test
npm run test:e2e
```

---

## Secrets + Repo Hygiene

- `onchain/` contains local wallets, node data, tokens, and other secrets/runtime state and must never be committed.
- `progress.md` is a local handoff log and is gitignored.
