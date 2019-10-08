#!/bin/bash

user=${@}

if [ -z "$user" ]; then
  user=$(whoami)
fi

sudo systemctl stop elrond.service
sudo systemctl disable elrond.service 
sudo systemctl daemon-reload

sudo rm -rf /lib/systemd/system/elrond.service
wget -q https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/systemd/elrond.service
sed -i "s/---USER---/${user}/g" elrond.service
sudo cp elrond.service /lib/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable elrond.service
sudo systemctl start elrond.service
sudo systemctl status elrond.service
