#!/bin/bash

# POOL=/tmp/subscribe/latest_pool.yaml
# FINAL_POOL=./final.yaml
# LOCATION=location.txt

# 验证IP是否非法
function check_ip() {
	local IP=$1
	local VALID_CHECK=$(echo ${IP} \
		| awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')
	
	local RULE="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
	if echo ${IP} | grep -E ${RULE}>/dev/null; 
	then
		if [ ${VALID_CHECK:-no} == "yes" ]; then
			echo "IP ${IP} available."
		else
			echo "IP ${IP} not available!"
		fi
	else
		echo "IP format error!"	
	fi
}

# 根据国家和地区名获取地域代码
function countrycode() {
	local CODE=Actions/code.csv
	echo -e $(cat ${CODE} | grep -P "\t$1\t" | awk -F"\t" '{print $1}')
}

# 远程获取单IP地域信息
function location_remote() {
	local URL=http://ip-api.com/json
	local LANG='zh-CN'
	
	# Taobao API
	local URL2=https://ip.taobao.com/outGetIpInfo\?ip\=
	local KEY=alibaba-inc

	local JSON=$(curl -s --connect-timeout 1 -m 2 -X GET ${URL}/$1\?lang\=$LANG)
	if [[ -z ${JSON} ]]; then
		local JSON=$(curl -s -X POST ${URL2}$1\&accessKey\=${KEY})
		if [[ -z ${JSON} ]]; then
			echo -e 未知\|\|\|\|
			return
		fi
	fi

	local COUNTRY=$(echo ${JSON} | awk -F"\"country\":" '{print $2}' \
		| awk -F"," '{print $1}' | sed 's/\"//g')
	local REGION=$(echo ${JSON} | awk -F"\"region\":" '{print $2}' \
		| awk -F"," '{print $1}' | sed 's/\"//g')
	local REGIONNAME=$(echo ${JSON} | awk -F"\"regionName\":" '{print $2}' \
		| awk -F"," '{print $1}' | sed 's/\"//g')
	local CITY=$(echo ${JSON} | awk -F"\"city\":" '{print $2}' \
		| awk -F"," '{print $1}' | sed 's/\"//g')
	local ISP=$(echo ${JSON} | awk -F"\"isp\":" '{print $2}' \
		| awk -F"," '{print $1}' | sed 's/\"//g')
		
	echo -e ${COUNTRY}\|${REGION}\|${REGIONNAME}\|${CITY}\|${ISP}
}

# 获取单个IP地域信息
function patch_location() {
	# DOMAIN=8.8.8.8

	local IP1=$1
	if [[ $(check_ip $1) != "IP $1 available." ]]; then
		local IP1=$(nslookup $1 |egrep 'Address:'|awk '{if(NR==2) print $NF}')
	fi

	#从本地IP数据库拉取
	local IPREGION=$(./Actions/search -d Actions/ip2region.db -i ${IP1})
	if [[ ${IPREGION} != '0|0|0|内网IP|内网IP' && ${IPREGION} ]]; then
		echo -e $1\|${IPREGION}
		return
	fi

	#本地IP数据库不存在，从远程拉取
	echo -e $1\|$(location_remote ${IP1})
}

# 获取全部代理节点
# $1 - 代理节点列表
function pool() {
	local POOL=$1
	local LIST=$(cat ${POOL} | grep "\-\ {")

	local NUM=$(echo -e "${LIST}" | head -n 1 | sed 's/[^\"]*//g' | wc -c)
	# 有引号分隔的yaml格式
	if [[ $[NUM] -gt 6 ]]; then
		echo -e "${LIST}" | awk -F '\"server\":' '{print $2}' \
			| awk -F',' '{print $1}' | sed 's/\"//g' | sort | uniq \
			| sed -r '/^\s*$/d'
	else
	# 没有引号分隔的yaml格式
		echo -e "${LIST}" | awk -F "server:" '{print $2}'| cut -d "," -f1 \
		| sed -e 's/^[ ]*//g' | sed -e 's/[ ]*$//g' | sort | uniq | sed -r '/^\s*$/d'
	fi
}

# 批量获取所有IP地域信息并写入文件
# $1 - 代理节点列表 $2 - LOCATION文件
function location() {

	[ -e /tmp/fd1 ] || mkfifo /tmp/fd1
	exec 3<>/tmp/fd1
	rm -rf /tmp/fd1
	for ((i=1; i<=$3; i++))
	do
		echo >&3
	done

	if [ ! -r $1 ]; then echo $1 不存在; return; fi
	rm -f $2 && touch $2
	pool $1 | while read line || [[ -n ${line} ]]
	do
		read -u3
		{
		local IPDATA=$(patch_location ${line})
		local COUNTRY=$(echo $IPDATA | awk -F"|" '{print $2}')
		local CODE=$(countrycode $COUNTRY)

		if [[ -z $CODE ]]; then local CODE='ZZ';fi

		if [[ $CODE == "CN" && $(echo ${IPDATA} | grep 台湾) ]]
		then
			local CODE='TW'
		fi
		if [[ $CODE == "CN" && $(echo ${IPDATA} | grep 香港) ]]
		then
			local CODE='HK'
		fi
		if [[ $CODE == "CN" && $(echo ${IPDATA} | grep 澳门) ]]
		then
			local CODE='MO'
		fi

		echo -e $CODE\|${IPDATA} >>$2
		echo >&3
		}&
	done
	wait

	exec 3<&-
	exec 3>&-

	unset i
}

function get_key_from_line() {
	local LINE=$1
	local KEY=$2
	local NUM=$(echo -e "${LINE}" | sed 's/[^\"]*//g' | wc -c)

	# 有引号分隔的yaml格式
    if [[ $[NUM] -gt 6 ]]; then
        echo -e "$LINE" | awk -F "${KEY}\":" '{print $2}'| cut -d "," -f1 | sed 's/^.//' | sed 's/.$//'
    else
    # 没有引号分隔的yaml格式
		echo -e "$LINE" | awk -F "${KEY}:" '{print $2}'| cut -d "," -f1 | sed -e 's/^[ ]*//g' | sed -e 's/[ ]*$//g'
    fi
}

function rename_line_by_value() {
    local LINE=$1            #line
    local NEW_VALUE=$2       #要更改为的名称
	local KEY=$3			 #键值

    local NUM=$(echo -e "${LINE}" | sed 's/[^\"]*//g' | wc -c)
	local OLD_VALUE=$(get_key_from_line "${LINE}" "${KEY}")

	# 去除行尾的空格和TAB
	LINE=$(echo -e ${LINE} | sed 's/[ \t]*$//g')
	# 有引号分隔的yaml格式
    if [[ $[NUM] -gt 6 ]]; then
		if [[ -z "${KEY}" ]]; then
			#键值不存在则新增
			echo -e "${LINE}" | sed s/.$/",\"${KEY}\":\"${NEW_VALUE}\"\}"/g
		else
			#键值存在则替换
			echo -e "${LINE}" | sed s/\""${OLD_VALUE}"\"/\""${NEW_VALUE}"\"/g
		fi
    else
    # 没有引号分隔的yaml格式
		if [[ -z "${KEY}" ]]; then
			#键值不存在则新增
			echo -e "${LINE}" | sed s/.$/", ${KEY}:${NEW_VALUE}\}"/g
		else
			#键值存在则替换
			echo -e "${LINE}" | sed s/\ "${OLD_VALUE}",/\ "${NEW_VALUE}",/g
		fi
    fi
}

# 单行重命名
function pool_rename_line() {

	local LINE=$(echo -e "$1")

	if [[ $(echo -e ${LINE} | awk -F" " '{print $1}') != '-' ]]; then
		local NEW_LINE=${LINE}
	else
		local SERVER=$(get_key_from_line "${LINE}" 'server')
		local COUNTRY=$(get_key_from_line "${LINE}" 'country')
		local NEW_NAME=$(cat ${LOCATION} | grep -e "|${SERVER}|" \
			| cut -d "|" -f1,3- | sed "s/\0|//g" | sed "s/|0//g")

		if [[ -z ${NEW_NAME} ]]; then
			local NEW_NAME='未知'
		fi

		# 修正国家代码
		local CODE=$(cat ${LOCATION} | grep -e "|${SERVER}|" | cut -d "|" -f1)
		local LINE=$(rename_line_by_value "${LINE}" "${CODE}" 'country')

		local NEW_LINE=$(rename_line_by_value "${LINE}" "${NEW_NAME}" 'name')
	fi
	
	echo -e "  ${NEW_LINE}"
}

# 根据地域批量节点服务器重命名
function pool_rename() {
	local NUM=$(echo -e $1 | cut -d "." -f1)
	cat $1 | while read line && [[ -n "${line}" ]]
	do
		local LINE=$(pool_rename_line "${line}")
		local NAME=$(get_key_from_line "${LINE}" 'name')
		if [[ -z ${NAME} ]]; then
			local NAME='ZZ|未知'
		fi
		local NEW_NAME=$(echo -e ${NAME}\|$(date +%N)\|)
		local NEW_LINE=$(rename_line_by_value "${LINE}" "${NEW_NAME}" 'name')

		echo -e "  ${NEW_LINE}" >> $2
	done
}

# 代理节点重命名 -- 多线程 -- 堵塞
# $1 原始代理池; $2 目标代理池; $3 每个进程最大处理行数设定 
function multi_pool_rename_pid() {
	local TOTAL=$(cat $1 | wc -l)
	local m=$3
	local n=$(expr $[TOTAL] / $[m] + 1)

	local START_TIME=$(date +%s)

	local TEMP_DIR=/tmp/tmp
	if [[ ! -d ${TEMP_DIR} ]]; then
		mkdir -p ${TEMP_DIR}
	fi

	if [[ $[n] -le 1 ]]; then
		cat $1 >${TEMP_DIR}/1.yaml
		pool_rename ${TEMP_DIR}/1.yaml ${TEMP_DIR}/FINAL-1.yaml
		cat ${TEMP_DIR}/FINAL-1.yaml >> $2
		local STOP_TIME=$(date +%s)
		echo -e "节点重命名总耗时: `expr $[STOP_TIME] - $[START_TIME]` 秒"
		exit 0		
	else
		for (( i=1; i<=$n; i++))
		do
			begin=$(($[i] * $[m] - $[m] + 1))
			if [ $i == $n ]; then
				end=$[TOTAL]
			else
				end=$(($[i] * $[m]))
			fi

			cat $1 | sed -n "$[begin],$[end]p" >${TEMP_DIR}/$i.yaml
			pool_rename ${TEMP_DIR}/$[i].yaml ${TEMP_DIR}/FINAL-$[i].yaml &
		done
	fi

	wait

	local i=1
	#echo "proxies:" > $1 
	while [ $[i] -le $[n] ]
	do
		cat ${TEMP_DIR}/FINAL-$[i].yaml >> $2
		let local i++
	done

	# rm -rf ${TEMP_DIR}
	
	local STOP_TIME=$(date +%s)
	echo -e "节点重命名总耗时: `expr $[STOP_TIME] - $[START_TIME]` 秒"
	
}

# 代理节点重命名 -- 多线程 -- 队列非堵塞
# $1 - 源配置文件 $2 - 目标配置文件 $3 - 每个线程队列数最大处理数
function multi_pool_rename_fd() {
	local m=$3

	echo 0 >/tmp/total_nodes
	local START_TIME=$(date +%s)
	[ -e /tmp/fd1 ] || mkfifo /tmp/fd1
	exec 3<>/tmp/fd1
	rm -rf /tmp/fd1
	for ((i=1; i<=$m; i++))
	do
		echo >&3
	done

	local i=0
	cat $1 | while read line && [[ -n ${line} ]]
	do
		read -u3
		let local i++
		{
			local LINE=$(pool_rename_line "${line}")
			local i=$(($(cat /tmp/total_nodes) + 1))
			local NAME=$(get_key_from_line "${LINE}" 'name')
			local NEW_NAME="${NAME}\|$(date +%N)\|"
			local NEW_LINE=$(rename_line_by_value "${LINE}" "${NEW_NAME}" 'name')			

			echo -e "${NEW_LINE}" >> $2
			echo $[i] >/tmp/total_nodes
			
			echo >&3
		}&
	done
	wait

	local STOP_TIME=$(date +%s)

	echo -e "节点命名总耗时: `expr $[STOP_TIME] - $[START_TIME]` 秒"
	exec 3<&-
	exec 3>&-
	
}

# 节点重命名速度测试
function rename_speed_test() {
	for ((i=$2; i<$3; i++))
	do
		if [ $1 == 1 ]; then
			local n=$[(($[i] * 100 + 100))]
			echo -e "重命名算法一:参数 $[n]"
			echo -e "$(multi_pool_rename_pid $FINAL_POOL $[n])"
		elif [ $1 == 2 ]; then
			local n=$[(($[i] * 10 + 10))]
			echo -e "重命名算法二:参数 $[n]"
			echo -e "$(multi_pool_rename_fd ${POOL} $FINAL_POOL $[n])"
		else
			echo -e "参数 $[$1] 错误"
			break
		fi
	done

	unset i
}

# multi_pool_rename_pid $POOL $FINAL_POOL 800

# multi_pool_rename_fd $POOL $FINAL_POOL 1


#test ok
# LINE=$(cat /tmp/tmp/1.yaml | tail -n 1)
# get_key_from_line "${LINE}" 'name'
# NEW_VALUE=wodfafad

# rename_line_by_value "${LINE}" "${NEW_VALUE}" 'name'

