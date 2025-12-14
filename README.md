# WeChat Versions

自动收集和管理微信多平台历史版本的项目。

## 功能特性

- 🤖 **自动检测**：每天定时检查微信官网是否有新版本
- 📦 **多平台支持**：自动下载 Mac、Windows、Android 等多个平台的安装包
- 🔍 **版本提取**：从安装包中提取精确的版本号（Mac 从 DMG，其他从文件名）
- 🔐 **完整性校验**：计算 SHA256 哈希值，确保文件完整性
- 📤 **自动发布**：将新版本自动推送到 GitHub Release
- ⚡ **去重机制**：通过哈希值对比，避免重复发布相同版本

## 工作流程

1. GitHub Actions 每天 UTC 7:00（北京时间 15:00）自动触发
2. 脚本访问微信官网（weixin.qq.com）获取最新下载链接
3. 从页面 JSON 数据中提取各平台下载链接
4. 下载所有平台的安装包（Mac DMG、Windows EXE、Android APK 等）
5. 从 Mac DMG 提取版本信息（最准确）
6. 计算所有文件的 SHA256 校验和
7. 与最新 Release 对比，如果不同则创建新 Release
8. 清理临时文件

## 项目结构

```
wechat-versions/
├── .github/
│   └── workflows/
│       ├── destversion.yml      # GitHub Actions 工作流（Mac 单平台）
│       └── destversion-all.yml  # GitHub Actions 工作流（多平台）
├── scripts/
│   ├── destVersionForMac.sh     # Mac 单平台脚本
│   └── destVersionForAll.sh     # 多平台脚本：下载、提取版本、创建Release
├── .gitignore                   # Git 忽略文件
└── README.md                    # 项目说明文档
```

## 使用方法

### 自动运行

项目配置了 GitHub Actions，会自动运行，无需手动操作。

### 手动触发

1. 进入 GitHub 仓库的 Actions 页面
2. 选择 "WeChat Version Check" 工作流
3. 点击 "Run workflow" 手动触发

### 本地运行

如果需要本地测试：

```bash
# 1. 确保已安装依赖
brew install wget curl git gh jq python3

# 2. 登录 GitHub CLI
gh auth login

# 3. 运行脚本
# Mac 单平台版本
bash scripts/destVersionForMac.sh

# 多平台版本（推荐）
bash scripts/destVersionForAll.sh
```

## 依赖要求

- macOS 系统（用于挂载 DMG 和运行脚本）
- `wget` - 下载工具
- `curl` - HTTP 客户端
- `git` - 版本控制
- `gh` - GitHub CLI
- `jq` - JSON 解析工具（多平台脚本需要）
- `python3` - Python 3（用于解析 JSON 数据）
- `hdiutil` - macOS 系统工具（用于挂载 DMG）
- `shasum` - macOS 系统工具（用于计算哈希）

## Release 信息

每个 Release 包含：
- **多平台安装包**：
  - Mac: DMG 文件
  - Windows: EXE 文件
  - Android: APK 文件（64位和32位）
- **版本信息文件**（version-info.txt），包含：
  - 版本号（从 Mac DMG 提取，最准确）
  - 各平台 SHA256 哈希值
  - 更新时间（UTC）
  - 下载来源链接

## 支持的平台

- ✅ **macOS** - 从 DMG 提取版本信息（最准确）
- ✅ **Windows** - EXE 安装包
- ✅ **Android** - APK 安装包（64位和32位）
- ⚠️ **iOS** - 仅提供下载链接（App Store）
- ⚠️ **Linux** - 仅提供下载链接

## 注意事项

- 项目仅保留官网版本，不保留 App Store 版本
- Mac 版本从 DMG 的 Info.plist 提取，最准确
- 其他平台版本从文件名提取，可能不够精确
- 如果同一版本在同一天多次检测到，会添加日期后缀区分
- 通过 SHA256 对比避免重复发布相同文件
- 各版本更新日志可参见官网 [changelog](https://weixin.qq.com/cgi-bin/readtemplate?lang=zh_CN&t=weixin_faq_list&head=true)

## License

本项目仅用于学习和研究目的。

## 免责声明

本项目仅用于收集和保存微信历史版本，不涉及任何商业用途。如有问题或侵权，请提交 Issue 告知。
