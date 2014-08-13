#!/bin/bash
#
# dyndns v0.6.0
# 
# This program is used to dynamicaly update BIND 
# records from a list of IPs. The first to be
# reachable via ICMP ping is set for the hostname
#
# Copyright (C) 2013-2014 Martin Dobrev <martin@dobrev.eu>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the Affero GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Chanegelog
# =========================================================
#
# v0.6.0 - Dual License under AGPL and MIT
# v0.5.9 - Initial Affero GNU GPL version
#
##################################################################
set +x

# Configuration
VERBOSE=0
LOGFILE=/var/log/dyndns.log
MAILTO="dnsadmin@dobrev.eu"
NSSERVER="10.0.0.1"
ZONE="lab.dobrev.eu"
KEY="/etc/named/Kdobrev.+125-342134.private"
TTL=60

# Do not chage below this line if you don't know what you do
# You're warned :)

PROG=$(basename $0)
VER="v0.6.0"

function check_alive {
  ping -c 1 -w 2 -W 1 -q $1 > /dev/null
  return $?
}

function do_nsupdate {
  local lHOST=$1
  local lIPADDR=$2
  local lTTL=$3

  CURIP=$(dig +short @$NSSERVER $lHOST)

  if [ "$CURIP" = "$lIPADDR" ]; then
    return
  fi

cat <<EOF | nsupdate -k "$KEY"
server $NSSERVER
zone $ZONE
update delete $lHOST. A
update add $lHOST. $lTTL A $lIPADDR
send
EOF

  RC=$?

  if [ $RC != 0 ]; then
    eecho "FAILURE: Updating dynamic IP $lIPADDR on $NSSERVER failed (RC=$RC)"
    (
      echo "Subject: DDNS update failed"
      echo "To: $MAILTO"
      echo
      echo "Updating dynamic IP $lIPADDR on $NSSERVER failed (RC=$RC)"
    ) | /usr/sbin/sendmail -f noreply@dobrev.eu -F "DynDNS updater" "$MAILTO"
    return $RC
  else
    eecho "SUCCESS: Updating dynamic IP $lIPADDR on $NSSERVER succeeded"
    return $RC
  fi
}

function clear_host_entry {
  HOST=$1

cat <<EOF | nsupdate -k "$KEY"
server $NSSERVER
zone $ZONE
update delete $HOST. A
send
EOF

  RC=$?

  if [ $RC != 0 ]; then
    eecho "FAILURE: Removing hostname entry for $HOST on $NSSERVER failed (RC=$RC)"
    (
      echo "Subject: DDNS update failed"
      echo "To: $MAILTO"
      echo
      echo "Removing hostname entry for $HOST on $NSSERVER failed (RC=$RC)"
    ) | /usr/sbin/sendmail -f noreply@dobrev.eu -F "DynDNS updater" "$MAILTO"
    return $RC
  else
    eecho "SUCCESS: Removing hostname entry for $HOST on $NSSERVER succeeded"
    return $RC
  fi
}


function ddns_update {
  local stat=1

  check_alive $PRIIP
  if [[ $? != 0 ]]; then
    # Primary IP not reachable
    # Loop through the backup list and set the first available
    for i in $( seq 0 $((${#BKPIP[@]} - 1))); do
      SECIP=${BKPIP[$i]}

      check_alive $SECIP
      if [[ $? != 0 ]]; then
        eecho "WARN: $SECIP is not reachable."
      else
        eecho "INFO: $SECIP reachable"
        do_nsupdate $HOST $SECIP $TTL
        stat=0
        break;
      fi
    done

    if ! [[ $stat -eq 0 ]]; then
      # Secondary IP not reachable too
      # Huston - We have a problem
      clear_host_entry $HOST
      (
      echo "Subject: DDNS update failed"
      echo "To: $MAILTO"
      echo
      echo "WARNING: Can't find any available IPs for $HOST."
      echo "Please contact your provider for additional information"
      ) | /usr/sbin/sendmail -f noreply@dobrev.eu -F "DynDNS updater" $MAILTO
    fi
  else
    eecho "INFO: $PRIIP available"
    do_nsupdate $HOST $PRIIP $TTL
  fi
}

function eecho {
  echo "$(LANG=C date +'%b %e %X') $(hostname) $PROG[$$]: $@" >> $LOGFILE
  if [ $VERBOSE -eq 1 ]; then
    echo "$(LANG=C date +'%b %e %X'): $@"
  fi
}

function validate_hostname {
  HAYSTACK="$1"
  NEEDLE="^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$";

  if ! [[ "$HAYSTACK" =~ $NEEDLE ]]; then
    eecho "FAILURE: Invalid hostname! Please use FQDN format"
    exit 2
  fi
}

function valid_ip {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      OIFS=$IFS
      IFS='.'
      ip=($ip)
      IFS=$OIFS
      [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
          && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
      stat=$?
    fi
    
    return $stat
}

function usage {
cat << EOF
Usage: $PROG -o hostname -p primaryip -b secondaryip [-b secondaryip] [-k keyfile] [-s server ] [-z zone] [-t ttl] [-c] [-v] [-V]

OPTIONS:
  -p primaryip    Sets the primary IP
  -b secondaryip  Sets the backup IP. Multiple entries are possible
  -o hostname     Change DNS settings for hostname. FQDN format required.
  -s server       Sets the DNS server to be modified. (Default: $NSSERVER)
  -z zone         Make changes in zone. (Default: $ZONE)
  -t ttl          Sets the TTL for the record. (Default: $TTL)
  -k keyfile      Use keyfile for DNS connection. (Default: $KEY)
  -c              Clears the DNS entry for hostname. See -o
  -v              Be verbose
  -V              Version ($VER)
  -h              This screen


If primary IP is not available/reachable then the system will try to access the secondary one and update
the DNS settings accordingly. Once Primary IP comes back up the system will switch back to it.

For additional information and modifications contact Martin Dobrev (martin@dobrev.eu)
EOF
}

CLEARHOSTENTRY=0
PRIIP=
declare -a BKPIP

while getopts "hs:z:t:p:b:co:k:vV" OPTION
do
     case $OPTION in
        h)
          usage
          exit 1
          ;;
        s)
          NSSERVER=$OPTARG
          ;;
        z)
          ZONE=$OPTARG
          ;;
        t)
          TTL=$OPTARG
          ;;
        v)
          VERBOSE=1
          ;;
        p)
          PRIIP=$OPTARG
          ;;
        b)
          BKPIP+=( $OPTARG )
          ;;
        c)
          CLEARHOSTENTRY=1
          ;;
        o)
          HOST=$OPTARG
          ;;
        k)
          KEY=$OPTARG
          ;;
        V)
          echo "$PROG version $VER"
          exit
          ;;
        ?)
          usage
          exit
          ;;
     esac
done

if [[ -n $HOST ]] && [[ $CLEARHOSTENTRY -eq 1 ]]
then
  clear_host_entry $HOST
  eecho "INFO: $HOST removed from server $NSSERVER (zone $ZONE)"
  exit 0
fi

if [[ -z $HOST ]] || [[ -z $PRIIP ]] || [[ ${#BKPIP[@]} -lt 1 ]]
then
  usage
  exit 99
fi

ddns_update
