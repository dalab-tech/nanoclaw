import * as pulumi from "@pulumi/pulumi";

// =============================================================================
// All config from Pulumi stack — run `pulumi config set` to populate
// =============================================================================

const gcpConfig = new pulumi.Config("gcp");
const githubConfig = new pulumi.Config("github");
const nanoclawConfig = new pulumi.Config("nanoclaw");

export const projectId = gcpConfig.require("project");
export const region = gcpConfig.get("region") || "us-central1";
export const zone = nanoclawConfig.get("zone") || `${region}-a`;
export const machineType = nanoclawConfig.get("machineType") || "e2-micro";
export const diskSizeGb = parseInt(nanoclawConfig.get("diskSizeGb") || "20", 10);
export const diskType = nanoclawConfig.get("diskType") || "pd-standard";

// GitHub PAT — 'anton-nanoclaw-pat' fine-grained PAT from the lamson-dev
// GitHub account (needs repo access to nanoclaw + anton)
export const antonNanoclawPAT = githubConfig.requireSecret("antonNanoclawPAT");
export const githubOwner = nanoclawConfig.get("githubOwner") || "dalab-tech";
export const githubRepo = nanoclawConfig.get("githubRepo") || "nanoclaw";
export const gitUserName = nanoclawConfig.get("gitUserName") || "Anton";
export const gitUserEmail = nanoclawConfig.get("gitUserEmail") || "anton@dalab.tech";
export const deployUser = nanoclawConfig.get("deployUser") || "anton";

// App environment variables (written to ~/nanoclaw/.env)
export const githubToken = nanoclawConfig.getSecret("githubToken") ?? pulumi.output("");
export const githubUsername = nanoclawConfig.get("githubUsername") || "anton-dalab";
export const claudeCodeOauthToken = nanoclawConfig.getSecret("claudeCodeOauthToken") ?? pulumi.output("");
export const slackBotToken = nanoclawConfig.getSecret("slackBotToken") ?? pulumi.output("");
export const slackAppToken = nanoclawConfig.getSecret("slackAppToken") ?? pulumi.output("");
export const assistantName = nanoclawConfig.get("assistantName") || "Anton";
export const webAuthToken = nanoclawConfig.getSecret("webAuthToken") ?? pulumi.output("");
export const stixWorkerUrl = nanoclawConfig.get("stixWorkerUrl") || "";
export const stixApiKey = nanoclawConfig.getSecret("stixApiKey") ?? pulumi.output("");

// Cloudflare Tunnel token (copied from cloudflare stack output after tunnel creation)
export const cloudflareTunnelToken = nanoclawConfig.getSecret("cloudflareTunnelToken") ?? pulumi.output("");
