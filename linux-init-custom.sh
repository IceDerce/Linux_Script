#!/bin/bash

# 本脚本意在一键初始化Linux服务器的环境

### 需要修改以下的内容  ###
KUBERNETES_VERSION=1.18.9
DOCKER_VERSION=19.03.8
### 需要修改以上的内容  ###

CMD_INSTALL=""
CMD_UPDATE=""
CMD_REMOVE=""
SOFTWARE_UPDATED=0
LinuxReleaseVersion=""

RED="31m"    ## 姨妈红
GREEN="32m"  ## 水鸭青
YELLOW="33m" ## 鸭屎黄
PURPLE="35m" ## 基佬紫
BLUE="36m"   ## 天依蓝

######## 颜色函数方法很精妙 ############
colorEcho() {
  echo -e "\033[${1}${@:2}\033[0m" 1>&2
}

check_root() {
  if [[ $EUID != 0 ]]; then
    colorEcho ${RED} "当前非root账号(或没有root权限)，无法继续操作，请更换root账号!"
    colorEcho ${YELLOW} "使用sudo -命令获取临时root权限（执行后可能会提示输入root密码）"
    exit 1
  fi
}

#######   获取系统版本及64位或32位信息
check_sys() {
  # sys_bit=$(uname -m)
  # case $sys_bit in
  # i[36]86)
  #     os_bit="32"
  #     release="386"
  #     ;;
  # x86_64)
  #     os_bit="64"
  #     release="amd64"
  #     ;;
  # *armv6*)
  #     os_bit="arm"
  #     release="arm6"
  #     ;;
  # *armv7*)
  #     os_bit="arm"
  #     release="arm7"
  #     ;;
  # *aarch64* | *armv8*)
  #     os_bit="arm64"
  #     release="arm64"
  #     ;;
  # *)
  #     colorEcho ${RED} "
  #     哈哈……这个 辣鸡脚本 不支持你的系统。 (-_-) \n
  #     备注: 仅支持 Ubuntu 16+ / Debian 8+ / CentOS 7+ 系统
  #     " && exit 1
  #     ;;
  # esac
  ## 判定Linux的发行版本
  if [ -f /etc/redhat-release ]; then
    LinuxReleaseVersion="centos"
  elif cat /etc/issue | grep -Eqi "debian"; then
    LinuxReleaseVersion="debian"
  elif cat /etc/issue | grep -Eqi "ubuntu"; then
    LinuxReleaseVersion="ubuntu"
  elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    LinuxReleaseVersion="centos"
  elif cat /proc/version | grep -Eqi "debian"; then
    LinuxReleaseVersion="debian"
  elif cat /proc/version | grep -Eqi "ubuntu"; then
    LinuxReleaseVersion="ubuntu"
  elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    LinuxReleaseVersion="centos"
  else
    LinuxReleaseVersion=""
  fi

  # 判断系统的包管理工具  apt, yum, or zypper
  getPackageManageTool() {
    if [[ -n $(command -v apt-get) ]]; then
      CMD_INSTALL="apt-get -y -qq install"
      CMD_UPDATE="apt-get -qq update"
      CMD_REMOVE="apt-get -y remove"
    elif [[ -n $(command -v yum) ]]; then
      CMD_INSTALL="yum -y -q install"
      CMD_UPDATE="yum -q makecache"
      CMD_REMOVE="yum -y remove"
    elif [[ -n $(command -v zypper) ]]; then
      CMD_INSTALL="zypper -y install"
      CMD_UPDATE="zypper ref"
      CMD_REMOVE="zypper -y remove"
    else
      return 1
    fi
    return 0
  }

  # 检查系统包管理方式，更新包
  getPackageManageTool
  if [[ $? -eq 1 ]]; then
    colorEcho ${RED} "系统的包管理不是 APT or YUM, 请手动安装所需要的软件."
    return 1
  fi

  ### 更新程序引索
  if [[ $SOFTWARE_UPDATED -eq 0 ]]; then
    colorEcho ${BLUE} "正在更新软件包管理..."
    $CMD_UPDATE
    SOFTWARE_UPDATED=1
  fi
  return 0
}

##  安装所需要的程序，及依赖程序
installDemandSoftwares() {
  for software in $@; do
    ## 安装该软件
    if [[ -n $(command -v ${software}) ]]; then
      colorEcho ${GREEN} "${software}已经安装了...跳过..."
      echo ""
    else
      colorEcho ${BLUE} "正在安装 ${software}.."
      $CMD_INSTALL ${software}

      ## 判断该软件是否安装成功
      if [[ $? -ne 0 ]]; then
        colorEcho ${RED} "安装 ${software} 失败. 请手动安装该程序."
        return 1
      else
        colorEcho ${GREEN} "已经成功安装 ${software}."
      fi
    fi
  done
  return 0
}

shutdownFirewall() {
  ## 关闭防火墙、SElinux、Swap
  systemctl stop firewalld
  systemctl disable firewalld

  setenforce 0
  sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config

}

disableSwap() {
  swapoff -a
  cp -f /etc/fstab /etc/fstab_bak
  cat /etc/fstab_bak | grep -v swap >/etc/fstab
}

## 安装docker时，修改系统的配置文件
modifySystemConfig_Docker() {

  ## 配置内核参数
  cat >>/etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.all.forwarding = 1
EOF

  ## 执行命令以应用
  sysctl -p /etc/sysctl.d/k8s.conf

  systemctl daemon-reload
  systemctl restart docker
}

## 安装kubernetes时，修改系统的配置文件
modifySystemConfig_Kubernetes() {
  if [ -f /etc/sysctl.d/k8s.conf ]; then
    colorEcho ${PURPLE} "系统配置的修改项已经存在了，现在跳过。。"
  else
    ## 配置内核参数
    cat >>/etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.all.forwarding = 1
EOF
    ## 执行命令以应用
    sysctl -p /etc/sysctl.d/k8s.conf
  fi

  ## 修改docker Cgroup Driver为systemd
  sed -i "s#^ExecStart=/usr/bin/dockerd.*#ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --exec-opt native.cgroupdriver=systemd#g" /usr/lib/systemd/system/docker.service

  systemctl daemon-reload
  systemctl restart docker
  systemctl enable kubelet && systemctl start kubelet
}

installDocker() {
  ### 国内的环境 ###
  ### 依赖colorEcho

  ## 清理docker环境
  $CMD_REMOVE docker docker-client docker-client-latest docker-ce-cli \
      docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux \
      docker-engine kubelet kubeadm kubectl

  if [ $LinuxReleaseVersion = "centos" ]; then
    ## 安装docker的依赖
    installDemandSoftwares yum-utils device-mapper-persistent-data lvm2 || return $?

    ## 添加docker的yum源
    yum-config-manager --add-repo https://mirrors.ustc.edu.cn/docker-ce/linux/centos/docker-ce.repo
    if [[ -f /etc/yum.repos.d/docker-ce.repo ]]; then
      sed -i 's/download.docker.com/mirrors.ustc.edu.cn\/docker-ce/g' /etc/yum.repos.d/docker-ce.repo
      colorEcho $GREEN "已成功添加中科大的docker-ce的yum源！"
      echo ""
      colorEcho $GREEN "可以安装的docker-ce的19.03版本为："
      yum list docker-ce --showduplicates | grep -w 19.03 | sort -r | awk '{print$2}' | cut -d ":" -f2
      echo ""
    else
      colorEcho ${RED} "docker的yum源添加失败，请手动添加"
    fi
  else
    $CMD_INSTALL apt-transport-https ca-certificates curl gnupg-agent software-properties-common

    curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    add-apt-repository \
    "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu \
      $(lsb_release -cs) \
      stable"

    colorEcho ${GREEN} "开始安装docker-ce，版本为${DOCKER_VERSION}"
    apt-get update
  fi

  installDemandSoftwares docker-ce-${DOCKER_VERSION} docker-ce-cli-${DOCKER_VERSION} containerd.io || return $?

  systemctl enable docker.service
  systemctl start docker.service
}

installDockerCompose() {
  colorEcho ${PURPLE} "正在下载 +++++++++++++ docker-compose文件 ++++++++++++++"
  #    curl -L "https://github.com.cnpmjs.org/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" \
  #        -o /usr/local/bin/docker-compose
  curl -L "https://objectstorage.ap-seoul-1.oraclecloud.com/n/cnk8d6fazu16/b/seoul/o/docker-compose-Linux-x86_64" \
  -o /usr/local/bin/docker-compose
  if [[ -e /usr/local/bin/docker-compose ]]; then
    colorEcho ${BLUE} "docker-compose文件下载成功！！"
    echo ""
    chmod +x /usr/local/bin/docker-compose
    docker-compose --version &>/dev/null
    if [[ $? -eq 0 ]]; then
      colorEcho ${GREEN} "docker-compose安装成功！！版本为$(docker-compose --version | cut -d" " -f3)尽情享用"
    else
      ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
  else
    colorEcho ${RED} "docker-compose文件下载失败！！ 无法访问github的资源。。"
    colorEcho ${RED} "请手动下载docker-compose的安装文件！"
  fi
}

installKubernetes() {
  ### 国内的环境 ###
  ## 添加kubernetes的yum源
  cat <<EOF >/etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
      http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

  installDemandSoftwares kubelet-${KUBERNETES_VERSION} kubeadm-${KUBERNETES_VERSION} kubectl-${KUBERNETES_VERSION} || return $?
}

installZSH() {
  installDemandSoftwares zsh git || return $?
  # 脚本会自动更换默认的shell
  echo y | sh -c "$(curl -fsSL https://cdn.jsdelivr.net/gh/robbyrussell/oh-my-zsh@master/tools/install.sh)"
  echo ""
  modifyZSH
  if [[ $? -eq 0 ]]; then
    colorEcho ${BLUE} "开始修改默认shell为zsh……"
    for i in {6..1..-1}
    do
      colorEcho ${BLUE} "倒计时开始 ->> $i 秒 <<-，准备切换shell，上文的日志输出将会消失！！"
      sleep 1
    done
    chsh -s /bin/zsh
    zsh
  else
    colorEcho ${RED} "zsh 安装失败，大概率是已经安装！！小概率是无法连接GitHub服务器~~"
  fi 
}

modifyZSH() {
  colorEcho ${PURPLE} "---------------------------------------------------------------------------"
  colorEcho ${BLUE} "开始修改zsh的相关配置信息，使其更加好用…………"
  echo ""
  cat >~/oh-my-zsh-plugins-list.txt <<EOF
https://cdn.jsdelivr.net/gh/ohmyzsh/ohmyzsh/plugins/command-not-found/command-not-found.plugin.zsh
https://cdn.jsdelivr.net/gh/ohmyzsh/ohmyzsh/plugins/autojump/autojump.plugin.zsh
https://cdn.jsdelivr.net/gh/ohmyzsh/ohmyzsh/plugins/themes/themes.plugin.zsh
EOF
  colorEcho ${BLUE} "正在下载zsh的一些好用的插件："
  git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/plugins/zsh-autosuggestions
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/plugins/zsh-syntax-highlighting

  wget -c -i ~/oh-my-zsh-plugins-list.txt -P ~/.oh-my-zsh/plugins/
  colorEcho ${GREEN} "插件已经下载完毕，现在开始修改zsh的配置文件…………"
  echo ""

  sed -i "s/robbyrussell/agnoster/g" ~/.zshrc
  sed -i 's/^# DISABLE_AUTO_UPDATE="true"/DISABLE_AUTO_UPDATE="true"/g' ~/.zshrc
  sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting command-not-found z themes)/g' ~/.zshrc
  colorEcho ${GREEN} "请检查当前zsh的插件开启情况："
  colorEcho ${GREEN} "------------------------------------------"
  cat ~/.zshrc | grep "plugins=" | grep -v "\#"
  cat ~/.zshrc | grep "plugins=" | grep -v "\#"
  cat ~/.zshrc | grep "plugins=" | grep -v "\#"
  colorEcho ${GREEN} "------------------------------------------"
  
  echo ""
  echo "----------------------------------------------------"
  echo "这里的错误输出无需在意"
  source /root/.zshrc
  echo "这里的错误输出无需在意"
  echo "----------------------------------------------------"

  colorEcho ${GREEN} "zsh 安装成功，已更换主题，禁止更新，尽情享用~~~"
  colorEcho ${GREEN} "-----------------------------------------------------------------------------"
  colorEcho ${PURPLE} "宇宙第一shell的zsh已经安装成功了！！！"
  colorEcho ${GREEN} "宇宙第一shell的zsh已经安装成功了！！！"
  colorEcho ${BLUE} "宇宙第一shell的zsh已经安装成功了！！！"
  colorEcho ${GREEN} "-----------------------------------------------------------------------------"
}

# 更换CentOS7的默认源
changeCentOS7DefaultRepo() {
  mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
  curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
  curl -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
  # curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.cloud.tencent.com/repo/centos7_base.repo
  yum clean all && yum makecache && yum update
}

# 修改docker的国内加速镜像
changeDockerRegisterMirror() {
  if [[ -e /etc/docker/daemon.json ]]; then
    colorEcho ${BLUE} "已经存在docker的daemeon文件。。"
    mv /etc/docker/daemon.json /etc/docker/daemon.backup.json
    colorEcho ${GREEN} "已经将daemeon文件备份"
  fi
  cat >>/etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 655360,
      "Soft": 655360
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 655360,
      "Soft": 655360
    }
  },
  "live-restore": true,
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "registry-mirrors": [
        "https://jxlws3de.mirror.aliyuncs.com",
        "https://docker.mirrors.ustc.edu.cn",
        "http://hub-mirror.c.163.com",
        "https://registry.docker-cn.com"
  ]
}
EOF
  systemctl restart docker.service
  docker info
  colorEcho ${GREEN} "请查看上文是否存在添加的国内的镜像！！！"
}

# 使用chrony进行NTP时间同步
changeTimeSyncToNTP() {
  installDemandSoftwares chrony || return $?
  # 这里使用的是 默认的NTP源，又不是不能用，为啥要换啊。
  systemctl enable chronyd && systemctl start chronyd
  if [[ $? -eq 0 ]]; then
    colorEcho ${GREEN} "NTP时间同步安装完成，时间为$(date -R)"
  fi
}

changeTimeZoneAndNTP() {
  if [[ -n $(command -v timedatectl) ]]; then
    timedatectl set-timezone Asia/Shanghai && timedatectl set-ntp true
    colorEcho ${GREEN} "同步时间完成。现在时间为 $(date -R)"
  fi
}

## 为了本脚本能够满足Ubuntu系统，做出设当的更改
commonToolInstall() {
  colorEcho ${GREEN} "当前系统的发行版为-- ${LinuxReleaseVersion}！！"
  colorEcho ${GREEN} "当前系统的发行版为-- ${LinuxReleaseVersion}！！"
  colorEcho ${GREEN} "当前系统的发行版为-- ${LinuxReleaseVersion}！！"

  if [[ ${LinuxReleaseVersion} == "centos" ]]; then
    centosCommonTool=(deltarpm net-tools iputils bind-utils lsof curl wget vim mtr)
    installDemandSoftwares ${centosCommonTool[@]} || return $?
  elif [[ ${LinuxReleaseVersion} == "ubuntu" ]] || [[ ${LinuxReleaseVersion} == "debian" ]]; then
    ubuntuCommonTool=(iputils-ping net-tools dnsutils lsof curl wget mtr-tiny vim)
    installDemandSoftwares ${ubuntuCommonTool[@]} || return $?
  fi
}

main() {
  check_root
  check_sys
  shutdownFirewall

  # 关闭虚拟缓存，k8s安装的时候才需要
  # disableSwap

  # 安装一些常用的小工具
  commonToolInstall

  # 安装docker，版本信息在本脚本的开头处修改~~
  installDocker || return $?
  installDockerCompose || return $?
  modifySystemConfig_Docker
  changeDockerRegisterMirror || return $?

  # 安装kubernetes，版本信息在本脚本的开头处修改~~
  # installKubernetes
  # modifySystemConfig_Kubernetes

  installZSH || return $?
  # 使用chrony进行NTP时间同步
  # changeTimeSyncToNTP || return $?
  # 使用timedatactl修改时间与时区
  changeTimeZoneAndNTP || return $?
}

main
