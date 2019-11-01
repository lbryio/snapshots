#!/bin/bash

echo "Running $0"

echo "Installing a few tools"
sudo apt update && \
sudo apt install -y unzip awscli

echo "Installing lbrycrd"
wget -O $HOME/lbrycrd-linux.zip $(curl -s https://api.github.com/repos/lbryio/lbrycrd/releases | grep -F 'lbrycrd-linux' | grep download | head -n 1 | cut -d'"' -f4) && \
unzip $HOME/lbrycrd-linux.zip -d $HOME && \
rm $HOME/lbrycrd-linux.zip

mkdir -p "$HOME/.lbrycrd"

echo "Downloading snapshot"
wget -O $HOME/blockchain_snapshot.tar.bz2 https://lbry.com/snapshot/blockchain && \
tar xvjf $HOME/blockchain_snapshot.tar.bz2 --directory $HOME/.lbrycrd/ && \
rm $HOME/blockchain_snapshot.tar.bz2

echo "Creating lbrycrd config"
cat << EOF | tee "$HOME/.lbrycrd/lbrycrd.conf"
port=9246
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
rpcport=9245
rpcuser=lbry
rpcpassword=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 24)
server=1
txindex=1
maxtxfee=0.5
dustrelayfee=0.00000001
EOF
