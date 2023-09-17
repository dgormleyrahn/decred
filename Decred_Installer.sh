#!/bin/bash

# === CONFIGURABLE VARIABLES ===

# Directories and Paths
HOME_DIR="/home/username"
ERROR_LOG="$HOME_DIR/error.log"
MESSAGE_LOG="$HOME_DIR/message.log"
GO_TAR_PATH="$HOME_DIR/go1.21.1.linux-amd64.tar.gz"
GOMINER_DIR="$HOME_DIR/gominer"
CERTIFICATE_DIR="$HOME_DIR/.dcrd"
CERTIFICATE_FILE="$CERTIFICATE_DIR/rpc.cert"
GOMINER_CONF="$HOME_DIR/.gominer/gominer.conf"

# URLs and Repos
GO_DOWNLOAD_URL="https://go.dev/dl/go1.21.1.linux-amd64.tar.gz"
GOMINER_REPO_URL="https://github.com/decred/gominer"

# Certificate content
CERTIFICATE_CONTENT="-----BEGIN CERTIFICATE-----
[... your certificate content here ...]
-----END CERTIFICATE-----"

# Gominer Configuration
SYS_USER="username"
RPC_USER="RPC User"
RPC_PASS="RPC Pass"
RPC_SERVER="Server Address"
RPC_CERT="$CERTIFICATE_FILE"

# ================================


# Function to log errors
log_error() {
  local timestamp
  timestamp=$(date +"%Y-%m-%d %T")
  echo "[$timestamp] Error: $1" >> "$ERROR_LOG"
}

# Function to log general messages
log_info() {
  local timestamp
  timestamp=$(date +"%Y-%m-%d %T")
  echo "[$timestamp] Info: $1" >> "$MESSAGE_LOG"
}

# Check if the script is run with sudo privileges
if [ "$EUID" -ne 0 ]; then
  log_error "Please run this script with sudo: sudo $0"
  exit 1
fi

# Clear the home directory
rm -rf $HOME_DIR/*
if [ $? -ne 0 ]; then
  log_error "Failed to clear @HOME_DIR directory."
  exit 1
fi


# Function to check if a command or package is available
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed"
}


# Check and install git if not present
if ! command_exists git; then
    echo "Installing git..."
    sudo apt update
    sudo apt install -y git
    if [ $? -ne 0 ]; then
        log_error "Failed to install git."
        exit 1
    fi
else
    echo "Git is already installed."
fi

# Use lspci to get the list of VGA devices
DETECTED_GPU=$(lspci | grep -E 'VGA|3D')

# Check if the detected GPU string contains NVIDIA or AMD
if echo "$DETECTED_GPU" | grep -qi "NVIDIA"; then
   log_info "Detected GPU: NVIDIA"
   
   # Install NVIDIA-specific package if it's not already installed
   if ! package_installed nvidia-opencl-dev; then
       sudo apt update
       if ! sudo apt install -y nvidia-opencl-dev; then
           log_error "Failed to install nvidia-opencl-dev."
           exit 1
       fi
   else
       log_info "NVIDIA OpenCL is already installed."
   fi

elif echo "$DETECTED_GPU" | grep -qi "Advanced Micro Devices"; then
   log_info "Detected GPU: AMD"
   
   # Install AMD-specific package if it's not already installed
   if ! package_installed opencl-headers; then
       sudo apt update
       if ! sudo apt install -y opencl-headers; then
           log_error "Failed to install opencl-headers."
           exit 1
       fi
   else
       log_info "AMD OpenCL is already installed."
   fi

else
   log_error "Unknown GPU type or unsupported GPU."
   exit 1
fi


if [ ! -f /usr/local/go/bin/go ]; then
  # Download and install go to home directory
  GO_TAR_PATH="$HOME_DIR/go1.21.1.linux-amd64.tar.gz"
  if ! sudo -u $SYS_USER wget https://go.dev/dl/go1.21.1.linux-amd64.tar.gz -O "$GO_TAR_PATH"; then
    log_error "Failed to download Go."
  else
    sudo tar -C /usr/local -xvf "$GO_TAR_PATH"
    rm -f "$GO_TAR_PATH"
    # Add Go binary directory to user's PATH
    echo 'export PATH=$PATH:/usr/local/go/bin' >> $HOME_DIR/.profile
  fi
else
  echo "Go is already installed."
fi


# Clone the gominer repository to home directory
if ! sudo -u $SYS_USER git clone https://github.com/decred/gominer $GOMINER_DIR; then
  log_error "Failed to clone gominer repository."
fi

# Build gominer with opencl tags using the full path and check for errors
source $HOME_DIR/.profile
cd $GOMINER_DIR
if sudo -u $SYS_USER /usr/local/go/bin/go build -tags opencl >> "$MESSAGE_LOG" 2>&1; then
    log_info "gominer built successfully."
else
    log_error "Failed to build gominer with opencl tags. Check $MESSAGE_LOG for details."
    exit 1
fi

# Remove any old certificates
rm -f $CERTIFICATE_FILE

# Create the directory if it doesn't exist
if [ ! -d "$CERTIFICATE_DIR" ]; then
  mkdir -p "$CERTIFICATE_DIR"
fi

# Write the certificate content to the file
echo "$CERTIFICATE_CONTENT" > "$CERTIFICATE_FILE"

# Check if the certificate file was created successfully
if [ -f "$CERTIFICATE_FILE" ]; then
  echo "Certificate file created successfully at $CERTIFICATE_FILE"
else
  echo "Failed to create the certificate file."
fi

# Create gominer configuration file if it doesn't exist
if [ ! -f "$GOMINER_CONF" ]; then
  echo "rpcuser=$RPC_USER" >> "$GOMINER_CONF"
  echo "rpcpass=$RPC_PASS" >> "$GOMINER_CONF"
  echo "rpcserver=$RPC_SERVER" >> "$GOMINER_CONF"
  echo "rpccert=$RPC_CERT" >> "$GOMINER_CONF"
  echo "Created gominer configuration file at $GOMINER_CONF"
fi
  
# Print a message indicating the script has completed
echo "Setup completed successfully."
