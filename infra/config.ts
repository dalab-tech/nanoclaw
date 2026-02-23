import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as pulumi from "@pulumi/pulumi";
import * as oci from "@pulumi/oci";
import { provider } from "./provider";

// =============================================================================
// All config from Pulumi stack — run ./setup.sh to populate
// =============================================================================

const ociConfig = new pulumi.Config("oci");
const nanoclawConfig = new pulumi.Config("nanoclaw");

// Compartment = tenancy OCID for free tier
export const compartmentId = ociConfig.require("tenancyOcid");

// =============================================================================
// GitHub deploy key + git config for the cloud instance
// =============================================================================

export const githubToken = nanoclawConfig.requireSecret("githubToken");
export const githubOwner = nanoclawConfig.require("githubOwner"); // e.g. "dalab-tech"
export const githubRepo = nanoclawConfig.require("githubRepo"); // e.g. "nanoclaw"
export const gitUserName = nanoclawConfig.require("gitUserName");
export const gitUserEmail = nanoclawConfig.require("gitUserEmail");

// Auto-discover first availability domain via API
export const availabilityDomain = oci.identity
  .getAvailabilityDomainsOutput({ compartmentId }, { provider })
  .apply((r) => r.availabilityDomains[0].name);

// =============================================================================
// Instance shape — AMD micro (always available) or ARM flex (better but scarce)
// =============================================================================
// ARM flex: VM.Standard.A1.Flex — max always-free specs
// 4 OCPU + 24GB = 2,976 OCPU-hrs + 17,856 GB-hrs/month (under 3,000 / 18,000 free caps)
export const shape = "VM.Standard.A1.Flex";
export const isFlexShape = true;
export const ocpus = 4;
export const memoryInGbs = 24;
export const bootVolumeSizeInGbs = 200;

// SSH key — reads from ~/.ssh/ on the machine running pulumi
function readSshPublicKey(): string {
  const sshDir = path.join(os.homedir(), ".ssh");
  for (const name of ["id_ed25519.pub", "id_rsa.pub"]) {
    const keyPath = path.join(sshDir, name);
    if (fs.existsSync(keyPath)) {
      return fs.readFileSync(keyPath, "utf-8").trim();
    }
  }
  throw new Error("No SSH public key found. Run: ssh-keygen -t ed25519");
}

export const sshPublicKey = readSshPublicKey();

// Optional: override the Ubuntu image OCID (defaults to auto-lookup)
export const imageId: string | undefined = undefined;
