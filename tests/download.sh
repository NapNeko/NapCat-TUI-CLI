#!/bin/bash


function log() {
    time=$(date +"%Y-%m-%d %H:%M:%S")
    message="[${time}]: $1 "
    case "$1" in
    *"失败"* | *"错误"* | *"sudo不存在"* | *"当前用户不是root用户"* | *"无法连接"*)
        echo -e "${RED}${message}${NC}"
        ;;
    *"成功"*)
        echo -e "${GREEN}${message}${NC}"
        ;;
    *"忽略"* | *"跳过"* | *"默认"*)
        echo -e "${YELLOW}${message}${NC}"
        ;;
    *)
        echo -e "${BLUE}${message}${NC}"
        ;;
    esac
}
function network_test() {
    local parm1=${1}
    local found=0
    target_proxy=""
    proxy_num=${proxy_num:-9}

    if [ "${parm1}" == "Github" ]; then
        proxy_arr=("https://ghfast.top" "https://ghp.ci" "https://gh.wuliya.xin" "https://gh-proxy.com" "https://x.haod.me")
        check_url="https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json"
    elif [ "${parm1}" == "Docker" ]; then
        proxy_arr=("docker.1panel.dev" "dockerpull.com" "dockerproxy.cn" "docker.agsvpt.work" "hub.021212.xyz" "docker.registry.cyou")
        check_url=""
    fi

    if [ ! -z "${proxy_num}" ] && [ "${proxy_num}" -ge 1 ] && [ "${proxy_num}" -le ${#proxy_arr[@]} ]; then
        log "手动指定代理: ${proxy_arr[$proxy_num - 1]}"
        target_proxy="${proxy_arr[$proxy_num - 1]}"
    else
        if [ "${proxy_num}" -ne 0 ]; then
            log "proxy 未指定或超出范围, 正在检查${parm1}代理可用性..."
            for proxy in "${proxy_arr[@]}"; do
                status=$(curl -o /dev/null -s -w "%{http_code}" "${proxy}/${check_url}")
                if [ "${parm1}" == "Github" ] && [ ${status} -eq 200 ]; then
                    found=1
                    target_proxy="${proxy}"
                    log "将使用${parm1}代理: ${proxy}"
                    break
                elif [ "${parm1}" == "Docker" ] && ([ ${status} -eq 200 ] || [ ${status} -eq 301 ]); then
                    found=1
                    target_proxy="${proxy}"
                    log "将使用${parm1}代理: ${proxy}"
                    break
                fi
            done

            if [ ${found} -eq 0 ]; then
                log "无法连接到${parm1}, 请检查网络。"
                exit 1
            fi
        else
            log "代理已关闭, 将直接连接${parm1}..."
        fi
    fi
}
function install_napcat_cli() {
    local cli_script_url_base="https://raw.githubusercontent.com/NapNeko/NapCat-TUI-CLI/main/script"
    local cli_script_name="install-cli.sh"
    local cli_script_local_path="./${cli_script_name}.download" # Download to a temporary name
    local cli_script_url="${target_proxy:+${target_proxy}/}${cli_script_url_base}/${cli_script_name}"
    local exit_status=1 # Default to failure

    # Ensure network test has run for Github to potentially set target_proxy
    # If network_test hasn't run, run it now.
    if [ -z "${target_proxy+x}" ]; then # Check if target_proxy is set at all
        log "运行 TUI-CLI 安装的网络测试..."
        network_test "Github"
        # Allow continuing even if network_test fails, curl might still work without proxy
    fi

    log "下载外部 TUI-CLI 安装脚本从 ${cli_script_url}..."
    sudo curl -L -# "${cli_script_url}" -o "${cli_script_local_path}"

    if [ $? -ne 0 ]; then
        log "错误: TUI-CLI 安装脚本 ${cli_script_name} 下载失败。"
        sudo rm -f "${cli_script_local_path}" # Clean up potentially partial download
        return 1 # Indicate failure
    fi

    log "设置 TUI-CLI 安装脚本权限..."
    sudo chmod +x "${cli_script_local_path}"
    if [ $? -ne 0 ]; then
        log "错误: 设置 TUI-CLI 安装脚本 (${cli_script_local_path}) 执行权限失败。"
        sudo rm -f "${cli_script_local_path}"
        return 1 # Indicate failure
    fi

    log "执行外部 TUI-CLI 安装脚本 (${cli_script_local_path})..."
    # Pass the proxy number argument (use 9 for auto if not set)
    sudo "${cli_script_local_path}" "${proxy_num_arg:-9}"

    exit_status=$? # Capture the exit status of the external script
    if [ ${exit_status} -ne 0 ]; then
         log "外部 TUI-CLI 安装脚本执行失败 (退出码: ${exit_status})。"
         # Decide if this should be a fatal error for the main script
         # return 1
    else
         log "外部 TUI-CLI 安装脚本执行成功。"
    fi

    log "清理 TUI-CLI 安装脚本 (${cli_script_local_path})..."
    sudo rm -f "${cli_script_local_path}"

    return ${exit_status} # Return the exit status of the external script
}
install_napcat_cli