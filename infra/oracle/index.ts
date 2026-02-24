import { availabilityDomain, shape } from "./config";
import { resolvedImageId, instance } from "./compute";
import { publicKeyOpenssh, deployKeyId } from "./github";

// Debug — check these if instance creation fails
export const debug = {
  availabilityDomain,
  shape,
  imageId: resolvedImageId,
};

// Public IP for SSH access
export const publicIp = instance.publicIp;

// Instance OCID
export const instanceId = instance.id;

// SSH command — connect as 'son' (human admin) by default
export const sshCommand = instance.publicIp.apply(
  (ip: string) => `ssh son@${ip}`
);

// GitHub deploy key (public half — for reference)
export const deployKeyPublic = publicKeyOpenssh;
export const githubDeployKeyId = deployKeyId;
