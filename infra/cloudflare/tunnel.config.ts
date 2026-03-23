/**
 * Cloudflare Tunnel configuration.
 *
 * Model: one Pulumi stack = one compute instance = one tunnel.
 * Two provider types (gcp, oci), each with a Pulumi project that can host
 * multiple stacks. Currently one stack each.
 *
 * Adding a tenant:  add a route, run `pulumi up` on cloudflare stack
 * Adding a service: add routes with the new service name
 * Adding an instance: add to `instances`, generate tunnel secret, add routes
 */

/** Domain for all tunnel subdomains */
export const domain = "dalab.lol";

/** Provider types — maps to Pulumi project directories */
export const providers = {
  gcp: "infra/gcp",
  oci: "infra/oracle",
} as const;

/** Compute instances — each gets its own Cloudflare Tunnel.
 *  Key: descriptive instance name (used as tunnel name + Pulumi resource prefix)
 *  provider: which Pulumi project (key from `providers`)
 *  stack: Pulumi stack name within that project
 *  Tunnel secrets in Pulumi config: tunnel:{name}Secret */
export const instances = {
  "nanoclaw-gcp": { provider: "gcp" as const, stack: "anton" },
  "nanoclaw-oci": { provider: "oci" as const, stack: "anton" },
};

/** Routes — each creates an ingress rule + CNAME record.
 *  Subdomain: {service}-nanoclaw-{tenant}.{domain}
 *  Port: localhost port the tenant's nanoclaw listens on
 *  Instance: key from `instances` above */
export const routes = [
  { service: "stix-api", tenant: "anton-gcp", port: 3200, instance: "nanoclaw-gcp" },
  { service: "stix-api", tenant: "anton", port: 3300, instance: "nanoclaw-oci" },
  // { service: "other",    tenant: "anton", port: 4001, instance: "nanoclaw-oci" },
] as const;
