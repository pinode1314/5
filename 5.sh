#!/bin/bash
export LANG=en_US.UTF-8
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'

red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}

[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
stty erase $'\b' 2>/dev/null || stty erase '^H' 2>/dev/null

if [[ -f /etc/redhat-release ]]; then
    release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
    release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
    release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
else 
    red "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi

export sbfiles="/etc/s-box/sb10.json /etc/s-box/sb11.json /etc/s-box/sb.json"
export sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
vsid=$(grep -i version_id /etc/os-release 2>/dev/null | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)

if [[ $(echo "$op" | grep -i -E "arch") ]]; then
    red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi

version=$(uname -r | cut -d "-" -f1)
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)

case $(uname -m) in
    armv7l) cpu=armv7;;
    aarch64) cpu=arm64;;
    x86_64) cpu=amd64;;
    *) red "目前脚本不支持$(uname -m)架构" && exit;;
esac

if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
    bbr=`sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}'`
elif [[ -n $(ping 10.0.0.2 -c 2 2>/dev/null | grep ttl) ]]; then
    bbr="Openvz版bbr-plus"
else
    bbr="Openvz/Lxc"
fi
hostname=$(hostname)

if [[ $vi = openvz ]]; then
    TUN=$(cat /dev/net/tun 2>&1)
    if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
        red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4
        cd /dev && mkdir net 2>/dev/null && mknod net/tun c 10 200 2>/dev/null && chmod 0666 net/tun
        TUN=$(cat /dev/net/tun 2>&1)
        if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
            green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit
        else
            echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir -p net && mknod net/tun c 10 200 2>/dev/null && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
            grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
            green "TUN守护功能已启动"
        fi
    fi
fi

v4v6(){
    v4=$(curl -s4m5 icanhazip.com -k)
    v6=$(curl -s6m5 icanhazip.com -k)
    v4dq=$(curl -s4m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null)
    v6dq=$(curl -s6m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null)
}

warpcheck(){
    wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

v6(){
    v4orv6(){
        if [ -z "$(curl -s4m5 icanhazip.com -k)" ]; then
            echo
            red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            yellow "检测到 纯IPV6 VPS，添加NAT64"
            echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf
            ipv=prefer_ipv6
        else
            ipv=prefer_ipv4
        fi
        if [ -n "$(curl -s6m5 icanhazip.com -k)" ]; then
            endip="2606:4700:d0::a29f:c001"
        else
            endip="162.159.192.1"
        fi
    }
    warpcheck
    if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
        v4orv6
    else
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
        v4orv6
        systemctl start wg-quick@wgcf >/dev/null 2>&1
        systemctl restart warp-go >/dev/null 2>&1
        systemctl enable warp-go >/dev/null 2>&1
        systemctl start warp-go >/dev/null 2>&1
    fi
}

close(){
    systemctl stop firewalld.service >/dev/null 2>&1
    systemctl disable firewalld.service >/dev/null 2>&1
    setenforce 0 >/dev/null 2>&1
    ufw disable >/dev/null 2>&1
    iptables -P INPUT ACCEPT >/dev/null 2>&1
    iptables -P FORWARD ACCEPT >/dev/null 2>&1
    iptables -P OUTPUT ACCEPT >/dev/null 2>&1
    iptables -t mangle -F >/dev/null 2>&1
    iptables -F >/dev/null 2>&1
    iptables -X >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    if [[ -n $(apachectl -v 2>/dev/null) ]]; then
        systemctl stop httpd.service >/dev/null 2>&1
        systemctl disable httpd.service >/dev/null 2>&1
        service apache2 stop >/dev/null 2>&1
        systemctl disable apache2 >/dev/null 2>&1
    fi
    sleep 1
    green "执行开放端口，关闭防火墙完毕"
}

openyn(){
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    readp "是否开放端口，关闭防火墙？\n1、是，执行 (回车默认)\n2、否，跳过！自行处理\n请选择【1-2】：" action
    if [[ -z $action ]] || [[ "$action" = "1" ]]; then
        close
    elif [[ "$action" = "2" ]]; then
        echo
    else
        red "输入错误,请重新选择" && openyn
    fi
}

inssb(){
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "使用哪个内核版本？"
    yellow "1：使用目前最新正式版内核 (回车默认)"
    yellow "2：使用之前1.10.7正式版内核 (支持geosite分流、IP优选级切换，无Anytls协议)"
    readp "请选择【1-2】：" menu
    if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
        sbcore=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
        [[ -z "$sbcore" ]] && sbcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases | grep -oP 'tag/v\K[0-9.]+' | head -n 1)
    else
        sbcore='1.10.7'
    fi
    sbname="sing-box-$sbcore-linux-$cpu"
    curl -L -o /etc/s-box/sing-box.tar.gz -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz
    if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
        tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
        mv /etc/s-box/$sbname/sing-box /etc/s-box/
        rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
        if [[ -f '/etc/s-box/sing-box' ]]; then
            chown root:root /etc/s-box/sing-box
            chmod +x /etc/s-box/sing-box
            blue "成功安装 Sing-box 内核版本：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
            sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
        else
            red "下载 Sing-box 内核不完整，安装失败，请再运行安装一次" && exit
        fi
    else
        red "下载 Sing-box 内核失败，请再运行安装一次，并检测VPS的网络是否可以访问Github" && exit
    fi
}

inscertificate(){
    ymzs(){
        ym_vl_re=apple.com
        echo
        blue "Vless-reality的SNI域名默认为 apple.com"
        tlsyn=true
        ym_vm_ws=$(cat /root/ygkkkca/ca.log 2>/dev/null)
        certificatec_vmess_ws='/root/ygkkkca/cert.crt'
        certificatep_vmess_ws='/root/ygkkkca/private.key'
        certificatec_hy2='/root/ygkkkca/cert.crt'
        certificatep_hy2='/root/ygkkkca/private.key'
        certificatec_tuic='/root/ygkkkca/cert.crt'
        certificatep_tuic='/root/ygkkkca/private.key'
        certificatec_an='/root/ygkkkca/cert.crt'
        certificatep_an='/root/ygkkkca/private.key'
    }

    zqzs(){
        ym_vl_re=apple.com
        echo
        blue "Vless-reality的SNI域名默认为 apple.com"
        tlsyn=false
        ym_vm_ws=www.bing.com
        certificatec_vmess_ws='/etc/s-box/cert.pem'
        certificatep_vmess_ws='/etc/s-box/private.key'
        certificatec_hy2='/etc/s-box/cert.pem'
        certificatep_hy2='/etc/s-box/private.key'
        certificatec_tuic='/etc/s-box/cert.pem'
        certificatep_tuic='/etc/s-box/private.key'
        certificatec_an='/etc/s-box/cert.pem'
        certificatep_an='/etc/s-box/private.key'
    }

    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "二、生成并设置相关证书"
    echo
    blue "自动生成bing自签证书中……" && sleep 2
    openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /etc/s-box/private.key -out /etc/s-box/cert.pem -subj "/CN=www.bing.com" 2>/dev/null
    echo
    if [[ -f /etc/s-box/cert.pem ]]; then
        blue "生成bing自签证书成功"
    else
        red "生成bing自签证书失败" && exit
    fi
    echo
    if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
        yellow "经检测，之前已使用Acme-yg脚本申请过Acme域名IP证书：$(cat /root/ygkkkca/ca.log) "
        green "是否使用 $(cat /root/ygkkkca/ca.log) 域名IP证书？"
        yellow "1：否！使用自签的证书 (回车默认)"
        yellow "2：是！使用 $(cat /root/ygkkkca/ca.log) 域名IP证书"
        readp "请选择【1-2】：" menu
        if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
            zqzs
        else
            ymzs
        fi
    else
        green "是否申请一个Acme域名IP证书？"
        yellow "1：否！继续使用自签的证书 (回车默认)"
        yellow "2：是！使用Acme-yg脚本申请Acme证书 (支持80端口域名IP证书模式与Dns API域名模式)"
        readp "请选择【1-2】：" menu
        if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
            zqzs
        else
            bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
            if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key && ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
                red "Acme证书申请失败，继续使用自签证书" 
                zqzs
            else
                ymzs
            fi
        fi
    fi
}

chooseport(){
    if [[ -z $port ]]; then
        port=$(shuf -i 10000-65535 -n 1)
        until [[ -z $(ss -tunlp 2>/dev/null | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp 2>/dev/null | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
        do
            yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
        done
    else
        until [[ -z $(ss -tunlp 2>/dev/null | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp 2>/dev/null | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
        do
            yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
        done
    fi
    blue "确认的端口：$port" && sleep 2
}

vlport(){
    readp "\n设置Vless-reality端口 (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_vl_re=$port
}
vmport(){
    readp "\n设置Vmess-ws端口 (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_vm_ws=$port
}
hy2port(){
    readp "\n设置Hysteria2主端口 (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_hy2=$port
}
tu5port(){
    readp "\n设置Tuic5主端口 (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_tu=$port
}
anport(){
    readp "\n设置Anytls主端口，最新内核时可用 (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_an=$port
}

insport(){
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "三、设置各个协议端口"
    yellow "1：自动生成每个协议的随机端口 (10000-65535范围内)，回车默认。请确保VPS后台已开放所有端口"
    yellow "2：自定义每个协议端口。请确保VPS后台已开放指定的端口"
    readp "请输入【1-2】：" port
    if [ -z "$port" ] || [ "$port" = "1" ] ; then
        ports=()
        for i in {1..5}; do
            while true; do
                port=$(shuf -i 10000-65535 -n 1)
                if ! [[ " ${ports[@]} " =~ " $port " ]] && \
                   [[ -z $(ss -tunlp 2>/dev/null | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && \
                   [[ -z $(ss -tunlp 2>/dev/null | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
                    ports+=($port)
                    break
                fi
            done
        done
        port_vm_ws=${ports[0]}
        port_vl_re=${ports[1]}
        port_hy2=${ports[2]}
        port_tu=${ports[3]}
        port_an=${ports[4]}
        if [[ $tlsyn == "true" ]]; then
            numbers=("2053" "2083" "2087" "2096" "8443")
        else
            numbers=("8080" "8880" "2052" "2082" "2086" "2095")
        fi
        port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
        until [[ -z $(ss -tunlp 2>/dev/null | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_vm_ws") ]]
        do
            port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
        done
        echo
        blue "根据Vmess-ws协议是否启用TLS，随机指定支持CDN优选IP的标准端口：$port_vm_ws"
    else
        vlport && vmport && hy2port && tu5port
        if [[ "$sbnh" != "1.10" ]]; then
            anport
        fi
    fi
    echo
    blue "各协议端口确认如下"
    blue "Vless-reality端口：$port_vl_re"
    blue "Vmess-ws端口：$port_vm_ws"
    blue "Hysteria-2端口：$port_hy2"
    blue "Tuic-v5端口：$port_tu"
    if [[ "$sbnh" != "1.10" ]]; then
        blue "Anytls端口：$port_an"
    fi
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "四、自动生成各个协议统一的uuid (密码)"
    uuid=$(/etc/s-box/sing-box generate uuid)
    blue "已确认uuid (密码)：${uuid}"
    blue "已确认Vmess的path路径：${uuid}-vm"
}

inssbjsonser(){
cat > /etc/s-box/sb10.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
    {
      "type": "vmess",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vmess-sb",
      "listen": "::",
      "listen_port": ${port_vm_ws},
      "users": [
        {
          "uuid": "${uuid}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${uuid}-vm",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"    
      },
      "tls": {
        "enabled": ${tlsyn},
        "server_name": "${ym_vm_ws}",
        "certificate_path": "$certificatec_vmess_ws",
        "key_path": "$certificatep_vmess_ws"
      }
    }, 
    {
      "type": "hysteria2",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "hy2-sb",
      "listen": "::",
      "listen_port": ${port_hy2},
      "users": [
        {
          "password": "${uuid}"
        }
      ],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$certificatec_hy2",
        "key_path": "$certificatep_hy2"
      }
    },
    {
      "type": "tuic",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "tuic5-sb",
      "listen": "::",
      "listen_port": ${port_tu},
      "users": [
        {
          "uuid": "${uuid}",
          "password": "${uuid}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$certificatec_tuic",
        "key_path": "$certificatep_tuic"
      }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct", "domain_strategy": "$ipv" },
    { "type": "direct", "tag": "vps-outbound-v4", "domain_strategy": "prefer_ipv4" },
    { "type": "direct", "tag": "vps-outbound-v6", "domain_strategy": "prefer_ipv6" },
    { "type": "socks", "tag": "socks-out", "server": "127.0.0.1", "server_port": 40000, "version": "5" },
    { "type": "direct", "tag": "socks-IPv4-out", "detour": "socks-out", "domain_strategy": "prefer_ipv4" },
    { "type": "direct", "tag": "socks-IPv6-out", "detour": "socks-out", "domain_strategy": "prefer_ipv6" },
    { "type": "direct", "tag": "warp-IPv4-out", "detour": "wireguard-out", "domain_strategy": "prefer_ipv4" },
    { "type": "direct", "tag": "warp-IPv6-out", "detour": "wireguard-out", "domain_strategy": "prefer_ipv6" },
    {
      "type": "wireguard",
      "tag": "wireguard-out",
      "server": "$endip",
      "server_port": 2408,
      "local_address": ["172.16.0.2/32", "${v6}/128"],
      "private_key": "$pvk",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": $res
    },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rules": [
      { "protocol": ["quic", "stun"], "outbound": "block" },
      { "outbound": "warp-IPv4-out", "domain_suffix": ["yg_kkk"], "geosite": ["yg_kkk"] },
      { "outbound": "warp-IPv6-out", "domain_suffix": ["yg_kkk"], "geosite": ["yg_kkk"] },
      { "outbound": "socks-IPv4-out", "domain_suffix": ["yg_kkk"], "geosite": ["yg_kkk"] },
      { "outbound": "socks-IPv6-out", "domain_suffix": ["yg_kkk"], "geosite": ["yg_kkk"] },
      { "outbound": "vps-outbound-v4", "domain_suffix": ["yg_kkk"], "geosite": ["yg_kkk"] },
      { "outbound": "vps-outbound-v6", "domain_suffix": ["yg_kkk"], "geosite": ["yg_kkk"] },
      { "outbound": "direct", "network": "udp,tcp" }
    ]
  }
}
EOF

cat > /etc/s-box/sb11.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-sb",
      "listen": "::",
      "listen_port": ${port_vm_ws},
      "users": [
        {
          "uuid": "${uuid}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${uuid}-vm",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"    
      },
      "tls": {
        "enabled": ${tlsyn},
        "server_name": "${ym_vm_ws}",
        "certificate_path": "$certificatec_vmess_ws",
        "key_path": "$certificatep_vmess_ws"
      }
    }, 
    {
      "type": "hysteria2",
      "tag": "hy2-sb",
      "listen": "::",
      "listen_port": ${port_hy2},
      "users": [
        {
          "password": "${uuid}"
        }
      ],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$certificatec_hy2",
        "key_path": "$certificatep_hy2"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic5-sb",
      "listen": "::",
      "listen_port": ${port_tu},
      "users": [
        {
          "uuid": "${uuid}",
          "password": "${uuid}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$certificatec_tuic",
        "key_path": "$certificatep_tuic"
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-sb",
      "listen": "::",
      "listen_port": ${port_an},
      "users": [
        {
          "password": "${uuid}"
        }
      ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "certificate_path": "$certificatec_an",
        "key_path": "$certificatep_an"
      }
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "address": ["172.16.0.2/32", "${v6}/128"],
      "private_key": "$pvk",
      "peers": [
        {
          "address": "$endip",
          "port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": ["0.0.0.0/0", "::/0"],
          "reserved": $res
        }
      ]
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "socks", "tag": "socks-out", "server": "127.0.0.1", "server_port": 40000, "version": "5" }
  ],
  "route": {
    "rules": [
      { "action": "sniff" },
      { "action": "resolve", "domain_suffix": ["yg_kkk"], "strategy": "prefer_ipv4" },
      { "action": "resolve", "domain_suffix": ["yg_kkk"], "strategy": "prefer_ipv6" },
      { "domain_suffix": ["yg_kkk"], "outbound": "socks-out" },
      { "domain_suffix": ["yg_kkk"], "outbound": "warp-out" },
      { "outbound": "direct", "network": "udp,tcp" }
    ]
  }
}
EOF
    [[ "$sbnh" == "1.10" ]] && num=10 || num=11
    cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
}

sbservice(){
    if command -v apk >/dev/null 2>&1; then
        echo '#!/sbin/openrc-run
description="sing-box service"
command="/etc/s-box/sing-box"
command_args="run -c /etc/s-box/sb.json"
command_background=true
pidfile="/var/run/sing-box.pid"' > /etc/init.d/sing-box
        chmod +x /etc/init.d/sing-box
        rc-update add sing-box default
        rc-service sing-box start
    else
        cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable sing-box >/dev/null 2>&1
        systemctl start sing-box
        systemctl restart sing-box
    fi
}

restartsb(){
    if command -v apk >/dev/null 2>&1; then
        rc-service sing-box restart
    else
        systemctl restart sing-box
    fi
}

sbactive(){
    if command -v apk >/dev/null 2>&1; then
        status_cmd="rc-service sing-box status"
        status_pattern="started"
    else
        status_cmd="systemctl is-active sing-box"
        status_pattern="active"
    fi
    if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") ]]; then
        green "Sing-box 运行正常"
    else
        red "Sing-box 运行异常，请检查配置文件 /etc/s-box/sb.json"
    fi
}

ipuuid(){
    if command -v apk >/dev/null 2>&1; then
        status_cmd="rc-service sing-box status"
        status_pattern="started"
    else
        status_cmd="systemctl is-active sing-box"
        status_pattern="active"
    fi
    if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
        v4v6
        if [[ -n $v4 && -n $v6 ]]; then
            green "调整IPv4/IPV6配置输出"
            yellow "1：刷新本地IP，使用IPV4配置输出 (回车默认) "
            yellow "2：刷新本地IP，使用IPV6配置输出"
            readp "请选择【1-2】：" menu
            if [ -z "$menu" ] || [ "$menu" = "1" ]; then
                server_ip="$v4"
                echo "$server_ip" > /etc/s-box/server_ip.log
                server_ipcl="$v4"
                echo "$server_ipcl" > /etc/s-box/server_ipcl.log
            else
                server_ip="[$v6]"
                echo "$server_ip" > /etc/s-box/server_ip.log
                server_ipcl="$v6"
                echo "$server_ipcl" > /etc/s-box/server_ipcl.log
            fi
        else
            yellow "VPS并不是双栈VPS，不支持IP配置输出的切换"
            serip=$(curl -s4m5 icanhazip.com -k || curl -s6m5 icanhazip.com -k)
            if [[ "$serip" =~ : ]]; then
                server_ip="[$serip]"
                echo "$server_ip" > /etc/s-box/server_ip.log
                server_ipcl="$serip"
                echo "$server_ipcl" > /etc/s-box/server_ipcl.log
            else
                server_ip="$serip"
                echo "$server_ip" > /etc/s-box/server_ip.log
                server_ipcl="$serip"
                echo "$server_ipcl" > /etc/s-box/server_ipcl.log
            fi
        fi
    else
        red "Sing-box服务未运行" && exit
    fi
}

wgcfgo(){
    warpcheck
    if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
        ipuuid
    else
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
        ipuuid
        systemctl start wg-quick@wgcf >/dev/null 2>&1
        systemctl restart warp-go >/dev/null 2>&1
        systemctl enable warp-go >/dev/null 2>&1
        systemctl start warp-go >/dev/null 2>&1
    fi
}

warpwg(){
    pvk=$(openssl rand -base64 32 2>/dev/null)
    res="[0,0,0]"
}

lnsb(){
    cat > /usr/bin/sb <<EOF
#!/bin/bash
bash <(cat /etc/s-box/sb.sh)
EOF
    chmod +x /usr/bin/sb
    cp -f $0 /etc/s-box/sb.sh 2>/dev/null
}

cronsb(){
    crontab -l 2>/dev/null > /tmp/crontab.tmp
    sed -i '/sb.sh/d' /tmp/crontab.tmp
    echo "0 4 * * * bash /etc/s-box/sb.sh check" >> /tmp/crontab.tmp
    crontab /tmp/crontab.tmp >/dev/null 2>&1
    rm /tmp/crontab.tmp
}

sbshare(){
    result_vl_vm_hy_tu
    resvless
    resvmess
    reshy2
    restu5
    [[ "$sbnh" != "1.10" ]] && resan
    sb_client
}

changeym(){
    [ -f /root/ygkkkca/ca.log ] && ymzs="$yellow切换为域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)$plain" || ymzs="$yellow未申请域名证书，无法切换$plain"
    vl_na="正在使用的域名：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')。$yellow更换符合reality要求的域名，不支持证书域名$plain"
    tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
    [[ "$tls" = "false" ]] && vm_na="当前已关闭TLS。$ymzs${yellow}将开启TLS，Argo隧道将不支持开启${plain}" \vert{}\vert{} vm_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为关闭TLS，Argo隧道将可用$plain"
    
    hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
    [[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_na="正在使用自签bing证书。$ymzs" \vert{}\vert{} hy2_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
    
    tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
    [[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_na="正在使用自签bing证书。$ymzs" \vert{}\vert{} tu5_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
    
    if [[ "$sbnh" != "1.10" ]]; then
        an_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.key_path')
        [[ "$an_sniname" = '/etc/s-box/private.key' ]] && an_na="正在使用自签bing证书。$ymzs" \vert{}\vert{} an_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
    fi

    echo
    green "请选择要切换证书模式的协议"
    green "1：vless-reality协议，$vl_na"
    if [[ -f /root/ygkkkca/ca.log ]]; then
        green "2：vmess-ws协议，$vm_na"
        green "3：Hysteria2协议，$hy2_na"
        green "4：Tuic5协议，$tu5_na"
        if [[ "$sbnh" != "1.10" ]]; then
            green "5：Anytls协议，$an_na"
        fi
    else
        red "仅支持选项1 (vless-reality)。因未申请域名证书，vmess-ws、Hysteria-2、Tuic-v5、Anytls的证书切换选项暂不予显示"
    fi
    green "0：返回上层"
    readp "请选择：" menu
    if [ "$menu" = "1" ]; then
        readp "请输入vless-reality域名 (回车使用apple.com)：" menu
        ym_vl_re=${menu:-apple.com}
        a=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')
        b=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.reality.handshake.server')
        echo $sbfiles | xargs -n1 sed -i "s/$a/$ym_vl_re/g" 2>/dev/null
        restartsb && sbshare > /dev/null 2>&1
        blue "Vless-reality域名证书更换完毕"
    elif [ "$menu" = "2" ] && [ -f /root/ygkkkca/ca.log ]; then
        a=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
        [ "$a" = "true" ] && a_a=false || a_a=true
        b_b=$(cat /root/ygkkkca/ca.log)
        c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.certificate_path')
        d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.key_path')
        if [ "$d" = '/etc/s-box/private.key' ]; then
            c_c='/root/ygkkkca/cert.crt'
            d_d='/root/ygkkkca/private.key'
        else
            c_c='/etc/s-box/cert.pem'
            d_d='/etc/s-box/private.key'
        fi
        echo $sbfiles | xargs -n1 sed -i "s#$c#$c_c#g" 2>/dev/null
        echo $sbfiles | xargs -n1 sed -i "s#$d#$d_d#g" 2>/dev/null
        restartsb && sbshare > /dev/null 2>&1
        blue "vmess-ws协议域名证书更换完毕"
    elif [ "$menu" = "3" ] && [ -f /root/ygkkkca/ca.log ]; then
        c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.certificate_path')
        d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
        if [ "$d" = '/etc/s-box/private.key' ]; then
            c_c='/root/ygkkkca/cert.crt'
            d_d='/root/ygkkkca/private.key'
        else
            c_c='/etc/s-box/cert.pem'
            d_d='/etc/s-box/private.key'
        fi
        echo $sbfiles | xargs -n1 sed -i "s#$c#$c_c#g" 2>/dev/null
        echo $sbfiles | xargs -n1 sed -i "s#$d#$d_d#g" 2>/dev/null
        restartsb && sbshare > /dev/null 2>&1
        blue "Hysteria2协议域名证书更换完毕"
    elif [ "$menu" = "4" ] && [ -f /root/ygkkkca/ca.log ]; then
        c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.certificate_path')
        d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
        if [ "$d" = '/etc/s-box/private.key' ]; then
            c_c='/root/ygkkkca/cert.crt'
            d_d='/root/ygkkkca/private.key'
        else
            c_c='/etc/s-box/cert.pem'
            d_d='/etc/s-box/private.key'
        fi
        echo $sbfiles | xargs -n1 sed -i "s#$c#$c_c#g" 2>/dev/null
        echo $sbfiles | xargs -n1 sed -i "s#$d#$d_d#g" 2>/dev/null
        restartsb && sbshare > /dev/null 2>&1
        blue "Tuic5协议域名证书更换完毕"
    elif [ "$menu" = "5" ] && [ -f /root/ygkkkca/ca.log ] && [ "$sbnh" != "1.10" ]; then
        c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.certificate_path')
        d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.key_path')
        if [ "$d" = '/etc/s-box/private.key' ]; then
            c_c='/root/ygkkkca/cert.crt'
            d_d='/root/ygkkkca/private.key'
        else
            c_c='/etc/s-box/cert.pem'
            d_d='/etc/s-box/private.key'
        fi
        echo $sbfiles | xargs -n1 sed -i "s#$c#$c_c#g" 2>/dev/null
        echo $sbfiles | xargs -n1 sed -i "s#$d#$d_d#g" 2>/dev/null
        restartsb && sbshare > /dev/null 2>&1
        blue "Anytls协议域名证书更换完毕"
    else
        main_menu
    fi
}

instsllsingbox(){
    if [[ -f '/etc/systemd/system/sing-box.service' ]] || [[ -f '/etc/init.d/sing-box' ]]; then
        red "已安装Sing-box服务，无法再次安装" && exit
    fi
    mkdir -p /etc/s-box
    v6
    openyn
    inssb
    inscertificate
    insport
    sleep 2
    echo
    blue "Vless-reality相关key与id将自动生成……"
    key_pair=$(/etc/s-box/sing-box generate reality-keypair)
    private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
    echo "$public_key" > /etc/s-box/public.key
    short_id=$(/etc/s-box/sing-box generate rand --hex 4)
    wget -q -O /root/geoip.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
    wget -q -O /root/geosite.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "五、自动生成warp-wireguard出站账户" && sleep 2
    warpwg
    inssbjsonser
    sbservice
    sbactive
    curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    lnsb && blue "Sing-box-yg脚本安装成功，脚本快捷方式：sb" && cronsb
    echo
    wgcfgo
    sbshare
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    blue "可选择9，刷新并显示所有协议配置及分享链接"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
}

main_menu(){
    clear
    green "=========================================================="
    blue "            Sing-Box 五合一 一键管理脚本                  "
    green "=========================================================="
    echo
    yellow "1. 安装 Sing-box"
    yellow "2. 卸载 Sing-box"
    yellow "3. 变更/切换证书模式"
    yellow "4. 设置 Argo 隧道"
    yellow "9. 显示所有节点分享链接与客户端配置"
    yellow "0. 退出脚本"
    echo
    readp "请输入选择【0-9】: " choice
    case "$choice" in
        1) instsllsingbox ;;
        2) 
            systemctl stop sing-box >/dev/null 2>&1
            systemctl disable sing-box >/dev/null 2>&1
            rm -rf /etc/s-box /usr/bin/sb /etc/systemd/system/sing-box.service
            green "Sing-box 已彻底卸载！"
            ;;
        3) changeym ;;
        4) cfargo_ym ;;
        9) sbshare ;;
        0) exit 0 ;;
        *) red "输入无效，请重新选择！" && sleep 1 && main_menu ;;
    esac
}

# 脚本入口执行
if [ "$1" = "check" ]; then
    sbactive
else
    main_menu
fi
