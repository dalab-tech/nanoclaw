import { instance } from "./compute";
import { cicdSa } from "./service-accounts";
import { workloadIdentityProvider } from "./workload-identity";

// Force side-effects: GitHub environment variables are created on import
import "./github-environments";

// Public IP for SSH access
export const publicIp = instance.networkInterfaces.apply(
  (nis) => nis[0]?.accessConfigs?.[0]?.natIp ?? "no-ip"
);

// Instance name
export const instanceName = instance.name;

// CI/CD service account email
export const cicdSaEmail = cicdSa.email;

// WIF provider name (for GitHub Actions auth)
export const workloadIdentityProviderName = workloadIdentityProvider.name;
