#!/bin/bash

INSTALL_DIR="/root/cfnatop"
CONFIG_FILE="$INSTALL_DIR/cfnat.conf"
PID_FILE="$INSTALL_DIR/cfnat.pid"
CFNAT_BINARY="$INSTALL_DIR/cfnat"
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'  

if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${GREEN}程序目录不存在，正在创建...${NC}"
    mkdir -p "$INSTALL_DIR"
fi

modify_config() {
    load_config  #

    echo -e "${GREEN}请修改以下配置（按回车使用当前值）：${NC}"

    read -p "请输入转发的目标端口 (当前: ${port:-1234}): " port
    port=${port:-1234}

    read -p "请输入 HTTP/HTTPS 响应状态码 (当前: ${code:-200}): " code
    code=${code:-200}

    read -p "请输入筛选数据中心 (当前: ${colo}，大写三字码，多个数据中心用逗号隔开,留空则忽略匹配): " colo

    read -p "请输入有效延迟（毫秒）(当前: ${delay:-300}): " delay
    delay=${delay:-300}

    read -p "请输入响应状态码检查的域名 (当前: ${domain:-cloudflaremirrors.com/debian}): " domain
    domain=${domain:-"cloudflaremirrors.com/debian"}

    read -p "请输入提取的有效IP数量 (当前: ${ipnum:-20}): " ipnum
    ipnum=${ipnum:-20}

    read -p "请输入生成 IPv4 或 IPv6 地址 (4或6) (当前: ${ips:-4}): " ips
    ips=${ips:-4}

    read -p "请输入目标负载 IP 数量 (当前: ${num:-10}): " num
    num=${num:-10}

    read -p "是否随机生成IP (true 或 false) (当前: ${random:-true}): " random
    random=${random:-true}

    read -p "请输入并发请求最大协程数 (当前: ${task:-100}): " task
    task=${task:-100}

    read -p "是否为 TLS 端口 (true 或 false) (当前: ${tls:-true}): " tls
    tls=${tls:-true}

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

    if [ ! -f "$output_path" ]; then
        echo -e "${RED}文件下载失败: $url${NC}"
        exit 1
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
            echo -e "${RED}不支持的系统架构: $ARCH，~_~我承认了，不是不支持，就是单纯懒得放链接了，去下一个方法目录里面改名cfnat就可以用了${NC}"
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
    if [ ! -f "$CFNAT_BINARY" ] || [ ! -f "$INSTALL_DIR/ips-v4.txt" ] || [ ! -f "$INSTALL_DIR/ips-v6.txt " ]; then
        echo -e "${YELLOW}未检测到主程序或必要文件，开始下载...${NC}"
        download_github_repo
        download_necessary_files
    else
        echo -e "${YELLOW}主程序和必要文件已存在，跳过下载${NC}"
    fi
}


save_config() {
    echo "addr=127.0.0.1" > $CONFIG_FILE  
    echo "port=$port" >> $CONFIG_FILE
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
    echo "lanip=$lan_ip" >> $CONFIG_FILE
}


load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${YELLOW}配置文件存在${NC}"
        
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
    load_config
    get_lan_ip
    if [ ! -f "$CONFIG_FILE" ]; then
        addr="127.0.0.1"

        echo -e "${YELLOW}如果你需要在本机同时运行cfnat和代理插件，请关闭代理插件的代理本机功能，否则cfnat无效，回车继续${NC}"
        read -p "按回车继续... "

        read -p "请输入转发的目标端口 (默认: ${port:-1234}): " port
        port=${port:-1234}

        read -p "请输入 HTTP/HTTPS 响应状态码 (默认: ${code:-200}): " code
        code=${code:-200}

        read -p "请输入筛选数据中心 (默认: ${colo},大写三字码，多个数据中心用逗号隔开,留空则忽略匹配): " colo

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
    cd $INSTALL_DIR && nohup ./cfnat -addr "$addr:$port" -code "$code" -colo "$colo" -delay "$delay" -domain "$domain" -ipnum "$ipnum" -ips "$ips" -num "$num" -random "$random" -task "$task" -tls "$tls" > /dev/null 2>&1 &


    sleep 1  
CFNAT_PID=$(pgrep -f "./cfnat")  

if [ -n "$CFNAT_PID" ]; then
    echo $CFNAT_PID > $PID_FILE  
else
    echo "未能启动cfnat或获取PID，检查进程。" >&2
    exit 1
fi

    if ps | grep -q "[c]fnat"; then
        echo -e "${GREEN}cfnat 已启动，PID: $(cat $PID_FILE)${NC}"
         echo "LAN 口的 IPv4 地址: $lan_ip"
         echo -e "${YELLOW}如果你在本机运行了代理插件，请把你的 CF 节点 IP 和端口改成：127.0.0.1:$port${NC}"
         echo -e "${YELLOW}如果你在其他设备运行代理插件，请把你的 CF 节点 IP 和端口改成：$lan_ip:$port${NC}"
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
        echo "端口 (port): $port"
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
        echo "LAN 连接地址: $lanip:$port"
        echo "========================"
        
    fi


    if pgrep -f "./cfnat" > /dev/null; then
        CFNAT_PID=$(pgrep -f "./cfnat") 
        echo -e "${GREEN}cfnat 正在运行，PID: $CFNAT_PID${NC}"
        echo "========================"
        echo -e "${YELLOW}如果你在本机运行了代理插件，请把你的 CF 节点 IP 修改为：127.0.0.1 端口修改为：$port${NC}"
        echo -e "${YELLOW}如果你在其他设备运行代理插件，请把你的 CF 节点 IP 修改为：$lanip 端口修改为：$port${NC}"
        echo -e "${YELLOW}如果你需要在本机同时运行cfnat和代理插件，请关闭代理插件的代理本机功能，否则cfnat无效${NC}"
    else
        echo -e "${RED}cfnat 未运行${NC}"
    fi
}


main_menu() {

    show_current_config

    echo "========================"
    echo -e "${GREEN}本脚本作者：CM群里面的某人${NC}"
    echo "========================"
    echo "1. 启动 cfnat"
    echo "2. 安装 cfnat"
    echo "3. 修改参数"
    echo "4. 卸载 cfnat"
    echo "5. 停止 cfnat"
    echo "0. 退出脚本"
    echo "请选择一个选项 [0-5]: "

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
            ;;
        0)
            echo -e "${GREEN}退出脚本${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项${NC}"
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
        CFNAT_PID=$(pgrep -f "./cfnat")
        if [ -n "$CFNAT_PID" ]; then
            kill "$CFNAT_PID"
            echo -e "${YELLOW}停止正在运行的cfnat${NC}"
        else
            echo -e "${RED}没有找到运行中的 cfnat 进程跳过本操作${NC}"
        fi
    fi
}

main_menu
