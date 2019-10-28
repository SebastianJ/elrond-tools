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
- Support for an auto-updater that compares the current installed version vs the most recent released version on Github

## Arguments
From `./setup.sh --help`:

```
Usage: ./setup.sh [option] command
Options:
   --nodes                    count   the number of nodes you want to install
   --path                     path    where the node data, keys and backups will be installed, defaults to $HOME/elrond
   --go-path                  path    the go path where files should be installed, will default to $HOME/go
   --display-name             name    the display name for the node
   --reinstall                        perform a clean / full reinstall (make sure you have backed up your keys before doing this!)
   --default-port             port    the default port that will be the base to start nodes from, default is 8080
   --backup-database                  backup node instance databases
   --remove-database                  removes/resets the database for node instances
   --gvm                              install go using gvm
   --go-version                       what version of golang to install, defaults to go1.13.1
   --install-auto-updater             install and run an auto-updater that automatically updates the git repos and compiles a new node binary when necessary
   --uninstall-auto-updater           uninstalls/removes the auto-updater
   --systemd                          use systemd for starting the node
   --update-systemd-units             if currently installed Systemd units should be reinstalled (e.g. if they've been updated in the repo)
   --tmux                             use tmux for starting the node
   --start                            if the script should start the node after the setup process has completed
   --stop                             stops all running nodes
   --auto-updater                     if the script should run in auto-updater node
   --interval                         how often the script should run while running in auto-updater mode
   --help                             print this help
```

## Local installation examples

Download and chmod the script:

```
curl -LOs https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/setup/setup.sh && chmod u+x setup.sh
```

### Basic install: `./setup.sh`

If this is done on a VPS/instance that hasn't executed this script before GVM and GO will automatically be installed. Git repos will be downloaded, dependencies fetched and binaries built. Node won't be started after installation.

### Start after install: `./setup.sh --start`

Same as above, but will start the binary after installation is complete.

### Set display name: `./setup.sh --display-name hello --start`

Same as above, but also sets the display name for the node to "hello"

### Using systemd: `./setup.sh --display-name hello --start --systemd`

Same as above, but will also install the Systemd unit and start the node using Systemd

### Using tmux: `./setup.sh --display-name hello --start --tmux`

Like above, but node will be started in a tmux session called elrond.

Attach to the session using tmux attach-session -t elrond

## Direct installation examples

```
bash <(curl -s -S -L https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/setup/setup.sh) --start
```

## Auto-update functionality

First run setup.sh to install everything and make sure that the node is functioning properly (use CTRL+C to stop the node when you see that it's running properly):

`./setup.sh --start`

It's highly recommended that you use Systemd for the auto-update functionality (the script currently only supports this but I'll add tmux support soon).

If the auto-updater by any unexpected reason terminates Systemd will automatically start it back up (same goes for the regular Systemd unit managing the node process).

After a regular setup, install everything required for Systemd and then start the node:

`./setup.sh --install-systemd --install-updater --start --systemd`

