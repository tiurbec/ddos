#!/bin/bash

#set -x

echoerr() 
{ 
  #Will output all params to STDERR
  echo "$@" 1>&2
}

echolog() 
{ 
  #Will write message to syslog
  logger -p $DT_LOGFAC -t $DT_LOGTAG "$@"
}

check_binaries()
{
  if ! [ -x $IPTABLES ];
  then
    echoerr "$IPTABLES not found. Check the config file"
    exit 1
  fi

  if ! [ -x $NETSTAT ];
  then
    echoerr "$NETSTAT not found. Check the config file"
    exit 1
  fi

  if ! [ -x $AWK ];
  then
    echoerr "$AWK not found. Check the config file"
    exit 1
  fi

  if ! [ -x $CUT ];
  then
    echoerr "$CUT not found. Check the config file"
    exit 1
  fi

  if ! [ -x $SORT ];
  then
    echoerr "$SORT not found. Check the config file"
    exit 1
  fi

  if ! [ -x $UNIQ ];
  then
    echoerr "$UNIQ not found. Check the config file"
    exit 1
  fi

  if ! [ -x $HEAD ];
  then
    echoerr "$HEAD not found. Check the config file"
    exit 1
  fi

  if ! [ -x $MKTEMP ];
  then
    echoerr "$MKTEMP not found. Check the config file"
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
  echolog "$IPTOBAN was banned."
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
  $IPTABLES -A $CHAINNAME -s $IPTOBAN/32 -j REJECT --reject-with icmp-port-unreachable 
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
  RULESCOUNT=$($IPTABLES -n --list|grep \ $IPTOBAN\  |wc -l)
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

}

remove_ipt_chain()
{
  $IPTABLES -n --list $CHAINNAME >/dev/null 2>&1
  if [ $? -eq 0 ];
  then
    $IPTABLES -F $CHAINNAME
    $IPTABLES -D INPUT -p tcp -m multiport --dports 80,443 -j $CHAINNAME
    $IPTABLES -X $CHAINNAME
  fi
}

# Main
main_func()
{
  check_binaries

  trap "{ echolog \"Exiting\" ; remove_ipt_chain ; exit 0; }" SIGINT SIGTERM

  touch $BANDB
  echolog "removing ipt chain"
  remove_ipt_chain
  echolog "creating ipt chain"
  create_ipt_chain
  echolog "starting loop"
  ( 
  while [ 1 -eq 1 ]
  do 
    TMPIPS=$($MKTEMP $DT_TMP/ddosips.XXXXXX)
    TMPBADIPS=$($MKTEMP $DT_TMP/ddosbadips.XXXXXX)
    TMPBANIPS=$($MKTEMP $DT_TMP/ddosbanips.XXXXXX)
    find_bad
    unban_ips
    ban_ips
    rm -f $TMPBADIPS
    rm -f $TMPIPS
    rm -f $TMPBANIPS
    sleep $DT_DELAY
  done 
  ) &
}

main_func

