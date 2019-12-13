#!/bin/bash

# set -x

echo "Running $0"

hash aws 2>/dev/null || { echo >&2 '`aws` command not found. Install it: sudo apt install awscli'; exit 1;  }
[ "$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials)" == "ec2-snapshotter" ] || { echo >&2 'This instance is missing the "ec2-snapshotter" IAM role'; exit 1;  }

user=$(whoami)

echo "Starting servers"
sudo docker-compose up --detach

echo "Waiting until lbrycrdd has caught up to the blockchain tip"
HEIGHT=$(curl -s https://explorer.lbry.com/api/v1/status | egrep -o 'height":([0-9])+' | egrep -o '[0-9]+')
while true; do
  #set +eo pipefail
  info=$(sudo docker exec ${user}_lbrycrd_1 lbrycrd-cli -conf=/etc/lbry/lbrycrd.conf getblockchaininfo 2>/dev/null)
  ret=$?
  if [ "$ret" != 0 ]; then echo "Waiting for lbrycrd to start"; sleep 5; continue; fi
  WALLET_BLOCKS=$(echo '{"id":1,"method":"blockchain.block.get_server_height"}' | nc localhost 50001 | egrep -m 1 -o 'result": [0-9]+' | egrep -o '[0-9]+')
  if [ -z "$WALLET_BLOCKS" ]; then echo "Waiting for wallet server to bind port"; sleep 5; continue; fi
  #set -eo pipefail

  HEADERS=$(echo "$info" | grep headers | egrep -o '[0-9]+')
  BLOCKS=$(echo "$info" | grep blocks | egrep -o '[0-9]+')
  echo "$HEIGHT $HEADERS $BLOCKS $WALLET_BLOCKS"
  if [[ "$HEADERS" -ge "$HEIGHT" && "$BLOCKS" -ge "$HEADERS" && "$WALLET_BLOCKS" -ge "$BLOCKS" ]]; then break; else sleep 1; fi
done
echo "final: $HEIGHT $HEADERS $BLOCKS $WALLET_BLOCKS"

LBRYCRD_VERSION=$(sudo docker exec ${user}_lbrycrd_1 lbrycrd-cli -conf=/etc/lbry/lbrycrd.conf getnetworkinfo 2>/dev/null | grep -m 1 subversion | egrep -o '[0-9\.]+')
WALLET_SERVER_VERSION=$(echo '{"id":1,"method":"server.version"}' | nc localhost 50001 | egrep -m 1 -o 'result[^,]+' | cut -d'"' -f3)

echo "Stopping servers"
sudo docker-compose down

# TODO: get volume data locations from `docker volume inspect` instead of hardcoding them below

BLOCKCHAIN_SNAPSHOT="$HOME/blockchain_snapshot_${WALLET_BLOCKS}_v${LBRYCRD_VERSION}_$(date +%F).tar.bz2"
echo "Making blockchain snapshot $BLOCKCHAIN_SNAPSHOT"
sudo tar -cjvf "$BLOCKCHAIN_SNAPSHOT" -C /var/lib/docker/volumes/${user}_lbrycrd/_data --group=$user --owner=$user blocks/ chainstate/ claimtrie/ indexes/
echo "Uploading blockchain snapshot to s3"
aws s3 cp "$BLOCKCHAIN_SNAPSHOT" s3://snapshots.lbry.com/blockchain/ --region us-east-2

WALLET_SNAPSHOT="$HOME/wallet_snapshot_${WALLET_BLOCKS}_v${WALLET_SERVER_VERSION}_$(date +%F).tar.bz2"
echo "Making wallet snapshot $SNAPSHOT"
sudo tar -cjvf "$WALLET_SNAPSHOT" -C /var/lib/docker/volumes/${user}_wallet_server/_data --group=$user --owner=$user claims.db hist/ meta/ utxo/
echo "Uploading wallet snapshot to s3"
aws s3 cp "$WALLET_SNAPSHOT" s3://snapshots.lbry.com/wallet/ --region us-east-2

rm -f "$BLOCKCHAIN_SNAPSHOT" "$WALLET_SNAPSHOT"


# shutdown instance (which will terminate it if shutdown behavior is set to terminate)
# sudo poweroff
