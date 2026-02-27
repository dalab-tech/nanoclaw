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
  cloudflareTunnelToken,
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

// Cloud-init script — assembled from cloud-init.sh (first-boot) + cloud-setup.sh (idempotent)
// cloud-setup.sh is inlined via placeholder, then status.sh is injected into cloud-setup's placeholder
const baseCloudInit = fs.readFileSync(
  path.join(__dirname, "..", "cloud-init.sh"),
  "utf-8"
);
const cloudSetup = fs.readFileSync(
  path.join(__dirname, "..", "cloud-setup.sh"),
  "utf-8"
);
const statusScript = fs.readFileSync(
  path.join(__dirname, "..", "status.sh"),
  "utf-8"
);
const cloudInit = baseCloudInit
  .replace("# __CLOUD_SETUP_PLACEHOLDER__", cloudSetup)
  .replace(
    "# __STATUS_SCRIPT_PLACEHOLDER__",
    `cat > /usr/local/bin/status << 'STATUS'\n${statusScript}STATUS\nchmod +x /usr/local/bin/status`
  );

const userData = pulumi
  .all([privateKeyOpenssh, gitUserName, gitUserEmail, dotenvContent, cloudflareTunnelToken])
  .apply(([privKey, userName, userEmail, dotenv, cfToken]) => {
    const repoUrl = `git@github.com:${githubOwner}/${githubRepo}.git`;

    const deployKeySection = `
# Written by Pulumi — deploy key + repo for all operators
for REPO_USER in ${deployUser} son; do
mkdir -p /home/$REPO_USER/.ssh
cat > /home/$REPO_USER/.ssh/github_deploy_key << 'DEPLOY_KEY'
${privKey.trim()}
DEPLOY_KEY
chmod 600 /home/$REPO_USER/.ssh/github_deploy_key
chown $REPO_USER:$REPO_USER /home/$REPO_USER/.ssh/github_deploy_key

cat > /home/$REPO_USER/.ssh/config << 'SSHCONFIG'
Host github.com
  IdentityFile ~/.ssh/github_deploy_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
SSHCONFIG
chmod 600 /home/$REPO_USER/.ssh/config
chown $REPO_USER:$REPO_USER /home/$REPO_USER/.ssh/config

su - $REPO_USER -c "git clone ${repoUrl} /home/$REPO_USER/${githubRepo}" || true
su - $REPO_USER -c "git config --global user.name '${userName}'"
su - $REPO_USER -c "git config --global user.email '${userEmail}'"
done

# Written by Pulumi — nanoclaw app secrets (tenant user only)
cat > /home/${deployUser}/${githubRepo}/.env << 'DOTENV'
${dotenv}DOTENV
chmod 600 /home/${deployUser}/${githubRepo}/.env
chown ${deployUser}:${deployUser} /home/${deployUser}/${githubRepo}/.env
`;

    const cfSection = cfToken ? `
# Written by Pulumi — Cloudflare Tunnel token
mkdir -p /etc/cloudflared
cat > /etc/cloudflared/token.env << 'CFTOKEN'
TUNNEL_TOKEN=${cfToken}
CFTOKEN
chmod 600 /etc/cloudflared/token.env
systemctl enable cloudflared
systemctl start cloudflared
` : "";

    const fullScript = cloudInit + deployKeySection + cfSection;
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
