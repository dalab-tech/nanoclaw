#!/bin/bash
set -euo pipefail

# Wait for unattended-upgrades to release apt lock (common on first boot)
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done

# Detect OS user (ubuntu on GCP/OCI-Ubuntu, opc on Oracle Linux, root otherwise)
if id ubuntu &>/dev/null; then USER_NAME=ubuntu
elif id opc &>/dev/null; then USER_NAME=opc
else USER_NAME=root; fi
USER_HOME=$(eval echo ~$USER_NAME)

# --- Swap ---
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# --- Users ---
# Only admin user created at first boot. Tenants added later via provision-tenant.sh.
ADMINS="son"
ALL_USERS="$ADMINS"

for NEW_USER in $ALL_USERS; do
  useradd -m -s /bin/bash "$NEW_USER"
  # Copy SSH authorized keys from default OS user
  mkdir -p "/home/$NEW_USER/.ssh"
  if [ -f "$USER_HOME/.ssh/authorized_keys" ]; then
    cp "$USER_HOME/.ssh/authorized_keys" "/home/$NEW_USER/.ssh/authorized_keys"
    chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
  fi
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  chmod 700 "/home/$NEW_USER/.ssh"
  # Workspace
  mkdir -p "/home/$NEW_USER/workspace"
  chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER/workspace"
  # SSH key for GitHub
  su - "$NEW_USER" -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -C '${NEW_USER}@nanoclaw'"
done

# Sudo for admins
for ADMIN in $ADMINS; do
  echo "$ADMIN ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ADMIN"
  chmod 440 "/etc/sudoers.d/$ADMIN"
done

# __CLOUD_SETUP_PLACEHOLDER__

# --- GitHub deploy key + repo clone (appended by Pulumi) ---

echo "=== cloud-init complete ==="
