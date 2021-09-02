#!/bin/bash
# set -euo pipefail

CONTROLLER_PORT=3333
CONTROLLER="http://127.0.0.1:${CONTROLLER_PORT}"
TEST_URL='https://www.gstatic.com/generate_204'

# POOL='/tmp/subscribe/latest_pool.yaml'
# VERIFIED_POOL='/tmp/tmp/verified_pool.yaml'
# TARGET_NODES=10000
# DURATION=2400
# THREADNUMBER=30
# TIMEOUT=1000
# BLOCK_SIZE=300
# TEST_URL=http://cp.cloudflare.com/generate_204

function urlencode() {
    local LEN="${#1}"

    for (( i = 0; i < $[LEN]; i++ )); do
        c="${1:$i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

function urldecode() {
    local DATA=${1//+/ }

    printf '%b' "${DATA//%/\x}"
}

function filter_nodes() {
    local SOURCE=$1
    local TARGET=$2

    echo "proxies:" > ${TARGET}
    cat ${SOURCE} | grep "\- {" >>${TARGET}
}

function clash_help() {
	echo "how to manage clash:"
	echo "clash_exec start config pid"
	echo "clash_exec restart config pid"
	echo "clash_exec stop config pid"
}

function clash_exec() {
	local LOG=/dev/null
	if [[ -e /tmp/bin/clash ]]; then 
		local CLASH='/tmp/bin/clash'
	else
		local CLASH="`pwd`/bin/clash"
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
}

function start_clash() {
    local POOL=$1
    START_POOL="$(mktemp)"

    # 规则转换
    cp -f ${POOL} /tmp/tmp/tmp.yaml

    curl -s http://127.0.0.1:25500/sub\?target\=clash\&emoji\=true\&url\=../tmp/tmp.yaml >${START_POOL}

    sed -i "s/.*external\-controller.*/external\-controller: 0.0.0.0:${CONTROLLER_PORT}\\n/g" ${START_POOL}
    sed -i "s/.*mode: Rule.*/mode:\ global/g" ${START_POOL}
    
    # 启动clash
    rm -f /tmp/tmp/clash.pid
    clash_exec start "${START_POOL}" "/tmp/tmp/clash.pid"
}

function is_connected() {
    local NAME=$(urlencode "$1")
    local TIMEOUT=$2
    local STATUS=$(curl --connect-timeout 4 -m 6 -s -G -d "url=${TEST_URL}" -d "timeout=${TIMEOUT}" GET "${CONTROLLER}/proxies/${NAME}/delay")

    if [[ -z $(echo ${STATUS} | grep 'delay') ]]; then
        echo $1 $(echo -e "${STATUS}")
    elif [[ -z ${STATUS} ]]; then
        echo $1 '无效检测'
    else
        echo ${STATUS} | jq -r '.delay'
    fi
}

function is_num() {
    local re='^[0-9]+$'

    if [[ $1 =~ $re ]]; then
        echo 'yes'
    else
        echo 'no'
    fi
}

function clash_node() {
    local NAME=$1            #查询条件-名称
    local POOL=$2            #代理池
    local VERIFIED_POOL=$3

    # 有引号分隔的yaml格式
    local NUM=$(cat ${POOL} | grep "${NAME}" | sed 's/[^\"]*//g' | wc -c)
    if [[ $[NUM] -gt 6 ]]; then 
        cat ${POOL} | grep -e "\"${NAME}\"" >>${VERIFIED_POOL}
    else
    # 没有引号分隔的yaml格式
        cat ${POOL} | grep -e "\ ${NAME}," >>${VERIFIED_POOL}
    fi 
}

function check_port() {
	CHECK=$(lsof -i :$1 | awk '{print $1 " "  $2}')
	if [[ -z ${CHECK} ]]; then
		echo -e "no"
	else
		echo -e "yes"
	fi

	unset CHECK
}

function split_config() {
    local POOL=$1
    local BLOCK_LINES=$2
    local SPLIT_FOLDER=/tmp/split

    local LIST=$(cat ${POOL} | grep "\-\ {")
    local TOTAL=$(echo -e "${LIST}" | wc -l)
    local n=$(($[TOTAL] / $[BLOCK_LINES]))

    rm -rf ${SPLIT_FOLDER}
    mkdir ${SPLIT_FOLDER}

    local i=1
    while [[ $[i] -le $[n] ]]
    do
        local BEGIN=$(($[i] * $[BLOCK_LINES] - $[BLOCK_LINES] + 1))
        local END=$(($[i] * $[BLOCK_LINES]))

        echo -e $[i]\\t$[BEGIN]\\t$[END]
        echo "proxies:" >${SPLIT_FOLDER}/$[i].yaml
        echo -e "${LIST}" | sed -n "$[BEGIN],$[END]p" >> ${SPLIT_FOLDER}/$[i].yaml
        
        if [[ $[i] -eq $[n] && $[END] -lt $[TOTAL] ]]; then
            local BEGIN=$(($[i] * $[BLOCK_LINES] +1))
            local END=$[TOTAL]
            
            echo -e $(($[i] + 1))\\t$[BEGIN]\\t$[END]

            echo "proxies:" >${SPLIT_FOLDER}/$(($[i] + 1)).yaml
            echo -e "${LIST}" | sed -n "$[BEGIN],$[END]p" >> ${SPLIT_FOLDER}/$(($[i] + 1)).yaml
        fi

        let local i++
    done
}

function connetion_test() {
    local POOL=$1
    local VERIFIED_POOL=$2
    local TARGET_NODES=$3
    local DURATION=$4
    local THREADNUMBER=$5
    local TIMEOUT=$6
    local CONTROLLER=${CONTROLLER}

    echo "开始规则转换，并启动clash客户端"
    # sudo netplan apply
    start_clash ${POOL}
	echo "暂停 2 秒 确保clash启动正常"
    sleep 2

    TRANS_POOL="$(mktemp)"
    filter_nodes ${START_POOL}  ${TRANS_POOL}

    echo "开始规则转换"
    local EXCL='(DIRECT|REJECT|节点选择|全球拦截|漏网之鱼|自动选择|国外媒体|国内媒体|微软服务|电报信息|苹果服务|全球直连|\[|\])' 
    local LIST=$(curl -s ${CONTROLLER}/proxies | jq -r ".proxies" | jq -r ".GLOBAL" | jq -r ".all" | egrep -v ${EXCL}| awk -F "\"" '{print $2}')
    local START_TIME=$(date +%s)

    echo "规则转换完成"
    # echo -e "${LIST}"

    # echo -e "proxies:" > ${VERIFIED_POOL}
    local COUNT_START=$(($(cat ${VERIFIED_POOL} | wc -l) - 1))

    # 线程数透传
    [ -e /tmp/fd2 ] || mkfifo /tmp/fd2
    exec 3<>/tmp/fd2
    rm -rf /tmp/fd2
    for ((i=1; i<=$[THREADNUMBER]; i++))
    do
        echo >&3
    done
    unset i

    # 节点数计数透传
    [ -e /tmp/fd1 ] || mkfifo /tmp/fd1
    exec 4<>/tmp/fd1
    rm -rf /tmp/fd1
    echo >&4

    echo -e "${LIST}" | while read line && [[ -n "${line}" ]]
    do
        read -u3 SIGNAL
        if [[ $[SIGNAL] -eq 1 ]]; then
            kill  `cat /tmp/tmp/clash.pid`
            rm -f /tmp/tmp/clash.pid
            break
        fi

        {
            local STOP_TIME=$(date +%s)
            local SPENT_TIME=$(($[STOP_TIME] - $[START_TIME]))
            if [[ $[SPENT_TIME] -gt $[DURATION] ]]; then
                echo 1 >&3
                exit 0
            fi

            local DELAY=$(is_connected "${line}" $[TIMEOUT])
            if [[ -z ${DELAY} || ${DELAY} == 'null' ]]; then echo >&3; exit 0; fi
            # echo "Delay ${DELAY}"
            if [[ $(is_num ${DELAY}) == 'yes' ]]; then
                read -u4 TOTAL_VALID_COUNT
                local TOTAL_VALID_COUNT=$(($[TOTAL_VALID_COUNT] + 1))
                echo $[TOTAL_VALID_COUNT] >&4

                if [[ $[TOTAL_VALID_COUNT] -gt $[TARGET_NODES] ]]; then
                    echo 1 >&3
                    exit 0
                fi
                clash_node "${line}" "${TRANS_POOL}" "${VERIFIED_POOL}" 
                echo -e "$[TOTAL_VALID_COUNT]  ${line} 延迟$[DELAY]毫秒 测试通过"
            fi
            echo >&3
        }&
    done

    local i=0
    while :
    do
        echo -e "正在退出 当前线程数" $(ps -ef | grep $(basename $0) | grep -v "grep" | wc -l)
        
        # 如果进程数小于或等于6,要求2秒内完成任务，否则判定为堵塞强制退出释放内存
        if [[ $(ps -ef | grep $(basename $0) | grep -v grep | wc -l) -le 6 ]]; then
            if [[ $[i] -le 2 ]]; then
                sleep 1
                let local i++
                continue
            fi
            # 如果2秒钟不能退出，则放弃, 停止进程
            # if [[ $(ps -ef | grep "bin/clash" | grep -v grep | wc -l) -ne 0 ]]; then
            #     kill -9 $(ps -ef | grep "bin/clash" | grep -v "grep" | awk '{print $2}')
            # fi
            break
        fi
        sleep 1
    done

    if [[ $(ps -ef | grep "bin/clash" | grep -v grep | wc -l) -ne 0 ]]; then
        kill -9 $(ps -ef | grep "bin/clash" | grep -v "grep" | awk '{print $2}')
    fi

    local STOP_TIME=$(date +%s)
    local COUNT_END=$(($(cat ${VERIFIED_POOL} | wc -l) - 1))
    local COUNT=$(($[COUNT_END]-$[COUNT_START]))
    local SINGLE_COUNT=$(echo -e "${LIST}" | wc -l)
    echo -e "发现延迟${TIMEOUT}毫秒以下节点(本次:${COUNT} | 累计:${COUNT_END}）个可用节点 本次共检测节点: ${SINGLE_COUNT} 耗时:`expr $[STOP_TIME] - $[START_TIME]` 秒"

    echo $(($(cat /tmp/check_count_total) + $[SINGLE_COUNT])) > /tmp/check_count_total   

    exec 4<&-
    exec 4>&-
    exec 3<&-
    exec 3>&-
}

function connetion_test_split() {
    local POOL=$1
    local VERIFIED_POOL=$2
    local TARGET_NODES=$3
    local DURATION=$4
    local THREADNUMBER=$5
    local TIMEOUT=$6
    local BLOCK_SIZE=$7
    local CONTROLLER=${CONTROLLER}
    local SPLIT_FOLDER=/tmp/split

    local START_TIME=$(date +%s)
    local DURATION_INIT=$[DURATION]
    local POOL_INIT=${POOL}
    local TARGET_NODES_INIT=$[TARGET_NODES]

    echo -e "proxies:" > ${VERIFIED_POOL}
    echo 0 >/tmp/check_count_total

    echo "开始分割文件"
    if [[ $(cat ${POOL} | wc -l) -gt  $[TARGET_NODES_INIT] ]]; then
        local SEGMENT=$(split_config ${POOL} $[BLOCK_SIZE])
        local CONFIG=$(echo -e "${SEGMENT}" | awk '{print $1}')
        echo "完成文件分割"  
    else
        echo "代理池节点数小于目标节点数，无需分割"
        rm -rf ${SPLIT_FOLDER}
        mkdir ${SPLIT_FOLDER}
        local LIST=$(cat ${POOL} | grep "\-\ {")
        echo -e "proxies:" >${SPLIT_FOLDER}/1.yaml
        echo -e "${LIST}" >>${SPLIT_FOLDER}/1.yaml
        local CONFIG='1'
    fi

    echo -e "${CONFIG}" | while read line && [[ -n ${CONFIG} ]]
    do
        # echo -e "开始测试第 ${line} 个配置文件"
        # sleep 1
        local POOL=${SPLIT_FOLDER}/${line}.yaml
        if [ -e ${VERIFIED_POOL} ]; then
            local CURRENT_NODES=$(($(cat ${VERIFIED_POOL} | wc -l) - 1))
        else
            local CURRENT_NODES=0
        fi
        if [[ $[CURRENT_NODES] -ge $[TARGET_NODES_INIT] ]]; then break; fi
        local TARGET_NODES=$(($[TARGET_NODES_INIT] - $[CURRENT_NODES]))
        local STOP_TIME=$(date +%s)
        local SPENT_TIME=$(($[STOP_TIME] - $[START_TIME]))
        if [[ $[SPENT_TIME] -ge $[DURATION_INIT] ]]; then break; fi
        local DURATION=$(($[DURATION_INIT] - $[SPENT_TIME]))

        echo -e "\\n开始测试 第${line}个配置文件 ${POOL}" "目标节点数:${TARGET_NODES} 延迟要求${TIMEOUT}毫秒以下 限时: ${DURATION}秒"
        connetion_test  "${POOL}" "${VERIFIED_POOL}" $[TARGET_NODES] $[DURATION] $[THREADNUMBER] $[TIMEOUT]
        echo -e "测试完成 ${POOL}"
    done

    local CURRENT_NODES=$(($(cat ${VERIFIED_POOL} | wc -l) - 1))
    local STOP_TIME=$(date +%s)
    echo -e "\\n全部检测完成!!\\n可用节点:${CURRENT_NODES} 共检测节点: $(cat /tmp/check_count_total) of $(cat ${POOL} | wc -l)  总耗时:`expr $[STOP_TIME] - $[START_TIME]` 秒"
}

# connetion_test_split "${POOL}" "${VERIFIED_POOL}" $[TARGET_NODES] $[DURATION] $[THREADNUMBER] $[TIMEOUT] $[BLOCK_SIZE]

# start_clash ${POOL}
# connetion_test  "${POOL}" "${VERIFIED_POOL}" $[TARGET_NODES] $[DURATION] $[THREADNUMBER] $[TIMEOUT]
