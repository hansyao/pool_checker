#!/bin/bash

KILL_CONV=$(ps -ef | grep "subconverter/subconverter"| grep -v grep | awk '{print $2}')
KILL_CLASH=$(ps -ef | grep "bin/clash/"| grep -v grep | awk '{print $2}')
KILL_VMESS=$(ps -ef | grep "Actions"| grep -v grep | awk '{print $2}')

if [ $1 == 'clean' ]; then
	if [ ! -z ${KILL_CONV} ]; then kill -9 "${KILL_CONV}"; fi
	if [ ! -z ${KILL_CLASH} ]; then kill -9 "${KILL_CLASH}"; fi
	# if [ ! -z ${KILL_VMESS} ]; then kill -9 "${KILL_VMESS}"; fi
	rm -rf /tmp/*
	rm -rf /tmp/.config
fi

if [ $1 == 'run' ]; then
	source .profile
	./env.sh
	./Actions/convert.sh
	./Actions/pool.sh
fi
