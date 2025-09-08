#!/bin/bash

# Create users for MerkleKV Mobile MQTT broker
# This script manages user accounts and passwords

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
PASSWD_FILE="${CONFIG_DIR}/passwd"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔐 MerkleKV Mobile User Management${NC}"
echo "=================================="

# Function to create a user
create_user() {
    local username="$1"
    local password="$2"
    
    if [ -z "$username" ] || [ -z "$password" ]; then
        echo -e "${RED}❌ Username and password are required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}📝 Creating user: $username${NC}"
    
    # Create or update user
    mosquitto_passwd -b "$PASSWD_FILE" "$username" "$password"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ User '$username' created/updated successfully${NC}"
    else
        echo -e "${RED}❌ Failed to create user '$username'${NC}"
        return 1
    fi
}

# Function to delete a user
delete_user() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo -e "${RED}❌ Username is required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}🗑️  Deleting user: $username${NC}"
    
    # Delete user
    mosquitto_passwd -D "$PASSWD_FILE" "$username"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ User '$username' deleted successfully${NC}"
    else
        echo -e "${RED}❌ Failed to delete user '$username'${NC}"
        return 1
    fi
}

# Function to list users
list_users() {
    echo -e "${BLUE}👥 Current users:${NC}"
    if [ -f "$PASSWD_FILE" ]; then
        cut -d: -f1 "$PASSWD_FILE" | sort
    else
        echo -e "${YELLOW}⚠️  No password file found${NC}"
    fi
}

# Function to generate a random password
generate_password() {
    openssl rand -base64 12 | tr -d "=+/" | cut -c1-12
}

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Check if mosquitto_passwd is available
if ! command -v mosquitto_passwd &> /dev/null; then
    echo -e "${RED}❌ mosquitto_passwd command not found${NC}"
    echo "Please install mosquitto-clients package"
    exit 1
fi

# Main menu
while true; do
    echo ""
    echo -e "${BLUE}What would you like to do?${NC}"
    echo "1) Create/Update user"
    echo "2) Delete user"
    echo "3) List users"
    echo "4) Create default users"
    echo "5) Exit"
    echo -n "Enter choice [1-5]: "
    
    read -r choice
    
    case $choice in
        1)
            echo -n "Enter username: "
            read -r username
            echo -n "Enter password (leave empty to generate): "
            read -s password
            echo
            
            if [ -z "$password" ]; then
                password=$(generate_password)
                echo -e "${YELLOW}Generated password: $password${NC}"
            fi
            
            create_user "$username" "$password"
            ;;
        2)
            echo -n "Enter username to delete: "
            read -r username
            delete_user "$username"
            ;;
        3)
            list_users
            ;;
        4)
            echo -e "${YELLOW}📝 Creating default users...${NC}"
            
            # Admin user
            admin_pass=$(generate_password)
            create_user "admin" "$admin_pass"
            echo -e "${GREEN}Admin password: $admin_pass${NC}"
            
            # Monitor user
            monitor_pass=$(generate_password)
            create_user "monitor" "$monitor_pass"
            echo -e "${GREEN}Monitor password: $monitor_pass${NC}"
            
            # Demo users
            create_user "flutter_demo" "flutter_demo_pass"
            create_user "rn_demo" "rn_demo_pass"
            create_user "cli_tool" "cli_tool_pass"
            
            # Test users
            create_user "test_user" "test_pass"
            create_user "integration_test" "integration_pass"
            create_user "developer" "dev_pass"
            
            # Service users
            repl_pass=$(generate_password)
            create_user "replication_service" "$repl_pass"
            echo -e "${GREEN}Replication service password: $repl_pass${NC}"
            
            monitoring_pass=$(generate_password)
            create_user "monitoring_service" "$monitoring_pass"
            echo -e "${GREEN}Monitoring service password: $monitoring_pass${NC}"
            
            backup_pass=$(generate_password)
            create_user "backup_service" "$backup_pass"
            echo -e "${GREEN}Backup service password: $backup_pass${NC}"
            
            echo -e "${GREEN}✅ Default users created successfully${NC}"
            echo -e "${YELLOW}⚠️  Please save the generated passwords securely!${NC}"
            ;;
        5)
            echo -e "${GREEN}👋 Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            ;;
    esac
done
