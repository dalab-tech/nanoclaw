import * as gcp from "@pulumi/gcp";
import { projectId } from "./config";

// =============================================================================
// Enable Required GCP APIs
// =============================================================================

const apis = [
  "compute.googleapis.com",
  "iam.googleapis.com",
  "iamcredentials.googleapis.com",
  "cloudresourcemanager.googleapis.com",
  "oslogin.googleapis.com",
  "iap.googleapis.com",
];

export const enabledApis = apis.map(
  (api) =>
    new gcp.projects.Service(`api-${api.split(".")[0]}`, {
      project: projectId,
      service: api,
      disableOnDestroy: false,
    })
);
