import * as fs from "fs";
import * as path from "path";
import * as pulumi from "@pulumi/pulumi";
import * as oci from "@pulumi/oci";
import { provider } from "./provider";
import {
  compartmentId,
  availabilityDomain,
  sshPublicKey,
  imageId,
  shape,
  isFlexShape,
  ocpus,
  memoryInGbs,
  bootVolumeSizeInGbs,
  githubOwner,
  githubRepo,
  gitUserName,
  gitUserEmail,
} from "./config";
import { subnet } from "./network";
import { privateKeyOpenssh } from "./github";

// Image lookup — Oracle Linux for micro (guaranteed free-tier compatible), Ubuntu for ARM
const imageOs = isFlexShape ? "Canonical Ubuntu" : "Oracle Linux";
const imageVersion = isFlexShape ? "24.04 Minimal aarch64" : "9";

export const resolvedImageId: pulumi.Input<string> = imageId
  ? imageId
  : oci.core
      .getImagesOutput({
        compartmentId,
        operatingSystem: imageOs,
        operatingSystemVersion: imageVersion,
        shape,
        sortBy: "TIMECREATED",
        sortOrder: "DESC",
      }, { provider })
      .apply((imgs) => {
        if (imgs.images.length === 0) {
          throw new Error(
            `No ${imageOs} ${imageVersion} image found for shape ${shape}.`
          );
        }
        return imgs.images[0].id;
      });

// Cloud-init script — base script + deploy key section appended by Pulumi
const baseCloudInit = fs.readFileSync(
  path.join(__dirname, "cloud-init.sh"),
  "utf-8"
);

const userData = pulumi
  .all([privateKeyOpenssh, gitUserName, gitUserEmail])
  .apply(([privKey, userName, userEmail]) => {
    const sshUser = isFlexShape ? "ubuntu" : "opc";
    const repoUrl = `git@github.com:${githubOwner}/${githubRepo}.git`;

    const deployKeySection = `
# Written by Pulumi — deploy key for GitHub
mkdir -p /home/${sshUser}/.ssh
cat > /home/${sshUser}/.ssh/github_deploy_key << 'DEPLOY_KEY'
${privKey.trim()}
DEPLOY_KEY
chmod 600 /home/${sshUser}/.ssh/github_deploy_key
chown ${sshUser}:${sshUser} /home/${sshUser}/.ssh/github_deploy_key

cat > /home/${sshUser}/.ssh/config << 'SSHCONFIG'
Host github.com
  IdentityFile ~/.ssh/github_deploy_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
SSHCONFIG
chmod 600 /home/${sshUser}/.ssh/config
chown ${sshUser}:${sshUser} /home/${sshUser}/.ssh/config

su - ${sshUser} -c "git clone ${repoUrl} /home/${sshUser}/workspace/nanoclaw" || true
su - ${sshUser} -c "git config --global user.name '${userName}'"
su - ${sshUser} -c "git config --global user.email '${userEmail}'"
`;

    const fullScript = baseCloudInit + deployKeySection;
    return Buffer.from(fullScript).toString("base64");
  });

export const instance = new oci.core.Instance("nanoclaw", {
  compartmentId,
  availabilityDomain,
  displayName: "nanoclaw",
  shape,
  // shapeConfig only applies to Flex shapes
  ...(isFlexShape && ocpus && memoryInGbs
    ? { shapeConfig: { ocpus, memoryInGbs } }
    : {}),
  sourceDetails: {
    sourceType: "image",
    sourceId: resolvedImageId,
    // Omit bootVolumeSizeInGbs for micro — let OCI use the image default
    ...(isFlexShape ? { bootVolumeSizeInGbs: String(bootVolumeSizeInGbs) } : {}),
  },
  createVnicDetails: {
    subnetId: subnet.id,
    assignPublicIp: "true",
    hostnameLabel: "nanoclaw",
  },
  metadata: {
    ssh_authorized_keys: sshPublicKey,
    user_data: userData,
  },
  freeformTags: {
    project: "nanoclaw",
    managed_by: "pulumi",
  },
}, { provider });
