#!/bin/bash

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

# -------------------------------------------------------------

# Script information

clear
echo ""
echo "This script will install an Jackal RPC Node along with all of its dependencies, and then start it up."
echo "It has been tested on a brand new installation of Ubuntu 22.04.2 LTS running in VMware 7.0.3."
echo "The virtual machine I used was configured with 2 CPUs, 14GB of RAM, and 700GB of HDD space on a 1TB NVMe drive."
echo "Download the script and type:"
echo ""
echo -e "${GREEN}chmod +x jackal_rpc_node_installer.sh${NC}" 
echo ""
echo "and then finally start it with:"
echo ""
echo -e "${GREEN}source jackal_rpc_node_installer.sh${NC}"
echo ""

echo "Press any key to continue..."
read -n 1 -s

# Prompt user for node name
read -p "Enter the name of your node, example -> mynode01:" nodename

# -------------------------------------------------------------

# Get the latest release information from JackalLabs/canine-chain GitHub
response=$(curl --silent --header "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/JackalLabs/canine-chain/releases/latest")

# Extract the version number from the response using grep and sed
canine_chain_version=$(echo $response | grep -oP '"tag_name": "\K[^"]+' )

# Print the version number
echo "Latest Canine Chain version: $canine_chain_version"

# -------------------------------------------------------------

# Get the latest GO release information from https://go.dev/dl/

go_version=$(curl -s https://go.dev/dl/ | grep -oP 'go\K\d+\.\d+\.\d+\.linux-amd64\.tar\.gz' | head -1 | grep -oP '\d+\.\d+\.\d+')

echo -e "\nLatest Go version: $go_version"
echo -e "Full download URL: https://go.dev/dl/go$go_version.linux-amd64.tar.gz\n"

# -------------------------------------------------------------

cd $HOME

# Countdown function

countdown() {
  for i in 3 2 1; do
    echo -ne "${RED}Starting in $i...${NC}\r"
    sleep 1
  done

  echo -e "\n\n"
}

# -------------------------------------------------------------

# Install required packages
echo -e "\n\n${GREEN}Installing required packages...${NC}"
countdown

sudo apt-get install git curl build-essential make jq gcc snapd chrony lz4 tmux unzip bc -y

# -------------------------------------------------------------

# Update system
echo -e "\n\n${GREEN}Updating system...${NC}"
countdown

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get autoremove -y
sudo apt-get autoclean -y
sudo apt-get remove -y gccgo-go

# -------------------------------------------------------------

# Install Go
echo -e "\n\n${GREEN}Installing Go v$go_version...${NC}"
countdown
wget https://go.dev/dl/go$go_version.linux-amd64.tar.gz && sudo apt-get -y install gcc
sudo tar -C /usr/local -xzf go$go_version.linux-amd64.tar.gz

# -------------------------------------------------------------

# Setting up environment
echo -e "\n\n${GREEN}Setting up environment...${NC}"
countdown

echo 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' >> ~/.profile

# -------------------------------------------------------------

# Reload environment variables
echo -e "\n\n${GREEN}Reload environment variables...${NC}"
countdown

source $HOME/.profile

# -------------------------------------------------------------

# Clone and install Canine Chain
echo -e "${GREEN}Cloning and installing Canine Chain...${NC}"
countdown

git clone https://github.com/JackalLabs/canine-chain
cd $HOME/canine-chain
git checkout $canine_chain_version
make install

# -------------------------------------------------------------

# Initialize Canine Chain
echo -e "${GREEN}Initializing Canine Chain...${NC}"
countdown

canined init "$nodename" --chain-id=jackal-1

# -------------------------------------------------------------

# Download and configure genesis.json, peers.txt, and addrbook.json
echo -e "${GREEN}Downloading and configuring genesis.json, peers.txt, and addrbook.json...${NC}"
countdown

curl https://snapshots.nodestake.top/jackal/genesis.json > $HOME/.canine/config/genesis.json
peers=$(curl -s https://snapshots.nodestake.top/jackal/peers.txt)
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$peers\"/" ~/.canine/config/config.toml
curl -Ls https://snapshots.nodestake.top/jackal/addrbook.json > $HOME/.canine/config/addrbook.json
sed -i 's/cors_allowed_origins = \[\]/cors_allowed_origins = \["\*"\]/g' ~/.canine/config/config.toml

# -------------------------------------------------------------

# Download and extract snapshot
echo -e "${GREEN}Downloading and extracting snapshot...${NC}"
countdown

SNAP_NAME=$(curl -s https://snapshots.nodestake.top/jackal/ | egrep -o ">20.*\.tar.lz4" | tr -d ">")
curl -o - -L https://snapshots.nodestake.top/jackal/${SNAP_NAME} | lz4 -c -d - | tar -x -C $HOME/.canine

# -------------------------------------------------------------

# Configure and start canined service
echo -e "${GREEN}Configuring and starting canined service...${NC}"
countdown

sudo tee /etc/systemd/system/canined.service > /dev/null <<EOF
[Unit]
Description=canined daemon
Wants=network-online.target
After=network-online.target
[Service]
User=jackal
ExecStart=/home/jackal/go/bin/canined start
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable canined
sudo systemctl start canined

# -------------------------------------------------------------

# Check if canined.service is active and running
echo -e "${GREEN}Check if canined.service is active and running...${NC}"
countdown

if systemctl is-active --quiet canined.service && systemctl status canined.service | grep -q "Active: active (running)"; then
  echo "canined.service is up and running."
else
  echo "canined.service is not running or not active."
fi

# Check if there are any errors in the log
if systemctl status canined.service | grep -q "Loaded: error"; then
  echo "There was an error loading canined.service."
elif systemctl status canined.service | grep -q "Failed to start Canine daemon"; then
  echo "canined.service failed to start."
elif systemctl status canined.service | grep -q "Exited with"; then
  echo "canined.service exited with an error."
else
  echo "No errors found in canined.service log."

# -------------------------------------------------------------

# Finished

echo "All done! It should now be up and running in the background, unless any errors occur."
echo "You can monitor the node by typing:"
echo ""
echo "journalctl -f -u canined.service"
echo ""
echo "in the command line."

cd $HOME

fi
