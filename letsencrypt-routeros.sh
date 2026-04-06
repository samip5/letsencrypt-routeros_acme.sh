#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
CONFIG_FILE="$SCRIPT_DIR/letsencrypt-routeros.settings"

source $CONFIG_FILE

if [[ -z $ROUTEROS_USER ]] || [[ -z $ROUTEROS_HOST ]] || [[ -z $ROUTEROS_SSH_PORT ]] || [[ -z $ROUTEROS_PRIVATE_KEY ]]; then
        echo "Check the config file $CONFIG_FILE. It MUST be filled with actual parameters"
        echo "Please avoid spaces"
        exit 1
fi

if [[ -n $1 ]] && [[ -n $2 ]] && [[ -n $3 ]] && [[ -n $4 ]] && [[ -n $5 ]]; then
        # Called as acme.sh deploy hook: domain keyfile certfile cafile fullchain
        DOMAIN=$1
        KEY=$2
        CERTIFICATE=$5
else
        # Manual invocation: use DOMAIN from config and detect paths
        if [[ -z $DOMAIN ]]; then
                echo "Check the config file $CONFIG_FILE. DOMAIN must be set."
                exit 1
        fi

        if [[ -z $LE_WORKING_DIR ]]; then
                echo "Not found installed acme.sh"
                echo "Edit $CONFIG_FILE and set up correct directory with acme.sh certificates in LE_WORKING_DIR variable"
                exit 1
        fi

        # Detect ECC: acme.sh stores ECC certs in ${DOMAIN}_ecc/ but key is still named ${DOMAIN}.key
        if [[ -d $LE_WORKING_DIR/${DOMAIN}_ecc ]]; then
                CERT_DIR=$LE_WORKING_DIR/${DOMAIN}_ecc
        else
                CERT_DIR=$LE_WORKING_DIR/$DOMAIN
        fi
        CERTIFICATE=$CERT_DIR/fullchain.cer
        KEY=$CERT_DIR/$DOMAIN.key
fi

#Create alias for RouterOS command
routeros="ssh -i $ROUTEROS_PRIVATE_KEY $ROUTEROS_USER@$ROUTEROS_HOST -p $ROUTEROS_SSH_PORT"

#Check connection to RouterOS
$routeros /system resource print

if [[ ! $? == 0 ]]; then
        echo -e "\nError in: $routeros"
        echo "More info: https://wiki.mikrotik.com/wiki/Use_SSH_to_execute_commands_(DSA_key_login)"
        exit 1
else
        echo -e "\nConnection to RouterOS Successful!\n"
fi

if [ ! -r $CERTIFICATE ] && [ ! -r $KEY ]; then
        echo -e "\nFile(s) not found:\n$CERTIFICATE\n$KEY\n"
        echo -e "Please check path to files and acme.sh home dir"
        exit 1
fi

# Remove previous certificate
$routeros /certificate remove [find name=$DOMAIN.pem_0]

# Create Certificate
# Delete Certificate file if the file exist on RouterOS
$routeros /file remove $DOMAIN.pem > /dev/null
# Upload Certificate to RouterOS
scp -q -P $ROUTEROS_SSH_PORT -i "$ROUTEROS_PRIVATE_KEY" "$CERTIFICATE" "$ROUTEROS_USER"@"$ROUTEROS_HOST":"$DOMAIN.pem"
sleep 2
# Import Certificate file
$routeros /certificate import file-name=$DOMAIN.pem passphrase=\"\"
# Delete Certificate file after import
$routeros /file remove $DOMAIN.pem

# Create Key
# Delete Key file if the file exist on RouterOS
$routeros /file remove $DOMAIN.key > /dev/null
# Upload Key to RouterOS
scp -q -P $ROUTEROS_SSH_PORT -i "$ROUTEROS_PRIVATE_KEY" "$KEY" "$ROUTEROS_USER"@"$ROUTEROS_HOST":"$DOMAIN.key"
sleep 2
# Import Key file
$routeros /certificate import file-name=$DOMAIN.key passphrase=\"\"
# Delete Key file after import
$routeros /file remove $DOMAIN.key

# Setup Certificate to SSTP Server
$routeros /interface sstp-server server set certificate=$DOMAIN.pem_0

#$routeros /ip service set www-ssl certificate=$DOMAIN.pem_0
#$routeros /ip service set api-ssl certificate=$DOMAIN.pem_0

exit 0
