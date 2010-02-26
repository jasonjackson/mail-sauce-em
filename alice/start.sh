#!/bin/sh
cd `dirname $0`
make
if [[ ! -f ebin/rest_app.boot ]]; then
	make boot
fi
#erl -pa $PWD/ebin -pa $PWD/deps/*/ebin -name alice -s reloader -boot alice $*

erl -pa $PWD/ebin -pa $PWD/deps/*/ebin -sname alice@sfqload01 -s reloader -boot alice $*

# Alice can be started via the command line with:
# rabbitmq@sfqload01  /data/distributed_email/alice
#$ ./start.sh -alice rabbithost "rabbit@sfqload01" -setcookie `cat /var/lib/rabbitmq/.erlang.cookie`
