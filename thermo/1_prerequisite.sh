#!/bin/bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv
sudo pip3 install west --break-system-packages
sudo pip3 install pyyaml --break-system-packages
brew install python@3.14
mkdir -p ~/.local/bin && cd ~/.local/bin
unlink pip
unlink pip3
unlink python
unlink python3
set -x
ln -s /home/linuxbrew/.linuxbrew/bin/pip3.14 pip
ln -s /home/linuxbrew/.linuxbrew/bin/pip3.14 pip3
ln -s /home/linuxbrew/.linuxbrew/bin/python3.14 python
ln -s /home/linuxbrew/.linuxbrew/bin/python3.14 python3
set +x
#west
sudo pip3 install west
brew install cmake
brew install ninja
sudo apt-get install -y libssl-dev libdbus-1-dev libglib2.0-dev libavahi-client-dev libgirepository1.0-dev libcairo2-dev libreadline-dev
