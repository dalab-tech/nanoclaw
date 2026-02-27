import * as pulumi from "@pulumi/pulumi";
import * as github from "@pulumi/github";
import { deployUser, cloudflareTunnelToken } from "./config";
import { githubProvider, cicdPrivateKeyOpenssh } from "./github";
import { instance } from "./compute";
import { dotenvContent } from "./dotenv";

// =============================================================================
// GitHub Environment & Variables for OCI deploy
// =============================================================================

const workflowRepo = "anton";

const ghEnv = new github.RepositoryEnvironment("nanoclaw-oci-env", {
  repository: workflowRepo,
  environment: "nanoclaw-oci",
}, { provider: githubProvider });

const opts = { provider: githubProvider, dependsOn: [ghEnv] };

const envVar = (slug: string, variableName: string, value: string | pulumi.Output<string>) =>
  new github.ActionsEnvironmentVariable(
    `gh-nanoclaw-oci-${slug}`,
    {
      repository: workflowRepo,
      environment: "nanoclaw-oci",
      variableName,
      value,
    },
    opts
  );

const envSecret = (slug: string, secretName: string, plaintextValue: pulumi.Output<string>) =>
  new github.ActionsEnvironmentSecret(
    `gh-nanoclaw-oci-${slug}`,
    {
      repository: workflowRepo,
      environment: "nanoclaw-oci",
      secretName,
      plaintextValue,
    },
    opts
  );

envVar("deploy-provider", "DEPLOY_PROVIDER", "oci");
envVar("deploy-host", "OCI_DEPLOY_HOST", instance.publicIp);
envVar("deploy-user", "OCI_DEPLOY_USER", deployUser);

envSecret("deploy-ssh-key", "OCI_DEPLOY_SSH_KEY", cicdPrivateKeyOpenssh);

envSecret("dotenv", "NANOCLAW_DOTENV", dotenvContent);
envSecret("tunnel-token", "TUNNEL_TOKEN", cloudflareTunnelToken);
