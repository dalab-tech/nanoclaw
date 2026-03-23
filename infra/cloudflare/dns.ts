import * as cloudflare from '@pulumi/cloudflare';
import { accountId, zones } from './zones';

// TTL values:
//   1 = "Automatic" (required when proxied: true)
//   300 = 5 minutes (good default for non-proxied records)
const TTL_AUTO = 1;
const TTL_DEFAULT = 300;

// Common CNAME targets
const PORKBUN_CNAME = 'pixie.porkbun.com'; // Porkbun registrar parking

// =============================================================================
// dalab.lol
// =============================================================================

export const dalabLol = zones.dalabLol
  ? (() => {
      const z = zones.dalabLol!;
      return {
        root: new cloudflare.DnsRecord('dalab-lol-root', {
          zoneId: z,
          name: '@',
          type: 'A',
          content: '192.0.2.1',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Root redirect to dalab.tech (see redirect ruleset)',
        }),
        www: new cloudflare.DnsRecord('dalab-lol-www', {
          zoneId: z,
          name: 'www',
          type: 'A',
          content: '192.0.2.1',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'www redirect to dalab.tech (see redirect ruleset)',
        }),
        googleVerification: new cloudflare.DnsRecord('dalab-lol-google-verification', {
          zoneId: z,
          name: '@',
          type: 'TXT',
          content: 'google-site-verification=tqnBTkxIzPa3K8-GOI8QKqbO8d-AJWmnEEPTiyuV23Y',
          ttl: TTL_DEFAULT,
          comment: 'Google site verification',
        }),
        // App subdomains (stix-web, stix-api, stix-worker, preview APIs)
        // are managed in stix-dns.ts.
      };
    })()
  : undefined;

// =============================================================================
// dalab.tech
// =============================================================================

export const dalabTech = zones.dalabTech
  ? (() => {
      const z = zones.dalabTech!;
      return {
        root: new cloudflare.DnsRecord('dalab-tech-root', {
          zoneId: z,
          name: '@',
          type: 'CNAME',
          content: 'dalab-tech.pages.dev',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Cloudflare Pages - dalab.tech landing page',
        }),
        www: new cloudflare.DnsRecord('dalab-tech-www', {
          zoneId: z,
          name: 'www',
          type: 'CNAME',
          content: 'dalab-tech.pages.dev',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'www → Cloudflare Pages dalab-tech',
        }),
        wildcard: new cloudflare.DnsRecord('dalab-tech-wildcard', {
          zoneId: z,
          name: '*',
          type: 'CNAME',
          content: PORKBUN_CNAME,
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Wildcard catch-all via Porkbun',
        }),
        // Custom domains for Cloudflare Pages project "dalab-tech"
        ...(accountId
          ? {
              pagesDomain: new cloudflare.PagesDomain('dalab-tech-pages-domain', {
                accountId,
                projectName: 'dalab-tech',
                name: 'dalab.tech',
              }),
              pagesDomainWww: new cloudflare.PagesDomain('dalab-tech-pages-domain-www', {
                accountId,
                projectName: 'dalab-tech',
                name: 'www.dalab.tech',
              }),
            }
          : {}),
        // App subdomains (stix-api, stix-worker, stix-worker-us)
        // are managed in stix-dns.ts.
      };
    })()
  : undefined;

// =============================================================================
// iamson.dev
// =============================================================================

export const iamsonDev = zones.iamsonDev
  ? (() => {
      const z = zones.iamsonDev!;
      return {
        root: new cloudflare.DnsRecord('iamson-dev-root', {
          zoneId: z,
          name: '@',
          type: 'CNAME',
          content: 'lamson-dev.pages.dev',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Cloudflare Pages - iamson.dev',
        }),
      };
    })()
  : undefined;

// =============================================================================
// lamson.dev
// =============================================================================

export const lamsonDev = zones.lamsonDev
  ? (() => {
      const z = zones.lamsonDev!;
      return {
        root: new cloudflare.DnsRecord('lamson-dev-root', {
          zoneId: z,
          name: '@',
          type: 'CNAME',
          content: 'lamson-dev.pages.dev',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Cloudflare Pages - lamson.dev',
        }),
        domainConnect: new cloudflare.DnsRecord('lamson-dev-domainconnect', {
          zoneId: z,
          name: '_domainconnect',
          type: 'CNAME',
          content: '_domainconnect.domains.squarespace.com',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Squarespace domain connect',
        }),
      };
    })()
  : undefined;

// =============================================================================
// onedictionary.app
// =============================================================================

export const onedictionaryApp = zones.onedictionaryApp
  ? (() => {
      const z = zones.onedictionaryApp!;
      return {
        root: new cloudflare.DnsRecord('onedictionary-app-root', {
          zoneId: z,
          name: '@',
          type: 'CNAME',
          content: 'bettervdict.pages.dev',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Cloudflare Pages - onedictionary.app',
        }),
        www: new cloudflare.DnsRecord('onedictionary-app-www', {
          zoneId: z,
          name: 'www',
          type: 'CNAME',
          content: 'ext-sq.squarespace.com',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Squarespace www redirect',
        }),
        domainConnect: new cloudflare.DnsRecord('onedictionary-app-domainconnect', {
          zoneId: z,
          name: '_domainconnect',
          type: 'CNAME',
          content: '_domainconnect.domains.squarespace.com',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Squarespace domain connect',
        }),
      };
    })()
  : undefined;

// =============================================================================
// tinai.dev
// =============================================================================

export const tinaiDev = zones.tinaiDev
  ? (() => {
      const z = zones.tinaiDev!;
      return {
        root: new cloudflare.DnsRecord('tinai-dev-root', {
          zoneId: z,
          name: '@',
          type: 'CNAME',
          content: 'tinai-dev.pages.dev',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Cloudflare Pages - tinai.dev',
        }),
        www: new cloudflare.DnsRecord('tinai-dev-www', {
          zoneId: z,
          name: 'www',
          type: 'CNAME',
          content: PORKBUN_CNAME,
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'www via Porkbun',
        }),
        wildcard: new cloudflare.DnsRecord('tinai-dev-wildcard', {
          zoneId: z,
          name: '*',
          type: 'CNAME',
          content: PORKBUN_CNAME,
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Wildcard catch-all via Porkbun',
        }),
        // Email (Resend via AWS SES)
        dmarc: new cloudflare.DnsRecord('tinai-dev-dmarc', {
          zoneId: z,
          name: '_dmarc',
          type: 'TXT',
          content: 'v=DMARC1; p=none;',
          ttl: TTL_DEFAULT,
          comment: 'DMARC policy',
        }),
        resendDkim: new cloudflare.DnsRecord('tinai-dev-resend-dkim', {
          zoneId: z,
          name: 'resend._domainkey',
          type: 'TXT',
          content:
            'p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC12+60+VJcGZOOBXN+/Wqzt91T/d1Wg6xa0HYMYJHv/1pGj4RNjj7PfHziQD2ent5U6d/OoZ1AV00PoWe1UmZGtQrh///TCzc13p/bBDVYPLBE9/CNlXUsIyug19MsLwxgEffkG+SD02NrCz4Rcn6zbAZomI22HFHrHLD/LNFKYQIDAQAB',
          ttl: TTL_DEFAULT,
          comment: 'Resend DKIM key',
        }),
        sendMx: new cloudflare.DnsRecord('tinai-dev-send-mx', {
          zoneId: z,
          name: 'send',
          type: 'MX',
          content: 'feedback-smtp.us-east-1.amazonses.com',
          priority: 10,
          ttl: TTL_DEFAULT,
          comment: 'AWS SES bounce handling for Resend',
        }),
        sendSpf: new cloudflare.DnsRecord('tinai-dev-send-spf', {
          zoneId: z,
          name: 'send',
          type: 'TXT',
          content: 'v=spf1 include:amazonses.com ~all',
          ttl: TTL_DEFAULT,
          comment: 'SPF for Resend sending domain',
        }),
      };
    })()
  : undefined;

// =============================================================================
// vibeboard.dev
// =============================================================================

export const vibeboardDev = zones.vibeboardDev
  ? (() => {
      const z = zones.vibeboardDev!;
      return {
        // Two A records for the root (load-balanced IPs)
        rootA1: new cloudflare.DnsRecord('vibeboard-dev-root-a1', {
          zoneId: z,
          name: '@',
          type: 'A',
          content: '44.227.76.166',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'vibeboard.dev primary IP',
        }),
        rootA2: new cloudflare.DnsRecord('vibeboard-dev-root-a2', {
          zoneId: z,
          name: '@',
          type: 'A',
          content: '44.227.65.245',
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'vibeboard.dev secondary IP',
        }),
        www: new cloudflare.DnsRecord('vibeboard-dev-www', {
          zoneId: z,
          name: 'www',
          type: 'CNAME',
          content: PORKBUN_CNAME,
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'www via Porkbun',
        }),
        wildcard: new cloudflare.DnsRecord('vibeboard-dev-wildcard', {
          zoneId: z,
          name: '*',
          type: 'CNAME',
          content: PORKBUN_CNAME,
          ttl: TTL_AUTO,
          proxied: true,
          comment: 'Wildcard catch-all via Porkbun',
        }),
      };
    })()
  : undefined;

// NOTE: Do NOT add MX records for dalab.tech here.
// Enabling email routing (see email.ts) auto-creates the required MX and SPF records.
