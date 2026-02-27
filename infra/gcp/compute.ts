import * as fs from "fs";
import * as path from "path";
import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import {
  projectId,
  zone,
  machineType,
  diskSizeGb,
  diskType,
  gitUserName,
  gitUserEmail,
  cloudflareTunnelToken,
} from "./config";
import { subnet } from "./network";
import { vmSa, cicdSa } from "./service-accounts";
import { enabledApis } from "./apis";
import { privateKeyOpenssh } from "./github";

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
  .all([privateKeyOpenssh, gitUserName, gitUserEmail, cloudflareTunnelToken])
  .apply(([privKey, userName, userEmail, cfToken]) => {

    const gitSection = `
# Written by Pulumi — deploy key for admin (tenants get it via provision-tenant.sh)
for REPO_USER in son; do
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

su - $REPO_USER -c "git config --global user.name '${userName}'"
su - $REPO_USER -c "git config --global user.email '${userEmail}'"
done
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

    return cloudInit + gitSection + cfSection;
  });

export const instance = new gcp.compute.Instance("nanoclaw-vm", {
  project: projectId,
  zone,
  machineType,
  allowStoppingForUpdate: true,
  tags: ["nanoclaw"],
  bootDisk: {
    initializeParams: {
      image: "ubuntu-os-cloud/ubuntu-2404-lts-amd64",
      size: diskSizeGb,
      type: diskType,
    },
  },
  networkInterfaces: [{
    subnetwork: subnet.id,
    accessConfigs: [{}], // Ephemeral external IP for outbound (WhatsApp/Slack)
  }],
  serviceAccount: {
    email: vmSa.email,
    scopes: ["cloud-platform"],
  },
  metadata: {
    "startup-script": userData,
    "enable-oslogin": "TRUE",
  },
  labels: {
    project: "nanoclaw",
    managed_by: "pulumi",
  },
}, { dependsOn: enabledApis });

// Instance-scoped osAdminLogin for CI/CD SA — allows sudo on this VM only,
// not project-wide. The SA SSHes as its own POSIX user, then `sudo -u anton`.
new gcp.compute.InstanceIAMMember("cicd-osadminlogin", {
  project: projectId,
  zone,
  instanceName: instance.name,
  role: "roles/compute.osAdminLogin",
  member: pulumi.interpolate`serviceAccount:${cicdSa.email}`,
});
