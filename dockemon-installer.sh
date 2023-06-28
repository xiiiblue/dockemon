#!/usr/bin/env bash

# 默认配置
SCRIPT_NAME=$(basename $0) # 当前脚本文件名称
BIN_PATH=/usr/local/bin # 二进制安装路径
BIN_FILE=${BIN_PATH}/dockemon # 二进制文件名
CONFIG_PATH=~/.dockemon # 配置文件目录
CONFIG_FILE=${CONFIG_PATH}/default.conf # 配置文件名
IMG_SRC=${CONFIG_PATH}/img_src.txt  # 原始镜像清单(注意最后一行必须是回车)
IMG_DEST=${CONFIG_PATH}/img_dest.txt  # 打标后镜像清单(自动生成)
IMG_REPO=${CONFIG_PATH}/img_repo.txt  # 仓库名清单(自动生成)
NERDCTL_FLAG=0  # 是否已安装nerdctl
WORK_DIR=`pwd`  # 当前工作目录

# 初始化安装
install() {
    echo "正在安装DOCKEMON..."
    cp -f ${SCRIPT_NAME} ${BIN_FILE}
    chmod +x ${BIN_FILE}

    echo "正在创建配置目录..."
    mkdir -p ${CONFIG_PATH}
    touch ${CONFIG_FILE}
    touch ${IMG_SRC}
    touch ${IMG_DEST}
    touch ${IMG_REPO}

    echo "正在生成默认配置..."
    cat << EOF >${CONFIG_FILE}
HARBOR_DOMAIN=harbor.dubhe:30002 # Harbor域名
HARBOR_USER="admin"  # Harbor用户名
HARBOR_PASSWD="Harbor12345"  # Harbor密码
CONTAINERD_SOCK=/run/k3s/containerd/containerd.sock
CONTAINERD_NAMESPACE=k8s.io
PLATFORM=linux/amd64
GZIP_BIN=gzip
EOF
    echo "DOCKEMON安装完成!!"
    echo
    echo "二进制文件: ${BIN_FILE}"
    echo "配置文件目录: ${CONFIG_PATH}/"
    echo
    echo "请在任意路径下执行 dockemon 启动程序"
}

# 编辑配置文件
conf() {
    vi ${CONFIG_FILE}
    echo "配置文件已修改: ${CONFIG_FILE}"
}

# 编辑镜像列表
edit() {
    vi ${IMG_SRC}
    echo "镜像列表已修改: ${IMG_SRC}"
}

# 查看镜像列表
show() {
    echo "原始镜像清单(${IMG_SRC}):"
    cat ${IMG_SRC}
    echo
    echo "打标后镜像清单(${IMG_DEST}):"
    cat ${IMG_DEST}
    echo
    echo "仓库名清单(${IMG_REPO}):"
    cat ${IMG_REPO}
    echo
}

# 拉取镜像
pull() {
    echo "拉取镜像 开始"
    echo "************************************************"
    echo
    cat ${IMG_SRC} | while read raw_name
    do
        if [ ! -z $raw_name ]; then
            echo 正在拉取: $raw_name 架构: ${PLATFORM}
            docker pull --platform ${PLATFORM} $raw_name
            if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
            echo ""
        fi
    done
    echo "拉取镜像 完成!"
    echo
}

# 推送镜像
push() {
    echo "推送镜像 开始"
    echo "************************************************"
    echo
    login
    cat ${IMG_DEST} | while read tag_name
    do
        echo "正在推送 $tag_name"
        if [ ${NERDCTL_FLAG} -eq 0 ]; then
            nerdctl --host=${CONTAINERD_SOCK} --namespace ${CONTAINERD_NAMESPACE} --insecure-registry push $tag_name
        else
            docker push $tag_name
        fi
        if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
        echo ""
    done
    echo "推送镜像 完成!"
    echo
}

# 导出镜像
save() {
    echo "导出镜像 开始"
    echo "************************************************"
    echo
    cat ${IMG_SRC} | while read img_name
    do
        # 取镜像名称未尾(不含仓库名)
        suffix=${img_name##*/}
        # 文件名(将:替换为-)
        file_name=${suffix/:/-}.tar.gz
        echo "正在导出: $file_name"
        docker save $img_name | ${GZIP_BIN} > $file_name
        if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
        echo
    done
    echo "正在导出镜像清单"
    cat $IMG_SRC>image-list.txt

    echo "导出镜像 完成!"
    echo
}

# 导入镜像
load() {
    echo "导入镜像 开始"
    echo "************************************************"
    echo
    echo "遍历当前目录下所有镜像"
    for file_name in ./*
    do
        if [[ -f $file_name && $file_name == *gz ]]; then
            echo 正在导入: $file_name
            if [ ${NERDCTL_FLAG} -eq 0 ]; then
                nerdctl --host=${CONTAINERD_SOCK} --namespace ${CONTAINERD_NAMESPACE} load -i $file_name
            else
                docker load -i $file_name
            fi
            if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
        fi
        echo ""
    done
    echo "导入镜像 完成!"
    echo
}

# 打标签
tag() {
    echo "打标签 开始"
    echo "************************************************"
    echo
    >${IMG_DEST}
    cat ${IMG_SRC} | while read raw_name
    do
        if [ ! -z $raw_name ]; then
            # 如果有域名则先剔除
            head=`echo $raw_name | awk -F '/' '{print $1}'`
            if [[ $head == *"."* ]]; then
                raw_name_without_domain=`echo $raw_name | sed -e "s/$head\///g"`
            else
                raw_name_without_domain=$raw_name
            fi

            # 如果没有默认仓库则补一个/library
            if [[ $raw_name_without_domain == *"/"* ]]; then
                tag_name=${HARBOR_DOMAIN}/$raw_name_without_domain
            else
                tag_name=${HARBOR_DOMAIN}/library/$raw_name_without_domain
            fi

            echo "正在打标签: [$raw_name] to [$tag_name]"
            echo $tag_name>>${IMG_DEST}
            # 打标签
            docker tag $raw_name $tag_name
            if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
            echo
        fi
    done

    # 生成仓库名清单
    echo "正在生成仓库清单"
    cat ${IMG_DEST} | awk -F '/' '{print $2}'|sort|uniq > ${IMG_REPO}
    echo
    echo "打标签 完成!"
    echo
}

# 打标签并归类
tag_group() {
    echo "打标签并归类 开始"
    echo "************************************************"
    echo
    if [ -z $1 ] ; then
        echo "必须传入一个仓库名"
        exit
    fi

    >${IMG_DEST}
    cat ${IMG_SRC}|while read raw_name
    do
        if [ ! -z $raw_name ]; then
            # 如果有域名则先剔除
            head=`echo $raw_name | awk -F '/' '{print $1}'`
            if [[ $head == *"."* ]]; then
                raw_name_without_domain=`echo $raw_name | sed -e "s/$head\///g"`
            else
                raw_name_without_domain=$raw_name
            fi

            suffix=${raw_name_without_domain##*/}
            tag_name=${HARBOR_DOMAIN}/$1/$suffix
            echo "正在打标签: [$raw_name] to [$tag_name]"
            echo "$tag_name>>${IMG_DEST}"
            docker tag $raw_name $tag_name
            if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
            echo
        fi
    done
    echo "打标签并归类 完成!"
    echo
}

# 登录harbor仓库
login() {
    echo "正在登录Harbor仓库..."
    if [ ${NERDCTL_FLAG} -eq 0 ]; then
        nerdctl login ${HARBOR_DOMAIN} -u ${HARBOR_USER} -p ${HARBOR_PASSWD} --insecure-registry
        if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
    else
        docker login ${HARBOR_DOMAIN} -u ${HARBOR_USER} -p ${HARBOR_PASSWD}
        if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
    fi
    echo
}

# 创建harbor仓库
repo() {
    echo "创建Harbor仓库 开始"
    echo "************************************************"
    echo

    if [ -z $1 ]; then
        echo "未获仓库名，处理 ${IMG_REPO} 中全部仓库"
    else
        echo "已获仓库名 $1"
        echo $1>${IMG_REPO}
    fi
    echo

    # 登录
    login
    cat ${IMG_REPO} | while read repo
    do
        echo "正在创建仓库: $repo"
        curl -u "${HARBOR_USER}:${HARBOR_PASSWD}" -X POST -H "Content-Type: application/json" "http://${HARBOR_DOMAIN}/api/v2.0/projects" -d "{ \"project_name\": \"${repo}\", \"public\": true}" -k
        echo ""
    done
    echo "创建Harbor仓库 完成!"
    echo
}

# 一键推送镜像
image() {
    echo "一键推送镜像 开始"
    echo "************************************************"
    echo

    if [ -z $1 ]; then
        echo "未获取镜像名，处理 ${IMG_SRC} 中全部镜像"
    else
        echo "已获取镜像名 $1"
        echo $1>${IMG_SRC}
    fi
    echo
    
    # 拉取镜像
    pull;
    # 打标签
    tag;
    # 建Harbor仓库
    repo;
    # 推送镜像
    push;
    echo "一键推送镜像 完成!"
    echo
}

# 分析Helm镜像清单
values() {
    echo "分析Helm镜像清单 开始"
    echo "************************************************"
    echo
    if [ -z $1 ]; then
        yaml_file="values.yaml"
        echo "未传入文件名，分析默认的values.yaml"
    else
        yaml_file=$1
        echo "已传入文件名: $1"
    fi
    # 清空镜像清单
    clean
    echo "正在生成镜像清单..."
    cat ${yaml_file} | grep -e repository: -e tag: | sed 's/ //g' | sed -n 'H;${x;s/\ntag:/:/g;p;}' | sed '/^\s*$/d' | sed 's/repository://g' | sort | uniq | tee ${IMG_SRC}
    if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
    echo
    echo "分析Helm镜像清单 完成!"
    echo
}

# 一键安装HelmChar
chart() {
    echo "一键安装Chart 开始"
    echo "************************************************"
    echo
     # 获取仓库名称
    repo=$1
    # 获取Chart名称
    chart=$2
    # 获取版本号
    version=$3
    # 清空镜像清单
    clean
    # 拉取chart
    echo "正在拉取Chart..."
    echo "仓库名称: ${repo} Chart名称: ${chart} 版本号: ${version}"
    helm pull ${repo}/${chart} --version ${version}
    if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
    # 解压chart
    echo "正在解压Chart..."
    tar -zxf ${chart}-${version}.tgz
    if [ $? -ne 0 ]; then echo "执行失败，程序终止！"; exit; fi
    echo 
    # 分析values.yaml，生成镜像清单
    values ${chart}/values.yaml
    # 拉取镜像
    pull;
    # 打标签
    tag;
    # 建Harbor仓库
    repo;
    # 推送镜像
    push;
    # helm安装
    echo "一键安装Chart 完成!"
    echo "接下来请手工执行helm install命令，传入您自定义的安装参数:"
    echo
    echo "helm install ${chart} ./${chart} --namespace ${chart} --create-namespace"
    echo
}

# 清空镜像清单
clean() {
    echo "正在清空镜像清单..."
    >${IMG_SRC}
    >${IMG_DEST}
    >${IMG_REPO}
    echo
}

# 展示Banner
banner() {
    echo "**************************"
    echo "*                        *"
    echo "*        DOCKEMON        *"
    echo "*                        *"
    echo "**************************"
    echo
}

# 判断使用docker还是nerdctl
check_docker() {
    which nerdctl>/dev/null
    if [ $? -eq 1 ]; then
        which docker>/dev/null
        if [ $? -eq 1 ]; then
            echo "请先安装nerdctl或docker"
            exit
        fi
        NERDCTL_FLAG=1 # 已安装docker
    fi
}

# 帮助
help() {
    echo "帮助信息:"
    echo "配置文件路径 ${CONFIG_FILE}"
    echo "镜像清单路径 ${IMG_SRC}"
    echo "请提前将要处理的内容写入镜像清单中，或通过dockemon edit命令直接编辑清单"
    echo
    echo "示例:"
    echo "dockemon conf  # 编辑配置文件，例如Harbor地址、帐密等"
    echo "dockemon edit  # 编辑镜像清单，请注意最后一行必须是回车"
    echo "dockemon show  # 查看镜像清单"
    echo "dockemon pull  # 拉取镜像"
    echo "dockemon push  # 推送镜像"
    echo "dockemon tag   # 打标签"
    echo "dockemon tag_group [仓库名]  # 打标签归到同一个仓库，必须传入一个仓库名"
    echo "  示例: dockemon tag_group my_repo"
    echo "dockemon load  # 导入镜像"
    echo "dockemon save  # 导出镜像"
    echo "dockemon login # 登录HARBOR"
    echo "dockemon repo  [仓库名]  # 创建HARBOR仓库 如果不传入仓库名，则创建清单中所有仓库"
    echo "  示例: dockemon repo myrepo"
    echo "dockemon image [镜像名]  # 一键推送镜像 包含: 拉取镜像->打标->建仓库->推送镜像 如果不传入镜像名，则批量处理镜像清单"
    echo "  示例: dockemon image nginx:alpine"
    echo "dockemon values [yaml文件名]  # 分析helm配置文件并生成镜像清单"
    echo "  示例: dockemon values values.yaml"
    echo "dockemon chart [仓库名称] [Chart名称] [版本号]  # 一键安装Chart 包含: 下载Chart->分析镜像清单->拉取镜像->打标->建仓库->推送镜像"
    echo "  示例: dockemon chart bitnami redis 17.10.3"
    echo "dockemon help  # 查看帮助"
    echo 
}

# 程序入口
banner
if [ ${SCRIPT_NAME} == *".sh"* ]; then
    # 如果当前文件名后缀为.sh，则先安装
    install
    exit
else
    # 加载配置
    source ${CONFIG_FILE}
    # 判断使用docker还是nerdctl
    check_docker
    # 主界面
    case $1 in
        conf) conf;; # 编辑配置文件
        edit) edit;; # 编辑镜像清单
        show) show;; # 查看镜像清单
        pull) pull;; # 拉取镜像
        push) push;; # 推送镜像
        tag) tag;; # 打标签
        tag_group) tag_group $2;; # 打标签并归类
        save) save;; # 保存镜像
        load) load;; # 导入镜像
        login) login;; # 登录Harbor
        repo) repo $2;; # 创建Harbor仓库
        image) image $2;; # 一键推送镜像
        values) values $2;; # 分析Helm镜像清单
        chart) chart $2 $3 $4;; # 一键安装Chart
        help) help;; # 查看帮助
        *) help;; # 查看帮助
    esac
fi