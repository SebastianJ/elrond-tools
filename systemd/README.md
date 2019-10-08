# elrond-tools / systemd

Systemd unit to run the elrond node.

Manual install:
 - Download Systemd unit file from https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/systemd/elrond.service
 - Replace $$$USER$$$ with the user that installed the node / running the node.
 - Activate the Systemd unit:
 
```
sudo systemctl daemon-reload
sudo systemctl enable elrond.service
sudo systemctl start elrond.service
sudo systemctl status elrond.service
```

Automatic install:

Using the automatic installer you can either let it default to set the user to the user currently running the script:

bash <(curl -s -S -L https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/systemd/install_systemd.sh)

or specify a user yourself:

bash <(curl -s -S -L https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/systemd/install_systemd.sh) user
