#!/bin/bash

function timestamp() {
	if [ $1 -eq 1 ]; then
		echo -e $(date -u +%s)
	elif [ $1 -eq 2 ]; then
		echo -e $(date -u +%F)
	else
		echo -e $(date -u "+%F %H:%M:%S")
	fi
}

function get_tc_env() {
	env | grep "$1" | sort | uniq
}

function env_var() {
	local ENV_LIST=$(get_tc_env 'TC_')
	if [[ -z ${ENV_LIST} ]]; then
		echo "没有有效的环境变量, 结束任务"
		exit 0
	fi
	echo -e "${ENV_LIST}" | while read ACCOUNT && [[ -n "${ACCOUNT}" ]]
	do
		local KEY=$(echo -e "${ACCOUNT}" | cut -d "=" -f1)
		local VALUE=$(echo -e "${ACCOUNT}" | cut -d "=" -f2)
		echo -n "{\"Key\":\"${KEY}\", \"Value\":\"${VALUE}\"},${ENV}"
	done
}

function hmac256_py() {

	cat >> $1 <<EOF
# -*- coding: utf-8 -*-
import sys
import hashlib
import hmac
secret_key = sys.argv[1]
service = sys.argv[2]
date = sys.argv[3]
string_to_sign = sys.argv[4]
def sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()
secret_date = sign(("TC3" + secret_key).encode("utf-8"), date)
secret_service = sign(secret_date, service)
secret_signing = sign(secret_service, "tc3_request")
signature = hmac.new(secret_signing, string_to_sign.encode(
    "utf-8"), hashlib.sha256).hexdigest()
print(signature)
EOF

}

function auth_sign() {
	local HEADER=$1
	local BODY=$2

	local SECRETID=${TC_SECRET_ID}
	local SECRETKEY=${TC_SECRET_KEY}
	local HMAC256="$(mktemp)"
	local ALGORITHM='TC3-HMAC-SHA256'
	local ENTER=$'\n'
	local TIME=$(echo -e "${HEADER}" | grep 'X-TC-Timestamp:' | awk '{print $2}')
	local DATE=$(date -u -d @${TIME} +%F)
	local TYPE=$(echo -e "${HEADER}" | grep 'Content-Type:' | sed s/\ //g)
	local HOST=$(echo -e "${HEADER}" | grep 'Host:' | awk '{print $2}')

	# ***************** 步骤 1：拼接规范请求串 *************
	local HTTP_REQUEST='POST'
	local URI='/'
	local QUERY=""
	local HEADERS="${TYPE}${ENTER}host:${HOST}\\n"
	local HEADERS=$(echo -n "${HEADERS}" | sed 's/\(.*\)/\L\1/')
	local SIGED_HEADERS='content-type;host'
	local HASED_REQUEST_PLAYLOAD=$(echo -n "${BODY}" | sha256sum | awk '{print $1}')
	local REQUEST="${HTTP_REQUEST}${ENTER}${URI}${ENTER}${QUERY}\
${ENTER}${HEADERS}${ENTER}${SIGED_HEADERS}${ENTER}${HASED_REQUEST_PLAYLOAD}"
	local HASHED_REQUEST=$(echo -e -n "${REQUEST}" | sha256sum | awk '{print $1}')

	# ***************** 步骤 2：拼接待签名字符串 *************
	local SERVICE=$(echo ${HOST} | cut -d "." -f1)
	local STRINGTOSIGN=$(echo -e "${ALGORITHM}${ENTER}${TIME}${ENTER}${DATE}\
/${SERVICE}/tc3_request${ENTER}${HASHED_REQUEST}")

	# ************* 步骤 3：计算签名 *************
	hmac256_py ${HMAC256}
	local SIGNATURE=$(python ${HMAC256} "${SECRETKEY}" "${SERVICE}" \
		"${DATE}" "${STRINGTOSIGN}")
	rm -f ${HMAC256}

	#  ************* 步骤 4：拼接 Authorization *************
	echo -e Authorization: ${ALGORITHM} 'Credential='${SECRETID}/${DATE}/${SERVICE}\
/tc3_request, 'SignedHeaders='${SIGED_HEADERS}, Signature=${SIGNATURE}
}

function header() {
	local HOST=$1
	local VERSION=$2
	local REGION=$3
	local ACTION=$4
	local HEADER=$5
	local TIME=$(timestamp 1)
	
	cat > ${HEADER} <<EOF
Host: ${HOST}
X-TC-Action: ${ACTION}
X-TC-Timestamp: ${TIME}
X-TC-Version: ${VERSION}
X-TC-Region: ${REGION}
X-TC-Language: zh-CN
Content-Type: application/json
EOF

}

function pack_code() {
	local ZIP_FILE=/tmp/$1.zip	
	# 打包代码
	zip -r ${ZIP_FILE} ./ -x ".git/*" -x ".github/*" -x "./bin/*" \
		-x "./lib/*" -x "./proxychain/*" -x "./share/*" \
		-x "./Actions/subscribe/*" -x "./subscribe/*" \
		-x "./subconverter/*" >/dev/null
	echo -e "${ZIP_FILE}"
}

function pack_code_layer() {
	local ZIP_FILE=/tmp/$1.zip	
	# 打包代码
	zip -r ${ZIP_FILE} ./ -i "bin/*" -i "lib/*" -i "proxychain/*" -i "share/*" -i "subconverter/*" >/dev/null
	echo -e "${ZIP_FILE}"
}

function body() {
	local ACTION=$1
	local FUNC_NAME=$2
	local BODY_JSON=$3

	if [[ ${ACTION} == 'CreateFunction' ]]; then
		# 函数基本配置
		local RUNTIME='CustomRuntime'
		local MEM=128
		local TIMEOUT=1800
		local AsyncRunEnable='TRUE'
		local TraceEnable='TRUE'

		if [[ -n $4 && -n $5 ]]; then
			local LAYERS="[{\"LayerName\": \"$4\", \"LayerVersion\": $5}]"
		else
			local LAYERS=\"\"
		fi

		# 代码基本配置
		local HANDLER='index.main_handler'
		local CODE='ZipFile'
		# 打包代码
		local ZIP_FILE=$(pack_code ${FUNC_NAME})
		local ZIPFILE_BASE64=$(cat ${ZIP_FILE} | base64 -w 0)
		echo -e "为函数${FUNC_NAME}打包代码为完成"

		echo -e "{\"FunctionName\": \"${FUNC_NAME}\", \
		\"Runtime\": \"${RUNTIME}\", \
		\"MemorySize\": ${MEM}, \
		\"Handler\": \"${HANDLER}\", \
		\"AsyncRunEnable\": \"${AsyncRunEnable}\", \
		\"TraceEnable\": \"${TraceEnable}\", \
		\"Timeout\": ${TIMEOUT}, \
		\"Layers\": ${LAYERS}, \
		\"Code\": {\"${CODE}\": \"${ZIPFILE_BASE64}\"}, \
		\"Environment\": {\"Variables\": [$(echo -n "$(env_var)" | sed s'/.$//')]}}" \
		>${BODY_JSON}

	elif [[ ${ACTION} == 'UpdateFunctionCode' ]]; then
		# 代码基本配置
		local HANDLER='index.main_handler'
		local CODE='ZipFile'
		# 打包代码
		local ZIP_FILE=$(pack_code ${FUNC_NAME})
		local ZIPFILE_BASE64=$(cat ${ZIP_FILE} | base64 -w 0)
		echo -e "为函数${FUNC_NAME}打包代码完成"

		echo -e "{\"FunctionName\": \"${FUNC_NAME}\", \
		\"Handler\": \"${HANDLER}\", \
		\"Code\": {\"${CODE}\": \""${ZIPFILE_BASE64}"\"}}" \
		>${BODY_JSON}

	elif [[ ${ACTION} == 'DeleteFunction' || ${ACTION} == 'Invoke' \
		|| ${ACTION} == 'GetFunction' ]]; then
		echo -e "{\"FunctionName\": \"${FUNC_NAME}\"}" \
		>${BODY_JSON}

	elif [[ ${ACTION} == 'UpdateFunctionConfiguration' ]]; then
		if [[ -n $4 && -n $5 ]]; then
			local LAYERS="[{\"LayerName\": \"$4\", \"LayerVersion\": $5}]"
		else
			local LAYERS=\"\"
		fi

		echo -e "{\"FunctionName\": \"${FUNC_NAME}\", \
		\"Layers\": ${LAYERS}, \
		\"Environment\": {\"Variables\": [$(echo -n "$(env_var)" | sed s'/.$//')]}}" \
		>${BODY_JSON}

	elif [[ "${ACTION}" == 'CreateTrigger' || "${ACTION}" == 'DeleteTrigger' ]]; then
		local TRIGGER_NAME=$4
		local TRIGGER_DESC=$5

		echo -e "{\"FunctionName\": \"${FUNC_NAME}\", \
		\"TriggerName\": \"${TRIGGER_NAME}\", \
		\"Type\": \"timer\", \
		\"TriggerDesc\": \"${TRIGGER_DESC}\"}" \
		>${BODY_JSON}

	elif [[ ${ACTION} == 'PublishLayerVersion' ]]; then
		# 层基本配置
		local LAYER_NAME="${FUNC_NAME}"
		local RUNTIMES='["CustomRuntime"]'
		local CODE='ZipFile'
		# 打包代码
		local ZIP_FILE=$(pack_code_layer ${LAYER_NAME})
		local ZIPFILE_BASE64=$(cat ${ZIP_FILE} | base64 -w 0)
		echo -e "为层 ${LAYER_NAME} 打包代码完成"

		echo -e "{\"LayerName\": \"${LAYER_NAME}\", \
		\"CompatibleRuntimes\": ${RUNTIMES}, \
		\"Content\": {\"${CODE}\": \""${ZIPFILE_BASE64}"\"}}" \
		>${BODY_JSON}

	elif [[ ${ACTION} == 'ListLayerVersions' ]]; then
		# 层基本配置
		local LAYER_NAME="${FUNC_NAME}"
		local RUNTIMES='["CustomRuntime"]'

		echo -e "{\"LayerName\": \"${LAYER_NAME}\"}" \
		>${BODY_JSON}
	else
		echo "参数错误！"
		echo -e "仅支持: \\n\
		CreateFunction	创建函数\\n\
		UpdateFunctionCode	更新函数代码\\n\
		UpdateFunctionConfiguration	更新函数配置\\n\
		CreateTrigger	创建触发器\\n\
		DeleteTrigger	删除触发器\\n\
		DeleteFunction	删除函数\\n\
		Invoke	运行函数\\n"
	fi
}

function post_result_func() {
	local ACTION=$1
	local BODY_JSON=$2

	# 定义函数
	local HOST='scf.tencentcloudapi.com'
	local VERSION='2018-04-16'
	local REGION='ap-shanghai'

	# 获取BODY内容
	local BODY=$(cat ${BODY_JSON})

	# 定义header
	local HEADER=/tmp/header.txt
	header "${HOST}" "${VERSION}" "${REGION}" "${ACTION}" "${HEADER}"

	# 根据HEADER和BODY签名
	local SIGNATURE=$(auth_sign "$(cat ${HEADER})" "${BODY}")

	# 将签名封装入header
	echo -e "${SIGNATURE}" >> ${HEADER}

	# 生成header数组，兼容老版本curl
	local ARGS[0]='-k'
	local i=1
	while read LINE && [[ -n "${LINE}" ]]
	do
		local ARGS[$[i]]='-H'
		local ARGS[$(($[i] + 1))]="${LINE}"
		i=$(($[i] + 2))
	done <${HEADER}

	# POST
	curl -s -H "${ARGS[@]}" -d @${BODY_JSON} "https://${HOST}/"
}

function wait_func_ready() {
	local FUNC_NAME=$1
	local BODY_JSON=$2

	local i=0
	while :
	do
		if [[ $[i] -ge 10 ]]; then
			echo -e "函数 ${FUNC_NAME} 更新超时$[i]秒"
			echo -e "结束任务"
			# 清理临时文件
			rm -f  ${ZIP_FILE}
			rm -f ${HEADER}
			rm -f ${BODY_JSON}
			return 1
		fi
		body 'GetFunction' "${FUNC_NAME}" "${BODY_JSON}"
		local RESPONSE=$(post_result_func GetFunction "${BODY_JSON}" \
			| jq -r '.Response.Status')
		if [[ "${RESPONSE}" == 'Active' ]]; then
			echo -e "函数 ${FUNC_NAME} 已经准备好"
			break
		fi
		sleep 1
		let i++
	done
}

ACTION=$1
FUNC_NAME=$2
BODY_JSON='/tmp/body.json'
ZIP_FILE=/tmp/"${FUNC_NAME}".zip

if [[ -z "${ACTION}" || -z "${FUNC_NAME}" ]]; then
	echo "缺少函数名或触发方式"
	exit 0
fi

if [[ "${ACTION}" == 'CreateFunction' ]]; then
	# 查询函数是否存在
	body 'GetFunction' "${FUNC_NAME}" "${BODY_JSON}"
	RESPONSE=$(post_result_func GetFunction "${BODY_JSON}")
	# 函数不存在，则创建
	if [[ $(echo -e "${RESPONSE}" | jq -r '.Response.Error') != 'null' ]]; then
		body 'CreateFunction' "${FUNC_NAME}" "${BODY_JSON}" "$3" "$4"
		post_result_func 'CreateFunction' "${BODY_JSON}"
	# 函数存在，则更新
	else
		echo '更新环境变量'
		body UpdateFunctionConfiguration "${FUNC_NAME}" "${BODY_JSON}" "$3" "$4"
		post_result_func UpdateFunctionConfiguration "${BODY_JSON}"

		echo -e "\\n等待环境变量更新成功"
		wait_func_ready "${FUNC_NAME}" "${BODY_JSON}"
		if [[ $? -eq 1 ]]; then exit 0; fi

		echo -e "\\n更新代码"
		body UpdateFunctionCode "${FUNC_NAME}" "${BODY_JSON}"
		post_result_func UpdateFunctionCode "${BODY_JSON}"
	fi

	echo -e "\\n等待函数发布成功"
	wait_func_ready "${FUNC_NAME}" "${BODY_JSON}"
	if [[ $? -eq 1 ]]; then exit 0; fi

	echo '开始测试运行函数'
	body Invoke "${FUNC_NAME}" "${BODY_JSON}"
	post_result_func Invoke "${BODY_JSON}"
	
elif [[ "${ACTION}" == 'CreateTrigger' || "${ACTION}" == 'DeleteTrigger' ]]; then
	TRIGGER_NAME=$3
	TRIGGER_DESC=$4
	body "${ACTION}" "${FUNC_NAME}" "${BODY_JSON}" "${TRIGGER_NAME}" "${TRIGGER_DESC}"
	post_result_func "${ACTION}" "${BODY_JSON}"
else
	# 按照触发条件生成BODY
	body "${ACTION}" "${FUNC_NAME}" "${BODY_JSON}"
	# 签名并执行函数
	post_result_func "${ACTION}" "${BODY_JSON}"
fi

# echo -e "\\n清理临时文件"
rm -f ${ZIP_FILE}
rm -f ${HEADER}
rm -f ${BODY_JSON}

exit 0