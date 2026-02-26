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
  deployUser,
  githubOwner,
  githubRepo,
  gitUserName,
  gitUserEmail,
} from "./config";
import { subnet } from "./network";
import { privateKeyOpenssh } from "./github";
import { dotenvContent } from "./dotenv";

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

// Cloud-init script — base script + status script injected + deploy key section appended
const baseCloudInit = fs.readFileSync(
  path.join(__dirname, "cloud-init.sh"),
  "utf-8"
);
const statusScript = fs.readFileSync(
  path.join(__dirname, "..", "status.sh"),
  "utf-8"
);
const cloudInit = baseCloudInit.replace(
  "# __STATUS_SCRIPT_PLACEHOLDER__",
  `cat > /usr/local/bin/status << 'STATUS'\n${statusScript}STATUS\nchmod +x /usr/local/bin/status`
);

const userData = pulumi
  .all([privateKeyOpenssh, gitUserName, gitUserEmail, dotenvContent])
  .apply(([privKey, userName, userEmail, dotenv]) => {
    const repoUrl = `git@github.com:${githubOwner}/${githubRepo}.git`;

    const deployKeySection = `
# Written by Pulumi — deploy key for GitHub (${deployUser} user)
mkdir -p /home/${deployUser}/.ssh
cat > /home/${deployUser}/.ssh/github_deploy_key << 'DEPLOY_KEY'
${privKey.trim()}
DEPLOY_KEY
chmod 600 /home/${deployUser}/.ssh/github_deploy_key
chown ${deployUser}:${deployUser} /home/${deployUser}/.ssh/github_deploy_key

cat > /home/${deployUser}/.ssh/config << 'SSHCONFIG'
Host github.com
  IdentityFile ~/.ssh/github_deploy_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
SSHCONFIG
chmod 600 /home/${deployUser}/.ssh/config
chown ${deployUser}:${deployUser} /home/${deployUser}/.ssh/config

su - ${deployUser} -c "git clone ${repoUrl} /home/${deployUser}/${githubRepo}" || true
su - ${deployUser} -c "git config --global user.name '${userName}'"
su - ${deployUser} -c "git config --global user.email '${userEmail}'"

# Written by Pulumi — nanoclaw app secrets
cat > /home/${deployUser}/${githubRepo}/.env << 'DOTENV'
${dotenv}DOTENV
chmod 600 /home/${deployUser}/${githubRepo}/.env
chown ${deployUser}:${deployUser} /home/${deployUser}/${githubRepo}/.env
`;

    const fullScript = cloudInit + deployKeySection;
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
}, { provider, ignoreChanges: ["metadata"] });
