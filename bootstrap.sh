#!/bin/bash
BASE_PATH="$(cd "$(dirname "$0")"; pwd -P)"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")

echo $BASE_PATH
echo $SCRIPT_FILE
echo "USER: $USER: $EMAIL" 
echo "HOSTNAME: $HOSTNAME"

## SET PREREQ ENV VARS
if [ -z ${EMAIL+x} ]; then
	echo "Empty var EMAIL"
	echo "set to your proper key"
	echo "export EMAIL=<VALUE>"
	exit 1
fi

## BOOTSTRAP SCRIPT ## 
# give a chance to bail out if we aren't doing an initial setup
# read -p "run bootstrap [y/n]: " -n 1 -r
# if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#   exit 1
# fi
# echo

## LOGIN
function load-creds {
  LPASS_DISABLE_PINENTRY=1 lpass login ${EMAIL}
	mkdir -p /root/.local/share/lpass
}

## RCLONE CONFIG
curl https://rclone.org/install.sh | sudo bash

## SET SECRETS
load-creds

# TAILSCALE VPN
TAILSCALE_ID=$(lpass ls Root | grep -i Tailscale | grep -oP '(?<=id: )([0-9]+)')
TAILSCALE_KEY=$(lpass show ${TAILSCALE_ID} --notes)
echo "export TAILSCALE_KEY=\"${TAILSCALE_KEY}\"" >> ~/.bash_profile

# SSH
SSH_ID=$(lpass ls Root | grep -i SSH_KEY | grep -oP '(?<=id: )([0-9]+)')
lpass show ${SSH_ID} --notes > ~/.ssh/key
ROOT_ID=$(lpass ls Root | grep -i localhost | grep -oP '(?<=id: )([0-9]+)')
echo "root:$(lpass show ${ROOT_ID} --notes)" | chpasswd

RCLONE_ID=$(lpass ls Root | grep -i GDRIVE | grep -oP '(?<=id: )([0-9]+)')
lpass show ${RCLONE_ID} --notes > /root/.config/rclone/rclone.conf

#TAILSCALEKEY=$(lpass ls Root | grep -i Tailscale | grep -oP '(?<=id: )([0-9]+)' | xargs -I{} -n1 bash -c 'lpass show {} --notes > $(eval echo $(lpass show --name {}))')
chmod 400 ~/.ssh/*

## INSTALL TOOLS

# install tfenv for terraform
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bash_profile

# install tailscale repo
curl https://pkgs.tailscale.com/stable/ubuntu/focal.gpg | sudo apt-key add -
sudo apt-add-repository "deb https://pkgs.tailscale.com/stable/ubuntu focal main"

# install docker repo
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# install other
sudo apt update && sudo apt -y install unzip nmap mosh terraform tailscale docker-ce make virtualenv python3-venv lastpass-cli nfs-common cifs-utils

## CONFIGURE TOOLS
tailscale up --authkey=${TAILSCALE_KEY}

echo "HISTSIZE=-1" >> ~/.bash_profile
echo "HISTFILESIZE=-1" >> ~/.bash_profile

source ~/.bash_profile
tfenv install latest

## Update dynamic DNS
CLOUDNS_ID=$(lpass ls Root | grep -i CLOUDNS | grep -oP '(?<=id: )([0-9]+)')
wget -q --read-timeout=0.0 --waitretry=5 --tries=400 --background $(lpass show ${CLOUDNS_ID} --notes)
rm index.html*
unset CLOUDNS_ID TAILSCALE_ID SSH_ID ROOT_ID

## SYNC DIRECTORIES AND BACKUP
/root/scripts/homesync.sh

## SSH Setup
#echo "Port 23178" >> /etc/ssh/sshd_config
#systemctl restart sshd

eval `ssh-agent`

## STATUS
tailscale status
sudo systemctl stop nginx
update-rc.d rpcbind disable
update-rc.d nfs-common disable
#reboot
