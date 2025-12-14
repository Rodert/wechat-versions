#!/usr/bin/env bash

set -eo pipefail

# ====================================================
# 配置变量
# ====================================================
TEMP_PATH="WeChatVersions/temp"
WEBSITE_URL="https://weixin.qq.com/"
DOWNLOAD_LINKS=""
RELEASE_FILES=()  # 全局变量，存储要发布的文件列表

# ====================================================
# 函数定义
# ====================================================

# 打印分隔线
print_separator() {
    printf '%*s\n' 60 | tr ' ' '#'
}

# 彩色输出函数
echo_color() {
    local color="$1"
    shift
    local message="$*"
    case "$color" in
        yellow)
            echo -e "\033[1;33m$message\033[0m"
            ;;
        red)
            echo -e "\033[1;31m$message\033[0m" >&2
            ;;
        green)
            echo -e "\033[1;32m$message\033[0m"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# 安装依赖项
install_depends() {
    print_separator
    echo_color "yellow" "Installing dependencies: wget, curl, git, gh, shasum, jq"
    print_separator

    brew install wget curl git gh jq
}

# 从网页提取下载链接（从 JSON 数据中）
extract_download_links() {
    print_separator
    echo_color "yellow" "Extracting download links from website..."
    print_separator

    # 获取页面内容
    HTML_CONTENT=$(curl -s "$WEBSITE_URL")
    
    # 提取 JSON 数据（从 __NUXT_DATA__ 脚本标签）
    # 使用 sed 提取 script 标签中的 JSON 数据
    JSON_DATA=$(echo "$HTML_CONTENT" | sed -n 's/.*<script[^>]*id="__NUXT_DATA__"[^>]*>\[\(.*\)\]<\/script>.*/\1/p' | head -1)
    
    if [ -z "$JSON_DATA" ]; then
        # 尝试另一种方式：直接提取整个 JSON 数组
        JSON_DATA=$(echo "$HTML_CONTENT" | grep -oP '(?<=id="__NUXT_DATA__"[^>]*>\[)[^\]]+(?=\]</script>)' | head -1)
    fi
    
    if [ -z "$JSON_DATA" ]; then
        echo_color "red" "Failed to extract JSON data from website!"
        echo_color "yellow" "Trying alternative method..."
        # 使用 Python 直接从 HTML 提取
        JSON_DATA=$(echo "$HTML_CONTENT" | python3 << 'PYTHON_EXTRACT'
import re
import sys
html = sys.stdin.read()
match = re.search(r'<script[^>]*id="__NUXT_DATA__"[^>]*>(\[.*?\])</script>', html, re.DOTALL)
if match:
    print(match.group(1))
PYTHON_EXTRACT
)
    fi
    
    if [ -z "$JSON_DATA" ]; then
        echo_color "red" "Failed to extract JSON data from website!"
        clean_data 1
    fi
    
    # 使用 Python 解析 JSON（更可靠）
    echo "$JSON_DATA" | python3 << 'PYTHON_SCRIPT'
import json
import sys
import re

try:
    # 读取标准输入
    data = sys.stdin.read().strip()
    
    # 清理数据，确保是有效的 JSON
    if not data.startswith('['):
        # 尝试找到 JSON 数组部分
        match = re.search(r'\[.*\]', data, re.DOTALL)
        if match:
            data = match.group(0)
    
    # 解析 JSON
    json_data = json.loads(data)
    
    # 查找 downloadConf
    download_conf = None
    
    # 遍历 JSON 结构查找 downloadConf
    def find_download_conf(obj, path=""):
        if isinstance(obj, dict):
            if 'downloadConf' in obj:
                return obj['downloadConf']
            for key, value in obj.items():
                result = find_download_conf(value, f"{path}.{key}")
                if result:
                    return result
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                result = find_download_conf(item, f"{path}[{i}]")
                if result:
                    return result
        return None
    
    download_conf = find_download_conf(json_data)
    
    if download_conf:
        # 提取各平台下载链接
        platforms = {
            'mac': download_conf.get('mac', ''),
            'windows': download_conf.get('windows', ''),
            'android': download_conf.get('android', ''),
            'android32': download_conf.get('android32', ''),
            'ios': download_conf.get('ios', ''),
            'linux': download_conf.get('linux', '')
        }
        
        # 输出为 shell 可读的格式
        for platform, url in platforms.items():
            if url and url != 'null' and url != '':
                print(f"{platform}|{url}")
    else:
        print("ERROR: downloadConf not found", file=sys.stderr)
        sys.exit(1)
        
except Exception as e:
    print(f"ERROR: {str(e)}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}

# 下载安装包
download_package() {
    local platform="$1"
    local url="$2"
    local filename="$3"
    
    if [ -z "$url" ] || [ "$url" = "null" ] || [ "$url" = "" ]; then
        echo_color "yellow" "Skipping $platform: No download URL available"
        return 0
    fi
    
    print_separator
    echo_color "yellow" "Downloading $platform package..."
    echo_color "green" "URL: $url"
    print_separator
    
    mkdir -p "$TEMP_PATH"
    
    wget -q "$url" -O "${TEMP_PATH}/${filename}" || {
        echo_color "red" "Failed to download $platform package!"
        return 1
    }
    
    echo_color "green" "Downloaded: ${filename}"
}

# 从 Mac DMG 提取版本信息
get_mac_version() {
    local dmg_file="$1"
    
    if [ ! -f "$dmg_file" ]; then
        return 1
    fi
    
    # 挂载 dmg
    MOUNT_DIR=$(hdiutil attach "$dmg_file" -nobrowse 2>/dev/null | sed -n 's/^.*\(\/Volumes\/.*\)$/\1/p' | tail -n1)
    
    if [ -z "$MOUNT_DIR" ]; then
        return 1
    fi
    
    # 定位 Info.plist
    INFO_PLIST="${MOUNT_DIR}/WeChat.app/Contents/Info.plist"
    
    if [ ! -f "$INFO_PLIST" ]; then
        hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
        return 1
    fi
    
    # 提取版本号
    VERSION=$(grep -A1 '<key>CFBundleShortVersionString</key>' "$INFO_PLIST" | grep '<string>' | sed -E 's/.*<string>([^<]+)<\/string>.*/\1/')
    
    # 卸载 dmg
    hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
    
    echo "$VERSION"
}

# 从文件名提取版本（用于 Windows/Android）
extract_version_from_filename() {
    local filename="$1"
    # 尝试从文件名中提取版本号
    # 例如: WeChatWin_4.1.5.exe -> 4.1.5
    echo "$filename" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# 计算 SHA256
compute_sha256() {
    local file_path="$1"
    shasum -a 256 "$file_path" 2>/dev/null | awk '{print $1}'
}

# 准备所有平台的安装包
prepare_all_packages() {
    print_separator
    echo_color "yellow" "Preparing all packages..."
    print_separator
    
    # 确定版本号（优先使用 Mac 版本，因为最准确）
    MAC_VERSION=""
    if [ -f "${TEMP_PATH}/WeChatMac.dmg" ]; then
        MAC_VERSION=$(get_mac_version "${TEMP_PATH}/WeChatMac.dmg")
    fi
    
    # 如果 Mac 版本获取失败，尝试从文件名提取
    if [ -z "$MAC_VERSION" ]; then
        MAC_VERSION=$(extract_version_from_filename "WeChatMac.dmg")
    fi
    
    if [ -z "$MAC_VERSION" ]; then
        # 使用日期作为版本标识
        MAC_VERSION="unknown_$(date -u '+%Y%m%d')"
    fi
    
    VERSION_DIR="WeChatVersions/$MAC_VERSION"
    mkdir -p "$VERSION_DIR"
    
    # 处理每个平台的安装包
    declare -A PLATFORMS=(
        ["mac"]="WeChatMac.dmg"
        ["windows"]="WeChatWin.exe"
        ["android"]="WeChatAndroid.apk"
        ["android32"]="WeChatAndroid32.apk"
    )
    
    RELEASE_FILES=()  # 重置数组
    SHA256_INFO=""
    
    for platform in "${!PLATFORMS[@]}"; do
        local temp_file="${TEMP_PATH}/${PLATFORMS[$platform]}"
        if [ -f "$temp_file" ]; then
            local filename="${PLATFORMS[$platform]}"
            local versioned_filename="${filename%.*}-${MAC_VERSION}.${filename##*.}"
            
            cp "$temp_file" "$VERSION_DIR/$versioned_filename"
            
            local sha256=$(compute_sha256 "$VERSION_DIR/$versioned_filename")
            RELEASE_FILES+=("$VERSION_DIR/$versioned_filename")
            
            # 首字母大写
            local platform_cap="${platform^}"
            SHA256_INFO="${SHA256_INFO}${platform_cap}: $sha256"$'\n'
            
            echo_color "green" "$platform: $versioned_filename (SHA256: $sha256)"
        fi
    done
    
    # 创建信息文件
    cat > "$VERSION_DIR/version-info.txt" <<EOF
Version: $MAC_VERSION
UpdateTime: $(date -u '+%Y-%m-%d %H:%M:%S') (UTC)
DownloadFrom: $WEBSITE_URL

SHA256 Checksums:
$SHA256_INFO
EOF
    
    echo "$MAC_VERSION"
}

# 获取最新的 GitHub Release 信息
get_latest_release_info() {
    print_separator
    echo_color "yellow" "Getting latest GitHub release info..."
    print_separator

    LATEST_BODY=$(gh release view --json body --jq ".body" 2>/dev/null || true)

    if [ -z "$LATEST_BODY" ]; then
        LATEST_VERSION=""
    else
        LATEST_VERSION=$(echo "$LATEST_BODY" | grep 'Version:' | awk -F': ' '{print $2}' | head -1)
    fi

    echo "Latest Version: $LATEST_VERSION"
}

# 创建新的 GitHub Release
create_release() {
    local version="$1"
    shift
    local files=("$@")
    
    print_separator
    echo_color "yellow" "Creating new GitHub release..."
    print_separator

    if [ "$version" = "$LATEST_VERSION" ] && [ -n "$LATEST_VERSION" ]; then
        VERSION_TAG="${version}_$(date -u '+%Y%m%d')"
    else
        VERSION_TAG="$version"
    fi

    # 构建 release 命令
    local release_cmd="gh release create \"v$VERSION_TAG\""
    
    # 添加所有文件
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            release_cmd="$release_cmd \"$file\""
        fi
    done
    
    # 添加版本信息文件
    local info_file="WeChatVersions/$version/version-info.txt"
    if [ -f "$info_file" ]; then
        release_cmd="$release_cmd -F \"$info_file\""
    fi
    
    release_cmd="$release_cmd -t \"WeChat Multi-Platform v$VERSION_TAG\""
    
    eval "$release_cmd"
    
    if [ "$?" -eq 0 ]; then
        echo_color "green" "Release created successfully: v$VERSION_TAG"
    else
        echo_color "red" "Failed to create release!"
        clean_data 1
    fi
}

# 清理临时数据并退出
clean_data() {
    print_separator
    echo_color "yellow" "Cleaning runtime and exiting..."
    print_separator

    rm -rf "WeChatVersions/temp"
    exit "$1"
}

# ====================================================
# 主流程
# ====================================================
main() {
    # 创建临时目录
    mkdir -p "$TEMP_PATH"

    # 安装依赖项
    install_depends

    # 提取下载链接
    DOWNLOAD_LINKS=$(extract_download_links)
    
    if [ -z "$DOWNLOAD_LINKS" ]; then
        echo_color "red" "Failed to extract download links!"
        clean_data 1
    fi
    
    # 下载各平台安装包
    while IFS='|' read -r platform url; do
        case "$platform" in
            mac)
                download_package "Mac" "$url" "WeChatMac.dmg"
                ;;
            windows)
                download_package "Windows" "$url" "WeChatWin.exe"
                ;;
            android)
                download_package "Android" "$url" "WeChatAndroid.apk"
                ;;
            android32)
                download_package "Android32" "$url" "WeChatAndroid32.apk"
                ;;
        esac
    done <<< "$DOWNLOAD_LINKS"
    
    # 准备所有安装包
    VERSION=$(prepare_all_packages)
    
    # 获取最新的 GitHub Release 信息
    get_latest_release_info
    
    # 检查是否已存在相同版本
    if [ "$VERSION" = "$LATEST_VERSION" ] && [ -n "$LATEST_VERSION" ]; then
        echo_color "green" "This version already exists in releases!"
        clean_data 0
    fi
    
    # 创建新的 GitHub Release
    if [ ${#RELEASE_FILES[@]} -gt 0 ]; then
        create_release "$VERSION" "${RELEASE_FILES[@]}"
    else
        echo_color "red" "No files to release!"
        clean_data 1
    fi
    
    # 清理临时数据并退出
    clean_data 0
}

# 执行主流程
main

