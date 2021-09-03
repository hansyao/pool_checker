GITHUB='https/github.com'
OS='linux-amd64'
USER='Dreamacro'
APP='clash'
REPO=$USER/$APP
FILE=/tmp/bin/$APP.gz
PROXY_URL='https://lingering-math-d2ca.hansyow.workers.dev/'
PLATFORM=2	# 1 - 腾讯云函数	2 - github	3 - 其他

get_latest_release() {
  curl --silent "${PROXY_URL}https/api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
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
	cp -r /opt/share/git-core /tmp/
	exit 0
fi

GIT_EXEC_PATH=`pwd`/bin/git-core
PATH=`pwd`/bin:/tmp/bin:$PATH
GITPERLLIB=`pwd`/lib/perl
LD_LIBRARY_PATH=`pwd`/lib:$LD_LIBRARY_PATH

cp -r `pwd`/share/git-core /tmp/

sudo bash -c 'cat >> /etc/sysctl.conf <<EOF
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
EOF'
sudo sysctl -p

export GIT_EXEC_PATH PATH GITPERLLIB LD_LIBRARY_PATH
export HOME=/tmp/

export LANGUAGE=zh_CN.UTF-8
export LANG=zh_CN.UTF-8
export LC_CTYPE=zh_CN.UTF-8
export LC_COLLATE=zh_CN.UTF-8
export LC_IDENTIFICATION=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

exit 0