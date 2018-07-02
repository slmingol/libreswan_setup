#!/usr/bin/env bash

print() {
    local msgtype="$1"
    local message="$2"
    local opt="$3"
    local date="$(date +'%Y-%m-%d %H:%M:%S') "
    local prefix

    case $msgtype in
        progress)
            prefix="${c_lgreen}[.] "
            ;;
        info)
            prefix="${c_yellow}[!] "
            ;;
        error)
            prefix="${c_red}[x] "
            ;;
        warning)
            prefix="${c_red}[!] "
            ;;
        confirm)
            prefix="${c_lblue}[?] "
            ;;
        exec)
            prefix="${c_lgrey}[$] executing: "
            ;;
        *)
            prefix="    "
            ;;
    esac

    echo -e $opt "${date}${prefix}${message}${c_normal}"
}

abort() {
    local message="$1"
    print error "$message"
    exit 1
}

execute() {
    print exec "'$*'"
    echo -e -n "${c_grey}"
    $sudo_cmd "$@"
    local ret=$?
    echo -e -n "${c_normal}"
    return $ret
}

setup_terminal() {
    if [ "$TERM" = "xterm" -o "$TERM" = "linux" -o "$TERM" = "xterm-256color" ]; then
        c_bold="\e[1m"
        c_unbold="\e[21m"
        c_red="\e[91m"
        c_grey="\e[90m"
        c_lgrey="\e[37m"
        c_yellow="\e[33m"
        c_lgreen="\e[92m"
        c_lblue="\e[94m"
        c_normal="\e[0m"
    fi

    redislabs="${c_bold}${c_red}redis${c_grey}labs${c_normal}"
    RedisLabs="${c_bold}${c_red}Redis${c_grey}Labs${c_normal}"
}



usage() {
    echo "usage: setup_ipsec.sh [-h] -p pre-shared-secret -i INTERFACE_NAME -addrs NODE1_IP,NODE2_IP..."
    echo "Where the node IP list does not contain this node IP"
    echo "And the interface name should match the internal cluster interface"
    echo "On the first node, run without -p flag to generate secret, and then use the specified secret on other nodes"
    exit 255
}

IPS=""
PSK=""
IFACE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h)
            usage
            ;;
        -i)
            IFACE="%$2"
            shift
            ;;
        -addrs)
            IPS="$2"
            shift
            ;;
        -p)
            PSK="$2"
            shift
            ;;
        *)
            usage
            ;;
    esac
    shift
done

if [ `whoami` = root ]; then
    print info "Running as user root, sudo is not required."
    sudo_cmd=""
else
    print progress "Not root, checking sudo"
    if [ `sudo whoami` != root ]; then
        abort "Failed to use sudo, please check configuration"
    else
        print info "sudo is working, you may need to re-type your password"
        sudo_cmd="sudo "
    fi
fi

toplevel_dir=`pwd`

$sudo_cmd yum install -yy libreswan

if [ "${PSK}" = "" ]; then
    print info "No secret provided, generating initial PSK"
    PSK=`openssl rand -base64 48`
    print info "Please use the following secret in all other nodes: ${PSK}"
fi

OLDIFS="${IFS}"
IFS=","
IP_LIST=(${IPS})
IFS=${OLDIFS}

# $sudo_cmd sh -c "echo \": PSK \"${PSK}\"\" > /etc/ipsec.d/redislabs.secrets"
$sudo_cmd sh -c "cat > /etc/ipsec.d/redislabs.secrets <<EOF
: PSK \"${PSK}\"
EOF"

$sudo_cmd sh -c "cat > /etc/ipsec.d/redislabs.conf <<EOF
conn host-to-host
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    left=${IFACE}
    type=tunnel
    authby=secret
    auto=start

EOF"

for ip in "${IP_LIST[@]}"; do
    echo "Adding IP $ip"
$sudo_cmd sh -c "cat >> /etc/ipsec.d/redislabs.conf <<EOF
conn node_$ip
    also=host-to-host
    right=$ip

EOF"
done

$sudo_cmd semanage fcontext -a -t ipsec_key_file_t '/etc/ipsec.d/.*'
$sudo_cmd restorecon -R -v /etc/ipsec.d/

$sudo_cmd ipsec restart