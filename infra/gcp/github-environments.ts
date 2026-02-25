import * as pulumi from "@pulumi/pulumi";
import * as github from "@pulumi/github";
import { githubRepo, projectId, zone } from "./config";
import { cicdSa } from "./service-accounts";
import { workloadIdentityProvider } from "./workload-identity";
import { instance } from "./compute";
import { githubProvider } from "./github";

// =============================================================================
// GitHub Environment & Variables for GCP deploy
// =============================================================================

const ghEnv = new github.RepositoryEnvironment("gcp-env", {
  repository: githubRepo,
  environment: "gcp",
}, { provider: githubProvider });

const opts = { provider: githubProvider, dependsOn: [ghEnv] };

const envVar = (slug: string, variableName: string, value: string | pulumi.Output<string>) =>
  new github.ActionsEnvironmentVariable(
    `gh-gcp-${slug}`,
    {
      repository: githubRepo,
      environment: "gcp",
      variableName,
      value,
    },
    opts
  );

envVar("project-id", "GCP_PROJECT_ID", projectId);
envVar("zone", "GCP_ZONE", zone);
envVar("wip", "WORKLOAD_IDENTITY_PROVIDER", workloadIdentityProvider.name);
envVar("cicd-sa", "CICD_SERVICE_ACCOUNT", cicdSa.email);
envVar("vm-instance", "VM_INSTANCE_NAME", instance.name);
