#!/bin/bash

INSTALL_DIR="/root/cfnatop"
CONFIG_FILE="$INSTALL_DIR/cfnat.conf"
PID_FILE="$INSTALL_DIR/cfnat.pid"
CFNAT_BINARY="$INSTALL_DIR/cfnat"
RC_LOCAL_FILE="/etc/rc.local"
SCRIPT_PATH=$(readlink -f "$0")
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

MIRROR_PREFIX="https://p.goxo.us.kg/zxxc/https/"
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${GREEN}程序目录不存在，正在创建...${NC}"
    mkdir -p "$INSTALL_DIR"
fi




enable_autostart() {
    if ! grep -q "bash $SCRIPT_PATH" "$RC_LOCAL_FILE"; then
        sed -i '$i (sleep 60; bash /root/cfnat.sh start &) \n' "$RC_LOCAL_FILE"
        echo -e "${GREEN}已启用开机自启，并延迟 60 秒启动${NC}"
    else
        echo -e "${YELLOW}开机自启已处于启用状态${NC}"
    fi
}


disable_autostart() {
    sed -i "\#sleep 60; bash $SCRIPT_PATH start#d" "$RC_LOCAL_FILE"
    echo -e "${GREEN}已禁用开机自启${NC}"
}


show_autostart_status() {

if grep -q "bash $SCRIPT_PATH start" "$RC_LOCAL_FILE"; then
        echo -e "${GREEN}开机自启已启用${NC}"
    else
        echo -e "${RED}开机自启未启用${NC}"
    fi
}


modify_config() {
    load_config  

    echo -e "${GREEN}请修改以下配置（按回车使用当前值）：${NC}"

    read -p "请输入转发的目标端口 (默认: 1234, 当前: ${lport:-1234}): " new_lport
    lport=${new_lport:-${lport:-1234}}

    read -p "请输入转发端口 (默认: 443, 当前: ${forward_port:-443}): " new_forward_port
    forward_port=${new_forward_port:-${forward_port:-443}}

    read -p "请输入 HTTP/HTTPS 响应状态码 (默认: 200, 当前: ${code:-200}): " new_code
    code=${new_code:-${code:-200}}

    read -p "请输入筛选数据中心 (默认: 留空,机场三字码，多个数据中心用逗号隔开,留空则忽略匹配,当前: ${colo}): " new_colo
    colo=${new_colo:-$colo}

    read -p "请输入有效延迟（毫秒）(默认: 300, 当前: ${delay:-300}): " new_delay
    delay=${new_delay:-${delay:-300}}

    read -p "请输入响应状态码检查的域名 (默认: cloudflaremirrors.com/debian, 当前: ${domain:-cloudflaremirrors.com/debian}): " new_domain
    domain=${new_domain:-${domain:-cloudflaremirrors.com/debian}}

    read -p "请输入提取的有效IP数量 (默认: 20, 当前: ${ipnum:-20}): " new_ipnum
    ipnum=${new_ipnum:-${ipnum:-20}}

    read -p "请输入生成 IPv4 或 IPv6 地址 (4或6) (默认: 4, 当前: ${ips:-4}): " new_ips
    ips=${new_ips:-${ips:-4}}

    read -p "请输入目标负载 IP 数量 (默认: 10, 当前: ${num:-10}): " new_num
    num=${new_num:-${num:-10}}

    read -p "是否随机生成IP (true 或 false) (默认: true, 当前: ${random:-true}): " new_random
    random=${new_random:-${random:-true}}

    read -p "请输入并发请求最大协程数 (默认: 100, 当前: ${task:-100}): " new_task
    task=${new_task:-${task:-100}}

    read -p "是否为 TLS 端口 (true 或 false) (默认: true, 当前: ${tls:-true}): " new_tls
    tls=${new_tls:-${tls:-true}}

    save_config  

    start_cfnat  
}

download_file() {
    local url=$1
    local output_path=$2

    if command -v wget > /dev/null; then
        wget --no-check-certificate -O "$output_path" "$url"
    elif command -v curl > /dev/null; then
        curl -L "$url" -o "$output_path"
    else
        echo -e "${RED}未找到 wget 或 curl，请安装后再试${NC}"
        exit 1
    fi

    if [ ! -f "$output_path" ] || [ ! -s "$output_path" ]; then
        echo -e "${YELLOW}文件下载失败或文件大小为0，使用镜像地址(使用clouflare代理)下载...${NC}"
        local mirror_url="${MIRROR_PREFIX}${url#https://}"
        if command -v wget > /dev/null; then
            wget --no-check-certificate -O "$output_path" "$mirror_url"
        elif command -v curl > /dev/null; then
            curl -L "$mirror_url" -o "$output_path"
        fi
        if [ ! -f "$output_path" ] || [ ! -s "$output_path" ]; then
            echo -e "${RED}使用镜像地址下载失败: $mirror_url${NC}"
            exit 1
        fi
    fi
}

download_github_repo() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            FILE_URL="https://raw.githubusercontent.com/PoemMistyMoon/cfnat-openwrt/main/cfnat-linux-amd64"
            ;;
        i386)
            FILE_URL="https://raw.githubusercontent.com/PoemMistyMoon/cfnat-openwrt/main/cfnat-linux-386"
            ;;
        aarch64)
            FILE_URL="https://raw.githubusercontent.com/PoemMistyMoon/cfnat-openwrt/main/cfnat-linux-arm64"
            ;;
        arm*)
            FILE_URL="https://raw.githubusercontent.com/PoemMistyMoon/cfnat-openwrt/main/cfnat-linux-arm"
            ;;
        *)
            echo -e "${RED}不支持的系统架构: $ARCH${NC}"
            exit 1
            ;;
    esac

    download_file "$FILE_URL" "$CFNAT_BINARY"
    chmod +x "$CFNAT_BINARY"
    echo -e "${GREEN}cfnat 主程序下载成功${NC}"
}

download_necessary_files() {
    download_file "https://raw.githubusercontent.com/PoemMistyMoon/cfnat-openwrt/main/ips-v4.txt" "$INSTALL_DIR/ips-v4.txt"
    download_file "https://raw.githubusercontent.com/PoemMistyMoon/cfnat-openwrt/main/ips-v6.txt" "$INSTALL_DIR/ips-v6.txt"
    download_file "https://raw.githubusercontent.com/PoemMistyMoon/cfnat-openwrt/main/locations.json" "$INSTALL_DIR/locations.json"
    echo -e "${GREEN}必要的文件下载成功${NC}"
}

check_files() {
    if [ ! -f "$CFNAT_BINARY" ] || [ ! -s "$CFNAT_BINARY" ] || [ ! -f "$INSTALL_DIR/ips-v4.txt" ] || [ ! -s "$INSTALL_DIR/ips-v4.txt" ] || [ ! -f "$INSTALL_DIR/ips-v6.txt" ] || [ ! -s "$INSTALL_DIR/ips-v6.txt" ]; then
        echo -e "${YELLOW}未检测到主程序或必要文件，开始下载...${NC}"
        download_github_repo
        download_necessary_files
    else
        echo -e "${YELLOW}主程序和必要文件已存在，跳过下载${NC}"
    fi
}

save_config() {
    echo "addr=127.0.0.1" > $CONFIG_FILE  
    echo "lport=$lport" >> $CONFIG_FILE
    echo "forward_port=$forward_port" >> $CONFIG_FILE
    echo "code=$code" >> $CONFIG_FILE
    echo "colo=$colo" >> $CONFIG_FILE
    echo "delay=$delay" >> $CONFIG_FILE
    echo "domain=$domain" >> $CONFIG_FILE
    echo "ipnum=$ipnum" >> $CONFIG_FILE
    echo "ips=$ips" >> $CONFIG_FILE
    echo "num=$num" >> $CONFIG_FILE
    echo "random=$random" >> $CONFIG_FILE
    echo "task=$task" >> $CONFIG_FILE
    echo "tls=$tls" >> $CONFIG_FILE
}


load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${YELLOW}正在读取配置文件...${NC}"
        
    else
        echo -e "${RED}配置文件不存在，将进行安装程序${NC}"
    fi
}


get_lan_ip() {
    lan_ip=$(ifconfig br-lan | grep 'inet addr' | awk -F: '{print $2}' | awk '{print $1}')
    if [ -z "$lan_ip" ]; then
        echo -e "${RED}未能检测到 LAN 口的 IPv4 地址，请检查接口名称${NC}"
        return 1
    else
        echo "LAN 口的 IPv4 地址: $lan_ip"
    fi
}
start_cfnat() {
    get_lan_ip
    load_config
    if [ ! -f "$CONFIG_FILE" ]; then
        addr="127.0.0.1"

        echo -e "${YELLOW}如果你需要在本机同时运行cfnat和代理插件，请关闭代理插件的代理本机功能，否则cfnat无效，回车继续${NC}"
        read -p "按回车继续... "

        read -p "请输入转发的目标端口 (默认: ${lport:-1234}): " lport
        lport=${lport:-1234}

        read -p "请输入转发端口 (默认: ${forward_port:-443}): " forward_port
        forward_port=${forward_port:-443}

        read -p "请输入 HTTP/HTTPS 响应状态码 (默认: ${code:-200}): " code
        code=${code:-200}

        read -p "请输入筛选数据中心 (默认: ${colo},机场三字码，多个数据中心用逗号隔开,留空则忽略匹配): " colo

        read -p "请输入有效延迟（毫秒）(默认: ${delay:-300}): " delay
        delay=${delay:-300}

        read -p "请输入响应状态码检查的域名 (默认: ${domain:-cloudflaremirrors.com/debian}): " domain
        domain=${domain:-"cloudflaremirrors.com/debian"}

        read -p "请输入提取的有效IP数量 (默认: ${ipnum:-20}): " ipnum
        ipnum=${ipnum:-20}

        read -p "请输入生成 IPv4 或 IPv6 地址 (4或6) (默认: ${ips:-4}): " ips
        ips=${ips:-4}

        read -p "请输入目标负载 IP 数量 (默认: ${num:-10}): " num
        num=${num:-10}

        read -p "是否随机生成IP (true 或 false) (默认: ${random:-true}): " random
        random=${random:-true}

        read -p "请输入并发请求最大协程数 (默认: ${task:-100}): " task
        task=${task:-100}

        read -p "是否为 TLS 端口 (true 或 false) (默认: ${tls:-true}): " tls
        tls=${tls:-true}
        save_config
    fi
        kill_cfnat_process  
        rm -f "$PID_FILE"
        cmd="cd $INSTALL_DIR && nohup ./cfnat -addr \"$addr:$lport\" -code \"$code\" -delay \"$delay\" -domain \"$domain\" -ipnum \"$ipnum\" -ips \"$ips\" -num \"$num\" -random \"$random\" -task \"$task\" -tls \"$tls\" -port \"$forward_port\""
    
if [ -n "$colo" ]; then
        cmd="$cmd -colo \"$colo\""
    fi

    cmd="$cmd > /dev/null 2>&1 &"

    eval $cmd

    sleep 2  
CFNAT_PID=$(pgrep -f "./cfnat -addr")  

if [ -n "$CFNAT_PID" ]; then
    echo $CFNAT_PID > $PID_FILE  
else
    echo "未能启动cfnat或获取PID，检查进程。" >&2
    exit 1
fi

    if ps | grep -q "[c]fnat"; then
        echo -e "${GREEN}cfnat 已启动，PID: $(cat $PID_FILE)${NC}"
         echo "LAN 口的 IPv4 地址: $lan_ip"
         echo "lanip=$lan_ip" >> $CONFIG_FILE
         echo -e "${YELLOW}如果你在本机运行了代理插件，请把你的 CF 节点 IP 和端口改成：127.0.0.1:$lport${NC}"
         echo -e "${YELLOW}如果你在其他设备运行代理插件，请把你的 CF 节点 IP 和端口改成：$lan_ip:$lport${NC}"
         echo -e "${YELLOW}如果你需要在本机同时运行cfnat和代理插件，请关闭代理插件的代理本机功能，否则cfnat无效${NC}"
    else
        echo -e "${RED}cfnat 启动失败，请检查配置或重试${NC}"
    fi
}

show_current_config() {
    echo "========================"
    echo -e "${GREEN}当前配置:${NC}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}未安装: 配置文件不存在${NC}"
    else
        source "$CONFIG_FILE"
        echo -e "${GREEN}已安装：配置文件内容:${NC}"
        echo "监听地址 (addr): 127.0.0.1"
        echo "监听端口 (lport): $lport"
        echo "转发端口 (forward_port): $forward_port"
        echo "HTTP/HTTPS 响应状态码 (code): $code"
        echo "筛选数据中心 (colo): ${colo:-未设置}"
        echo "有效延迟 (delay): $delay"
        echo "响应状态码检查的域名 (domain): $domain"
        echo "提取的有效IP数量 (ipnum): $ipnum"
        echo "生成 IPv4 或 IPv6 地址 (ips): $ips"
        echo "目标负载 IP 数量 (num): $num"
        echo "是否随机生成IP (random): $random"
        echo "并发请求最大协程数 (task): $task"
        echo "是否为 TLS 端口 (tls): $tls"
        echo "LAN 连接地址: $lanip:$lport"
        echo "========================"
        
    fi


    if pgrep -f "./cfnat -addr" > /dev/null; then
        CFNAT_PID=$(pgrep -f "./cfnat -addr") 
        echo -e "${GREEN}cfnat 正在运行，PID: $CFNAT_PID${NC}"
        show_autostart_status 
        echo "========================"
        echo -e "${YELLOW}如果你在本机运行了代理插件，请把你的 CF 节点 IP 修改为：127.0.0.1 端口修改为：$lport${NC}"
        echo -e "${YELLOW}如果你在其他设备运行代理插件，请把你的 CF 节点 IP 修改为：$lanip 端口修改为：$lport${NC}"
        echo -e "${YELLOW}如果你需要在本机同时运行cfnat和代理插件，请关闭代理插件的代理本机功能，否则cfnat无效${NC}"
    else
        echo -e "${RED}cfnat 未运行${NC}"
    fi
}


main_menu() {
    show_current_config
    echo "========================"
    echo -e "${GREEN}脚本作者：PoemMistyMoon${NC}"
    echo "========================"
    echo "1. 启动 cfnat"
    echo "2. 安装 cfnat"
    echo "3. 修改参数"
    echo "4. 卸载 cfnat"
    echo "5. 停止 cfnat"
    echo "6. 启用开机自启"
    echo "7. 禁用开机自启"
    echo "8. 恢复默认配置"
    echo "0. 退出脚本"
    echo "请选择一个选项 [0-8]: "

    read choice
    case $choice in
        1)
            check_files
            start_cfnat
            ;;
        2)
            check_files
            start_cfnat
            ;;
        3)
            modify_config
            ;;
        4)
            uninstall
            ;;
        5)
            kill_cfnat_process
            main_menu
            ;;
        6)
            enable_autostart
            main_menu
            ;;
        7)
            disable_autostart
            main_menu
            ;;
        8)
            if [ -f "$CONFIG_FILE" ]; then
             rm -r "$CONFIG_FILE"
             echo -e "${GREEN}已清空配置文件，即将重新安装${NC}"
             sleep 1
            check_files
            start_cfnat
          else
          echo -e "${RED}似乎没有检测到配置文件，代表着你可能还没安装呢,即将返回主菜单${NC}"
            sleep 2
            main_menu
            fi
             ;;
        0)
            echo -e "${GREEN}退出脚本${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项,即将返回主菜单${NC}"
            sleep 2
            main_menu
            ;;
    esac
}

uninstall() {
    echo -e "${GREEN}正在卸载 cfnat...${NC}"
    kill $(cat "$PID_FILE")  
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}卸载成功${NC}"
}

kill_cfnat_process() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" > /dev/null 2>&1; then
            kill "$PID"
            rm -f "$PID_FILE"
            echo -e "${YELLOW}停止正在运行的cfnat${NC}"
        else
            echo -e "${RED}没有找到运行中的 cfnat 进程跳过本操作${NC}"
        fi
    else
        CFNAT_PID=$(pgrep -f "./cfnat -addr")
        if [ -n "$CFNAT_PID" ]; then
            kill "$CFNAT_PID"
            echo -e "${YELLOW}停止正在运行的cfnat${NC}"
        else
            echo -e "${RED}没有找到运行中的 cfnat 进程跳过本操作${NC}"
        fi
    fi
}



if [ "$1" == "start" ]; then
    check_files
    start_cfnat
else
    main_menu
fi
