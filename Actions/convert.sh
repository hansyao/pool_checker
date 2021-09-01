#!/bin/bash

TEMP_DIR=/tmp
GITHUB=http/github.com
OS=linux64
USER=tindy2013
APP=subconverter
REPO=$USER/$APP
FILE=${TEMP_DIR}/$APP.tar.gz
PROXY_URL=https://lingering-math-d2ca.hansyow.workers.dev/

get_latest_release() {
  curl --silent "${PROXY_URL}https/api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}
VERSION=$(get_latest_release $REPO)

rm -rf $APP
rm -f $FILE

echo -e "下载$FILE"
curl -s -L -X GET ${PROXY_URL}${GITHUB}/${REPO}/releases/download/$VERSION/$APP\_$OS.tar.gz -o $FILE
echo -e "下载完成, 开始解压缩到 ${TEMP_DIR}/$APP"
tar -xvf $FILE -C ${TEMP_DIR}/ >/dev/null 2>&1
echo -e "解压完成，删除 $FILE"
rm -f $FILE

echo -e "设置权限 chmod 755 ${TEMP_DIR}/$APP/$APP"
chmod 755 ${TEMP_DIR}/$APP/$APP
echo -e "扩充EMOJI库"
cp -f ./Actions/emoji.txt ${TEMP_DIR}/${APP}/snippets/emoji.txt
echo -e "运行规则转换工具"
${TEMP_DIR}/$APP/$APP >/dev/null 2>&1 &
