#!/bin/bash

# ***************参数初始化****************** /
if [[ ! -d ${TEMP_DIR} ]]; then
	TEMP_DIR=/tmp/tmp
	mkdir -p ${TEMP_DIR}
fi
if [[ $[TARGET_NODES] -eq 0 ]]; then
	TARGET_NODES=100
fi
if [[ $[DURATION] -eq 0 ]]; then
	DURATION=1200
fi
if [[ $[TIMEOUT] -eq 0 ]]; then
	TIMEOUT=2
fi
# ****************参数初始化完成************** /

clash_help() {
	echo "how to manage clash:"
	echo "clash_exec start config pid"
	echo "clash_exec restart config pid"
	echo "clash_exec stop config pid"
}

clash_exec() {
	LOG=/dev/null
	if [[ -e /tmp/bin/clash ]]; then 
		CLASH='/tmp/bin/clash'
	else
		CLASH="`pwd`/bin/clash"
	fi
	
	if [[ $1 == 'start' && -n $2 && -n $3 ]]; then
		nohup ${CLASH} -f $2 -d /tmp/.config > ${LOG} 2>&1 &
		echo "$!" > $3
	elif [[ $1 == 'stop' && -n $2 && -n $3 ]]; then
		kill `cat $3`
	elif [[ $1 == 'restart' && -n $2 && -n $3 ]]; then
		kill `cat $3`
		nohup ${CLASH} -f $2 -d /tmp/.config > ${LOG} 2>&1 &
		echo "$!" > $3
	else
		clash_help
	fi

	unset CONFIG
	unset PID
	unset LOG
	unset CLASH
}

# generate single config file
# $1: PORT	$2: config line	$3: config file
config() {

	NAME=$(echo $2 | awk -F":" '{print $2}' | awk -F"," '{print $1}'| sed 's/\"//g')

	cat >$3 <<EOL
socks-port: $1
allow-lan: true
mode: Rule
log-level: silent
proxies:
$2
proxy-groups:
  - name: 🐟 全局
    type: select
    proxies:
      - ${NAME}

rules:
  - MATCH,🐟 全局
EOL

	unset NAME
}

check_port() {
	CHECK=$(lsof -i :$1 | awk '{print $1 " "  $2}')
	if [[ -z ${CHECK} ]]; then
		echo -e "no"
	else
		echo -e "yes"
	fi

	unset CHECK
}

isconnected() {
	PORT=$1
	CONFIG=$2
	PID=${TEMP_DIR}/${PORT}.pid

	PROXY=socks5h://127.0.0.1:$[PORT]
	GEN_204=https://www.gstatic.com/generate_204 
	
	# check if port is available
	if [ $(check_port $[PORT]) == 'no' ]; then
		clash_exec start ${CONFIG} ${PID}

	else
		echo -e "PORT $[PORT] is in use"
		return
	fi

	# recheck PORT status after clash start
	n=0
	while : 
	do
		CHECK=$(check_port $[PORT])
		if [[ ${CHECK} == 'yes' || $[n] -gt 5 ]]; then
			break
		fi
		let n++
	done
	if [[ $[n] -gt 5 ]]; then
		echo -e "${PORT} failed"
		return
	fi

	# check conneciton status
	RESULT=$(curl --connect-timeout $[TIMEOUT] -m $[TIMEOUT]  -x ${PROXY} -s -L -i ${GEN_204}| head -n 1 | grep 204)
	if [[ -z ${RESULT} ]]; then
		echo -e "no"
	else
		echo -e "yes"
	fi
	
	if [ ! -e ${TEMP_DIR}/${PORT}.pid ]; then 
		kill -9 $(ps axu | grep "${TEMP_DIR}/${PORT}.pid" | grep -v '\-\-color=auto' | awk '{print $2}')
	else
		clash_exec stop "$2" "${TEMP_DIR}/${PORT}.pid"
	fi
	
	unset PID
	unset PORT
	unset CONFIG
	unset GEN_204
	unset PID
	unset n
	unset CHECK
	unset RESULT
}

pool_validate() {
	for ((k=$3; k<$4; k++))
	do
		LINE=$(cat $1 | sed -n "$[k]p")
		if [[ -z $(echo ${LINE} | grep "\- {") ]]; then
			continue
		fi

		END_TIME=$(date +%s)
		TOTAL_VALID=$(cat ${TOTAL_VALID_COUNT})
		if [[ $[TOTAL_VALID] -ge $[TARGET_NODES] || $(($[END_TIME] - $[START_TIME])) -gt $[DURATION] ]]; then
			break
		fi

		{
		
		# generate config file for each node
		PORT=$[k]
		PORT=$((8000 + $[k]))
		CONFIG=${TEMP_DIR}/${PORT}.yaml

		END_TIME=$(date +%s)
		TOTAL_VALID=$(cat ${TOTAL_VALID_COUNT})
		if [[ $[TOTAL_VALID] -ge $[TARGET_NODES] || $(($[END_TIME] - $[START_TIME])) -gt $[DURATION] ]]; then
			exit 0
		fi

		config "${PORT}" "${LINE}" "${CONFIG}"

		# validate connection availabe status
		if [[ $(isconnected "${PORT}" "${CONFIG}") == 'yes' ]]; then

			END_TIME=$(date +%s)
			TOTAL_VALID=$(cat ${TOTAL_VALID_COUNT})
			if [[ $[TOTAL_VALID] -ge $[TARGET_NODES] || $(($[END_TIME] - $[START_TIME])) -gt $[DURATION] ]]; then
				exit 0
			fi

			echo ${LINE} >> $2
			echo $(($(cat ${TOTAL_VALID_COUNT}) + 1)) > ${TOTAL_VALID_COUNT}
			echo -e "已爬取可用节点数 $(cat ${TOTAL_VALID_COUNT}) 总耗时 $(($[END_TIME] - $[START_TIME])) 秒 限时 $[DURATION] 秒"
		fi
		}&
	done

	wait

	unset LINE
	unset k
	unset PORT
	unset CONFIG
	unset PID
}

pool_validate_fd() {

	START_TIME=$(date +%s)

	if [ ! -e ${TOTAL_VALID_COUNT} ]; then
		TOTAL_VALID_COUNT=/tmp/total_valid_nodes
		echo 0 >${TOTAL_VALID_COUNT}
	fi

	if [[ $[DURATION] -eq 0 ]]; then
		DURATION=1200
	fi
	rm -rf $2
	rm -rf ${TEMP_DIR} && mkdir ${TEMP_DIR}
	echo 'proxies:' >$2

	[ -e /tmp/fd1 ] || mkfifo /tmp/fd1
	exec 3<>/tmp/fd1
	rm -rf /tmp/fd1
	for ((i=1; i<=$[$3]; i++))
	do
		echo >&3
	done

	i=0
	cat $1 | while read line || [[ -n ${line} ]]
	do
		read -u 3

		if [[ -z $(echo ${line} | grep "\- {") ]]; then
			continue
		fi

		END_TIME=$(date +%s)
		TOTAL_VALID=$(cat ${TOTAL_VALID_COUNT})
		if [[ $[TOTAL_VALID] -ge $[TARGET_NODES] || $(($[END_TIME] - $[START_TIME])) -gt $[DURATION] ]]; then
			break
		fi

		{
			# generate config file for each node
			PORT=$((8000 + $[i]))
			CONFIG=${TEMP_DIR}/${PORT}.yaml
			config "${PORT}" "${line}" "${CONFIG}"

			# validate connection availabe status
			if [[ $(isconnected "${PORT}" "${CONFIG}") == 'yes' ]];
			then
				END_TIME=$(date +%s)
				TOTAL_VALID=$(cat ${TOTAL_VALID_COUNT})
				if [[ $[TOTAL_VALID] -ge $[TARGET_NODES] || $(($[END_TIME] - $[START_TIME])) -gt $[DURATION] ]]; then
					exit 0
				fi
				echo ${line} >> $2
				echo $(($(cat ${TOTAL_VALID_COUNT}) + 1)) > ${TOTAL_VALID_COUNT}
				echo -e "已爬取可用节点数 $(cat ${TOTAL_VALID_COUNT})"
			fi
			echo >&3
		}&
		let i++
	done

	wait

	#rm -rf ${TEMP_DIR}

	STOP_TIME=$(date +%s)
	echo -e "可用节点检测总耗时: `expr $[STOP_TIME] - $[START_TIME]` 秒"
	exec 3<&-
	exec 3>&-

	unset START_TIME
	unset STOP_TIME
	unset i
	unset PORT
	unset CONFIG
	unset TOTAL_VALID_COUNT
}

pool_validate_pid() {
	START_TIME=$(date +%s)

	if [ ! -e ${TOTAL_VALID_COUNT} ]; then
		TOTAL_VALID_COUNT=/tmp/total_valid_nodes
		echo 0 >${TOTAL_VALID_COUNT}
	fi

	if [[ $[DURATION] -eq 0 ]]; then
		DURATION=1200
	fi

	TOTAL=$(cat $1 | wc -l)
	m=$3
	z=$(expr $TOTAL / $m + 1)

	rm -rf $2
	rm -rf ${TEMP_DIR} && mkdir ${TEMP_DIR}
	echo 'proxies:' >$2

	for (( i=1; i<=$z; i++))
	do
		begin=$(($i * $m - $m + 1))
		if [ $i == $z ]; then
			end=$TOTAL
		else
			end=$(($i * $m))
		fi
		pool_validate $1 $2 $[begin] $[end]
	done

	# wait

	#rm -rf ${TEMP_DIR}
	
	STOP_TIME=$(date +%s)
	echo -e "可用节点检测总耗时: `expr $[STOP_TIME] - $[START_TIME]` 秒"
	
	unset begin
	unset end
	unset STOP_TIME
	unset START_TIME
	unset m
	unset z
	unset i
	unset TOTAL
}


#get_clash
#pool_validate_pid $1 $2 20
#pool_validate_fd $1 $2 800


#get_clash
#pool_validate_pid $1 $2 20
#pool_validate_fd $1 $2 800
