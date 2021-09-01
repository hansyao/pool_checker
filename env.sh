GITHUB='https/github.com'
OS='linux-amd64'
USER='Dreamacro'
APP='clash'
REPO=$USER/$APP
FILE=/tmp/bin/$APP.gz
PROXY_URL='https://lingering-math-d2ca.hansyow.workers.dev/'

get_latest_release() {
  curl --silent "${PROXY_URL}https/api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

get_clash() {
 
	CLASH=`pwd`/bin/clash
	
	if [[ -e ${CLASH} ]]; then
		if [[ $(${CLASH} -v | awk '{print $2}') == $(get_latest_release $REPO) ]]; then
		echo -e "${CLASH} 是最新版本"
		unset CLASH
		return
		fi
	fi

	echo -e "开始更新和安装clash"
	VERSION=$(get_latest_release ${REPO})
	curl -L -s ${PROXY_URL}${GITHUB}/${USER}/${APP}/releases/download/${VERSION}/${APP}-${OS}-${VERSION}.gz -o ${FILE}
	gzip -f -d ${FILE}
	chmod 755 -R /tmp/bin/${APP}
	unset CLASH
	unset VERSION
}

mkdir /tmp/bin && chmod 755 -R /tmp/bin/
mkdir /tmp/subscribe
mkdir -p /tmp/tmp 
mkdir /tmp/.config
ulimit -SHn 65536
	
get_clash

unset GITHUB
unset OS
unset USER
unset APP
unset REPO
unset FILE
unset PROXY_URL

exit 0