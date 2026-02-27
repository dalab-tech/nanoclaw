import * as pulumi from "@pulumi/pulumi";
import * as github from "@pulumi/github";
import { projectId, zone } from "./config";
import { cicdSa } from "./service-accounts";
import { workloadIdentityProvider } from "./workload-identity";
import { instance } from "./compute";
import { githubProvider } from "./github";
import { dotenvContent } from "./dotenv";
import { cloudflareTunnelToken } from "./config";

// =============================================================================
// GitHub Environment & Variables for GCP deploy
// =============================================================================

// Environments live in the anton repo (where the deploy workflow is)
const workflowRepo = "anton";

const ghEnv = new github.RepositoryEnvironment("gcp-env", {
  repository: workflowRepo,
  environment: "gcp",
}, { provider: githubProvider });

const opts = { provider: githubProvider, dependsOn: [ghEnv] };

const envVar = (slug: string, variableName: string, value: string | pulumi.Output<string>) =>
  new github.ActionsEnvironmentVariable(
    `gh-gcp-${slug}`,
    {
      repository: workflowRepo,
      environment: "gcp",
      variableName,
      value,
    },
    opts
  );

envVar("project-id", "GCP_PROJECT_ID", projectId);
envVar("zone", "GCP_ZONE", zone);
envVar("wip", "GCP_WORKLOAD_IDENTITY_PROVIDER", workloadIdentityProvider.name);
envVar("cicd-sa", "GCP_CICD_SERVICE_ACCOUNT", cicdSa.email);
envVar("vm-instance", "GCP_VM_INSTANCE_NAME", instance.name);

const envSecret = (slug: string, secretName: string, plaintextValue: pulumi.Output<string>) =>
  new github.ActionsEnvironmentSecret(
    `gh-gcp-${slug}`,
    {
      repository: workflowRepo,
      environment: "gcp",
      secretName,
      plaintextValue,
    },
    opts
  );

envSecret("dotenv", "NANOCLAW_DOTENV", dotenvContent);
envSecret("tunnel-token", "TUNNEL_TOKEN", cloudflareTunnelToken);
