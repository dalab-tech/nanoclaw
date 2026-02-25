import * as pulumi from "@pulumi/pulumi";

// =============================================================================
// All config from Pulumi stack — run `pulumi config set` to populate
// =============================================================================

const gcpConfig = new pulumi.Config("gcp");
const nanoclawConfig = new pulumi.Config("nanoclaw");

export const projectId = gcpConfig.require("project");
export const region = gcpConfig.get("region") || "us-central1";
export const zone = nanoclawConfig.get("zone") || `${region}-a`;
export const machineType = nanoclawConfig.get("machineType") || "e2-micro";
export const diskSizeGb = parseInt(nanoclawConfig.get("diskSizeGb") || "20", 10);
export const diskType = nanoclawConfig.get("diskType") || "pd-standard";

// GitHub config
export const githubToken = nanoclawConfig.requireSecret("githubToken");
export const githubOwner = nanoclawConfig.get("githubOwner") || "dalab-tech";
export const githubRepo = nanoclawConfig.get("githubRepo") || "nanoclaw";
export const gitUserName = nanoclawConfig.get("gitUserName") || "Anton";
export const gitUserEmail = nanoclawConfig.get("gitUserEmail") || "anton@dalab.tech";
export const deployUser = nanoclawConfig.get("deployUser") || "anton";
