#!/bin/bash


#########color code#############
RED="31m"      # Error message
GREEN="32m"    # Success message
YELLOW="33m"   # Warning message
BLUE="36m"     # Info message

SYSTEMCTL_CMD=$(command -v systemctl &>/dev/null)
SERVICE_CMD=$(command -v service &>/dev/null)

sshConfigFile="/etc/ssh/sshd_config"

### SSH的登录端口修改
SSHLoginPort="22333"

## 下面的应该被改成yes
PermitRootLogin="PermitRootLogin"
PasswordAuthentication="PasswordAuthentication"
tcpKeepAlive="TCPKeepAlive"

## 下面的应该被改成no
changeResponseAuthentication="ChallengeResponseAuthentication"
PermitEmptyPasswords="PermitEmptyPasswords"
StrictModes="StrictModes"

###############color echo func#################
colorEcho(){
    echo -e "\033[${1}${@:2}\033[0m" 1>& 2
}

check_root(){
	if [[ $EUID != 0 ]];then
    colorEcho ${RED} "当前非root账号(或没有root权限)，无法继续操作，请更换root账号!"
    colorEcho ${YELLOW} "使用sudo -命令获取临时root权限（执行后可能会提示输入root密码）"
    exit 1
    fi
}

back_up_config(){
    if [ -a $sshConfigFile.backup ] 
    then
        colorEcho ${BLUE} "sshd的备份文件已存在，无需备份。"
    else
        cp $sshConfigFile $sshConfigFile.backup
        colorEcho ${GREEN} "sshd.config文件备份成功！！"
    fi
}

modify_sshd_config_yes(){
    numOfElements=$#
   
    while [ $# -gt 0 ] 
    do
        if grep -x "$1 yes" $sshConfigFile
        then
            shift
        elif grep -x "#$1 yes" $sshConfigFile 
        then
            sed -i "s/#$1 yes/$1 yes/g" $sshConfigFile
            shift
        elif grep -x "$1 no" $sshConfigFile
        then
            sed -i "s/$1 no/$1 yes/g" $sshConfigFile
            shift
  
        else
            sed -i "$ a $1 yes" $sshConfigFile
            shift
        fi      
    done
}

modify_sshd_config_no(){
    numOfElements=$#
   
    while [ $# -gt 0 ]
    do
        if grep -x "$1 no" $sshConfigFile
        then
            shift
        elif grep -x "#$1 no" $sshConfigFile 
        then
            sed -i "s/#$1 no/$1 no/g" $sshConfigFile
            shift
        elif grep -x "$1 yes" $sshConfigFile
        then
            sed -i "s/$1 yes/$1 no/g" $sshConfigFile
            shift
        else
            sed -i "$ a $1 no" $sshConfigFile
            shift
        fi
    done
}

modify_sshd_config(){

    declare -a needToChangeYes
    declare -a needToChangeNo

    needToChangeYes[0]=$tcpKeepAlive 
    needToChangeYes[1]=$PermitRootLogin
    needToChangeYes[2]=$PasswordAuthentication 

    needToChangeNo[0]=$PermitEmptyPasswords
    needToChangeNo[1]=$changeResponseAuthentication
    needToChangeNo[2]=$StrictModes

    #  以数组的方式 将参数传入函数
    modify_sshd_config_yes "${needToChangeYes[@]}"
    modify_sshd_config_no "${needToChangeNo[@]}"

    colorEcho $GREEN "SSHD文件已经修改成功。。。"
}

restartSSHDService(){
    check_success(){
        if [[ $1 -eq 0 ]]
        then 
            colorEcho ${BLUE} "sshd.service服务已经重启完成！"
            colorEcho ${GREEN} "sshd文件已经修改成功，可以进行root登录，请修改root密码~~"
        else 
            colorEcho ${RED} "sshd服务重启失败，请检查原因!!!"
            colorEcho ${RED} "如果是CentOS，大概率是防火墙的问题。"
        fi
    }

    if [[ ${SYSTEMCTL_CMD} -eq 0 ]] 
    then
        systemctl restart sshd.service
        check_success $?
    elif [[ ${SERVICE_CMD} -eq 0 ]]
    then
        service restart sshd.service
        check_success $?
    else
        colorEcho ${RED} "缺少systemctl和service，本脚本不支持！！！"
        return 23
    fi
}

changeSSHLoginPort(){
    if grep -xw "Port ${SSHLoginPort}" $sshConfigFile &>/dev/null
    then
        colorEcho ${BLUE} "当前的ssh登录端口已经为${SSHLoginPort}，无需修改！"
    else
        sed -i "/^#Port 22/a Port ${SSHLoginPort}" $sshConfigFile
        if [[ $? -eq 0 ]] 
        then
            colorEcho ${GREEN} "ssh的登陆端口已被修改为${SSHLoginPort}，请修改防火墙以开放该端口！！"
        fi
    fi
}

extendIntervalTime(){
    echo "ClientAliveInterval 30" >> /etc/ssh/sshd_config
    echo "ClientAliveCountMax 60" >> /etc/ssh/sshd_config
}

modify_firewall(){
  echo ""
  colorEcho $GREEN "本脚本会默认关闭防火墙和SElinux！！"
  colorEcho $GREEN "本脚本会默认关闭防火墙和SElinux！！"
  colorEcho $GREEN "本脚本会默认关闭防火墙和SElinux！！"

  systemctl stop firewalld
  systemctl disable firewalld
  systemctl stop ufw
  systemctl disable ufw

  setenforce 0
  sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
#  iptables -F
}

main(){
    # 首先检查是否拥有root权限
    check_root

    # 备份一份sshd的配置文件
    back_up_config

    # 使用函数修改一些配置
    modify_sshd_config

    # 增加访问端口改变
    changeSSHLoginPort

    # 修改ssh的连接中断延时
    extendIntervalTime

    # 关闭防火墙服务，否则无法重启sshd服务
    modify_firewall

    # 重启SSHD服务
    restartSSHDService    
}

main
