import { availabilityDomain, shape, isFlexShape } from "./config";
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

// SSH command (ubuntu for Ubuntu ARM, opc for Oracle Linux)
const sshUser = isFlexShape ? "ubuntu" : "opc";
export const sshCommand = instance.publicIp.apply(
  (ip: string) => `ssh ${sshUser}@${ip}`
);

// GitHub deploy key (public half — for reference)
export const deployKeyPublic = publicKeyOpenssh;
export const githubDeployKeyId = deployKeyId;
