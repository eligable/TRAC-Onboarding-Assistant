import test from 'node:test';
import assert from 'node:assert/strict';

import { decodeBolt11, verifyBolt11MatchesInvoiceBody } from '../src/ln/bolt11.js';

test('bolt11: decodes payment_hash + amount', () => {
  // Generated locally via CLN regtest (`lightning-cli invoice 1234msat ...`).
  const bolt11 =
    'lnbcrt12340p1p5ct6ensp525myu22mhh03a2zr636tn59eahjhkprajmd2ppnl586qz27wvjxqpp5xkvweakdjc9m0rlxm3hhmfvz9hd6acjexfkuz06aeax0n2c7u0zqdq8v3jhxccxqyjw5qcqp29qxpqysgqtrheftp4lndgsjz80xx64sf3vfmtn7qzrtdha9mwxqg0mnqqz8hncgk9k3dzh48ftud92w4j4eskck044tdzpkl9ymrjf3hzsf6cjtgpupxvn0';

  const decoded = decodeBolt11(bolt11);
  assert.equal(decoded.currency, 'bcrt');
  assert.equal(decoded.amount_msat, 1234n);
  assert.equal(
    decoded.payment_hash_hex,
    '3598ecf6cd960bb78fe6dc6f7da5822ddbaee259326dc13f5dcf4cf9ab1ee3c4'
  );
  assert.equal(decoded.expires_at_unix, 1770988979);

  const ok = verifyBolt11MatchesInvoiceBody({
    bolt11,
    payment_hash_hex: decoded.payment_hash_hex,
    amount_msat: '1234',
    expires_at_unix: decoded.expires_at_unix,
  });
  assert.equal(ok.ok, true);

  const bad = verifyBolt11MatchesInvoiceBody({
    bolt11,
    payment_hash_hex: '00'.repeat(32),
    amount_msat: '1234',
    expires_at_unix: decoded.expires_at_unix,
  });
  assert.equal(bad.ok, false);
  assert.match(bad.error, /payment_hash/i);
});

