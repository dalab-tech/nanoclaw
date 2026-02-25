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
  deployUser,
  sshPrivateKey,
  githubOwner,
  githubRepo,
  gitUserName,
  gitUserEmail,
} from "./config";
import { subnet } from "./network";
import { vmSa, cicdSa } from "./service-accounts";
import { enabledApis } from "./apis";

// Cloud-init script — base script + git config section appended by Pulumi
const baseCloudInit = fs.readFileSync(
  path.join(__dirname, "cloud-init.sh"),
  "utf-8"
);

const userData = pulumi
  .all([sshPrivateKey, gitUserName, gitUserEmail])
  .apply(([privKey, userName, userEmail]) => {
    const repoUrl = `git@github.com:${githubOwner}/${githubRepo}.git`;

    const gitSection = `
# Written by Pulumi — SSH key for GitHub (${deployUser} user)
mkdir -p /home/${deployUser}/.ssh
cat > /home/${deployUser}/.ssh/github_key << 'SSHKEY'
${privKey.trim()}
SSHKEY
chmod 600 /home/${deployUser}/.ssh/github_key
chown ${deployUser}:${deployUser} /home/${deployUser}/.ssh/github_key

cat > /home/${deployUser}/.ssh/config << 'SSHCONFIG'
Host github.com
  IdentityFile ~/.ssh/github_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
SSHCONFIG
chmod 600 /home/${deployUser}/.ssh/config
chown ${deployUser}:${deployUser} /home/${deployUser}/.ssh/config

su - ${deployUser} -c "git clone ${repoUrl} /home/${deployUser}/${githubRepo}" || true
su - ${deployUser} -c "git config --global user.name '${userName}'"
su - ${deployUser} -c "git config --global user.email '${userEmail}'"
`;

    return baseCloudInit + gitSection;
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
