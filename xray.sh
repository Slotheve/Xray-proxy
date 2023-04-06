#!/bin/bash
# xray一键安装脚本
# Author: Slotheve<https://slotheve.com>


RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'


CONFIG_FILE="/usr/local/etc/xray/config.json"
OS=`hostnamectl | grep -i system | cut -d: -f2`

IP=`curl -sL -4 ip.sb`
TROJAN="false"

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        result=$(id | awk '{print $1}')
	if [[ $result != "用户id=0(root)" ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
	fi
    fi

    res=`which yum 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        res=`which apt 2>/dev/null`
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " 不受支持的Linux系统"
            exit 1
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
        CMD_UPGRADE="apt update; apt upgrade -y; apt autoremove -y"
    else
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
        CMD_UPGRADE="yum update -y"
    fi
    res=`which systemctl 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        colorEcho $RED " 系统版本过低，请升级到最新版本"
        exit 1
    fi
}

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

config() {
    local conf=`grep wsSettings $CONFIG_FILE`
    if [[ -z "$conf" ]]; then
        echo no
        return
    fi
    echo yes
}

status() {
    if [[ ! -f /usr/local/bin/xray ]]; then
        echo 0
        return
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo 1
        return
    fi
    port=`grep port $CONFIG_FILE| head -n 1| cut -d: -f2| tr -d \",' '`
    res=`ss -nutlp| grep ${port} | grep -i xray`
    if [[ -z "$res" ]]; then
        echo 2
        return
    fi
    
    if [[ `config` != "yes" ]]; then
        echo 3
    fi
}

statusText() {
    res=`status`
    case $res in
        2)
            echo -e ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        3)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}Xray正在运行${PLAIN}
            ;;
        *)
            echo -e ${RED}未安装${PLAIN}
            ;;
    esac
}

normalizeVersion() {
    if [ -n "$1" ]; then
        case "$1" in
            v*)
                echo "$1"
            ;;
            http*)
                echo "v1.4.2"
            ;;
            *)
                echo "v$1"
            ;;
        esac
    else
        echo ""
    fi
}

# 1: new Xray. 0: no. 1: yes. 2: not installed. 3: check failed.
getVersion() {
    VER=`/usr/local/bin/xray version|head -n1 | awk '{print $2}'`
    RETVAL=$?
    CUR_VER="$(normalizeVersion "$(echo "$VER" | head -n 1 | cut -d " " -f2)")"
    TAG_URL="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
    NEW_VER="$(normalizeVersion "$(curl -s "${TAG_URL}" --connect-timeout 10| grep -Eo '\"tag_name\"(.*?)\",' | cut -d\" -f4)")"

    if [[ $? -ne 0 ]] || [[ $NEW_VER == "" ]]; then
        colorEcho $RED " 检查Xray版本信息失败，请检查网络"
        return 3
    elif [[ $RETVAL -ne 0 ]];then
        return 2
    elif [[ $NEW_VER != $CUR_VER ]];then
        return 1
    fi
    return 0
}

archAffix(){
    case "$(uname -m)" in
        i686|i386)
            echo '32'
        ;;
        x86_64|amd64)
            echo '64'
        ;;
        armv5tel)
            echo 'arm32-v5'
        ;;
        armv6l)
            echo 'arm32-v6'
        ;;
        armv7|armv7l)
            echo 'arm32-v7a'
        ;;
        armv8|aarch64)
            echo 'arm64-v8a'
        ;;
        mips64le)
            echo 'mips64le'
        ;;
        mips64)
            echo 'mips64'
        ;;
        mipsle)
            echo 'mips32le'
        ;;
        mips)
            echo 'mips32'
        ;;
        ppc64le)
            echo 'ppc64le'
        ;;
        ppc64)
            echo 'ppc64'
        ;;
        ppc64le)
            echo 'ppc64le'
        ;;
        riscv64)
            echo 'riscv64'
        ;;
        s390x)
            echo 's390x'
        ;;
        *)
            colorEcho $RED " 不支持的CPU架构！"
            exit 1
        ;;
    esac

	return 0
}

getData() {
    read -p " 请输入xray监听端口[100-65535的一个数字]：" PORT
    [[ -z "${PORT}" ]] && PORT=`shuf -i200-65000 -n1`
    if [[ "${PORT:0:1}" = "0" ]]; then
	colorEcho ${RED}  " 端口不能以0开头"
	exit 1
    fi
    colorEcho ${BLUE}  " xray端口：$PORT"
    if [[ "$TROJAN" = "true" ]]; then
        echo ""
        read -p " 请设置trojan密码（不输则随机生成）:" PASSWORD
        [[ -z "$PASSWORD" ]] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
        colorEcho $BLUE " trojan密码：$PASSWORD"
    fi
}

setSelinux() {
    if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

installXray() {
    rm -rf /tmp/xray
    mkdir -p /tmp/xray
    DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/download/${NEW_VER}/Xray-linux-$(archAffix).zip"
    colorEcho $BLUE " 下载Xray: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /tmp/xray/xray.zip ${DOWNLOAD_LINK}
    if [ $? != 0 ];then
        colorEcho $RED " 下载Xray文件失败，请检查服务器网络设置"
        exit 1
    fi
    systemctl stop xray
    mkdir -p /usr/local/etc/xray /usr/local/share/xray && \
    unzip /tmp/xray/xray.zip -d /tmp/xray
    cp /tmp/xray/xray /usr/local/bin
    cp /tmp/xray/geo* /usr/local/share/xray
    chmod +x /usr/local/bin/xray || {
        colorEcho $RED " Xray安装失败"
        exit 1
    }

    cat >/etc/systemd/system/xray.service<<-EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls https://hijk.art
After=network.target nss-lookup.target

[Service]
User=root
#User=nobody
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xray.service
}

vmessConfig() {
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    local alterid=0
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 1,
          "alterId": $alterid
        }
      ]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

trojanConfig() {
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "trojan",
    "settings": {
      "clients": [
        {
          "password": "$PASSWD"
        }
      ]},
     "streamSettings": {
       "network": "tcp",
       "security": "none",
       "tcpSettings": {
         "header": {
           "type": "none"
          }
        }
      }
    }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

configXray() {
    mkdir -p /usr/local/xray
	if [[ "$TROJAN" = "true" ]]; then
	    trojanConfig
	else
        vmessConfig
	fi
}

install() {
    getData

    $PMT clean all
    [[ "$PMT" = "apt" ]] && $PMT update
    #echo $CMD_UPGRADE | bash
    $CMD_INSTALL wget vim unzip tar openssl
    $CMD_INSTALL net-tools
    if [[ "$PMT" = "apt" ]]; then
        $CMD_INSTALL libssl-dev
    fi
    res=`which unzip 2>/dev/null`
    if [[ $? -ne 0 ]]; then
        colorEcho $RED " unzip安装失败，请检查网络"
        exit 1
    fi

    colorEcho $BLUE " 安装Xray..."
    getVersion
    RETVAL="$?"
    if [[ $RETVAL == 0 ]]; then
        colorEcho $BLUE " Xray最新版 ${CUR_VER} 已经安装"
    elif [[ $RETVAL == 3 ]]; then
        exit 1
    else
        colorEcho $BLUE " 安装Xray ${NEW_VER} ，架构$(archAffix)"
        installXray
    fi

    configXray

    setSelinux

    start
    showInfo
}

update() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi

    getVersion
    RETVAL="$?"
    if [[ $RETVAL == 0 ]]; then
        colorEcho $BLUE " Xray最新版 ${CUR_VER} 已经安装"
    elif [[ $RETVAL == 3 ]]; then
        exit 1
    else
        colorEcho $BLUE " 安装Xray ${NEW_VER} ，架构$(archAffix)"
        installXray
        stop
        start

        colorEcho $GREEN " 最新版Xray安装成功！"
    fi
}

uninstall() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi

    echo ""
    read -p " 确定卸载Xray？[y/n]：" answer
    if [[ "${answer,,}" = "y" ]]; then
    stop
    systemctl disable xray
    rm -rf /etc/systemd/system/xray.service
    systemctl daemon-reload
    rm -rf /usr/local/bin/xray
    rm -rf /usr/local/etc/xray
    colorEcho $GREEN " Xray卸载成功"
    fi
}

start() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi
    systemctl restart xray
    sleep 2
    
    port=`grep port $CONFIG_FILE| head -n 1| cut -d: -f2| tr -d \",' '`
    res=`ss -nutlp| grep ${port} | grep -i xray`
    if [[ "$res" = "" ]]; then
        colorEcho $RED " Xray启动失败，请检查日志或查看端口是否被占用！"
    else
        colorEcho $BLUE " Xray启动成功"
    fi
}

stop() {
    systemctl stop xray
    colorEcho $BLUE " Xray停止成功"
}


restart() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi

    stop
    start
}


getConfigFileInfo() {
	trojan="false"
    protocol="VMess"

    port=`grep port $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    uid=`grep id $CONFIG_FILE | head -n1| cut -d: -f2 | tr -d \",' '`
    alterid=`grep alterId $CONFIG_FILE  | cut -d: -f2 | tr -d \",' '`
    network=`grep network $CONFIG_FILE  | tail -n1| cut -d: -f2 | tr -d \",' '`
	
	vmess=`grep vmess $CONFIG_FILE`
    if [[ "$vmess" = "" ]]; then
        trojan=`grep trojan $CONFIG_FILE`
        trojan="true"
        password=`grep password $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        protocol="trojan"
    fi
}

outputVmess() {
    raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"tcp\",
  \"type\":\"none\"
}"
    link=`echo -n ${raw} | base64 -w 0`
    link="vmess://${link}"

    echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
    echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
    echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}none${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
    echo  
    echo -e "   ${BLUE}vmess链接:${PLAIN} $RED$link$PLAIN"
}

outputTrojan() {
    echo -e "   ${BLUE}IP/域名(address): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}密码(password)：${PLAIN}${RED}${password}${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
}

showInfo() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi
    
    echo ""
    echo -n -e " ${BLUE}Xray运行状态：${PLAIN}"
    statusText
    echo -e " ${BLUE}Xray配置文件: ${PLAIN} ${RED}${CONFIG_FILE}${PLAIN}"
    colorEcho $BLUE " Xray配置信息："

    getConfigFileInfo

    echo -e "   ${BLUE}协议: ${PLAIN} ${RED}${protocol}${PLAIN}"
    if [[ "$trojan" = "true" ]]; then
        outputTrojan
    else
		outputVmess
    fi
}

showLog() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi

    journalctl -xen -u xray --no-pager
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                     ${RED}Xray一键安装脚本${PLAIN}                      #"
    echo -e "# ${GREEN}作者${PLAIN}: 怠惰(Slotheve)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://slotheve.com                                #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://slotheve.com                                #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/slotheve                               #"
    echo "#############################################################"
    echo -e "  ${GREEN}1.${PLAIN}  安装Vmess"
	echo -e "  ${GREEN}2.${PLAIN}  安装Trojan"
    echo " -------------"
    echo -e "  ${GREEN}3.${PLAIN}  更新Xray"
    echo -e "  ${GREEN}4.${RED}  卸载Xray${PLAIN}"
    echo " -------------"
    echo -e "  ${GREEN}5.${PLAIN}  启动Xray"
    echo -e "  ${GREEN}6.${PLAIN}  重启Xray"
    echo -e "  ${GREEN}7.${PLAIN}  停止Xray"
    echo " -------------"
    echo -e "  ${GREEN}8.${PLAIN}  查看Xray配置"
    echo -e "  ${GREEN}9.${PLAIN}  查看Xray日志"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN}  退出"
    echo -n " 当前状态："
    statusText
    echo 

    read -p " 请选择操作[0-8]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            TROJAN="true"
            install
			;;
        3)
            update
            ;;
        4)
            uninstall
            ;;
        5)
            start
            ;;
        6)
            restart
            ;;
        7)
            stop
            ;;
        8)
            showInfo
            ;;
        9)
            showLog
            ;;
        *)
            colorEcho $RED " 请选择正确的操作！"
            exit 1
            ;;
    esac
}

checkSystem

action=$1
[[ -z $1 ]] && action=menu
case "$action" in
    menu|update|uninstall|start|restart|stop|showInfo|showLog)
        ${action}
        ;;
    *)
        echo " 参数错误"
        echo " 用法: `basename $0` [menu|update|uninstall|start|restart|stop|showInfo|showLog]"
        ;;
esac