# elrond-tools / setup

Installation and updater script for Elrond: Battle of Nodes.

The script has the following functionality:
- Auto-install GVM (Go Version Manager) and Go (the script automatically detects if this needs to be done)
- Fetch the latest released versions of elrond-go and elrond-config
- Fetch all dependent go modules
- Builds the relevant binaries
- Automatically generate keys if no existing keypairs are detected
- Automatically copy existing keypairs if they are detected
- Automatic backups of detected keypairs
- Automatic cleanup of previous installation's log and stats files. Previous database can also be removed using --reset-database
- Automatic installation of a Systemd unit with appropriate settings
- Automatically start the node using the normal binary, using tmux or using Systemd when the installation has completed

## Arguments
From `./setup.sh --help`:

Usage: ./setup.sh [option] command
Options:
   --go-path        path  the go path where files should be installed, will default to /home/deploy/go
   --display-name   name  the display name for the node
   --reinstall            perform a clean / full reinstall (make sure you have backed up your keys before doing this!)
   --reset-database       resets the database for an existing installation
   --gvm                  force installation/reinstallation of gvm and go
   --go-version           what version of golang to install, defaults to go1.13.1
   --systemd              install a systemd to manage the node process
   --tmux                 use tmux for starting the node
   --start                if the script should start the node after the setup process has completed
   --help                 print this help

## Local installation examples

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

## Direct installation examples

bash <(curl -s -S -L https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/setup/setup.sh) --start