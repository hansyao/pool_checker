#!/bin/bash

# ***********************参数初始化************************* /
RENAME='yes'                    #是否重新命名
CONVERT='yes'                   #是否规则转换
DURATION=1500                   #目标运行时间：秒
TARGET_NODES=20000              #目标验证节点数
TIMEOUT=2                       #连接超时：秒
BLOCK_SIZE=300                  #配置文件切分大小
THREADNUMBER=150                 #线程数(连接数check)：按性能调整
THREADNUMBER2=100                 #线程数(节点重命名)：按性能调整
ALGORITHM=3                     #多线程算法:1-队列；2-动态分组; 3-队列（CLASH API）
URL=${TC_POOL_URL}              # 代理池URL地址
PLATFORM=2                      # 1 - 腾讯云函数	2 - github	3 - 其他
# ***********************参数初始化完成********************* /

SUSCRIBE_DIR=/tmp/subscribe
TOTAL_VALID_COUNT=/tmp/total_valid_nodes
TEMP_DIR=/tmp/tmp
TEMP=temp_pool.yaml
ALLPOOL=pool.yaml
ALLPOOL_RENAMED=pool_renamed.yaml
VALID_POOL=valid_pool.yaml
LPOOL=latest_pool.yaml
POOL=pool_no_cn.yaml
POOL_VERIFIED=pool_no_cn_verified.yaml
POOL_CHINA=pool_cn_only.yaml
CLASH1=clash_all_verified.yaml                  #所有地区
CLASH2=clash.yaml                               #缺省（亚太和美国节点)
CLASH3=clash_asia.yaml                          #亚太（香港，台湾，日本，韩国）
CLASH4=clash_south_asia.yaml                    #南亚（印度，新加坡，印尼，巴基斯坦，泰国，越南, 土耳其等)
CLASH5=clash_china.yaml                         #回国模式，中国内地
CLASH6=clash_others.yaml                        #其他 (非洲，欧洲，南美等)
LOCATION=/tmp/location.txt

function timestamp() {
        date +"%Y-%m-%d %H:%M:%S" # current time
}

function roundup() {
        FLOOR=`echo "scale=0;$1/1"|bc -l ` # 向下取整
        ADD=`awk -v NUM1=${FLOOR} -v NUM2=$1 'BEGIN{print(NUM1<NUM2)?"1":"0"}'`
        echo `expr $FLOOR + $ADD`

        unset NUM1
        unset NUM2
        unset FLOOR
        unset ADD
}

echo 0 >/tmp/total_valid_nodes
START_TIME=$(date +%s)
echo -e "开始爬取 $(timestamp)"

rm -rf "${SUSCRIBE_DIR}/${LPOOL}"
rm -f "${SUSCRIBE_DIR}/${TEMP}"
i=0
while [[ ! -s "${SUSCRIBE_DIR}/${TEMP}" ]]
do
	if [ $i -ge 50 ]; then
                echo "爬取失败超过50次，终止爬取"
                exit 0
        fi

        sleep 1
        if [ $i != 0 ]; then
	        echo -e 第 $i 次爬取失败
        fi
	rm -f "${SUSCRIBE_DIR}/${TEMP}"
	curl -s -L ${URL} | grep "\-\ {" >"${SUSCRIBE_DIR}/${TEMP}"
	let i++
done

echo -e "第 $i 次爬取成功 获得节点信息 >> "${SUSCRIBE_DIR}/${TEMP}" $(timestamp)"
unset i



sed -i '1i\proxies\:'  "${SUSCRIBE_DIR}/${TEMP}"

echo -e "检查代理池是否有变化"
if [[ $(md5sum "${SUSCRIBE_DIR}/${TEMP}" | awk -F" " '{print $1}') == $(md5sum "${SUSCRIBE_DIR}/$LPOOL" | awk -F" " '{print $1}') ]]; then
        echo -e "代理池没变化退出流程 $(timestamp)"
        rm -f "${SUSCRIBE_DIR}/${TEMP}"
        exit 0
fi
echo -e "代理池检查完成 $(timestamp)"
cp -f "${SUSCRIBE_DIR}/${TEMP}" "${SUSCRIBE_DIR}/${LPOOL}"
rm -f "${SUSCRIBE_DIR}/${ALLPOOL}"

echo -e "开始排除不可用节点 $(timestamp)"

if [[ $[ALGORITHM] -eq 1 ]]; then
        # 算法一
        source ./Actions/connection_test.sh
        pool_validate_fd "${SUSCRIBE_DIR}/${TEMP}" "${SUSCRIBE_DIR}/${VALID_POOL}" "$[THREADNUMBER]"
elif [[ $[ALGORITHM] -eq 2 ]]; then
        # 算法二
        source ./Actions/connection_test.sh
        NUM=$(($(cat ${SUSCRIBE_DIR}/${TEMP} | wc -l) / $[THREADNUMBER]))
        NUM=$(roundup $[NUM])
        pool_validate_pid "${SUSCRIBE_DIR}/${TEMP}" "${SUSCRIBE_DIR}/${VALID_POOL}" "$[NUM]"
elif [[ $[ALGORITHM] -eq 3 ]]; then
        # 算法三
        source ./Actions/conn_test_by_clash_api.sh
        connetion_test_split  "${SUSCRIBE_DIR}/${TEMP}" "${SUSCRIBE_DIR}/${VALID_POOL}" $[TARGET_NODES] $[DURATION] $[THREADNUMBER] $(($[TIMEOUT] * 1000)) $[BLOCK_SIZE]
fi
echo -e "排除不可用节点完成 $(timestamp)"

# echo -e "已抓取可用节点......"
# cat "${SUSCRIBE_DIR}/${VALID_POOL}"

if [[ ${RENAME} == 'no' ]]; then
        if [[ ${CONVERT} == 'yes' ]]; then
                echo -e "开始规则转换 $(timestamp)"
                curl -s http://127.0.0.1:25500/sub\?target\=clash\&emoji\=true\&url\=../subscribe/${VALID_POOL} -o "${SUSCRIBE_DIR}/${CLASH1}"
                echo -e "clash规则转化完成 $(timestamp)"
        else
                cp -r "${SUSCRIBE_DIR}/${VALID_POOL}" "${SUSCRIBE_DIR}/${CLASH1}"
        fi
        ./gitpush.sh "${SUSCRIBE_DIR}/${CLASH1}"
        exit 0
fi

echo -e "开始地域查询与转换 $(timestamp)"
source ./Actions/proxy_rename.sh
# 得到IP地域文件
START_TIME=$(date +%s)
location "${SUSCRIBE_DIR}/${VALID_POOL}" "${LOCATION}" $[THREADNUMBER2]
STOP_TIME=$(date +%s)
echo -e "查询IP地域总耗时: `expr $[STOP_TIME] - $[START_TIME]` 秒"

echo -e "开始节点重命名 $(timestamp)"
cp "${SUSCRIBE_DIR}/${VALID_POOL}" "${SUSCRIBE_DIR}/${ALLPOOL}"

if [[ $[ALGORITHM] -eq 10 ]]; then
        multi_pool_rename_fd "${SUSCRIBE_DIR}/${VALID_POOL}" "${SUSCRIBE_DIR}/${ALLPOOL_RENAMED}" "$[THREADNUMBER2]"
else
        NUM=$(($(cat ${SUSCRIBE_DIR}/${VALID_POOL} | wc -l) / $[THREADNUMBER2]))
        NUM=$(roundup $[NUM])
        multi_pool_rename_pid "${SUSCRIBE_DIR}/${VALID_POOL}" "${SUSCRIBE_DIR}/${ALLPOOL_RENAMED}" "$[NUM]"
fi


echo -e "开始规则转换 $(timestamp)"
echo CLASH1=clash_all_verified.yaml                  #除中国外所有地区
echo CLASH2=clash.yaml                               #缺省（亚太和美国节点)
echo CLASH3=clash_asia.yaml                          #亚太（香港，台湾，日本，韩国, 澳洲）
echo CLASH4=clash_south_asia.yaml                    #南亚（印度，新加坡，印尼，巴基斯坦，泰国，越南, 土耳其等)
echo CLASH5=clash_china.yaml                         #回国模式，中国内地
echo CLASH6=clash_others.yaml                        #其他 (非洲，欧洲，南美等)


echo -e "回国模式China Only $(timestamp)"
cat "${SUSCRIBE_DIR}/${ALLPOOL_RENAMED}" | grep '中国\|proxies:' | grep -v '台湾' | grep -v '香港' | grep -v '澳门' > "${SUSCRIBE_DIR}/${POOL_CHINA}"
echo -e "转换CHINA节点 $(timestamp)"
curl -s http://127.0.0.1:25500/sub\?target\=clash\&emoji\=true\&url\=../subscribe/${POOL_CHINA} -o "${SUSCRIBE_DIR}/${CLASH5}" >/dev/null 2>&1

echo -e "排除CHINA节点 $(timestamp)"
cat "${SUSCRIBE_DIR}/${ALLPOOL_RENAMED}" | grep -v '中国' | grep -Ev '^#|^$' > "${SUSCRIBE_DIR}/${POOL_VERIFIED}"
cat "${SUSCRIBE_DIR}/${ALLPOOL_RENAMED}" | grep '台湾\|香港\|澳门' >> "${SUSCRIBE_DIR}/${POOL_VERIFIED}"
echo -e "转换非CHINA节点 $(timestamp)"
curl -s http://127.0.0.1:25500/sub\?target\=clash\&emoji\=true\&url\=../subscribe/${POOL_VERIFIED} -o "${SUSCRIBE_DIR}/${CLASH1}" >/dev/null 2>&1 

INCL=\(HK\|香港\|TW\|台湾\|JP\|日本\|KR\|韩国\|US\|美国\|CA\|加拿大\)
echo -e '转换亚太区(台湾|日本|韩国|香港|美国|加拿大)为缺省配置'
curl -s http://127.0.0.1:25500/sub\?target\=clash\&emoji\=true\&include=$INCL\&url\=../subscribe/${POOL_VERIFIED}  -o "${SUSCRIBE_DIR}/${CLASH2}" >/dev/null 2>&1 

INCL=\(HK\|香港\|TW\|台湾\|JP\|日本\|KR\|韩国\|澳洲\|澳大利亚\)
echo -e '转换亚太区+澳洲(台湾|日本|韩国|香港|澳大利亚)' $(timestamp)
curl -s http://127.0.0.1:25500/sub\?target\=clash\&emoji\=true\&include=$INCL\&url\=../subscribe/${POOL_VERIFIED}  -o "${SUSCRIBE_DIR}/${CLASH3}" >/dev/null 2>&1 

INCL=\(IN\|印度\|SG\|新加坡\|印尼\|印度尼西亚\|巴基斯坦\|泰国\|越南\|土耳其\)
echo -e '转换南亚区(印度，新加坡，印尼，巴基斯坦，泰国，越南, 土耳其)' $(timestamp)
curl -s http://127.0.0.1:25500/sub\?target\=clash\&emoji\=true\&include=$INCL\&url\=../subscribe/${POOL_VERIFIED}  -o "${SUSCRIBE_DIR}/${CLASH4}" >/dev/null 2>&1 

EXCL=\(HK\|香港\|TW\|台湾\|JP\|日本\|KR\|韩国\|US\|美国\|CA\|加拿大\|HK\|香港\|TW\|台湾\|JP\|日本\|KR\|韩国\|澳洲\|澳大利亚\|印度\|新加坡\|印尼\|印尼\|印度尼西亚\|巴基斯坦\|泰国\|越南\|土耳其\|中国\)
echo -e '转换其他区 (非洲，欧洲，南美等)' $(timestamp)
curl -s http://127.0.0.1:25500/sub\?target\=clash\&emoji\=true\&exclude=$EXCL\&url\=../subscribe/${POOL_VERIFIED}  -o "${SUSCRIBE_DIR}/${CLASH6}" >/dev/null 2>&1 


echo -e "clash规则转化完成 $(timestamp)"

if [[ $[PLATFORM] -ne 2 ]]; then
        ./gitpush.sh "${SUSCRIBE_DIR}/${CLASH1}" \
                "${SUSCRIBE_DIR}/${CLASH2}" "${SUSCRIBE_DIR}/${CLASH3}" \
                "${SUSCRIBE_DIR}/${CLASH4}" "${SUSCRIBE_DIR}/${CLASH5}" \
                "${SUSCRIBE_DIR}/${CLASH6}" "${SUSCRIBE_DIR}/${POOL_VERIFIED}"

        echo -e '清除环境....'
        ./start.sh clean

        echo -e '清除环境完成，结束任务退出....'
        exit 0
fi

if [[ ! -d subscribe ]]; then mkdir subscribe; fi
cp -f ${SUSCRIBE_DIR}/clash*.yaml ./subscribe/
cp -f "${SUSCRIBE_DIR}/${POOL_VERIFIED}" ./subscribe/
