#!/bin/bash

SECRET_ID=${TC_SECRET_ID}
SECRET_KEY=${TC_SECRET_KEY}

HEADER_FILE='/tmp/header.txt'

CMD=$1		# 命令: 可选upload_file, get_bucket
HOST=$2		# tencent cos host名称
UPLOAD_FILE=$3	# 上传文件路径
CONTENT_TYPE=$4	# 文件类型
HTTPURI=$5	# tencent cos文件夹路径
OBJ_KEY$6	# tencent cos的文件名

function urlencode() {
	ENCODE_STR=$(echo -E "$1" |sed "s/%/%%/g")
	printf -- "$ENCODE_STR" \
	| curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "" \
	| cut -c 3-
}

function xmlphaser() {
	awk "/<\/*$1\/*>/{gsub(/[[:space:]]*<\/*$1\/*>/,\"\");print \$0}"
}

function httpHeaders() {
	local HEADER_FILE=$1
	local SENARIO=$2
	if [[ ${SENARIO} == 'HeaderList' ]]; then
		local HeaderList=$(cat "${HEADER_FILE}" \
			| sort -d | cut -d ":" -f1 \
			| sed 's/\(.*\)/\L\1/' | sed ":a;N;s/\n/\;/g;ta")
		echo -n "${HeaderList}"
	elif [[ ${SENARIO} == 'HttpHeaders' ]]; then
		cat "${HEADER_FILE}" | sort -d | while read LINE && [[ -n ${LINE} ]]
		do
			local KEY=$(echo -e "${LINE}" | cut -d ":" -f1 \
				| sed 's/\(.*\)/\L\1/')
			local VALUE=$(echo -e "${LINE}" | cut -d ":" -f2- \
				| sed 's/^ *//g')
			echo -e "${KEY}"\=$(urlencode "${VALUE}")
		done
	else
		return 1
	fi
}

function auth_sign() {
	local SECRET_ID=$1
	local SECRET_KEY=$2
	local StartTimestamp=$3
	local SIGN_EXPIRES=$4	# 单位: 分钟
	local HTTP_METHOD=$5
	local HEADER_FILE=$6
	local HTTPURI=$7

	# 步骤1：生成 KeyTime
	local EndTimestamp=$(($[StartTimestamp] + $[SIGN_EXPIRES] * 60))
	local KeyTime="${StartTimestamp};${EndTimestamp}"

	# 步骤2：生成 SignKey
	local SignKey=$(echo -e -n "${KeyTime}" \
		| openssl dgst -hmac "${SECRET_KEY}" -sha1 -hex | awk '{print $2}')

	# 步骤3：生成 UrlParamList 和 HttpParameters
	local HttpParameters=''
	local UrlParamList=''

	# 步骤4：生成 HeaderList 和 HttpHeaders
	local HeaderList=$(httpHeaders "${HEADER_FILE}" 'HeaderList')
	local HttpHeaders=$(httpHeaders "${HEADER_FILE}" 'HttpHeaders' \
		| sed ":a;N;s/\n/\&/g;ta")

	# 步骤5：生成 HttpString
	local HttpString="${HTTP_METHOD}\\n${HTTPURI}\\n${HttpParameters}\\n${HttpHeaders}\\n"

	# 步骤6：生成 StringToSign
	local StringToSign="sha1\\n${KeyTime}\\n$(echo -e -n "${HttpString}" \
		| sha1sum | cut -d " " -f1)\\n"

	# 步骤7：生成 Signature
	local Signature=$(echo -e -n "${StringToSign}" \
		| openssl dgst -hmac "${SignKey}" -sha1 -hex | awk '{print $2}')

	# 步骤8：生成签名
	echo -e Authorization: q-sign-algorithm=sha1\
\&q-ak=${SECRET_ID}\
\&q-sign-time=${KeyTime}\
\&q-key-time=${KeyTime}\
\&q-header-list=${HeaderList}\
\&q-url-param-list=${UrlParamList}\
\&q-signature=${Signature}
}

function header_array() {
	ARGS[0]='-k'
	local i=1
	while read LINE && [[ -n "${LINE}" ]]
	do
		ARGS[$[i]]='-H'
		ARGS[$(($[i] + 1))]="${LINE}"
		i=$(($[i] + 2))
	done <$1
}

function upload_file() {
	local UPLOAD_FILE=$1
	local CONTENT_TYPE=$2
	local HTTPURI=$3
	local OBJ_KEY=$4
	local SIGN_EXPIRES=60

	# 定义header
	local StartTimestamp=$(date -u +%s)
	cat > ${HEADER_FILE} <<EOF
HOST: ${HOST}
Date: $(date -u -R -d @$[StartTimestamp] | sed s/\+0000/GMT/g)
Content-MD5: $(openssl md5 -binary "${UPLOAD_FILE}" | base64)
Content-Disposition: attachment
x-cos-acl: public-read
x-cos-storage-class: STANDARD
Expires: ${SIGN_EXPIRES}
Content-Type: ${CONTENT_TYPE}
EOF

	# 追加签名到header
	auth_sign "${SECRET_ID}" "${SECRET_KEY}" "${StartTimestamp}" \
		${SIGN_EXPIRES} put "${HEADER_FILE}" "${HTTPURI}${OBJ_KEY}" >>"${HEADER_FILE}"

	# 生成header数组，兼容老版本curl
	header_array "${HEADER_FILE}"

	# 上传文件
	URL="https://${HOST}${HTTPURI}${OBJ_KEY}"
	curl --connect-timeout 2 -m 4 -s -o /dev/null -w "%{http_code}" \
		-H "${ARGS[@]}" -T ${UPLOAD_FILE} -X PUT "${URL}"

	unset ARGS
}

function get_bucket() {
	local HTTPURI=$1
	local SIGN_EXPIRES=60

	# 定义header
	local StartTimestamp=$(date -u +%s)
	cat > ${HEADER_FILE} <<EOF
HOST: ${HOST}
EOF

	# 追加签名到header
	auth_sign "${SECRET_ID}" "${SECRET_KEY}" "${StartTimestamp}" \
		${SIGN_EXPIRES} get "${HEADER_FILE}" "${HTTPURI}" >>"${HEADER_FILE}"

	# 生成header数组，兼容老版本curl
	header_array "${HEADER_FILE}"

	# 请求
	URL="https://${HOST}${HTTPURI}"
	curl --connect-timeout 2 -m 4 -s \
		-H "${ARGS[@]}" "${URL}"

	unset ARGS
}

function check_bucket() {
	local HTTPURI=$1
	local SIGN_EXPIRES=60

	# 定义header
	local StartTimestamp=$(date -u +%s)
	cat > ${HEADER_FILE} <<EOF
HOST: ${HOST}
Date: $(date -u -R -d @$[StartTimestamp] | sed s/\+0000/GMT/g)
EOF

	# 追加签名到header
	auth_sign "${SECRET_ID}" "${SECRET_KEY}" "${StartTimestamp}" \
		${SIGN_EXPIRES} head "${HEADER_FILE}" "${HTTPURI}" >>"${HEADER_FILE}"

	# 生成header数组，兼容老版本curl
	header_array "${HEADER_FILE}"

	# 请求
	URL="https://${HOST}${HTTPURI}"
	curl --connect-timeout 2 -m 4 -i -s -o /dev/null -w "%{http_code}" \
		-H "${ARGS[@]}" -X HEAD "${URL}"

	unset ARGS
}

if [[ $CMD == upload_file ]]; then
	upload_file "${UPLOAD_FILE}" "${CONTENT_TYPE}" "${HTTPURI}" "${OBJ_KEY}"
elif [[ $CMD == get_bucket ]]; then
	get_bucket "/" | xmlphaser 'Name'
elif [[ $CMD == check_bucket ]]; then
	check_bucket "/"
else
	echo "命令参数错误!"
fi