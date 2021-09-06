#!/bin/bash

GITHUB='https://github.com'
OS='linux-amd64'
USER='Dreamacro'
APP='clash'
REPO=$USER/$APP
FILE=/tmp/bin/$APP.gz
PROXY_URL='https://ghproxy.com/'
PLATFORM=2	# 1 - 腾讯云函数	2 - github	3 - 其他

get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

get_clash() {
 
	if [[ $[PLATFORM] -eq 1 ]]; then
		local CLASH=/opt/bin/clash
	else
		local CLASH=`pwd`/bin/clash
	fi
	
	if [[ -e ${CLASH} ]]; then
		if [[ $(${CLASH} -v | awk '{print $2}') == $(get_latest_release $REPO) ]]; then
		echo -e "${CLASH} 是最新版本"
		return
		fi
	fi

	echo -e "开始更新和安装clash"
	VERSION=$(get_latest_release ${REPO})
	curl -L -s ${PROXY_URL}${GITHUB}/${USER}/${APP}/releases/download/${VERSION}/${APP}-${OS}-${VERSION}.gz -o ${FILE}
	gzip -f -d ${FILE}
	chmod 755 -R /tmp/bin/${APP}
	unset VERSION
}

mkdir /tmp/bin && chmod 755 -R /tmp/bin/
mkdir /tmp/subscribe
mkdir -p /tmp/tmp 
mkdir /tmp/.config
ulimit -SHn 65536

get_clash

if [[ $[PLATFORM] -eq 1 ]]; then
	cp -rf /opt/share/git-core /tmp/
	cp -rf /opt/subconverter /tmp/
	exit 0
fi

cp -rf `pwd`/share/git-core /tmp/
cp -rf `pwd`/subconverter /tmp/

sudo bash -c 'echo 10 >/proc/sys/net/ipv4/tcp_fin_timeout'
sudo bash -c 'echo 10 >/proc/sys/net/ipv4/tcp_keepalive_time'
sudo bash -c 'echo 1 >/proc/sys/net/ipv4/tcp_syncookies'
sudo bash -c 'echo 1 >/proc/sys/net/ipv4/tcp_tw_reuse'
sudo bash -c 'echo 10000 65000 >/proc/sys/net/ipv4/ip_local_port_range'
sudo bash -c 'echo 8192 >/proc/sys/net/ipv4/tcp_max_syn_backlog'
sudo bash -c 'echo 500 >/proc/sys/net/ipv4/tcp_max_tw_buckets'

exit 0