# elrond-tools / setup

Installation and updater script for Elrond: Battle of Nodes.

The script has the following functionality:
- Auto-install GVM (Go Verson Manager) and Go (the script automatically detects if this needs to be done)
- Fetch the latest released versions of elrond-go and elrond-config
- Fetch all dependent go modules
- Build the relevant binaries
- Automatically generate keys if no existing keypairs are detected
- Automatically copy existing keypairs if they are detected
- Automatic backups of detected keypairs
- Automatic cleanup of previous installation's log and stats file. Previous database can also be removed using --reset-database
- Automatic installation of a Systemd unit with appropriate settings
- Automatically start the node using the normal binary, using tmux or using Systemd when the installation has completed

## Examples

### Basic install: `./setup.sh`

If this is done on a VPS/instance that hasn't executed this script before GVM and GO will automatically be installed. Git repos will be downloaded, dependencies fetched and binaries built. Node won't be started after installation.

### Start after install: `./setup.sh --start`

Same as above, but will start the binary after installation is complete.

### Set display name: `./setup.sh --start --display-name hello`

Same as above, but also sets the display name for the node to "hello"


### Using systemd: `./setup.sh --start --display-name hello --systemd`

Same as above, but will also install the Systemd unit and start the node using Systemd

### Using tmux: `./setup.sh --start --display-name hello --tmux`

Like above, but node will be started in a tmux session called elrond.

Attach to the session using tmux attach-session -t elrond

