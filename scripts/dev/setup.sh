#!/bin/bash

# Development environment setup script for MerkleKV Mobile
# This script sets up the complete development environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo -e "${BLUE}🚀 MerkleKV Mobile Development Environment Setup${NC}"
echo "=================================================="

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install system dependencies
install_system_deps() {
    echo -e "${YELLOW}📦 Installing system dependencies...${NC}"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Ubuntu/Debian
        if command_exists apt; then
            sudo apt update
            sudo apt install -y \
                curl \
                git \
                unzip \
                xz-utils \
                zip \
                libglu1-mesa \
                build-essential \
                libssl-dev \
                pkg-config \
                mosquitto-clients \
                docker.io \
                docker-compose
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            brew install mosquitto docker docker-compose
        else
            echo -e "${RED}❌ Homebrew not found. Please install Homebrew first.${NC}"
            exit 1
        fi
    fi
}

# Function to install Dart SDK
install_dart() {
    echo -e "${YELLOW}🎯 Installing Dart SDK...${NC}"
    
    if command_exists dart; then
        echo -e "${GREEN}✅ Dart SDK already installed: $(dart --version)${NC}"
        return
    fi
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Install Dart on Linux
        sudo sh -c 'wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -'
        sudo sh -c 'wget -qO- https://storage.googleapis.com/download.dartlang.org/linux/debian/dart_stable.list > /etc/apt/sources.list.d/dart_stable.list'
        sudo apt update
        sudo apt install dart
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Install Dart on macOS
        brew tap dart-lang/dart
        brew install dart
    fi
    
    # Add Dart to PATH
    export PATH="$PATH:/usr/lib/dart/bin"
    echo 'export PATH="$PATH:/usr/lib/dart/bin"' >> ~/.bashrc
}

# Function to install Flutter
install_flutter() {
    echo -e "${YELLOW}📱 Installing Flutter SDK...${NC}"
    
    if command_exists flutter; then
        echo -e "${GREEN}✅ Flutter SDK already installed: $(flutter --version | head -n1)${NC}"
        return
    fi
    
    FLUTTER_DIR="$HOME/flutter"
    
    if [ ! -d "$FLUTTER_DIR" ]; then
        cd "$HOME"
        git clone https://github.com/flutter/flutter.git -b stable
    fi
    
    # Add Flutter to PATH
    export PATH="$PATH:$FLUTTER_DIR/bin"
    echo "export PATH=\"\$PATH:$FLUTTER_DIR/bin\"" >> ~/.bashrc
    
    # Run Flutter doctor
    flutter doctor
}

# Function to install Node.js and npm
install_nodejs() {
    echo -e "${YELLOW}📦 Installing Node.js and npm...${NC}"
    
    if command_exists node && command_exists npm; then
        echo -e "${GREEN}✅ Node.js already installed: $(node --version)${NC}"
        echo -e "${GREEN}✅ npm already installed: $(npm --version)${NC}"
        return
    fi
    
    # Install Node.js using NodeSource repository
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt install -y nodejs
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install node
    fi
}

# Function to install global Dart/Flutter tools
install_dart_tools() {
    echo -e "${YELLOW}🔧 Installing Dart/Flutter global tools...${NC}"
    
    # Install Melos for monorepo management
    dart pub global activate melos
    
    # Install coverage tool
    dart pub global activate coverage
    
    # Install build_runner
    dart pub global activate build_runner
    
    # Install dhttpd for serving docs
    dart pub global activate dhttpd
    
    echo -e "${GREEN}✅ Global Dart tools installed${NC}"
}

# Function to setup Docker
setup_docker() {
    echo -e "${YELLOW}🐳 Setting up Docker...${NC}"
    
    if ! command_exists docker; then
        echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
        return 1
    fi
    
    # Add user to docker group (Linux only)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo usermod -aG docker $USER
        echo -e "${YELLOW}⚠️  You may need to log out and back in for Docker group changes to take effect${NC}"
    fi
    
    # Test Docker
    if docker run --rm hello-world > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Docker is working correctly${NC}"
    else
        echo -e "${YELLOW}⚠️  Docker may require additional setup${NC}"
    fi
}

# Function to bootstrap the project
bootstrap_project() {
    echo -e "${YELLOW}🏗️  Bootstrapping MerkleKV Mobile project...${NC}"
    
    cd "$PROJECT_ROOT"
    
    # Install npm dependencies
    if [ -f "package.json" ]; then
        npm install
    fi
    
    # Bootstrap Dart packages with Melos
    if [ -f "melos.yaml" ]; then
        melos bootstrap
    fi
    
    echo -e "${GREEN}✅ Project bootstrapped successfully${NC}"
}

# Function to setup MQTT broker
setup_mqtt_broker() {
    echo -e "${YELLOW}🌐 Setting up local MQTT broker...${NC}"
    
    cd "$PROJECT_ROOT/broker/mosquitto"
    
    # Generate TLS certificates
    if [ ! -f "config/tls/ca.crt" ]; then
        echo -e "${YELLOW}🔐 Generating TLS certificates...${NC}"
        ./scripts/generate_certs.sh
    fi
    
    # Create default users
    if [ ! -f "config/passwd" ]; then
        echo -e "${YELLOW}👥 Creating default users...${NC}"
        # Create empty password file first
        touch config/passwd
        # Run user creation script with default option
        echo "4" | ./scripts/create_users.sh
    fi
    
    echo -e "${GREEN}✅ MQTT broker configured${NC}"
}

# Function to start development environment
start_dev_env() {
    echo -e "${YELLOW}🚀 Starting development environment...${NC}"
    
    cd "$PROJECT_ROOT/broker/mosquitto"
    
    # Start MQTT broker
    docker-compose up -d
    
    # Wait for broker to be ready
    echo -e "${YELLOW}⏳ Waiting for MQTT broker to be ready...${NC}"
    sleep 10
    
    # Test MQTT connection
    if mosquitto_pub -h localhost -p 1883 -u test_user -P test_pass -t test/topic -m "Hello MerkleKV!" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ MQTT broker is running and accessible${NC}"
    else
        echo -e "${RED}❌ MQTT broker connection test failed${NC}"
    fi
    
    echo -e "${GREEN}✅ Development environment started${NC}"
}

# Function to show development environment status
show_status() {
    echo -e "${BLUE}📊 Development Environment Status${NC}"
    echo "=================================="
    
    # Check Dart
    if command_exists dart; then
        echo -e "${GREEN}✅ Dart: $(dart --version 2>&1 | head -n1)${NC}"
    else
        echo -e "${RED}❌ Dart: Not installed${NC}"
    fi
    
    # Check Flutter
    if command_exists flutter; then
        echo -e "${GREEN}✅ Flutter: $(flutter --version | head -n1)${NC}"
    else
        echo -e "${RED}❌ Flutter: Not installed${NC}"
    fi
    
    # Check Node.js
    if command_exists node; then
        echo -e "${GREEN}✅ Node.js: $(node --version)${NC}"
    else
        echo -e "${RED}❌ Node.js: Not installed${NC}"
    fi
    
    # Check Docker
    if command_exists docker; then
        echo -e "${GREEN}✅ Docker: $(docker --version)${NC}"
    else
        echo -e "${RED}❌ Docker: Not installed${NC}"
    fi
    
    # Check Melos
    if command_exists melos; then
        echo -e "${GREEN}✅ Melos: Installed${NC}"
    else
        echo -e "${RED}❌ Melos: Not installed${NC}"
    fi
    
    # Check MQTT broker
    if docker ps | grep -q merkle_kv_mosquitto; then
        echo -e "${GREEN}✅ MQTT Broker: Running${NC}"
    else
        echo -e "${YELLOW}⚠️  MQTT Broker: Not running${NC}"
    fi
}

# Main setup function
main() {
    case "${1:-setup}" in
        "setup")
            echo -e "${BLUE}🔧 Running full development environment setup...${NC}"
            install_system_deps
            install_dart
            install_flutter
            install_nodejs
            install_dart_tools
            setup_docker
            bootstrap_project
            setup_mqtt_broker
            show_status
            echo ""
            echo -e "${GREEN}🎉 Development environment setup complete!${NC}"
            echo ""
            echo -e "${YELLOW}📝 Next steps:${NC}"
            echo "1. Run 'source ~/.bashrc' or restart your terminal"
            echo "2. Run '$0 start' to start the development environment"
            echo "3. Run '$0 status' to check the status"
            ;;
        "start")
            start_dev_env
            ;;
        "status")
            show_status
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  setup    Run full development environment setup (default)"
            echo "  start    Start the development environment"
            echo "  status   Show development environment status"
            echo "  help     Show this help message"
            ;;
        *)
            echo -e "${RED}❌ Unknown command: $1${NC}"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
