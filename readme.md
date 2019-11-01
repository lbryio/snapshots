# snapshots
Repo containing scripts to create blockchain and wallet server snapshots

Run `./ec2go.sh` to kick off the process. This will create an EC2 instance that installs lbrycrd, catches up to the blockchain tip, creates
a snapshot, and uploads it to https://snapshots.lbry.com. The instance will stick around, and you can run the `snapshot.sh` script on the
instance to create another snapshot at any time (it will be faster, because most of the blockchain data will already be there).
