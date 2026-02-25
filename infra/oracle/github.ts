import * as pulumi from "@pulumi/pulumi";
import * as tls from "@pulumi/tls";
import * as github from "@pulumi/github";
import { githubToken, githubOwner, githubRepo } from "./config";

// GitHub provider — authenticated with a PAT that has repo admin access
export const githubProvider = new github.Provider("github", {
  owner: githubOwner,
  token: githubToken,
});

// ED25519 key pair for the deploy key
const deployKey = new tls.PrivateKey("nanoclaw-deploy-key", {
  algorithm: "ED25519",
});

// Register the public key as a deploy key on the repo (read-write)
const repoDeployKey = new github.RepositoryDeployKey("nanoclaw-deploy-key", {
  repository: githubRepo,
  title: pulumi.interpolate`nanoclaw-instance-${Date.now()}`,
  key: deployKey.publicKeyOpenssh,
  readOnly: false,
}, { provider: githubProvider });

// ED25519 key pair for CI/CD (GitHub Actions SSH into VM)
const cicdKey = new tls.PrivateKey("cicd-ssh-key", {
  algorithm: "ED25519",
});

export const privateKeyOpenssh = deployKey.privateKeyOpenssh;
export const publicKeyOpenssh = deployKey.publicKeyOpenssh;
export const deployKeyId = repoDeployKey.id;
export const cicdPrivateKeyOpenssh = cicdKey.privateKeyOpenssh;
export const cicdPublicKeyOpenssh = cicdKey.publicKeyOpenssh;
