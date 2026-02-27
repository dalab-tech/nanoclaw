/**
 * Cloudflare Tunnel resources — driven by tunnel.config.ts
 *
 * For each instance: creates a tunnel, managed ingress config, and DNS CNAMEs.
 * Tunnel tokens are exported for cross-stack handoff to GCP/OCI compute stacks.
 */

import * as pulumi from "@pulumi/pulumi";
import * as cloudflare from "@pulumi/cloudflare";
import { domain, instances, routes } from "./tunnel.config";
import { accountId, zones } from "./zones";

const config = new pulumi.Config("tunnel");

// ── Validation ───────────────────────────────────────────────────────────────

const instanceNames = new Set(Object.keys(instances));
for (const route of routes) {
  if (!instanceNames.has(route.instance)) {
    throw new Error(
      `Route "${route.service}-nanoclaw-${route.tenant}" references unknown instance "${route.instance}". ` +
      `Known instances: ${[...instanceNames].join(", ")}`
    );
  }
}

const subdomains = routes.map(r => `${r.service}-nanoclaw-${r.tenant}`);
const dupes = subdomains.filter((s, i) => subdomains.indexOf(s) !== i);
if (dupes.length > 0) {
  throw new Error(`Duplicate subdomains: ${[...new Set(dupes)].join(", ")}`);
}

// ── Group routes by instance ─────────────────────────────────────────────────

const routesByInstance = new Map<string, typeof routes[number][]>();
for (const route of routes) {
  const list = routesByInstance.get(route.instance) ?? [];
  list.push(route);
  routesByInstance.set(route.instance, list);
}

// ── Resources per instance ───────────────────────────────────────────────────

export const tunnelOutputs: Record<string, {
  tunnelId: pulumi.Output<string>;
  tunnelToken: pulumi.Output<string>;
}> = {};

for (const [name, _instance] of Object.entries(instances)) {
  const tunnelSecret = config.requireSecret(`${name}Secret`);
  const zoneId = zones.dalabLol;

  if (!zoneId) {
    throw new Error("dalabLol zone ID not configured — set cloudflare-dns:dalabLolZoneId");
  }
  if (!accountId) {
    throw new Error("Cloudflare account ID not configured — set cloudflare-dns:accountId");
  }

  // Tunnel
  const tunnel = new cloudflare.ZeroTrustTunnelCloudflared(`tunnel-${name}`, {
    accountId,
    name,
    tunnelSecret,
    configSrc: "cloudflare",
  });

  // Ingress config — routes for this instance + catch-all 404
  const instanceRoutes = routesByInstance.get(name) ?? [];
  const ingresses: pulumi.Input<cloudflare.types.input.ZeroTrustTunnelCloudflaredConfigConfigIngress>[] =
    instanceRoutes.map(route => ({
      hostname: `${route.service}-nanoclaw-${route.tenant}.${domain}`,
      service: `http://localhost:${route.port}`,
    }));

  // Catch-all rule (required by Cloudflare — must be last, no hostname)
  ingresses.push({ service: "http_status:404" });

  new cloudflare.ZeroTrustTunnelCloudflaredConfig(`tunnel-config-${name}`, {
    accountId,
    tunnelId: tunnel.id,
    config: {
      ingresses,
    },
  });

  // DNS CNAMEs — one per route, proxied through Cloudflare
  for (const route of instanceRoutes) {
    const subdomain = `${route.service}-nanoclaw-${route.tenant}`;
    new cloudflare.DnsRecord(`cname-${subdomain}`, {
      zoneId,
      type: "CNAME",
      name: subdomain,
      content: tunnel.id.apply(id => `${id}.cfargotunnel.com`),
      proxied: true,
      ttl: 1, // Auto TTL (required when proxied)
    });
  }

  // Construct tunnel token: base64(JSON({a: accountId, t: tunnelId, s: tunnelSecret}))
  // This is the token format cloudflared expects with `--token`
  const tunnelToken = pulumi.all([tunnel.accountId, tunnel.id, tunnelSecret])
    .apply(([acctId, tunnelId, secret]) =>
      Buffer.from(JSON.stringify({ a: acctId, t: tunnelId, s: secret })).toString("base64")
    );

  tunnelOutputs[name] = {
    tunnelId: tunnel.id,
    tunnelToken,
  };
}
