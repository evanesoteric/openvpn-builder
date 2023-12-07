#!/bin/bash
#
# build openVPN server


###############################
#    CHANGE THESE VARIABLE    #
###############################
easy_rsa_version="3.0.8"      # check releases at: https://github.com/OpenVPN/easy-rsa/releases
ca_user="root"                # keep as root
ca_host="CHANGE_ME"           # CA IP
ssh_port="22"                 # 22 is for plebs
user_to_create="daji"         # name for local user (can be removed along with 'adduser' line #99)
################################################################
# (CA root login is enabled. CA should always be powered off!) #
################################################################

# set vpn name
echo "Enter vpn name (atl-1 / who-atl-1)"
read vpn_name

# verify vpn name
while true
do
  echo
  echo "Is this correct?: ${vpn_name}"
	read -r -p "Are You Sure? [Y/n] " input

	case $input in
	    [yY][eE][sS]|[yY])
			break;;
	    [nN][oO]|[nN])
			exit;;
	    * )	echo "Aborted by user input."	;;
	esac
done

# vpn server name
vpn_server_name=${vpn_name}

# vpn client name (renames later when complete)
vpn_client_name=${vpn_server_name}-client


################################################################
################################################################

# kill if not running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

################################################################
################################################################


# initialize
cd $HOME
mkdir -p $HOME/vpn
chmod 700 $HOME/vpn


# update system packages
apt update

# upgrade system
apt -y install \
gnupg \
rsync \
curl \
wget \
git \
nftables \
psmisc \
ntp \
htop \
iotop \
unzip \
vnstat \
openvpn \
lsof \
strace \
sysstat \
python3-dev \
python3-setuptools \
python3-pip \
python3-virtualenv

# purge iptables
apt -y purge iptables

# set date and time
ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
systemctl restart ntp
systemctl enable ntp

# create user account
adduser ${user_to_create}

# modify sshd (1st)
sed -i "s/#Port 22/Port ${ssh_port}/" /etc/ssh/sshd_config
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl reload sshd

# sync ssh key
echo "[PAUSE] copy ssh key to users"
read -p "Press enter to continue"

# modify sshd (2nd)
sed -i 's/PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl reload sshd

# firewall
echo "[PAUSE] sync firewall rules"
read -p "Press enter to continue"
systemctl restart nftables
systemctl enable nftables

# ip4 forwarding
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# openvpn setup
wget https://github.com/OpenVPN/easy-rsa/releases/download/v${easy_rsa_version}/EasyRSA-${easy_rsa_version}.tgz
tar xzf EasyRSA-${easy_rsa_version}.tgz
rm EasyRSA-${easy_rsa_version}.tgz
cd $HOME/EasyRSA-${easy_rsa_version}

# pull ca.crt
scp -P ${ssh_port} ${ca_user}@${ca_host}:/root/EasyRSA-v3.0.6/pki/ca.crt $HOME/vpn/
cp $HOME/vpn/ca.crt /etc/openvpn/

# init easyrsa
bash -c "./easyrsa init-pki"

# generate dh/tls keys [ ERROR HERE !!!  TODO ]
bash -c "./easyrsa gen-dh"
cp $HOME/EasyRSA-${easy_rsa_version}/pki/dh.pem /etc/openvpn/

bash -c "openvpn --genkey --secret ta.key"
cp $HOME/EasyRSA-${easy_rsa_version}/ta.key $HOME/vpn/
cp $HOME/EasyRSA-${easy_rsa_version}/ta.key /etc/openvpn/

# generate vpn server certificate
bash -c "./easyrsa gen-req ${vpn_server_name} nopass"
scp -P ${ssh_port} $HOME/EasyRSA-${easy_rsa_version}/pki/reqs/${vpn_server_name}.req ${ca_user}@${ca_host}:/tmp

# generate vpn client certificate
bash -c "./easyrsa gen-req ${vpn_client_name} nopass"
scp -P ${ssh_port} $HOME/EasyRSA-${easy_rsa_version}/pki/reqs/${vpn_client_name}.req ${ca_user}@${ca_host}:/tmp

# sign CA requests
echo "Import and sign requests on CA;"
read -p "[PAUSE] press enter to continue"

# pull server cert from CA
scp -P ${ssh_port} ${ca_user}@${ca_host}:/root/EasyRSA-v3.0.6/pki/issued/${vpn_server_name}.crt /etc/openvpn/server.crt

# copy server key to /etc/openvpn
cp $HOME/EasyRSA-${easy_rsa_version}/pki/private/${vpn_server_name}.key /etc/openvpn/server.key

# pull client cert from CA
scp -P ${ssh_port} ${ca_user}@${ca_host}:/root/EasyRSA-v3.0.6/pki/issued/${vpn_client_name}.crt $HOME/vpn/${vpn_name}.crt

# copy client key to /root/vpn
cp $HOME/EasyRSA-${easy_rsa_version}/pki/private/${vpn_client_name}.key $HOME/vpn/${vpn_name}.key

# pull server.conf
scp -P ${ssh_port} ${ca_user}@${ca_host}:/root/server.conf /etc/openvpn/

# complete (could use error handling)
echo "OpenVPN server started and service enabled. Enjoy!"
systemctl restart openvpn@server
systemctl enable openvpn@server


##########
##  CA  ##
##########
# ./easyrsa import-req /tmp/who-atl-1.req who-atl-1
# ./easyrsa import-req /tmp/who-atl-1-client.req who-atl-1-client
# ./easyrsa sign-req server who-atl-1
# ./easyrsa sign-req client who-atl-1-client
