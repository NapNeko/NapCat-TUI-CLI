#!/bin/bash
set -e

function log() {
    printf '[%s CLI]: %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
}

function run_as_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo --preserve-env=http_proxy,https_proxy,all_proxy,no_proxy,HTTP_PROXY,HTTPS_PROXY,ALL_PROXY,NO_PROXY,CURL_CA_BUNDLE,SSL_CERT_FILE "$@"
    fi
}

target_proxy=""

function network_test() {
    local proxy_num=${1:-9}
    local proxy_arr=("https://ghfast.top" "https://ghproxy.net" "https://gh-proxy.com" "https://github.dpik.top" "https://ghm.078465.xyz")
    local check_url="https://raw.githubusercontent.com/NapNeko/NapCat-TUI-CLI/main/LICENSE"
    local proxy probe_file
    case "$proxy_num" in
        0) target_proxy="" ;;
        [1-5]) target_proxy="${proxy_arr[$proxy_num - 1]}" ;;
        http://*|https://*) target_proxy="${proxy_num%/}" ;;
        9|auto)
            probe_file=$(mktemp) || return 1
            for proxy in "" "${proxy_arr[@]}"; do
                if curl -fLsS --connect-timeout 3 --max-time 5 --max-filesize 65536 \
                    --proto '=http,https' --proto-redir '=http,https' \
                    -o "$probe_file" "${proxy:+${proxy}/}${check_url}" &&
                    grep -q '^Creative Commons Attribution-NonCommercial 4.0' "$probe_file"; then
                    target_proxy="$proxy"
                    rm -f -- "$probe_file"
                    log "使用 GitHub 代理: ${target_proxy}"
                    return
                fi
            done
            rm -f -- "$probe_file"
            log "错误: 没有可用的 GitHub 代理。可用参数 0 选择直连，或 1-5 指定代理。"
            return 1
            ;;
        *) log "错误: 代理参数必须为 0-5、9、auto 或 HTTP(S) URL。"; return 1 ;;
    esac
    log "GitHub 下载方式: ${target_proxy:-直连}"
}

function install_ffmpeg() (
    local ffmpeg_arch
    case "$(uname -m)" in
        x86_64) ffmpeg_arch=linux64 ;;
        aarch64) ffmpeg_arch=linuxarm64 ;;
        *) log "错误: 不支持的 FFmpeg 架构。"; exit 1 ;;
    esac
    local temporary_dir
    temporary_dir=$(mktemp -d)
    trap 'rm -rf -- "$temporary_dir"' EXIT
    local archive_name="ffmpeg-master-latest-${ffmpeg_arch}-gpl"
    local download_url="${target_proxy:+${target_proxy}/}https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/${archive_name}.tar.xz"
    curl -fL --connect-timeout "${NAPCAT_CONNECT_TIMEOUT:-20}" --max-time "${NAPCAT_DOWNLOAD_TIMEOUT:-1800}" \
        --proto '=http,https' --proto-redir '=http,https' "$download_url" -o "$temporary_dir/ffmpeg.tar.xz"
    tar -xf "$temporary_dir/ffmpeg.tar.xz" -C "$temporary_dir"
    "$temporary_dir/$archive_name/bin/ffmpeg" -version >/dev/null
    "$temporary_dir/$archive_name/bin/ffprobe" -version >/dev/null
    run_as_root install -d /opt/ffmpeg/bin /usr/local/bin
    run_as_root install -m 755 "$temporary_dir/$archive_name/bin/ffmpeg" "$temporary_dir/$archive_name/bin/ffprobe" /opt/ffmpeg/bin/
    run_as_root ln -sf /opt/ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
    run_as_root ln -sf /opt/ffmpeg/bin/ffprobe /usr/local/bin/ffprobe
    log "FFmpeg 安装成功。"
)

function check_and_install_dependencies() {
    local package_manager
    local missing_deps=()
    if command -v apt-get >/dev/null; then
        package_manager=apt-get
    elif command -v dnf >/dev/null; then
        package_manager=dnf
    else
        log "错误: TUI-CLI 安装脚本支持 apt-get 或 dnf。"
        return 1
    fi
    if ! command -v dialog >/dev/null; then
        missing_deps+=(dialog)
    fi
    if ! command -v jq >/dev/null; then
        missing_deps+=(jq)
    fi
    if { ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; } && [ "$package_manager" = apt-get ]; then
        missing_deps+=(ffmpeg)
    fi
    if [ ${#missing_deps[@]} -gt 0 ]; then
        if [ "$package_manager" = apt-get ]; then
            run_as_root apt-get update -y -qq
            run_as_root apt-get install -y -qq "${missing_deps[@]}"
        else
            run_as_root dnf install -y "${missing_deps[@]}"
        fi
    fi
    if { ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; } && [ "$package_manager" = dnf ]; then
        run_as_root dnf install -y tar xz
        install_ffmpeg
    fi
}

function install_cli_components() (
    network_test "${1:-9}"
    check_and_install_dependencies
    local temporary_dir
    temporary_dir=$(mktemp -d)
    trap 'rm -rf -- "$temporary_dir"' EXIT
    local base_url="https://raw.githubusercontent.com/NapNeko/NapCat-TUI-CLI/main/script/tui-cli"
    local files=(napcat _napcat_Boot _napcat_Config _napcat_old)
    local file_name
    local first_line
    for file_name in "${files[@]}"; do
        curl -fL --connect-timeout "${NAPCAT_CONNECT_TIMEOUT:-20}" --max-time "${NAPCAT_DOWNLOAD_TIMEOUT:-1800}" \
            --proto '=http,https' --proto-redir '=http,https' \
            "${target_proxy:+${target_proxy}/}${base_url}/${file_name}" -o "$temporary_dir/$file_name"
        read -r first_line < "$temporary_dir/$file_name"
        if [[ "$first_line" != '#!'* ]]; then
            log "错误: ${file_name} 不是 Shell 脚本。"
            exit 1
        fi
        bash -n "$temporary_dir/$file_name"
    done
    run_as_root install -d /usr/local/bin
    for file_name in "${files[@]}"; do
        run_as_root install -m 755 "$temporary_dir/$file_name" "/usr/local/bin/$file_name"
    done
    local config_directory="${XDG_CONFIG_HOME:-$HOME/.config}/napcat"
    mkdir -p -- "$config_directory"
    printf '%s\n' "${target_proxy:-0}" > "$temporary_dir/github-proxy"
    install -m 600 "$temporary_dir/github-proxy" "$config_directory/github-proxy"
    log "所有 TUI-CLI 组件安装/更新成功。"
)

install_cli_components "${1:-9}"
