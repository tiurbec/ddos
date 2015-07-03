#!/bin/sh
#
# chkconfig: - 86 14
# description: ddos tool daemon
# processname: ddostool
# config: /etc/ddostool.conf
#

### BEGIN INIT INFO
# Provides: zabbix-agent
# Required-Start: $local_fs $network
# Required-Stop: $local_fs $network
# Should-Start: zabbix zabbix-proxy
# Should-Stop: zabbix zabbix-proxy
# Default-Start:
# Default-Stop: 0 1 2 3 4 5 6
# Short-Description: Start and stop Zabbix agent
# Description: Zabbix agent
### END INIT INFO

# Source function library.
. /etc/rc.d/init.d/functions

if [ -x /usr/local/bin/ddostool ]; then
    exec=/usr/local/bin/ddostool
else
    exit 5
fi

prog=${exec##*/}
conf=/etc/ddostool.conf
pidfile=$(grep -e "^PidFile=.*$" $conf | cut -d= -f2)

#if [ -f /etc/sysconfig/zabbix-agent ]; then
#    . /etc/sysconfig/zabbix-agent
#fi

lockfile=/var/lock/subsys/ddostool

start()
{
    echo -n $"Starting DDoS tool: "
    daemon $exec -c $conf
    rv=$?
    echo
    [ $rv -eq 0 ] && touch $lockfile
    PID=`ps aux|grep -v 'grep'|grep -e $exec|awk '{print $2}'`
    echo $PID > $pidfile
    return $rv
}

stop()
{
    echo -n $"Shutting down DDoS tool: "
    killproc $prog
    rv=$?
    echo
    [ $rv -eq 0 ] && rm -f $lockfile
    return $rv
}

restart()
{
    stop
    start
}

case "$1" in
    start|stop|restart)
        $1
        ;;
    force-reload)
        restart
        ;;
    status)
        status -p $pidfile $prog 
        ;;
    try-restart|condrestart)
        if status $prog >/dev/null ; then
            restart
        fi
        ;;
    reload)
        action $"Service ${0##*/} does not support the reload action: " /bin/false
        exit 3
        ;;
    *)
	echo $"Usage: $0 {start|stop|status|restart|try-restart|force-reload}"
	exit 2
	;;
esac

