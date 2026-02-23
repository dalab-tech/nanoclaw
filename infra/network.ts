import * as oci from "@pulumi/oci";
import { provider } from "./provider";
import { compartmentId } from "./config";

const opts = { provider };

export const vcn = new oci.core.Vcn("nanoclaw-vcn", {
  compartmentId,
  cidrBlocks: ["10.0.0.0/16"],
  displayName: "nanoclaw-vcn",
  dnsLabel: "nanoclaw",
}, opts);

export const internetGateway = new oci.core.InternetGateway("nanoclaw-igw", {
  compartmentId,
  vcnId: vcn.id,
  displayName: "nanoclaw-igw",
  enabled: true,
}, opts);

export const routeTable = new oci.core.RouteTable("nanoclaw-rt", {
  compartmentId,
  vcnId: vcn.id,
  displayName: "nanoclaw-rt",
  routeRules: [{
    destination: "0.0.0.0/0",
    destinationType: "CIDR_BLOCK",
    networkEntityId: internetGateway.id,
  }],
}, opts);

export const securityList = new oci.core.SecurityList("nanoclaw-sl", {
  compartmentId,
  vcnId: vcn.id,
  displayName: "nanoclaw-sl",
  ingressSecurityRules: [
    {
      protocol: "6",
      source: "0.0.0.0/0",
      description: "SSH",
      tcpOptions: { min: 22, max: 22 },
    },
    {
      protocol: "6",
      source: "0.0.0.0/0",
      description: "HTTP",
      tcpOptions: { min: 80, max: 80 },
    },
    {
      protocol: "6",
      source: "0.0.0.0/0",
      description: "HTTPS",
      tcpOptions: { min: 443, max: 443 },
    },
    {
      protocol: "1",
      source: "0.0.0.0/0",
      description: "ICMP path MTU discovery",
      icmpOptions: { type: 3, code: 4 },
    },
    {
      protocol: "1",
      source: "10.0.0.0/16",
      description: "ICMP from VCN",
      icmpOptions: { type: 3 },
    },
  ],
  egressSecurityRules: [{
    protocol: "all",
    destination: "0.0.0.0/0",
    description: "Allow all outbound",
  }],
}, opts);

export const subnet = new oci.core.Subnet("nanoclaw-subnet", {
  compartmentId,
  vcnId: vcn.id,
  cidrBlock: "10.0.1.0/24",
  displayName: "nanoclaw-public-subnet",
  dnsLabel: "pub",
  routeTableId: routeTable.id,
  securityListIds: [securityList.id],
  prohibitPublicIpOnVnic: false,
}, opts);
