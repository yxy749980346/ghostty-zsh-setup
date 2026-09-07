# Ghostty Zsh Setup

[English](readme.md)

这是一个面向 macOS 的 Ghostty 和 Zsh 环境配置脚本。它会安装常用命令行工具，配置 Ghostty 的主题、字体、外观、快捷键和窗口布局，并为 Ghostty 提供自动进度条。

脚本会保留已有的 `~/.zshrc` 内容，只更新自己标记的配置区。它不会把现有的环境变量、别名、代理、私有变量或其他 Shell 配置整体替换掉。

## 功能

- 安装或检查 Homebrew、Oh My Zsh 和常用命令行工具。
- 安装 `zsh-autosuggestions`、`zsh-syntax-highlighting` 等 Zsh 插件。
- 安装 Meslo Nerd Font 和 Ghostty 配置使用的 MesloLGS NF 字体。
- 配置 Catppuccin Mocha Purple 主题、半透明背景、窗口留白和窗口布局恢复。
- 配置全局 `Option + Space` 快捷终端。
- 配置 Starship、zoxide、yazi、lazygit 和常用别名。
- 为运行时间较长的前台命令显示 Ghostty 自动进度条。
- 使用 Ghostty 自带校验器检查生成的配置。

脚本不会自动安装 Ghostty 应用本身。请先通过官网或其他可信渠道安装 Ghostty。

## 使用前准备

- macOS。
- 使用普通用户执行脚本，不要使用 `sudo bash setup-ghostty-env.sh`。
- 系统可以使用 `zsh`、`git` 和 `curl`。
- 网络可以访问 Homebrew、GitHub、codeload、raw 和 jsDelivr。

如果尚未安装 Xcode Command Line Tools，可以先执行：

```bash
xcode-select --install
```

Homebrew 尚未安装时，完整模式会尝试安装它。安装过程可能需要输入密码或确认系统权限。

使用全局快捷终端前，需要在 macOS 的辅助功能设置中允许 Ghostty，并确认 `Option + Space` 没有与其他应用冲突。

## 快速开始

下载或克隆项目后，在项目目录执行：

```bash
# 检查脚本语法
bash -n setup-ghostty-env.sh

# 运行完整配置
bash setup-ghostty-env.sh
```

脚本默认会先显示执行计划并等待确认。确认配置范围后，也可以跳过脚本自己的确认：

```bash
bash setup-ghostty-env.sh --yes
# 或
bash setup-ghostty-env.sh -y
```

`--yes` 只跳过脚本的确认提示，不会绕过 Homebrew、系统权限或密码提示。

## 运行模式

默认模式会执行完整配置，包括 Homebrew、字体、命令行工具、Oh My Zsh、Zsh 插件、Starship、Zsh 集成和 Ghostty 配置。

如果只想配置 Ghostty，可以使用：

```bash
bash setup-ghostty-env.sh --ghostty-only
```

`--ghostty-only` 会安装 Ghostty 配置使用的 MesloLGS NF 字体，写入主题和 Ghostty 配置并执行校验，但不会：

- 安装 Homebrew、Oh My Zsh、Zsh 插件或命令行工具。
- 修改 `~/.zshrc`。
- 生成或覆盖 `~/.config/starship.toml`。

旧版本使用的 `--with-personal` 参数仍然兼容，它与默认完整模式等价。

## 配置文件处理方式

| 路径 | 处理方式 |
| --- | --- |
| `~/.zshrc` | 先备份，只删除并重新生成脚本自己的托管区，其他内容保留 |
| `~/.config/starship.toml` | 先备份，然后重新生成 Catppuccin Powerline 预设 |
| `~/.config/ghostty/config` | 先备份，然后重新生成 Ghostty 配置 |
| `~/.config/ghostty/themes/Catppuccin Mocha Purple` | 不存在时创建，已有文件保留 |
| `~/.oh-my-zsh` 和插件目录 | 不存在时安装，已有目录跳过 |
| `~/Library/Fonts` | 用于安装字体 |

`.zshrc` 中由脚本维护的区域带有以下标记：

```zsh
# >>> ghostty-zsh-setup managed >>>
# 脚本生成的 Ghostty 和 Zsh 集成
# <<< ghostty-zsh-setup managed <<<
```

脚本重复运行时，只会更新这两个标记之间的内容。标记之外的配置会保留。脚本还会检查已有的同名函数和别名，尽量避免覆盖用户自己的定义。

如果已有自定义 Starship 配置或 Ghostty 配置，请在运行前另行保存。它们会先生成带时间戳的备份，然后由脚本重新生成。

## 配置生效

Ghostty 配置保存后通常会自动热加载，也可以在 Ghostty 中按 `Cmd + Shift + ,` 重载。

Zsh 集成写入后，在当前终端执行：

```zsh
exec zsh
```

也可以直接关闭当前窗口并重新打开 Ghostty。

安装完成后，可以测试：

```zsh
z 项目目录片段    # zoxide 智能跳转
y                 # yazi 文件管理器
lg                # lazygit
ll                # ls -lah
sleep 3           # 观察自动进度条
```

Starship 和自动进度条只在 `TERM_PROGRAM=ghostty` 时启用。其他终端仍会加载 Oh My Zsh 和其他 Zsh 配置。

## 自动进度条

自动进度条表示命令仍在运行，不代表实际完成百分比。命令通常运行超过约 1.5 秒后才开始显示，短命令不会显示蓝条。检测到 TUI 或不适合探测的终端状态时，脚本会抑制自动进度条。

如果程序自己通过 OSC 9;4 管理进度，可以关闭脚本的自动进度：

```zsh
GHOSTTY_PROGRESS_AUTO=0 your-command
```

也可以在当前 Shell 中暂时关闭：

```zsh
export GHOSTTY_PROGRESS_AUTO=0

# 恢复默认行为
unset GHOSTTY_PROGRESS_AUTO
```

自动进度条的运行状态位于 `/tmp/.ghostty-progress-<UID>/`。相关终端或 worker 仍在运行时，不要手动删除其中的状态文件。

## 备份与恢复

覆盖已有配置前，脚本会生成类似下面的备份文件：

```text
~/.zshrc.bak.YYYYMMDD-HHMMSS
~/.config/starship.toml.bak.YYYYMMDD-HHMMSS
~/.config/ghostty/config.bak.YYYYMMDD-HHMMSS
```

脚本结束时会列出本次生成的备份路径。恢复时，建议先另存当前文件，再把需要恢复的备份复制回原路径，最后执行 `exec zsh` 并重载 Ghostty 配置。

这些备份只针对配置文件。脚本不会自动卸载 Homebrew 软件、字体、Oh My Zsh、插件或已经创建的主题。

## 验证与排查

检查脚本语法：

```bash
bash -n setup-ghostty-env.sh
```

检查 Ghostty 配置：

```bash
ghostty +validate-config --config-file="$HOME/.config/ghostty/config"
```

如果 Ghostty 应用位于默认位置但 `ghostty` 不在 `PATH` 中，可以执行：

```bash
/Applications/Ghostty.app/Contents/MacOS/ghostty \
  +validate-config --config-file="$HOME/.config/ghostty/config"
```

常见问题：

- 字体或图标异常：确认 Ghostty 使用的是 `MesloLGS NF` 或 `MesloLGS Nerd Font`，并重新打开 Ghostty。
- 快捷终端没有反应：检查辅助功能权限、快捷键冲突和 Ghostty 配置校验结果。
- 配置校验失败：根据已安装的 Ghostty 版本调整配置项。脚本会输出警告，但不会自动回滚已经写入的文件。
- 下载失败：检查网络以及 Homebrew、GitHub、jsDelivr 等服务是否可访问。

脚本使用上游当前内容，未固定所有依赖版本。正式使用前请审阅脚本及其下载来源。
