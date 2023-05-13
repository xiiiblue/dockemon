# DOCKEMON

## 简介
**DOCKEMON**是一个Docker镜像工具包，用于简化离线K8S环境下的镜像的拉取、打标、推送、导出导入等批量操作

同时支持**一键安装Chart**、**一键推送镜像**等快捷操作



## 系统要求

- 推荐macOS、Linux下的bash或zsh环境，Windows下的mobaXterm未经测试
- 涉及镜像相关操作，需要安装DockerDesktop或Nerdctl
- 涉及Chart相关操作，需要安装Helm



## 安装

将`dockemon-installer.sh`安装脚本下载到本机或服务器，并执行: 
```sh
chmod +x dockemon-installer.sh & ./dockemon-installer.sh
```
安装完成后，在任意路径下执行 `dockemon` 即可启动程序



## 配置

1. 执行`dockemon help`查看帮助信息
2. 执行`dockemon conf`配置Harbor地址等常用参数(可选)
3. 执行`dockemon edit`配置要处理的镜像清单，`dockemon show`查看清单(可选)



## 常用功能

### 一键安装Chart
一键安装Chart。包含: 下载Chart->分析镜像清单->拉取镜像->打标->建仓库->推送镜像
```sh
dockemon chart [仓库名称] [Chart名称] [版本号]  
```

示例:   
```sh
dockemon chart bitnami redis 17.10.3
```

### 一键推送镜像
一键推送镜像。包含: 拉取镜像->打标->建仓库->推送镜像。如果不传入镜像名，则批量处理镜像清单
```sh
dockemon image [镜像名]
```

示例:   
```sh
dockemon image nginx:alpine
```
### 其它批量操作
```sh
dockemon pull  # 拉取镜像
dockemon tag   # 打标签
dockemon tag_group [仓库名]  # 打标签归到同一个仓库，必须传入一个仓库名
dockemon push  # 推送镜像
dockemon save  # 导出镜像
dockemon load  # 导入镜像
dockemon login # 登录HARBOR
dockemon repo  # 创建HARBOR仓库
dockemon values # 分析helm配置文件并生成镜像清单
```



## 注意事项
1. Helm操作在本机联网环境下远程执行，请确保`～/.kube/config`配置正确，`kubectl get nodes`能连接到集群

2.  安装Chart前需要先添加好仓库并更新，示例:  
```sh
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

3. Harbor仓库如果使用域名连接，请先配置好`/etc/hosts`的指向

4. 如果无法通过VPN连接到离线集群(例如隔着堡垒机)，则只能分步操作上传镜像，大体步骤为:  
```sh
pull -> tag -> save -> 手工上传 -> load
```