GITHUB='https://github.com'
OS='linux-amd64'
USER='Dreamacro'
APP='clash'
REPO=$USER/$APP
FILE=$APP.gz
CLASH_CONFIG=${GITHUB_WORKSPACE}/Actions/subscribe/clash_china.yaml
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

	# 把流量转发到 12345 端口，即redsocks
	sudo iptables -t nat -A CLASH -p tcp -j REDIRECT --to-ports 12345
	
	# 转发给代理端口
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
	LOG=${CLASH_LOG}
	#CLASH=$(get_clash)
	CLASH='/tmp/bin/clash'
	
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

	unset CONFIG
	unset PID
	unset LOG
	unset CLASH
}

proxy_chain() {
	git clone https://github.com/rofl0r/proxychains-ng.git
	cd proxychains-ng
	echo "开始编译proxychains"	
	./configure --prefix=/usr --sysconfdir=/etc >/dev/null
	make >/dev/null
	sudo make install >/dev/null
	echo "编译并安装成功"
	sudo rm -rf /etc/proxychains.conf
	echo "设置代理配置文件"
	cat > proxychains.conf <<EOL
strict_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000
[ProxyList]
socks5 	127.0.0.1 7891
EOL

	sudo cp -f proxychains.conf /etc/proxychains.conf && rm proxychains.conf
	cd ..
}


function init_redsocks() {
	echo "拉取代码"
	git clone --depth 1 https://github.com/darkk/redsocks.git
	cd redsocks
	echo "安装依赖"
	sudo apt install libevent-dev

	echo "开始编译"
	make
	echo "安装到/usr/local/bin/"
	sudo cp -f redsocks /usr/local/bin/redsocks
	
	echo "定义配置文件"
	cat >> /tmp/redsocks.conf << EOF
base {
    log_debug = off;
    log_info = on;
    log = "file:/tmp/redsocks.log";
    daemon = off;
    redirector = iptables;
}
redsocks {
    local_ip = 0.0.0.0;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 7891;
    type = socks5;
}

EOF

	echo "启动redsocks"
	pkill redsocks
	redsocks -c /tmp/redsocks.conf &

	cd ..
}

echo -e "本地流量转发"
ip_foward

echo -e "查看网络接口"
ifconfig

echo -e "部署clash环境"
get_clash

echo -e "获取clash配置文件"
if [ ! -e ${CLASH_CONFIG} ]; then
  echo "配置文件不存在"
  exit 0
fi

echo -e "新建user clash"
sudo adduser clash
# UID=$(id clash | cut -d "=" -f2 | cut -d "(" -f1)

get_config ${CLASH_CONFIG} ${FINAL_CONFIG}

echo -e "启动CLASH"
clash start ${FINAL_CONFIG} ${CLASH_PID}

# echo -e "部署redsocks"
# init_redsocks

echo -e "iptables防火墙配置"
firwall_set 1002

# echo -e "启动proxy_chain"
# proxy_chain

echo "延迟 3 等待透明代理启动"
sleep 3

echo -e "测试网络连通性 ($[i])"
STATUS=$(curl --connect-timeout 2 -m 4 -s -i  https://connect.rom.miui.com/generate_204 | grep 204)
if [[ -z ${STATUS} ]]; then
	echo -e "网络连通测试失败"
fi

IP=$(curl --connect-timeout 2 -m 4 -s -L https://api.ipify.org)
IPINFO=$(curl --connect-timeout 2 -m 4 -s -X POST https://ip.taobao.com/outGetIpInfo\?ip\=${IP}\&accessKey\=alibaba-inc)

echo -e "公网IP信息： ${IPINFO}"
#echo -e "网卡信息"
#ifconfig

echo -e "${STATUS}"
cat ${CLASH_LOG}

unset STATUS
unset IP
