#!/bin/bash

echo "Running $0"

echo "Starting lbrycrdd"
$HOME/lbrycrdd -daemon -datadir="$(echo $HOME)/.lbrycrd"

echo "Waiting until lbrycrdd has caught up to the blockchain tip"
HEIGHT=$(curl -s https://explorer.lbry.com/api/v1/status | egrep -o 'height":([0-9])+' | egrep -o '[0-9]+')
while true; do
  #set +eo pipefail
  info=$($HOME/lbrycrd-cli getblockchaininfo 2>/dev/null)
  ret=$?
  if [ "$ret" == 28 ]; then echo "Waiting for lbrycrd to start"; sleep 5; continue; fi
  #set -eo pipefail

  HEADERS=$(echo "$info" | grep headers | egrep -o '[0-9]+')
  BLOCKS=$(echo "$info" | grep blocks | egrep -o '[0-9]+')
  echo "$HEIGHT $HEADERS $BLOCKS"
  if [[ "$HEADERS" -ge "$HEIGHT" && "$BLOCKS" -ge "$HEADERS" ]]; then break; else sleep 1; fi
done
echo "final: $HEIGHT $HEADERS $BLOCKS"

echo "Stopping lbrycrdd"
$HOME/lbrycrd-cli stop
sleep 5 # make sure it has shut down

SNAPSHOT="$HOME/lbrycrd_snapshot_${BLOCKS}_$(date +%F).tar.bz2"
echo "Making snapshot $SNAPSHOT"
(
  cd $HOME/.lbrycrd
  tar -cjvf "$SNAPSHOT" blocks/ chainstate/ claimtrie/ indexes/
)

echo "Uploading snapshot to s3"
aws s3 cp $SNAPSHOT s3://snapshots.lbry.com/blockchain/ --region us-east-2

# shutdown instance (which will terminate it if shutdown behavior is set to terminate)
# sudo poweroff
