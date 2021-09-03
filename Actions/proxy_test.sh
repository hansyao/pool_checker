GITHUB='https://github.com'
OS='linux-amd64'
USER='Dreamacro'
APP='clash'
REPO=$USER/$APP
FILE=$APP.gz
CLASH_CONFIG=${GITHUB_WORKSPACE}/Actions/subscribe/clash.yaml
FINAL_CONFIG=/tmp/clash_final.yaml
CLASH_PID='/tmp/clash.pid'
CLASH_LOG='/tmp/clash.log'

get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}
VERSION=$(get_latest_release $REPO)

ip_foward() {
	sudo bash -c 'echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf' && sudo sysctl -p
	sudo bash -c 'echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf' && sudo sysctl -p
}

firwall_set() {
	local MYUID=$1
	sudo iptables -t nat -N CLASH

	# 忽略局域网地址
	sudo iptables -t nat -A CLASH -d 0.0.0.0/8 -j RETURN
	sudo iptables -t nat -A CLASH -d 10.0.0.0/8 -j RETURN
	sudo iptables -t nat -A CLASH -d 10.1.0.0/8 -j RETURN
	sudo iptables -t nat -A CLASH -d 127.0.0.0/8 -j RETURN
	sudo iptables -t nat -A CLASH -d 169.254.0.0/16 -j RETURN
	sudo iptables -t nat -A CLASH -d 172.16.0.0/12 -j RETURN
	sudo iptables -t nat -A CLASH -d 172.17.0.0/12 -j RETURN
	sudo iptables -t nat -A CLASH -d 192.168.0.0/16 -j RETURN
	sudo iptables -t nat -A CLASH -d 224.0.0.0/4 -j RETURN
	sudo iptables -t nat -A CLASH -d 240.0.0.0/4 -j RETURN

	# 把流量转发到 12345 端口
	sudo iptables -t nat -A CLASH -p tcp -j REDIRECT --to-ports 12345
	
	# 转发给CLASH
	sudo iptables -t nat -A OUTPUT -m owner --uid-owner ${MYUID} -j RETURN
	sudo iptables -t nat -A OUTPUT -p tcp -j CLASH
	# sudo iptables -t nat -A POSTROUTING -j MASQUERADE
}

get_config() {
	cat $1 | sed '/全球直连/d' > $2
	sed -i '1 i\tproxy-port: 7893' $2
	sed -i '1 i\redir-port: 12345' $2
	sed -i "s/log-level:.*/log-level: info/g" $2
	#sed -i "/mode:/c\mode: Global" $2
	
	curl -s -L https://raw.githubusercontent.com/wp-statistics/GeoLite2-Country/master/GeoLite2-Country.mmdb.gz -o mmdb.gz
	gzip -d mmdb.gz
	if [ ! -d /home/clash/.config/clash/ ]; then
		sudo runuser -l clash -c "mkdir -p /home/clash/.config/clash"
	fi
	sudo mv mmdb /home/clash/.config/clash/Country.mmdb
}

get_clash() {
 
	CLASH=`pwd`/Actions/clash
	if [ -e ${CLASH} ]; then
		echo ${CLASH} 已经存在
		unset CLASH
		return
	fi

        curl -L -s ${GITHUB}/${USER}/${APP}/releases/download/${VERSION}/${APP}-${OS}-${VERSION}.gz -o ${FILE}
        gzip -d ${FILE}
	chmod 755 clash
  	echo ${CLASH} 部署成功
  
	unset CLASH
}

clash_help() {
	echo "how to manage clash:"
	echo "clash start config pid"
	echo "clash restart config pid"
	echo "clash stop config pid"
}

clash() {
	local LOG=${CLASH_LOG}
	#CLASH=$(get_clash)
	local CLASH='/tmp/bin/clash'
	
	sudo setcap cap_net_bind_service,cap_net_admin+ep ${CLASH}
	
	if [[ $1 == 'start' && -n $2 && -n $3 ]]; then
		sudo runuser -l clash -c "nohup ${CLASH} -f $2 > ${LOG} 2>&1 &"
		echo "$!" > $3
	elif [[ $1 == 'stop' && -n $2 && -n $3 ]]; then
		sudo kill `cat $3`
	elif [[ $1 == 'restart' && -n $2 && -n $3 ]]; then
		sudo kill `cat $3`
		sudo runuser -l clash -c "nohup ${CLASH} -f $2 > ${LOG} 2>&1 &"
		echo "$!" > $3
	else
		clash_help
	fi
}

echo -e "本地流量转发"
ip_foward

echo -e "部署clash环境"
get_clash

echo -e "获取clash配置文件"
if [ ! -e ${CLASH_CONFIG} ]; then
  echo "配置文件不存在"
  exit 0
fi

echo -e "新建user clash"
sudo adduser clash >/dev/null
MYUID=$(id clash | cut -d "=" -f2 | cut -d "(" -f1)

get_config ${CLASH_CONFIG} ${FINAL_CONFIG}

echo -e "启动CLASH"
clash start ${FINAL_CONFIG} ${CLASH_PID}

echo -e "iptables防火墙配置"
firwall_set ${MYUID}

echo -e "测试网络连通性"
STATUS=$(curl --connect-timeout 4 -m 6 -s -i  https://connect.rom.miui.com/generate_204 | grep 204)
if [[ -z ${STATUS} ]]; then
	echo -e "网络连通测试失败"
fi
echo -e "状态码： ${STATUS}"

IP=$(curl --connect-timeout 4 -m 6 -s -L https://api.ipify.org)
IPINFO=$(curl --connect-timeout 4 -m 6 -s -X POST https://ip.taobao.com/outGetIpInfo\?ip\=${IP}\&accessKey\=alibaba-inc)
echo -e "公网IP地址： ${IP}"
echo -e "公网IP信息： ${IPINFO}"

echo "CLASH 日志："
cat ${CLASH_LOG}
