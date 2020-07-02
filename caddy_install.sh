#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#==================:===============================
#       System Required: CentOS/Debian/Ubuntu
#       Description: Caddy Install       
#=================================================

#######color code########
RED="31m"      # Error message
GREEN="32m"    # Success message
YELLOW="33m"   # Warning message
BLUE="36m"     # Info message


systemd=true

SYSTEMCTL_CMD=$(command -v systemctl 2>/dev/null)
SERVICE_CMD=$(command -v service 2>/dev/null)

caddy_tmp="/tmp/install_caddy"
caddy_tmp_file="/tmp/install_caddy/caddy.tar.gz"

###############################
colorEcho(){
    echo -e "\033[${1}${@:2}\033[0m" 1>& 2
}


check_root(){
	[[ $EUID != 0 ]] && colorEcho ${RED} "当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用" && colorEcho ${YELLOW} "sudo - 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）" && exit 1
}

#######   获取系统版本及64位或32位信息
check_sys(){
	sys_bit=$(uname -m)
    case $sys_bit in
    i[36]86)
        v2ray_bit="32"
        release="386"
        ;;
    x86_64)
        v2ray_bit="64"
        release="amd64"
        ;;
    *armv6*)
        v2ray_bit="arm"
        release="arm6"
        ;;
    *armv7*)
        v2ray_bit="arm"
        release="arm7"
        ;;
    *aarch64* | *armv8*)
        v2ray_bit="arm64"
        release="arm64"
        ;;
    *)
        colorEcho ${YELLOW} " 
        哈哈……这个 辣鸡脚本 不支持你的系统。 (-_-) \n
        备注: 仅支持 Ubuntu 16+ / Debian 8+ / CentOS 7+ 系统
        " && exit 1
        ;;
    esac
    return 0
}

download_caddy_file() {
    if [[ -d $caddy_tmp ]]
    then
        rm -rf $caddy_tmp
    fi

    mkdir -p $caddy_tmp

	if [[ ! ${release} ]]; then
        colorEcho ${RED} "获取 Caddy 下载参数失败！"
        return 1
	fi

	caddy_download_link="https://caddyserver.com/download/linux/${release}?license=personal"

	mkdir -p $caddy_tmp
    wget --no-check-certificate -O $caddy_tmp_file $caddy_download_link

	if [[ ! -s $caddy_tmp_file ]]; then
		colorEcho ${RED} "下载 Caddy 文件失败！"
        return 1
    else
        tar -zxf $caddy_tmp_file -C $caddy_tmp
	fi

	# wget -qO- https://getcaddy.com | bash -s personal
}

install_caddy_service() {

    cp -f ${caddy_tmp}/caddy /usr/local/bin/

    if ! [ -n "$(command -v setcap)" ]; then
        apt-get update && apt-get install -y libcap2-bin
    fi
	setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/caddy

	if [[ $systemd ]]; then
        cp -f $caddy_tmp/init/linux-systemd/caddy.service /lib/systemd/system/caddy.service
        systemctl daemon-reload
		systemctl enable caddy
	else
		cp -f ${caddy_tmp}/init/linux-sysvinit/caddy /etc/init.d/caddy
		# sed -i "s/www-data/root/g" /etc/init.d/caddy
		chmod +x /etc/init.d/caddy
		update-rc.d -f caddy defaults
	fi

	if [ -z "$(grep www-data /etc/passwd)" ]; then
		useradd -M -s /usr/sbin/nologin www-data
	fi
}

caddy_config(){
    
	mkdir -p /etc/caddy
	chown -R root:root /etc/caddy
	mkdir -p /etc/ssl/caddy
	chown -R root:www-data /etc/ssl/caddy
	chmod 0770 /etc/ssl/caddy

	## create sites dir
	mkdir -p /etc/caddy/sites
    mkdir -p /var/www
    chown www-data:www-data /var/www
    chmod 555 /var/www

    ### 生成九位的随机数字
    local email=$(((RANDOM << 16)))
    
    cat >/etc/caddy/Caddyfile <<EOF
caddy_install.com {
tls ${email}@qq.com
gzip
timeouts none
proxy /https://bing.com {
    except /v2ice
}
proxy /v2ice 127.0.0.1:9000 {
    without /v2ice
    websocket
}
}
import sites/*
EOF
    if [[ -n $DomainAdress ]];then
        sed -i "s/caddy_install.com/$DomainAdress/g" /etc/caddy/Caddyfile
    fi
}

main(){
    check_sys

    DomainAdress=$1

    download_caddy_file
    install_caddy_service
    caddy_config
}
