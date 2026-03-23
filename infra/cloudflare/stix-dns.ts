/**
 * STIX DNS Records (Cloudflare)
 *
 * ## New engineer?
 *
 * 1. Add your entry to ENGINEER_ENVS:
 *      { slug: 'yourname', gcpProjectId: 'stix-yourname' }
 *
 * 2. Run:
 *      pulumi preview -s lamson-dev && pulumi up -s lamson-dev
 *
 * This auto-creates:
 *   stix-{slug}.dalab.lol         → Firebase Hosting (web app)
 *   stix-{slug}-worker.dalab.lol  → Cloud Run (worker)
 *
 * When App Hosting is configured for your API backend, add the appHosting
 * field with values from: Firebase console → App Hosting → Custom domains.
 */

import * as cloudflare from '@pulumi/cloudflare';
import { zones } from './zones';

// =============================================================================
// Constants
// =============================================================================

const TTL = 300; // 5 minutes
const GHS_CNAME = 'ghs.googlehosted.com';

// =============================================================================
// Types
// =============================================================================

type AppHostingDns = {
  aRecordIp: string;
  txtClaim: string;
  acmeSubdomain: string;
  acmeTarget: string;
};

type EngineerEnv = {
  /** Short name (e.g., 'dang'). Drives subdomains: stix-{slug}, stix-{slug}-worker, stix-{slug}-api */
  slug: string;
  /** GCP project ID (e.g., 'stix-dang') */
  gcpProjectId: string;
  /** App Hosting DNS — add when custom domain is configured in Firebase console */
  appHosting?: AppHostingDns;
};

// =============================================================================
// Engineer Environments (dalab.lol)
// =============================================================================
// New engineer? Add your entry here:

const ENGINEER_ENVS: EngineerEnv[] = [
  { slug: 'dang', gcpProjectId: 'stix-dang' },
  // { slug: 'yourname', gcpProjectId: 'stix-yourname' },
];

// =============================================================================
// Dev Environment (dalab.lol) — non-standard naming, extra records
// =============================================================================

const DEV_PROJECT_ID = 'stix-dev-13dd5';

const DEV_APP_HOSTING = [
  {
    subdomain: 'stix-api',
    resourceSlug: 'stix-api',
    aRecordIp: '35.219.200.11',
    txtClaim: 'fah-claim=002-02-13c7791f-2b0c-4b04-8034-476b755abb32',
    acmeSubdomain: '_acme-challenge_4zu73vkmbcnfihuf.stix-api',
    acmeTarget: '0bdf3eaa-654d-4410-a195-3a952b319dec.16.authorize.certificatemanager.goog',
  },
  {
    subdomain: 'stix-dev-api-p1',
    resourceSlug: 'stix-api-p1', // legacy — resource name doesn't match subdomain
    aRecordIp: '35.219.200.11',
    txtClaim: 'fah-claim=002-02-37c18192-9df2-42a4-8aeb-984072de2361',
    acmeSubdomain: '_acme-challenge_4zu73vkmbcnfihuf.stix-dev-api-p1',
    acmeTarget: '67d80cd4-e8e5-432c-b839-30b5b2bf1d23.8.authorize.certificatemanager.goog',
  },
];

// =============================================================================
// Record Generation
// =============================================================================

function tld(domain: string): string {
  return domain.split('.').pop()!;
}

/** Create DNS records for an engineer environment using naming conventions. */
function createEngineerRecords(
  env: EngineerEnv,
  zoneId: string,
  domain = 'dalab.lol'
): Record<string, cloudflare.DnsRecord> {
  const records: Record<string, cloudflare.DnsRecord> = {};
  const t = tld(domain);
  const pfx = `stix-${env.slug}`;

  // Web: stix-{slug}.dalab.lol → {gcpProjectId}.web.app
  records[pfx] = new cloudflare.DnsRecord(`cf-${pfx}-web-${t}`, {
    zoneId,
    name: pfx,
    type: 'CNAME',
    content: `${env.gcpProjectId}.web.app`,
    ttl: TTL,
    proxied: false,
    comment: `Firebase Hosting - ${pfx} web app`,
  });

  // Worker: stix-{slug}-worker.dalab.lol → ghs.googlehosted.com
  records[`${pfx}-worker`] = new cloudflare.DnsRecord(`cf-${pfx}-worker-${t}`, {
    zoneId,
    name: `${pfx}-worker`,
    type: 'CNAME',
    content: GHS_CNAME,
    ttl: TTL,
    proxied: false,
    comment: `Cloud Run - ${pfx} worker`,
  });

  // App Hosting API: stix-{slug}-api.dalab.lol (optional)
  if (env.appHosting) {
    const api = `${pfx}-api`;
    const fqdn = `${api}.${domain}`;

    records[`${api}-a`] = new cloudflare.DnsRecord(`cf-apphosting-${api}-${t}-a`, {
      zoneId,
      name: fqdn,
      type: 'A',
      content: env.appHosting.aRecordIp,
      ttl: TTL,
      proxied: false,
      comment: `App Hosting A record (${fqdn})`,
    });

    records[`${api}-txt`] = new cloudflare.DnsRecord(`cf-apphosting-${api}-${t}-txt`, {
      zoneId,
      name: fqdn,
      type: 'TXT',
      content: env.appHosting.txtClaim,
      ttl: TTL,
      proxied: false,
      comment: `App Hosting TXT record (${fqdn})`,
    });

    records[`${api}-acme`] = new cloudflare.DnsRecord(`cf-apphosting-${api}-${t}-acme`, {
      zoneId,
      name: `${env.appHosting.acmeSubdomain}.${domain}`,
      type: 'CNAME',
      content: env.appHosting.acmeTarget,
      ttl: TTL,
      proxied: false,
      comment: `App Hosting ACME record (${fqdn})`,
    });
  }

  return records;
}

/** Dev environment has non-standard subdomain names (stix, not stix-dev). */
function createDevRecords(zoneId: string, domain = 'dalab.lol'): Record<string, cloudflare.DnsRecord> {
  const records: Record<string, cloudflare.DnsRecord> = {};
  const t = tld(domain);

  // Web: stix.dalab.lol
  records.web = new cloudflare.DnsRecord(`cf-stix-web-${t}`, {
    zoneId,
    name: 'stix',
    type: 'CNAME',
    content: `${DEV_PROJECT_ID}.web.app`,
    ttl: TTL,
    proxied: false,
    comment: `Firebase Hosting CDN - stix web app (${domain})`,
  });

  // Worker: stix-worker.dalab.lol
  records['stix-worker'] = new cloudflare.DnsRecord(`cf-stix-worker-${t}`, {
    zoneId,
    name: 'stix-worker',
    type: 'CNAME',
    content: GHS_CNAME,
    ttl: TTL,
    proxied: false,
    comment: 'Cloud Run - stix worker dev',
  });

  // Preview: stix-p1.dalab.lol (short alias)
  records['stix-p1'] = new cloudflare.DnsRecord(`cf-stix-p1-${t}`, {
    zoneId,
    name: 'stix-p1',
    type: 'CNAME',
    content: 'stix-dev-spa-p1.web.app',
    ttl: TTL,
    proxied: false,
    comment: `Firebase Hosting CDN - stix-p1 preview short alias (${domain})`,
  });

  // Preview: stix-dev-spa-p1.dalab.lol (canonical, matches Firebase site ID)
  records['stix-dev-spa-p1'] = new cloudflare.DnsRecord(`cf-stix-dev-spa-p1-${t}`, {
    zoneId,
    name: 'stix-dev-spa-p1',
    type: 'CNAME',
    content: 'stix-dev-spa-p1.web.app',
    ttl: TTL,
    proxied: false,
    comment: `Firebase Hosting CDN - stix-dev-spa-p1 preview canonical (${domain})`,
  });

  // App Hosting backends
  for (const ah of DEV_APP_HOSTING) {
    const fqdn = `${ah.subdomain}.${domain}`;

    records[`${ah.subdomain}-a`] = new cloudflare.DnsRecord(`cf-apphosting-${ah.resourceSlug}-${t}-a`, {
      zoneId,
      name: fqdn,
      type: 'A',
      content: ah.aRecordIp,
      ttl: TTL,
      proxied: false,
      comment: `Firebase App Hosting A record (${fqdn})`,
    });

    records[`${ah.subdomain}-txt`] = new cloudflare.DnsRecord(`cf-apphosting-${ah.resourceSlug}-${t}-txt`, {
      zoneId,
      name: fqdn,
      type: 'TXT',
      content: ah.txtClaim,
      ttl: TTL,
      proxied: false,
      comment: `Firebase App Hosting TXT record (${fqdn})`,
    });

    records[`${ah.subdomain}-acme`] = new cloudflare.DnsRecord(`cf-apphosting-${ah.resourceSlug}-${t}-acme`, {
      zoneId,
      name: `${ah.acmeSubdomain}.${domain}`,
      type: 'CNAME',
      content: ah.acmeTarget,
      ttl: TTL,
      proxied: false,
      comment: `Firebase App Hosting ACME record (${fqdn})`,
    });
  }

  return records;
}

/** Prod workers on dalab.tech. */
function createProdRecords(zoneId: string): Record<string, cloudflare.DnsRecord> {
  const records: Record<string, cloudflare.DnsRecord> = {};

  for (const w of [
    { sub: 'stix-worker', comment: 'Cloud Run - stix worker prod' },
    { sub: 'stix-worker-us', comment: 'Cloud Run - stix worker US region prod' },
  ]) {
    records[w.sub] = new cloudflare.DnsRecord(`cf-${w.sub}-tech`, {
      zoneId,
      name: w.sub,
      type: 'CNAME',
      content: GHS_CNAME,
      ttl: TTL,
      proxied: false,
      comment: w.comment,
    });
  }

  return records;
}

// =============================================================================
// Generate all records
// =============================================================================

export const GCP_PROJECTS = {
  dev: DEV_PROJECT_ID,
} as const;

export const stixRecordsByZone: Record<string, Record<string, cloudflare.DnsRecord>> = {};

// dalab.lol — dev + engineer environments
const dalabLolZoneId = zones.dalabLol;
if (dalabLolZoneId) {
  stixRecordsByZone.dalabLol = { ...createDevRecords(dalabLolZoneId) };

  for (const env of ENGINEER_ENVS) {
    Object.assign(stixRecordsByZone.dalabLol, createEngineerRecords(env, dalabLolZoneId));
  }
}

// dalab.tech — prod workers
const dalabTechZoneId = zones.dalabTech;
if (dalabTechZoneId) {
  stixRecordsByZone.dalabTech = createProdRecords(dalabTechZoneId);
}
