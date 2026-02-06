import b4a from 'b4a';
import { bech32 } from 'bech32';

// Bech32 charset (BIP-0173). BOLT11 tag identifiers are encoded as these 5-bit values.
const BECH32_CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

function wordsToBigInt(words) {
  let n = 0n;
  for (const w of words) n = (n << 5n) + BigInt(w);
  return n;
}

function parseHrpAmountMsat(hrp) {
  if (typeof hrp !== 'string' || !hrp.startsWith('ln')) throw new Error('Invalid HRP');
  // HRP is `ln` + currency + amount, where amount starts at the first digit (if any).
  let i = 2;
  while (i < hrp.length) {
    const ch = hrp[i];
    if (ch >= '0' && ch <= '9') break;
    i += 1;
  }
  const currency = hrp.slice(2, i);
  const amountPart = hrp.slice(i);
  if (!amountPart) return { currency, amountMsat: null };

  const m = amountPart.match(/^([0-9]+)([munp]?)$/);
  if (!m) throw new Error('Invalid amount in HRP');
  const digits = BigInt(m[1]);
  const unit = m[2] || '';

  // 1 BTC = 100_000_000 sats = 100_000_000_000 millisats.
  // Multipliers:
  // - m = 10^-3 BTC  -> factor 100_000_000 msat
  // - u = 10^-6 BTC  -> factor 100_000 msat
  // - n = 10^-9 BTC  -> factor 100 msat
  // - p = 10^-12 BTC -> factor 0.1 msat (so must be divisible by 10)
  switch (unit) {
    case '':
      return { currency, amountMsat: digits * 100_000_000_000n };
    case 'm':
      return { currency, amountMsat: digits * 100_000_000n };
    case 'u':
      return { currency, amountMsat: digits * 100_000n };
    case 'n':
      return { currency, amountMsat: digits * 100n };
    case 'p': {
      if (digits % 10n !== 0n) throw new Error('Invalid pico amount (not a whole millisat)');
      return { currency, amountMsat: digits / 10n };
    }
    default:
      throw new Error('Unsupported amount unit');
  }
}

function decodeTagChar(tagWord) {
  const ch = BECH32_CHARSET[tagWord];
  if (!ch) throw new Error('Invalid tag');
  return ch;
}

function bytesToHex(bytes) {
  return b4a.toString(b4a.from(bytes), 'hex');
}

export function decodeBolt11(bolt11) {
  if (typeof bolt11 !== 'string' || bolt11.trim().length === 0) throw new Error('bolt11 is required');
  const text = bolt11.trim().toLowerCase();

  let decoded;
  try {
    decoded = bech32.decode(text, 1500);
  } catch (_e) {
    throw new Error('Invalid bech32 invoice');
  }

  const hrp = decoded.prefix;
  const { currency, amountMsat } = parseHrpAmountMsat(hrp);

  const words = decoded.words || [];
  const signatureWords = 104; // 65-byte sig = 520 bits = 104x5-bit words
  if (words.length < 7 + signatureWords) throw new Error('Invoice too short');

  const timestampUnix = Number(wordsToBigInt(words.slice(0, 7)));
  if (!Number.isFinite(timestampUnix) || timestampUnix <= 0) throw new Error('Invalid invoice timestamp');

  const end = words.length - signatureWords;
  let idx = 7;
  let paymentHashHex = null;
  let expirySeconds = 3600; // default per BOLT11

  while (idx < end) {
    if (idx + 3 > end) throw new Error('Truncated tagged field header');
    const tagWord = words[idx];
    const tag = decodeTagChar(tagWord);
    const dataLen = (words[idx + 1] << 5) + words[idx + 2]; // length in 5-bit words
    idx += 3;
    if (idx + dataLen > end) throw new Error('Truncated tagged field data');
    const dataWords = words.slice(idx, idx + dataLen);
    idx += dataLen;

    if (tag === 'p') {
      const bytes = bech32.fromWords(dataWords);
      paymentHashHex = bytesToHex(bytes);
    } else if (tag === 'x') {
      const n = wordsToBigInt(dataWords);
      if (n > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('Expiry too large');
      expirySeconds = Number(n);
    }
  }

  const expiresAtUnix = timestampUnix + expirySeconds;

  return {
    hrp,
    currency,
    amount_msat: amountMsat,
    timestamp_unix: timestampUnix,
    payment_hash_hex: paymentHashHex,
    expiry_seconds: expirySeconds,
    expires_at_unix: expiresAtUnix,
  };
}

export function verifyBolt11MatchesInvoiceBody({ bolt11, payment_hash_hex, amount_msat, expires_at_unix }) {
  let decoded;
  try {
    decoded = decodeBolt11(bolt11);
  } catch (err) {
    return { ok: false, error: err?.message ?? String(err), decoded: null };
  }

  const wantHash = payment_hash_hex ? String(payment_hash_hex).trim().toLowerCase() : null;
  if (wantHash && decoded.payment_hash_hex && decoded.payment_hash_hex !== wantHash) {
    return { ok: false, error: 'bolt11 payment_hash mismatch', decoded };
  }

  if (amount_msat !== undefined && amount_msat !== null && decoded.amount_msat !== null) {
    const want = BigInt(String(amount_msat));
    if (decoded.amount_msat !== want) {
      return { ok: false, error: 'bolt11 amount mismatch', decoded };
    }
  }

  if (expires_at_unix !== undefined && expires_at_unix !== null) {
    const wantExp = Number(expires_at_unix);
    if (!Number.isFinite(wantExp)) return { ok: false, error: 'invalid expires_at_unix', decoded };
    if (decoded.expires_at_unix !== wantExp) {
      return { ok: false, error: 'bolt11 expires_at_unix mismatch', decoded };
    }
  }

  return { ok: true, error: null, decoded };
}

