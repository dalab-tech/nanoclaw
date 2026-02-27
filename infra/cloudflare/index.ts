/**
 * Cloudflare Infrastructure — Pulumi
 *
 * Manages DNS records, domain redirects, email routing, and Cloudflare Tunnels for all domains
 * in the lamson-dev Cloudflare account. Single stack manages all zones.
 *
 * Fully isolated from the GCP infrastructure in infra/.
 * Uses a local file backend (state stored outside repo at ../.dalab-cloudflare-state/).
 *
 * Usage:
 *   cd infra/cloudflare
 *   export PULUMI_CONFIG_PASSPHRASE="<passphrase>"
 *   pulumi preview   # Preview changes
 *   pulumi up        # Deploy
 */

import * as dns from './dns';
import * as stixDns from './stix-dns';
import * as redirects from './redirects';
import * as email from './email';
import * as tunnel from './tunnel';
import { zones } from './zones';

const outputs: Record<string, unknown> = {};

// ─── Account-level: Email destinations ───────────────────────────────
if (email.emailDestinations) {
  Object.assign(outputs, {
    emailDestinationAddresses: email.emailDestinationAddresses,
    emailDestinationAddressIds: email.emailDestinationAddressIds,
  });
}

// ─── Per-zone outputs ────────────────────────────────────────────────
// Each entry declares: zone, dns root record, and optional services.
// This makes it trivial to see which domains have email/redirects.

const zoneConfigs = [
  { key: 'dalabLol', zone: zones.dalabLol, dns: dns.dalabLol, rootField: 'root', redirect: redirects.lolRedirect },
  { key: 'dalabTech', zone: zones.dalabTech, dns: dns.dalabTech, rootField: 'root', email: email.dalabTechEmail },
  { key: 'iamsonDev', zone: zones.iamsonDev, dns: dns.iamsonDev, rootField: 'root', email: email.iamsonDevEmail },
  { key: 'lamsonDev', zone: zones.lamsonDev, dns: dns.lamsonDev, rootField: 'root', email: email.lamsonDevEmail },
  { key: 'onedictionaryApp', zone: zones.onedictionaryApp, dns: dns.onedictionaryApp, rootField: 'root' },
  { key: 'tinaiDev', zone: zones.tinaiDev, dns: dns.tinaiDev, rootField: 'root', email: email.tinaiDevEmail },
  { key: 'vibeboardDev', zone: zones.vibeboardDev, dns: dns.vibeboardDev, rootField: 'rootA1' },
] as const;

for (const cfg of zoneConfigs) {
  if (!cfg.zone || !cfg.dns) continue;

  const rootSuffix = cfg.rootField[0].toUpperCase() + cfg.rootField.slice(1);
  outputs[`${cfg.key}ZoneId`] = cfg.zone;
  outputs[`${cfg.key}${rootSuffix}Id`] = (cfg.dns as Record<string, any>)[cfg.rootField].id;

  if ('email' in cfg && cfg.email) {
    outputs[`${cfg.key}EmailRoutingId`] = cfg.email.emailRouting.id;
  }
  if ('redirect' in cfg && cfg.redirect) {
    outputs[`${cfg.key}RedirectId`] = cfg.redirect.id;
  }
}

// ─── STIX DNS record IDs ────────────────────────────────────────────
for (const [zoneKey, records] of Object.entries(stixDns.stixRecordsByZone)) {
  for (const [key, record] of Object.entries(records)) {
    outputs[`stix_${zoneKey}_${key}`] = record.id;
  }
}

// ─── Tunnel outputs ─────────────────────────────────────────────────
for (const [name, out] of Object.entries(tunnel.tunnelOutputs)) {
  const key = name.replace(/-/g, '_');
  outputs[`tunnel_${key}_id`] = out.tunnelId;
  outputs[`tunnel_${key}_token`] = out.tunnelToken;
}

module.exports = outputs;
