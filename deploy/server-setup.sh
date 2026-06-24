#!/bin/bash
# Run as root on a fresh Ubuntu 24.04 Hetzner server.
# Usage: ssh root@YOUR_IP 'bash -s' < server-setup.sh
set -euo pipefail

echo "==> Creating deploy user..."
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy

echo "==> Copying SSH keys to deploy user..."
mkdir -p /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

echo "==> Hardening SSH..."
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd

echo "==> Setting timezone to UTC..."
timedatectl set-timezone UTC

echo "==> Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Setting up swap (2GB)..."
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
# Prefer RAM, only swap under pressure
sysctl vm.swappiness=10
echo 'vm.swappiness=10' >> /etc/sysctl.conf

echo "==> Installing packages..."
apt-get update -qq
apt-get install -y -qq fail2ban unattended-upgrades curl ca-certificates
systemctl enable fail2ban

# Enable automatic security updates non-interactively
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

echo "==> Installing Docker..."
curl -fsSL https://get.docker.com | sh
usermod -aG docker deploy

# Docker daemon: enable log rotation to prevent disk bloat
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker

echo "==> Creating project directory..."
mkdir -p /home/deploy/kaguya/certs
chown -R deploy:deploy /home/deploy/kaguya

echo ""
echo "========================================="
echo "  Server setup complete!"
echo "========================================="
echo ""
echo "  Swap:      2 GB"
echo "  Firewall:  22, 80, 443 open"
echo "  Docker:    $(docker --version)"
echo ""
echo "Next steps:"
echo "  1. Open a NEW terminal and verify deploy login:"
echo "     ssh deploy@YOUR_IP"
echo "  2. Once confirmed, close this root session"
echo "  3. Copy config files to /home/deploy/kaguya/"
echo ""
echo "IMPORTANT: Root login is now disabled."
echo "           Verify deploy SSH works before closing this session."
