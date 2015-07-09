#!/bin/sh
#
# chkconfig: - 86 14
# description: ddos tool daemon
# processname: ddostool
# config: /etc/ddostool.conf
#


if [ -x /usr/local/bin/ddostool ]; then
    exec=/usr/local/bin/ddostool
else
    exit 5
fi

prog=${exec##*/}
conf=/etc/ddostool.conf
pidfile=$(grep -e "^PidFile=.*$" $conf | cut -d= -f2)

lockfile=/var/lock/ddostool

restart()
{
    stop
    start
}

oldmain()
{
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
}

title() {
        local x w="$( stty size 2>/dev/null </dev/tty | cut -d" " -f2  )"
        [ -z "$w" ] && w="$( stty size </dev/console | cut -d" " -f2  )"
        for (( x=1; x<w; x++ )) do echo -n .; done
        echo -e "\e[222G\e[3D v \r\e[36m$* \e[0m"
        error=0
}

status() {
        if [ $error -eq 0 ]
        then
                echo -e "\e[1A\e[222G\e[4D\e[32m [OK]\e[0m"
        else
                echo -e "\e[1A\e[222G\e[8D\a\e[1;31m [FAILED]\e[0m"
        fi
}

start()
{
        title "Starting DDoS prevention tool."
       (/usr/local/bin/ddostool -c /etc/ddostool.conf) || error=$?
        status
        [ $error -eq 0 ] && touch $lockfile
        PID=`ps aux|grep -v 'grep'|grep -e $exec|awk '{print $2}'`
        echo $PID > $pidfile
}

stop()
{
        title "Stopping DDoS prevention tool."
	if [ -f $pidfile ];
	then
            kill $(cat $pidfile) || error=$?
	else
	    error=1
	fi
        status
	[ $error -eq 0 ] && rm -f $lockfile
	[ $error -eq 0 ] && rm -f $pidfile
}

servicestatus()
{
    if [ -f $pidfile ];
    then
	proccount=$(ps aux | grep -e `cat $pidfile` |grep -c ddostool)
	if [ $proccount -eq 1 ];
	then
		echo "Service is running under PID: $(cat $pidfile)"
		$exec -s
	else
	    echo "Pidfile exists ($(cat $pidfile)) but there is no process with that pid."
	fi
    else
	echo "DDoS prevention tool is stopped."
    fi
}

case "$1" in

   start)
	start
        ;;

   stop)
   	stop
        status
        ;;

   restart)
	restart
        status
        ;;
   status)
	servicestatus
	;;
    *)
        echo "Usage: $0 { start | stop | restart | status }"
        exit 1 ;;

esac

exit 0


