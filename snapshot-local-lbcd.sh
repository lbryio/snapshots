#!/bin/bash

#
# Make a local blockchain snapshot
#

#set -x
#set -e
set -uo pipefail

BIN_DIR="$HOME/lbcd"   # directory where lbcd binary exists
CONF_DIR="$HOME/.lbcd"  # directory where config files and wallets are
SNAPSHOT_DIR="/mnt/sdb"       # directory where to temporarily put the snapshot

AWS_PATH="s3://snapshots.lbry.com/blockchain/"  # Where to upload the snapshot to
AWS_FLAGS="--region us-east-2"    # General AWS flags (region, profile, etc)

# TODO: add timing info to each step so I know how long it takes



echo "Running $0"

hash aws 2>/dev/null || { echo >&2 'aws command not found. Install it: sudo apt install awscli'; exit 1;  }

if ! aws $AWS_FLAGS s3 ls > /dev/null 2>/dev/null; then
  echo "not logged into mfa profile on aws. run aws-mfa-refresh.sh"
  exit 1
fi

if ! pgrep lbcd;  then
  echo "Starting lbcd"
  "$BIN_DIR/lbcd" -server -daemon
fi


EXPLORER_BLOCKS=$(curl -s https://explorer.lbry.com/api/v1/status | grep -Eo 'height":([0-9])+' | grep -Eo '[0-9]+')

echo "Waiting until lbcd has caught up to the blockchain tip"

while true; do
  info=$("$BIN_DIR/lbcctl" getblockchaininfo 2>/dev/null)
  if [ "$?" != 0 ]; then
    echo "Waiting for lbcd to start"
    sleep 10
    continue
  fi

  HEADERS=$(echo "$info" | grep headers | grep -Eo '[0-9]+')
  BLOCKS=$(echo "$info" | grep blocks | grep -Eo '[0-9]+')
  TIP=$(( EXPLORER_BLOCKS > HEADERS ? EXPLORER_BLOCKS : HEADERS ))
  echo "tip: $TIP, height: $BLOCKS"

  [[ "$BLOCKS" -ge "$TIP" ]] && break

  ((blocksToGo=TIP-BLOCKS))
  ((sleepTime=blocksToGo/10)) # I get ~3 blocks per second but I don't want to oversleep
  if [ "$sleepTime" -lt 2 ]; then sleepTime=2; fi
  echo "$blocksToGo blocks to go. Checking again in $sleepTime seconds (at $(date -d "+ $sleepTime seconds" "+%H:%M"))..."
  sleep $sleepTime
done


LBCD_VERSION=$("$BIN_DIR/lbcctl" getnetworkinfo 2>/dev/null | grep -m 1 subversion | sed -E 's/.*:([0-9\.]*)\(.*/\1/g')

echo "Stopping lbcd at $BLOCKS blocks"
pkill lbcd
echo "Waiting for lbcd to shut down..."
while pgrep lbcd > /dev/null; do sleep 3; done
echo "lbcd stopped"

BLOCKCHAIN_SNAPSHOT="$SNAPSHOT_DIR/lbcd_snapshot_${BLOCKS}_v${LBCD_VERSION}_$(date +%F).tar"

case "$LBCD_VERSION" in
  *)
    TARGETS="data"
    ;;
esac

echo "Making blockchain snapshot $BLOCKCHAIN_SNAPSHOT"
tar -cvf "$BLOCKCHAIN_SNAPSHOT" -C "$CONF_DIR" $TARGETS
if [ "$?" != 0 ]; then
  echo "Failed to make snapshot"
  exit 1
fi

echo "Uploading blockchain snapshot to s3"
aws $AWS_FLAGS s3 cp "$BLOCKCHAIN_SNAPSHOT" "$AWS_PATH"
if [ "$?" != 0 ]; then
  echo "Upload failed. Leaving snapshot at $BLOCKCHAIN_SNAPSHOT"
  exit 1
fi

echo "Upload finished. Deleting snapshot"

rm -f "$BLOCKCHAIN_SNAPSHOT"

echo "Done"
