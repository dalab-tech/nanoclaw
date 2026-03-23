import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { projectId, githubOwner } from "./config";
import { cicdSa } from "./service-accounts";

// =============================================================================
// Workload Identity Federation for GitHub Actions (OIDC)
// =============================================================================

// The deploy workflow lives in the anton repo, not nanoclaw
const workflowRepo = "anton";
const fullRepo = `${githubOwner}/${workflowRepo}`;

const workloadIdentityPool = new gcp.iam.WorkloadIdentityPool("github-pool", {
  project: projectId,
  workloadIdentityPoolId: "github-prod",
  displayName: "GitHub Actions (prod)",
  description: "Workload Identity Pool for GitHub Actions OIDC",
  disabled: false,
});

export const workloadIdentityProvider = new gcp.iam.WorkloadIdentityPoolProvider("github-provider", {
  project: projectId,
  workloadIdentityPoolId: workloadIdentityPool.workloadIdentityPoolId,
  workloadIdentityPoolProviderId: "github-actions",
  displayName: "GitHub Actions",
  description: "OIDC provider for GitHub Actions",
  attributeMapping: {
    "google.subject": "assertion.sub",
    "attribute.actor": "assertion.actor",
    "attribute.repository": "assertion.repository",
    "attribute.repository_owner": "assertion.repository_owner",
  },
  attributeCondition: `assertion.repository == "${fullRepo}"`,
  oidc: {
    issuerUri: "https://token.actions.githubusercontent.com",
  },
});

// Allow GitHub Actions to impersonate CI/CD service account
new gcp.serviceaccount.IAMMember("cicd-workload-identity", {
  serviceAccountId: cicdSa.name,
  role: "roles/iam.workloadIdentityUser",
  member: pulumi.interpolate`principalSet://iam.googleapis.com/${workloadIdentityPool.name}/attribute.repository/${fullRepo}`,
});
