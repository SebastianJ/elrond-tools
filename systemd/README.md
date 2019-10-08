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

