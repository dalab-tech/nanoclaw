import * as gcp from "@pulumi/gcp";
import { projectId, region } from "./config";
import { enabledApis } from "./apis";

// =============================================================================
// VPC, Subnet, Firewall
// =============================================================================

export const vpc = new gcp.compute.Network("nanoclaw-vpc", {
  project: projectId,
  autoCreateSubnetworks: false,
}, { dependsOn: enabledApis });

export const subnet = new gcp.compute.Subnetwork("nanoclaw-subnet", {
  project: projectId,
  network: vpc.id,
  region,
  ipCidrRange: "10.0.0.0/24",
}, { dependsOn: enabledApis });

// Allow SSH only from IAP's IP range (Identity-Aware Proxy)
export const firewallIap = new gcp.compute.Firewall("nanoclaw-allow-iap-ssh", {
  project: projectId,
  network: vpc.id,
  direction: "INGRESS",
  allows: [{
    protocol: "tcp",
    ports: ["22"],
  }],
  sourceRanges: ["35.235.240.0/20"],
  targetTags: ["nanoclaw"],
}, { dependsOn: enabledApis });
