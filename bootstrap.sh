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

NEW_USER=$(echo $EMAIL| cut -d@ -f1)

if id "$1" &>/dev/null; then
    echo 'User Found. Skipping creation'
else
    echo 'User not found. Creating user'
    useradd -m -s /bin/bash ${NEW_USER}
fi


# install tfenv for terraform
git clone https://github.com/tfutils/tfenv.git /home/${NEW_USER}/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> /home/${NEW_USER}/.bash_profile

# # install tailscale repo
curl https://pkgs.tailscale.com/stable/ubuntu/focal.gpg | sudo apt-key add -
sudo apt-add-repository "deb https://pkgs.tailscale.com/stable/ubuntu focal main"
curl -fsSL https://pkgs.tailscale.com/stable/raspbian/buster.gpg | sudo apt-key add -
curl -fsSL https://pkgs.tailscale.com/stable/raspbian/buster.list | sudo tee /etc/apt/sources.list.d/tailscale.list

# install docker repo
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh


## INSTALL 
sudo apt -y update && sudo apt -y install lastpass-cli unzip tmux nmap mosh make terraform tailscale virtualenv python3-venv nfs-common cifs-utils vim software-properties-common
sudo apt -y upgrade


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
echo "export TAILSCALE_KEY=\"${TAILSCALE_KEY}\"" >> /home/${NEW_USER}/.bash_profile

# SSH

mkdir -p /home/${NEW_USER}/.ssh
mkdir -p /home/${NEW_USER}/.config/rclone/
sed -i "s/.*RSAAuthentication.*/RSAAuthentication yes/g" /etc/ssh/sshd_config
sed -i "s/.*PubkeyAuthentication.*/PubkeyAuthentication yes/g" /etc/ssh/sshd_config
sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication no/g" /etc/ssh/sshd_config
sed -i "s/.*AuthorizedKeysFile.*/AuthorizedKeysFile\t\.ssh\/authorized_keys/g" /etc/ssh/sshd_config
sed -i "s/.*PermitRootLogin.*/PermitRootLogin no/g" /etc/ssh/sshd_config
#sed -i "s/.*Port.*/Port 23178/g" /etc/ssh/sshd_config
echo "${NEW_USER}  ALL=(ALL:ALL) ALL" >> /etc/sudoers
chmod 400 /home/${NEW_USER}/.ssh/key
chmod 600 /home/${NEW_USER}/.ssh/authorized_keys
chmod 700 /home/${NEW_USER}/.ssh
chown ${NEW_USER} -R /home/${NEW_USER}/
usermod -aG docker pi
usermod -aG docker ${NEW_USER}


# SHHH

SSH_ID=$(lpass ls Root | grep -i SSH_KEY | grep -oP '(?<=id: )([0-9]+)')
lpass show ${SSH_ID} --notes > /home/${NEW_USER}/.ssh/key

SSHPUB_ID=$(lpass ls Root | grep -i SSH_PUB_KEY | grep -oP '(?<=id: )([0-9]+)')
lpass show ${SSHPUB_ID} --notes > /home/${NEW_USER}/.ssh/authorized_keys

ROOT_ID=$(lpass ls Root | grep -i Local_root | grep -oP '(?<=id: )([0-9]+)')
echo "root:$(lpass show ${ROOT_ID} --notes)" | chpasswd

USER_ID=$(lpass ls Root | grep -i Local_user | grep -oP '(?<=id: )([0-9]+)')
echo "${NEW_USER}:$(lpass show ${USER_ID} --notes)" | chpasswd

RCLONE_ID=$(lpass ls Root | grep -i GDRIVE | grep -oP '(?<=id: )([0-9]+)')
lpass show ${RCLONE_ID} --notes > /root/.config/rclone/rclone.conf

#TAILSCALEKEY=$(lpass ls Root | grep -i Tailscale | grep -oP '(?<=id: )([0-9]+)' | xargs -I{} -n1 bash -c 'lpass show {} --notes > $(eval echo $(lpass show --name {}))')

## INSTALL TOOLS

## CONFIGURE TOOLS
tailscale up --authkey=${TAILSCALE_KEY}

echo "HISTSIZE=-1" >> /home/${NEW_USER}/.bash_profile
echo "HISTFILESIZE=-1" >> /home/${NEW_USER}/.bash_profile

## Update dynamic DNS
CLOUDNS_ID=$(lpass ls Root | grep -i CLOUDNS_${HOSTNAME} | grep -oP '(?<=id: )([0-9]+)')
wget -q --read-timeout=0.0 --waitretry=5 --tries=400 --background $(lpass show ${CLOUDNS_ID} --notes)
rm *index.html*
unset CLOUDNS_ID TAILSCALE_ID SSH_ID ROOT_ID

## SYNC DIRECTORIES AND BACKUP
mkdir /home/${NEW_USER}/work
rclone copy gdrive:/SYNC/work /home/${NEW_USER}/work

eval `ssh-agent`

## STATUS
systemctl restart sshd
sudo systemctl stop nginx
update-rc.d rpcbind disable
update-rc.d nfs-common disable

tailscale status

