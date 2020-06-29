#!/bin/bash


# CLI arguments
Info_font_prefix="\033[32m" && Error_font_prefix="\033[31m" && Info_background_prefix="\033[42;37m" && Error_background_prefix="\033[41;37m" && Font_suffix="\033[0m"
systemd=true

sshConfigFile="/etc/ssh/sshd_config"

## 下面的应该被改成yes
PermitRootLogin="PermitRootLogin"
PasswordAuthentication="PasswordAuthentication"
tcpKeepAlive="TCPKeepAlive"

## 下面的应该被改成no
changeResponseAuthentication="ChallengeResponseAuthentication"
PermitEmptyPasswords="PermitEmptyPasswords"
StrictModes="StrictModes"

check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
}

back_up_config(){
    cp $sshConfigFile $sshConfigFile.backup
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


main(){
    # 首先检查是否拥有root权限
    check_root
    # 备份一份sshd的配置文件
    back_up_config

    declare -a needToChangeYes
    declare -a needToChangeNo

    needToChangeYes[0]=$tcpKeepAlive 
    needToChangeYes[1]=$PermitRootLogin
    needToChangeYes[2]=$PasswordAuthentication 

    needToChangeNo[0]=$PermitEmptyPasswords
    needToChangeNo[1]=$changeResponseAuthentication

    modify_sshd_config_yes "${needToChangeYes[@]}"
    modify_sshd_config_no "${needToChangeNo[@]}"
    
    systemctl restart sshd
    if [ $? ];then echo "sshd文件已经修改成功，可以进行root登录，请修改root密码！！";else echo "sshd服务重启失败，请检查原因";fi
}

main
