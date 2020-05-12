#!/bin/bash
# Usage entrypoint.sh CDM_IP="Y.X.Y.Z" CDM_USER="" CDM_KEY="" JUMPHOST_IP="" JUMPHOST_USER="" JUMPHOST_KEY=""
for ARGUMENT in "$@"
do
    
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)
    
    case "$KEY" in
        CDM_IP)           CDM_IP=${VALUE} ;;
        CDM_USER)         CDM_USER=${VALUE} ;;
        CDM_KEY)          CDM_KEY=${VALUE} ;;
        JUMPHOST_IP)      JUMPHOST_IP=${VALUE} ;;
        JUMPHOST_USER)    JUMPHOST_USER=${VALUE} ;;
        JUMPHOST_KEY)     JUMPHOST_KEY=${VALUE} ;;
        METHOD)           METHOD=${VALUE} ;;
        VERBOSE)          VERBOSE=${VALUE} ;;
        AUTO_LAUNCH)      AUTO_LAUNCH=${VALUE} ;;
        *)
    esac
    
done

METHOD=$(echo $METHOD | awk '{print tolower($0)}')
VERBOSE=$(echo $VERBOSE | awk '{print tolower($0)}')
AUTO_LAUNCH=$(echo $AUTO_LAUNCH | awk '{print tolower($0)}')

echo "METHOD = $METHOD"
echo "VERBOSE = $VERBOSE"
echo "AUTO_LAUNCH = $AUTO_LAUNCH"

# Set Auto Launch to default true
if [ "$AUTO_LAUNCH" == "false" ]; then
    AUTO_LAUNCH=false
else
    AUTO_LAUNCH=true
fi

# Check if METHOD and VERBOSE argument exist
if [ -n "$METHOD" ]; then
    if ! ( [ "$METHOD" == "auto" ] || [ "$METHOD" == "nat" ] || [ "$METHOD" == "tproxy" ] || [ "$METHOD" == "pf" ] ); then
        METHOD="auto"
    fi
else
    METHOD="auto"
fi

if [ -n "$VERBOSE" ]; then
    VERBOSE="-$VERBOSE"
fi

# Create SSH Config
PROXY_COMMAND=""

if [ -n "$JUMPHOST_IP" ] && [ -n "$JUMPHOST_USER" ] && [ -n "$JUMPHOST_KEY" ]
then
    echo "Create JumpHost SSH Configuration"
cat << EOF > /root/.ssh/config
# JUMP HOST
Host JumpHost
    HostName ${JUMPHOST_IP}
    User ${JUMPHOST_USER}
    IdentityFile ${JUMPHOST_KEY}
EOF
    PROXY_COMMAND="ProxyCommand ssh -q -W %h:%p JumpHost"
fi

if [ -z "$CDM_IP" ] || [ -z "$CDM_USER" ] || [ -z "$CDM_KEY" ]
then
    echo "No or not enough arguments"
    exit 22
else
    echo "Create RemoteCDM SSH Configuration"
cat << EOF >> /root/.ssh/config
# CUSTOMER CDM
Host RemoteCDM
    HostName ${CDM_IP}
    User ${CDM_USER}
    IdentityFile ${CDM_KEY}
    ${PROXY_COMMAND}
EOF
fi

echo "CDM_IP = $CDM_IP"
echo "CDM_USER = $CDM_USER"
echo "CDM_KEY = $CDM_KEY"
echo "JUMPHOST_IP = $JUMPHOST_IP"
echo "JUMPHOST_USER = $JUMPHOST_USER"
echo "JUMPHOST_KEY = $JUMPHOST_KEY"
echo "METHOD = $METHOD"
echo "VERBOSE = $VERBOSE"
echo "AUTO_LAUNCH = $AUTO_LAUNCH"

# Set Permission
echo "Change Write Permission: /root/.ssh/config"
if [[ -f "/root/.ssh/config" ]]
then
    echo "File /root/.ssh/config exist"
    chmod 600 /root/.ssh/config
    echo "---  STAT OF CONTENT --- "
    cat /root/.ssh/config
    echo "---  END OF CONTENT --- "
fi

#
echo "Check $JUMPHOST_KEY"
if [[ -f "$JUMPHOST_KEY" ]]
then
    #chmod 600 $JUMPHOST_KEY
    echo "File $JUMPHOST_KEY exist"
    echo "---  STAT OF CONTENT --- "
    cat $JUMPHOST_KEY
    echo "---  END OF CONTENT --- "
    echo "Add Jump Host Fingerprint"
    ssh-keyscan -H $JUMPHOST_IP >> /root/.ssh/known_hosts
else
    if [ -n "$JUMPHOST_KEY" ]; then
        echo "Create JumpHost key file"
        mkdir -p "$(dirname "$JUMPHOST_KEY")" && touch "$JUMPHOST_KEY"
        chmod 600 $JUMPHOST_KEY
    fi
fi

#
echo "Check $CDM_KEY"
if [[ -f "$CDM_KEY" ]]
then
    #chmod 600 $CDM_KEY
    echo "File $CDM_KEY exist"
    echo "---  STAT OF CONTENT --- "
    cat $CDM_KEY
    echo "---  END OF CONTENT --- "
    
    
    if [[ -z "$PROXY_COMMAND" ]]
    then
        echo "Add CDM Fingerprint"
        ssh-keyscan -H $CDM_IP >> /root/.ssh/known_hosts
    else
        echo "Add CDM Fingerprint with expect"
cat << EOF >> /root/tmp.sh
#!/usr/bin/expect
set timeout 5
set prompt {[#>$]}
spawn ssh RemoteCDM
expect {
    "fingerprint" {
        send "yes\r"
        expect {
            timeout { puts stderr "Login timeout" ; close $spawn_id; exit 1 }
            -re $prompt { puts stdout "Auto login successful"; close $spawn_id; exit 0 }
        }
        puts stderr "Auto login failed"
        close $spawn_id
        exit 1
    }
}
puts stderr "No connection / prompt"
close $spawn_id
exit 1
EOF
        chmod +x /root/tmp.sh
        expect /root/tmp.sh
        rm /root/tmp.sh
    fi
else
    if [ -n "$CDM_KEY" ]; then
        echo "Create RemoteCDM key file"
        mkdir -p "$(dirname "$CDM_KEY")" && touch "$CDM_KEY"
        chmod 600 $CDM_KEY
    fi
fi

# Start SSH and Rsyslog
# /etc/init.d/rsyslog --dry-run start
# /etc/init.d/rsyslog start
/etc/init.d/sshd --dry-run start
/etc/init.d/sshd start

if [ "$AUTO_LAUNCH" == "true" ]; then
    # Launch sshuttle as deamon
    INET_ADDR=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
    echo "Run sshuttle"
    echo "$ sshuttle -l 0.0.0.0:0 --dns $VERBOSE --exclude $CDM_IP --exclude $INET_ADDR --method $METHOD --remote RemoteCDM --python=/usr/bin/python2.7 0/0"
    sshuttle -l 0.0.0.0:0 --dns $VERBOSE --exclude $CDM_IP --exclude $INET_ADDR --method $METHOD --remote RemoteCDM --python=/usr/bin/python2.7 0/0
else
    echo "Run without sshuttle"
    tail -f /dev/null
fi