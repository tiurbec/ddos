#!/bin/bash


echoerr() 
{ 
  #Will output all params to STDERR
  echo "$@" 1>&2
}

echolog() 
{ 
# Will write message to syslog
  logger -p $DT_LOGFAC -t $DT_LOGTAG "$@"
}

echollog()
{
# Will write message to syslog according to level previously set in config file
# accepted levels: none=0, info=1, warn=2, error=3, debug=4
# default level is error
  logStr=${2:-"no message"}
  levelStr=${1:-"error"}
  levelStr={$levelStr,,}
  case "$levelStr" in
	none)	level=0
		;;
	info)	level=1
		;;
	warn)	level=2
		;;
	error)	level=3
		;;
	debug)	level=4
		;;
	*)	level=3
  esac

  confLevelStr=${DT_LOGLVL:-"error"}
  confLevel={$confLevelStr,,}
  case "$confLevelStr" in
        none)   confLevel=0
                ;;
        info)   confLevel=1
                ;;
        warn)   confLevel=2
                ;;
        error)  confLevel=3
                ;;
        debug)  confLevel=4
                ;;
        *)      confLevel=3
  esac

  if [ "$level" -lt "$confLevel" ];
  then
    echolog $logStr
  fi
}

check_binaries()
{
  if ! [ -x $IPTABLES ];
  then
    echoerr "$IPTABLES not found. Check the config file"
    echollog "error" "$IPTABLES not found. Check the config file"
    exit 1
  fi

  if ! [ -x $NETSTAT ];
  then
    echoerr "$NETSTAT not found. Check the config file"
    echollog "error" "$NETSTAT not found. Check the config file"
    exit 1
  fi

  if ! [ -x $AWK ];
  then
    echoerr "$AWK not found. Check the config file"
    echollog "error" "$AWK not found. Check the config file"
    exit 1
  fi

  if ! [ -x $CUT ];
  then
    echoerr "$CUT not found. Check the config file"
    echollog "error" "$CUT not found. Check the config file"
    exit 1
  fi

  if ! [ -x $SORT ];
  then
    echoerr "$SORT not found. Check the config file"
    echollog "error" "$SORT not found. Check the config file"
    exit 1
  fi

  if ! [ -x $UNIQ ];
  then
    echoerr "$UNIQ not found. Check the config file"
    echollog "error" "$UNIQ not found. Check the config file"
    exit 1
  fi

  if ! [ -x $HEAD ];
  then
    echoerr "$HEAD not found. Check the config file"
    echollog "error" "$HEAD not found. Check the config file"
    exit 1
  fi

  if ! [ -x $MKTEMP ];
  then
    echoerr "$MKTEMP not found. Check the config file"
    echollog "error" "$MKTEMP not found. Check the config file"
    exit 1
  fi

}

find_bad()
{
  $NETSTAT -ntu | $AWK '{print $5}' | $CUT -d: -f1 | $SORT | $UNIQ -c | $SORT -nr > $TMPIPS
  exec 3<$TMPIPS
  while read hostconn hostip <&3; do
    if [ $hostconn -gt $DT_CONN ]; then
      echo "$hostip" >> $TMPBADIPS
    fi
  done
  exec 3>&-
  grep -v --file=$DT_WHITELIST $TMPBADIPS > $TMPBANIPS
}


ban_ip()
{
  IPTOBAN=$1
  UTIME=$(date +%s)
  ban_rule $IPTOBAN
  echo "$UTIME $IPTOBAN" >> $BANDB
  echollog "warn" "$IPTOBAN was banned."
  if [ $ZABBIX_ENABLED -eq 1 ];
  then
    $ZABBIX_SENDER -c $ZABBIX_CONFIG -k ddos.ip -o "$IPTOBAN" >/dev/null 2>&1
    $ZABBIX_SENDER -c $ZABBIX_CONFIG -k ddos.attack -o "1" >/dev/null 2>&1
    echollog "debug" "Zabbix server updated"
  fi
}

ban_ips()
{
  exec 4<$TMPBANIPS
  while read hostip <&4; do
    if [ $(is_banned $hostip) -eq 0 ];
    then
      ban_ip $hostip
    fi
  done
  exec 4>&-
}

unban_ips()
{
# Will parse ddosbanned.txtdb and unban expired hosts
  RIGHTNOW=$(date +%s)
  TBANDB=$($MKTEMP $DT_TMP/tbandb.XXXXXX)
  exec 5<$BANDB
  while read utime hostip <&5; do
    if [ ! -z $utime ];
    then
      if [ $(($RIGHTNOW - $utime)) -gt $DT_TIMEOUT ];
      then
        unban_rule $hostip
        echollog "warn" "$IPTOBAN was unbanned."
      else
        echo "$UTIME $IPTOBAN" >> $TBANDB
      fi
    fi 
  done
  exec 5>&-
  rm -f $BANDB
  mv $TBANDB $BANDB
}

ban_rule()
{
# Add iptables rule for single ip address
  IPTOBAN=$1
  $IPTABLES -I $CHAINNAME -s $IPTOBAN/32 -j REJECT --reject-with icmp-port-unreachable 
}

unban_rule()
{
# Removes rule for single ip address
  IPTOBAN=$1
  while [ $(is_banned $IPTOBAN) -eq 1 ]
  do
    $IPTABLES -D $CHAINNAME -s $IPTOBAN/32 -j REJECT --reject-with icmp-port-unreachable
  done
}

is_banned()
{
# Checks if there is a rule for ip in ddostool chain
  IPTOBAN=$1
  RULESCOUNT=$($IPTABLES -n --list $CHAINNAME | grep -c \ $IPTOBAN\  )
  if [ $RULESCOUNT -gt 0 ];
  then
    echo 1
  else
    echo 0
  fi
}

create_ipt_chain()
{
  $IPTABLES -N $CHAINNAME
  $IPTABLES -I INPUT -p tcp -m multiport --dports 80,443 -j $CHAINNAME
  $IPTABLES -I $CHAINNAME -j RETURN
  echollog "debug" "Created \"$CHAINNAME\" chain"
}

remove_ipt_chain()
{
  echollog "debug" "remove_ipt_chain()"
  $IPTABLES -n --list $CHAINNAME >/dev/null 2>&1
  if [ $? -eq 0 ];
  then
    echollog "debug" "Flushing chain $CHAINNAME"
    $IPTABLES -F $CHAINNAME
    $IPTABLES -D INPUT -p tcp -m multiport --dports 80,443 -j $CHAINNAME
    $IPTABLES -X $CHAINNAME
    echollog "debug" "Removed chain $CHAINNAME"
  fi
}


show_help()
{
  echo "Help"
}

finish()
{
  echollog "debug" "finish()"
  remove_ipt_chain 
  echollog "debug" "Chain removed"
  echollog "info" "Service ddostool stopped"
}

# Main loop
main_func()
{
  local i=0
  echollog "debug" "Checking binaries"
  check_binaries

  touch $BANDB
  echollog "debug" "Removing ipt chain"
  remove_ipt_chain
  echollog "debug" "Creating ipt chain"
  create_ipt_chain
  echollog "debug" "Starting main loop"
  (
  trap "{ finish; }" EXIT
  echollog "info" "Service ddostool started"
  while :
  do 
    echollog "debug" "================================================================================"
    echollog "debug" "Starting another iteration i=$i"
    TMPIPS=$($MKTEMP $DT_TMP/ddosips.XXXXXX)
    echollog "debug" "Created $TMPIPS"
    TMPBADIPS=$($MKTEMP $DT_TMP/ddosbadips.XXXXXX)
    echollog "debug" "Created $TMPBADIPS"
    TMPBANIPS=$($MKTEMP $DT_TMP/ddosbanips.XXXXXX)
    echollog "debug" "Created $TMPBANIPS"
    echollog "debug" "Finding bad IPs"
    find_bad
    echollog "debug" "Removing ban for clean and expired banned IPs"
    unban_ips
    echollog "debug" "Banning new IPs"
    ban_ips
    echollog "debug" "Removing temporary files"
    rm -f $TMPBADIPS
    rm -f $TMPIPS
    rm -f $TMPBANIPS
    echollog "debug" "Going to sleep for $DT_DELAY seconds."
    sleep $DT_DELAY
    echollog "debug" "Slept"
    i=$(( i + 1 ))
  done 
  ) &
}

default_env()
{
  DT_TIMEOUT=60
  DT_CONN=100
  DT_TMP=/tmp
  DT_WHITELIST=/etc/ddostool.white
  DT_DELAY=60
  BANDB=$DT_TMP/ddosbanned.txtdb
  CHAINNAME=ddostool
  DT_LOGFAC=local0.info
  DT_LOGTAG=ddostool
  DT_LOGLVL=debug
  IPTABLES=/sbin/iptables
  NETSTAT=/bin/netstat
  AWK=/bin/awk
  CUT=/bin/cut
  SORT=/bin/sort
  UNIQ=/usr/bin/uniq
  HEAD=/usr/bin/head
  MKTEMP=/bin/mktemp
  PidFile=/var/run/ddostool.pid
  ZABBIX_ENABLED=0
  ZABBIX_SENDER=/usr/bin/zabbix_sender
  ZABBIX_CONFIG=/etc/zabbix/zabbix_agentd.conf
}

#unset $configfile
default_env

configfile=${1:-"/etc/ddostool.conf"}

for arg in "$@"
do
  case "$arg" in
	-c)	shift
		configfile=${1:-"/etc/ddostool.conf"}
		;;
	-h)	show_help
		exit 0
		;;
	--help)	show_help
		exit 0
		;;
	-*)	echoerr "Unknown argument $arg"
		exit 255
		;;
  esac
done 

if [ -f $configfile ];
then
  . $configfile
  echollog "info" "Reading config file $configfile"
else
  echoerr "Config file not found: $configfile"
  exit 254
fi

echollog "debug" "Starting main loop"

main_func

