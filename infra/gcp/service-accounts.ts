import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { projectId } from "./config";
import { enabledApis } from "./apis";

// =============================================================================
// Service Accounts
// =============================================================================

// VM service account — attached to the GCE instance
export const vmSa = new gcp.serviceaccount.Account("nanoclaw-vm-sa", {
  accountId: "nanoclaw-vm",
  displayName: "NanoClaw VM",
  description: "Service account for the NanoClaw GCE instance",
  project: projectId,
}, { dependsOn: enabledApis });

const vmRoles = [
  "roles/logging.logWriter",
  "roles/monitoring.metricWriter",
];

vmRoles.forEach((role, index) => {
  new gcp.projects.IAMMember(`vm-role-${index}`, {
    project: projectId,
    role,
    member: pulumi.interpolate`serviceAccount:${vmSa.email}`,
  });
});

// CI/CD service account — for GitHub Actions via WIF
export const cicdSa = new gcp.serviceaccount.Account("nanoclaw-cicd-sa", {
  accountId: "nanoclaw-cicd",
  displayName: "NanoClaw CI/CD",
  description: "Service account for GitHub Actions deployments",
  project: projectId,
}, { dependsOn: enabledApis });

const cicdRoles = [
  "roles/compute.instanceAdmin.v1",
  "roles/iap.tunnelResourceAccessor",
  "roles/compute.osLogin",
  "roles/iam.serviceAccountUser",
];

cicdRoles.forEach((role, index) => {
  new gcp.projects.IAMMember(`cicd-role-${index}`, {
    project: projectId,
    role,
    member: pulumi.interpolate`serviceAccount:${cicdSa.email}`,
  });
});
