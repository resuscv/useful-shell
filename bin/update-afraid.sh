#!/bin/sh
# FreeDNS updater script
#   https://freedns.afraid.org/scripts/update.sh.txt
#
# The config file needs to define these two variables...
#    APIKEY='123abc'
#    DOMAIN='my.cool.domain'
#
# and the crontab is
#    08 */2 * * *  ${HOME}/bin/update-afraid.sh

CFG=${XDG_CONFIG_HOME:-$HOME/.config}/.afraidcfg

if [ -f ${CFG} ]; then

  # Get configuration info
  . ${CFG}

  UPDATEURL="https://freedns.afraid.org/dynamic/update.php?${APIKEY}"

  registered=$(nslookup $DOMAIN|tail -n2|grep A|sed s/[^0-9.]//g)
  current=$(wget -q -O - http://checkip.dyndns.org|sed s/[^0-9.]//g)

  [ "$current" != "$registered" ] && {
    wget -q -O /dev/null $UPDATEURL
    echo "DNS updated on:"; date
  }

fi

## END
