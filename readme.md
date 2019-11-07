# snapshots
Repo containing scripts to create blockchain and wallet server snapshots

Run `./ec2go.sh` to kick off the process. This will create an EC2 instance that installs Docker, [sets up the servers](https://gist.github.com/lyoshenka/2557c08344bfe1020f0c0a13b9c5b0ce), catches up to the blockchain tip, creates
snapshots, and uploads them to https://snapshots.lbry.com. The instance will stick around, and you can run the `snapshot.sh` script on it to create new snapshots at any time. Subsequent snapshots are faster than the first one because most of the data is already there.
