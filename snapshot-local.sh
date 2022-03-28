#!/bin/bash

#
# Make a local blockchain snapshot
#

#set -x
#set -e
set -uo pipefail

BIN_DIR="$HOME/lbrybins"   # directory where lbrycrdd and lbrycrd-cli binaries are
CONF_DIR="$HOME/.lbrycrd"  # directory where config files and wallets are
SNAPSHOT_DIR="$HOME"       # directory where to temporarily put the snapshot

AWS_PATH="s3://snapshots.lbry.com/blockchain/"  # Where to upload the snapshot to
AWS_FLAGS="--profile mfa --region us-east-2"    # General AWS flags (region, profile, etc)

# TODO: add timing info to each step so I know how long it takes



echo "Running $0"

hash aws 2>/dev/null || { echo >&2 'aws command not found. Install it: sudo apt install awscli'; exit 1;  }

if ! aws $AWS_FLAGS s3 ls > /dev/null 2>/dev/null; then
  echo "not logged into mfa profile on aws. run aws-mfa-refresh.sh"
  exit 1
fi

if ! pgrep lbrycrdd;  then
  echo "Starting lbrycrdd"
  "$BIN_DIR/lbrycrdd" -server -daemon
fi


EXPLORER_BLOCKS=$(curl -s https://explorer.lbry.com/api/v1/status | grep -Eo 'height":([0-9])+' | grep -Eo '[0-9]+')

echo "Waiting until lbrycrdd has caught up to the blockchain tip"

while true; do
  info=$("$BIN_DIR/lbrycrd-cli" getblockchaininfo 2>/dev/null)
  if [ "$?" != 0 ]; then
    echo "Waiting for lbrycrdd to start"
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


LBRYCRD_VERSION=$("$BIN_DIR/lbrycrd-cli" getnetworkinfo 2>/dev/null | grep -m 1 subversion | grep -Eo '[0-9\.]+')

echo "Stopping lbrycrdd at $BLOCKS blocks"
pkill lbrycrdd
echo "Waiting for lbrycrdd to shut down..."
while pgrep lbrycrdd > /dev/null; do sleep 3; done
echo "lbrycrdd stopped"



BLOCKCHAIN_SNAPSHOT="$SNAPSHOT_DIR/lbrycrd_snapshot_${BLOCKS}_v${LBRYCRD_VERSION}_$(date +%F).tgz"

case "$LBRYCRD_VERSION" in
  0.17.3.*)
    TARGETS="blocks/ chainstate/ claimtrie/ indexes/"
    ;;
  0.17.4.*)
    TARGETS="blocks/ indexes/ claims.sqlite block_index.sqlite coins.sqlite"
    ;;
  0.19.1.*)
    TARGETS="blocks/ indexes/ claims.sqlite block_index.sqlite coins.sqlite txindex.sqlite"
    ;;
  *)
    echo "unsupported lbrycrd version $LBRYCRD_VERSION"
    exit 1
    ;;
esac

echo "Making blockchain snapshot $BLOCKCHAIN_SNAPSHOT"
tar -czvf "$BLOCKCHAIN_SNAPSHOT" -C "$CONF_DIR" $TARGETS
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
