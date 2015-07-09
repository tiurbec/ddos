#!/bin/sh
#
# chkconfig: - 86 14
# description: ddos prevention tool daemon
# processname: ddostool
# config: /etc/ddostool.conf
#

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
    echo -n $"Starting DDoS prevention tool: "
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
    echo -n $"Shutting down DDoS prevention tool: "
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
    details)
	$exec -s
	;;
    *)
	echo $"Usage: $0 {start|stop|status|restart|try-restart|force-reload|details}"
	exit 2
	;;
esac

