#!/usr/bin/env bash
# =============================================================================
#  setup-ghostty-env.sh
#  Ghostty + Zsh 开发环境配置脚本 (macOS)
#
#  特性:
#    - 默认配置 Ghostty、Oh My Zsh、Starship、命令行工具和自动进度条
#    - 保留原有 ~/.zshrc: 只更新脚本自己的 Ghostty 管理区
#    - --ghostty-only 只配置 Ghostty，不触碰 Zsh 和个人命令行环境
#    - 安全覆盖: 所有被覆盖的文件均先备份为 <原路径>.bak.<时间戳>
#
#  用法:
#    bash setup-ghostty-env.sh                      # 完整配置，保留原有 ~/.zshrc
#    bash setup-ghostty-env.sh --yes                # 完整配置，免确认
#    bash setup-ghostty-env.sh --ghostty-only       # 只配置 Ghostty
# =============================================================================
set -euo pipefail

# ------------------------------- 日志与工具函数 ------------------------------
if [[ -t 1 ]]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; CYAN=$'\e[36m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
  RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; RESET=""
fi

info()  { printf '%s\n' "${CYAN}▸${RESET} $*"; }
ok()    { printf '%s\n' "${GREEN}✔${RESET} $*"; }
warn()  { printf '%s\n' "${YELLOW}⚠${RESET} $*"; }
die()   { printf '%s\n' "${RED}✗ $*${RESET}" >&2; exit 1; }
step()  { printf '\n%s\n' "${BOLD}${CYAN}━━━━ $* ━━━━${RESET}"; }

trap 'printf "%s\n" "${RED}✗ 脚本在第 ${LINENO} 行执行失败，请检查上方输出${RESET}" >&2' ERR

command_exists() { command -v "$1" &>/dev/null; }

# 网络容错: 国内网络对 github 各域名表现不一 (git 协议易挂起, codeload/raw 时通时断)。
# 所有下载统一使用带重试/超时的 curl 参数, 并提供镜像回退。
CURL_OPTS=(-fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 180)

TS="$(date +%Y%m%d-%H%M%S)"
BACKUPS=()

backup_file() {  # backup_file <路径> — 文件存在则备份
  local f="$1"
  if [[ -f "$f" ]]; then
    local dst="${f}.bak.${TS}"
    cp "$f" "$dst"
    BACKUPS+=("$dst")
    warn "已备份: $f → $dst"
  fi
}

GHOSTTY_ZSH_MARK_BEGIN="# >>> ghostty-zsh-setup managed >>>"
GHOSTTY_ZSH_MARK_END="# <<< ghostty-zsh-setup managed <<<"

install_managed_zsh_block() {  # install_managed_zsh_block <~/.zshrc> <临时配置块>
  local target="$1" block="$2" tmp target_mode=

  if [[ -e "$target" && ! -f "$target" ]]; then
    die "~/.zshrc 不是普通文件，已停止以避免覆盖: $target"
  fi

  tmp="$(mktemp -t ghostty-zshrc)"
  if [[ -f "$target" ]]; then
    backup_file "$target"
    target_mode="$(stat -f '%Lp' "$target")"
    if grep -Fq -- "$GHOSTTY_ZSH_MARK_BEGIN" "$target" \
        && grep -Fq -- "$GHOSTTY_ZSH_MARK_END" "$target"; then
      awk -v begin="$GHOSTTY_ZSH_MARK_BEGIN" -v end="$GHOSTTY_ZSH_MARK_END" '
        $0 == begin { inside = 1; next }
        $0 == end { inside = 0; next }
        !inside { print }
      ' "$target" > "$tmp"
    else
      cp "$target" "$tmp"
    fi
    if [[ -s "$tmp" ]]; then
      printf '\n\n' >> "$tmp"
    fi
  fi

  cat "$block" >> "$tmp"
  if [[ -n "$target_mode" ]]; then
    chmod "$target_mode" "$tmp"
  fi
  if [[ -L "$target" ]]; then
    cp "$tmp" "$target"
    rm -f "$tmp"
  else
    mv "$tmp" "$target"
  fi
  rm -f "$block"
}

usage() {
  cat <<'USAGE'
用法:
  bash setup-ghostty-env.sh [--yes|-y]
  bash setup-ghostty-env.sh --ghostty-only [--yes|-y]

默认执行完整配置，同时保留 ~/.zshrc 原有内容，只更新脚本自己的 Ghostty 管理区。
--ghostty-only 只配置 Ghostty，不安装 Oh My Zsh、插件或命令行工具。
USAGE
}

ASSUME_YES=0
WITH_PERSONAL=1
for arg in "$@"; do
  case "$arg" in
    --yes|-y)
      ASSUME_YES=1
      ;;
    --with-personal)
      # 兼容旧版本参数；完整配置现在就是默认行为。
      WITH_PERSONAL=1
      ;;
    --ghostty-only)
      WITH_PERSONAL=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "未知参数: $arg"
      ;;
  esac
done

if (( WITH_PERSONAL )); then
  TOTAL_STEPS=8
  GHOSTTY_STEP=7
  DONE_STEP=8
else
  TOTAL_STEPS=4
  GHOSTTY_STEP=3
  DONE_STEP=4
fi

# ------------------------------- 0. 预检与确认 -------------------------------
step "0/${TOTAL_STEPS} 预检"
[[ "$(uname -s)" == "Darwin" ]] || die "本脚本仅支持 macOS"
command_exists curl || die "未检测到 curl"
if (( WITH_PERSONAL )); then
  command_exists zsh || die "未检测到 zsh (macOS 自带，请勿使用异常的精简环境)"
  command_exists git || die "未检测到 git，请先执行: xcode-select --install"
  ok "macOS $(sw_vers -productVersion) · $(uname -m) · zsh $(zsh --version | awk '{print $2}')"
else
  ok "macOS $(sw_vers -productVersion) · $(uname -m)"
fi

if (( ! ASSUME_YES )); then
  if (( WITH_PERSONAL )); then
    cat <<'PLAN'

即将执行的操作:
  1. 检查/安装 Homebrew
  2. 安装 Nerd Font 字体
  3. 安装命令行工具
  4. 安装 Oh My Zsh
  5. 安装 Zsh 插件
  6. 保留 ~/.zshrc 原文，更新脚本自己的 Ghostty 集成区
  7. 生成 Starship 和 Ghostty 配置，并校验 Ghostty
  8. 完成
PLAN
  else
    cat <<'PLAN'

即将执行的操作:
  1. 准备 Ghostty 使用的 MesloLGS NF 字体
  2. 写入 ~/.config/ghostty/themes/Catppuccin Mocha Purple
  3. 写入 ~/.config/ghostty/config (覆盖前自动备份)
  4. 使用 ghostty +validate-config 校验配置
PLAN
  fi
  local_reply=""
  read -r -p "继续? [y/N] " local_reply
  [[ "$local_reply" =~ ^[yY]$ ]] || die "已取消，未做任何修改"
fi

mkdir -p "$HOME/Library/Fonts"

if (( WITH_PERSONAL )); then
  # ----------------------------- 1. Homebrew ---------------------------------
  step "1/8 Homebrew"
  if ! command_exists brew; then
    info "未检测到 Homebrew，开始安装 (可能需要输入密码)……"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  # 将 brew 纳入当前脚本环境 (Apple Silicon: /opt/homebrew, Intel: /usr/local)
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  command_exists brew || die "Homebrew 安装/定位失败"
  ok "Homebrew $(brew --version | head -n1 | awk '{print $2}') → $(command -v brew)"

  # ----------------------------- 2. Nerd Font --------------------------------
  step "2/8 Nerd Font 字体"
  if brew list --cask font-meslo-lg-nerd-font &>/dev/null; then
    ok "已安装 (brew): font-meslo-lg-nerd-font"
  else
    info "安装 (brew cask): font-meslo-lg-nerd-font ……"
    if ! brew install --cask font-meslo-lg-nerd-font; then
      warn "直接安装失败，尝试补充 homebrew/cask-fonts tap 后重试……"
      brew tap homebrew/cask-fonts 2>/dev/null || true
      brew install --cask font-meslo-lg-nerd-font
    fi
  fi
else
  step "1/${TOTAL_STEPS} Ghostty 字体"
  info "Ghostty-only 模式跳过 Homebrew，仅安装配置中使用的 MesloLGS NF 字体。"
fi

# 注意: brew 此 cask 装出的字体族名是 "MesloLGS Nerd Font"，而 Ghostty 配置中要求的
# "MesloLGS NF" 是 romkatv (powerlevel10k) 发布的另一套同源字体 —— 族名不同。
# 为使 font-family = "MesloLGS NF" 真正生效，这里额外安装 romkatv 版的 4 个字重。
MESLO_DIR="$HOME/Library/Fonts"
if [[ -f "$MESLO_DIR/MesloLGS NF Regular.ttf" ]]; then
  ok "已安装: MesloLGS NF (romkatv 版)"
else
  info "安装 MesloLGS NF (romkatv/powerlevel10k-media)……"
  for style in "Regular" "Bold" "Italic" "Bold Italic"; do
    enc="${style// /%20}"
    out="$MESLO_DIR/MesloLGS NF ${style}.ttf"
    # 首选 jsdelivr CDN 镜像, 失败回退 github 直连
    curl "${CURL_OPTS[@]}" -o "$out" \
      "https://cdn.jsdelivr.net/gh/romkatv/powerlevel10k-media@master/MesloLGS%20NF%20${enc}.ttf" ||
      curl "${CURL_OPTS[@]}" -o "$out" \
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20${enc}.ttf"
    [[ -s "$out" ]] || die "字体下载失败: $style"
    ok "  已安装: MesloLGS NF ${style}"
  done
fi

configure_personal_environment() {
# ------------------------------- 3. CLI 工具 ---------------------------------
step "3/8 命令行工具 (brew)"
FORMULAS=(starship zoxide yazi lazygit ripgrep fd jq poppler imagemagick ffmpegthumbnailer)
for f in "${FORMULAS[@]}"; do
  if brew list --formula "$f" &>/dev/null; then
    ok "已安装: $f"
  else
    info "安装: $f ……"
    brew install "$f"
  fi
done

# ------------------------------- 4. Oh My Zsh --------------------------------
step "4/8 Oh My Zsh"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  ok "已安装: ~/.oh-my-zsh"
else
  # 首选 codeload tarball 直装 (curl 稳定); git 协议在本机网络下易挂起, 仅作兜底
  info "安装 Oh My Zsh (codeload tarball)……"
  OMZ_TMP="$(mktemp -d)"
  if curl "${CURL_OPTS[@]}" -o "$OMZ_TMP/omz.tar.gz" \
       "https://codeload.github.com/ohmyzsh/ohmyzsh/tar.gz/refs/heads/master" \
     && tar -xzf "$OMZ_TMP/omz.tar.gz" -C "$OMZ_TMP"; then
    mv "$OMZ_TMP/ohmyzsh-master" "$HOME/.oh-my-zsh"
    mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
    ok "已安装: ~/.oh-my-zsh (master tarball)"
  else
    warn "tarball 下载失败，回退官方安装脚本……"
    RUNZSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl "${CURL_OPTS[@]}" https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi
  rm -rf "$OMZ_TMP"
fi

# ------------------------------- 5. Zsh 插件 ---------------------------------
step "5/8 Zsh 插件"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
install_plugin() {  # install_plugin <名称> <github 仓库地址>
  local name="$1" url="$2"
  local dir="$ZSH_CUSTOM/plugins/$name"
  if [[ -d "$dir" ]]; then
    ok "已安装插件: $name"
    return 0
  fi
  local repo="${url#https://github.com/}"   # → owner/repo[.git]
  repo="${repo%.git}"
  local tmp; tmp="$(mktemp -d)"
  info "安装插件: $name (codeload tarball)……"
  if curl "${CURL_OPTS[@]}" -o "$tmp/p.tar.gz" \
       "https://codeload.github.com/${repo}/tar.gz/refs/heads/master" \
     && tar -xzf "$tmp/p.tar.gz" -C "$tmp"; then
    mkdir -p "$ZSH_CUSTOM/plugins"
    mv "$tmp/${name}-master" "$dir"
    ok "已安装插件: $name"
  else
    warn "tarball 下载失败，回退 git clone……"
    mkdir -p "$ZSH_CUSTOM/plugins"
    git clone --depth=1 "$url" "$dir"
  fi
  rm -rf "$tmp"
}
install_plugin "zsh-autosuggestions"   "https://github.com/zsh-users/zsh-autosuggestions"
install_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"

# ------------------------------- 6. ~/.zshrc ---------------------------------
step "6/8 更新 ~/.zshrc 中的 Ghostty 集成"
GHOSTTY_ZSH_BLOCK="$(mktemp -t ghostty-zsh-block)"
cat > "$GHOSTTY_ZSH_BLOCK" <<'ZSHRC'
# >>> ghostty-zsh-setup managed >>>

# ---------- Homebrew ----------
if [[ "$(uname -m)" == "arm64" && -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ---------- Oh My Zsh ----------
if [[ -r "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
  export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
  typeset -ga plugins
  for ghostty_plugin in git zsh-autosuggestions zsh-syntax-highlighting; do
    if [[ " ${plugins[*]} " != *" $ghostty_plugin "* ]]; then
      plugins+=("$ghostty_plugin")
    fi
  done
  unset ghostty_plugin
  if [[ -z "${ZSH_THEME+x}" ]]; then
    ZSH_THEME=""
  fi
  if [[ -z "${_GHOSTTY_ZSH_SETUP_OMZ_LOADED:-}" ]] \
      && (( ! ${+functions[omz]} )); then
    source "$ZSH/oh-my-zsh.sh"
  fi
  typeset -g _GHOSTTY_ZSH_SETUP_OMZ_LOADED=1
fi

# OMZ 已经在原有 ~/.zshrc 中加载时，补充尚未加载的插件；已加载的插件不重复 source。
if [[ -r "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] \
    && (( ! ${+functions[_zsh_autosuggest_start]} )); then
  source "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
if [[ -r "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] \
    && (( ! ${+functions[zsh_highlight]} )); then
  source "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# ---------- Starship (仅 Ghostty 生效) ----------
if [[ "$TERM_PROGRAM" == "ghostty" ]] && command -v starship >/dev/null 2>&1 \
    && (( ! ${+functions[starship_precmd]} )); then
  eval "$(starship init zsh)"
fi

# ---------- zoxide (z 智能跳转) ----------
if command -v zoxide >/dev/null 2>&1 \
    && (( ! ${+aliases[z]} && ! ${+functions[z]} )); then
  eval "$(zoxide init zsh)"
fi

# ---------- yazi (退出跟随目录) ----------
if command -v yazi >/dev/null 2>&1 \
    && (( ! ${+functions[y]} && ! ${+aliases[y]} )); then
  function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [[ -n "$cwd" ]] && [[ "$cwd" != "$PWD" ]]; then
      builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
  }
fi

# ---------- 常用别名 ----------
if (( ! ${+aliases[ll]} && ! ${+functions[ll]} )); then
  alias ll='ls -lah'
fi
if command -v lazygit >/dev/null 2>&1 \
    && (( ! ${+aliases[lg]} && ! ${+functions[lg]} )); then
  alias lg='lazygit'
fi

# ---------- 前台命令进度条 (仅 Ghostty; 延迟 + termios 探测, 零名单) ----------
if (( ! ${+functions[_ghostty_progress_on]} )); then
# 命令活过 1.5s 后开始探测；raw-mode TUI 每秒复查，显示期间约每 8 秒保活一次。
# Ghostty macOS 会在最后一次进度上报 15 秒后清除状态；显式豁免命令登记共享 native 所有权。
# 一整条输入（含管道、&& 和 ;）只要有子命令显式豁免，就整体交给程序管理进度。
# 自带 OSC 9;4 的命令可用 `GHOSTTY_PROGRESS_AUTO=0 command` 交出进度状态所有权。
# marker + stop 目录负责收尾；父 shell 不跨命令保存 FD，也不关闭缓存的数字 FD。
# worker 在干净的非交互 zsh 中启动并关闭继承 FD，避免脚本等待 EOF 时形成环路。
# 每个 TTY 的状态锁和单调序号会在嵌套 shell 之间选出最新活动命令。
() {
  emulate -L zsh
  setopt noerrexit nobgnice
  local REPLY REPLY2 REPLY3
  local progress_dir
  local previous_progress_version="${_GHOSTTY_PROGRESS_PROTOCOL_VERSION:-0}"
  local -i legacy_progress=0

  # 先禁用旧版基于导出 PID 的信号路径。未知旧版可能操作已复用的数字 FD，绝不调用。
  unset GHOSTTY_PROGRESS_PARENT_WORKER_PID GHOSTTY_PROGRESS_PARENT_SHELL_PID

  # 无条件卸载上一版：即使 TERM_PROGRAM 已改变，重复 source 也能真正关闭功能。
  if [[ "$previous_progress_version" == 3 || "$previous_progress_version" == 4 \
        || "$previous_progress_version" == 5 ]] \
      && (( ${+functions[_ghostty_progress_off]} )); then
    _ghostty_progress_off
  elif (( ${+functions[_ghostty_progress_off]} || ${+functions[_progress_off]} )); then
    legacy_progress=1
  fi

  typeset -ga preexec_functions precmd_functions zshexit_functions
  preexec_functions=("${(@)preexec_functions[@]:#_progress_on}")
  preexec_functions=("${(@)preexec_functions[@]:#_ghostty_progress_on}")
  precmd_functions=("${(@)precmd_functions[@]:#_progress_off}")
  precmd_functions=("${(@)precmd_functions[@]:#_ghostty_progress_off}")
  zshexit_functions=("${(@)zshexit_functions[@]:#_ghostty_progress_off}")

  unfunction -m '_ghostty_progress_*' 2>/dev/null
  unfunction _prog_is_tui _progress_worker _progress_on _progress_off 2>/dev/null
  unset _prog_fd _GHOSTTY_PROGRESS_WORKER_PROGRAM _GHOSTTY_PROGRESS_WORKER_FILE
  unset _GHOSTTY_PROGRESS_TTY_NAME
  unset _GHOSTTY_PROGRESS_OWNER_PID _GHOSTTY_PROGRESS_OWNER_IDENTITY
  unset _GHOSTTY_PROGRESS_SUPPRESSED_PID
  unset _GHOSTTY_PROGRESS_RECONCILE_PID
  unset _GHOSTTY_PROGRESS_PROTOCOL_VERSION

  # 未知旧版只做路径定向的幂等清屏；旧 marker 稍后由新协议清理。
  (( legacy_progress )) \
    && { builtin print -rn -- $'\e]9;4;0\a' >/dev/tty } 2>/dev/null

  [[ "$TERM_PROGRAM" == "ghostty" ]] || return 0
  zmodload zsh/zselect 2>/dev/null || return 0
  zmodload zsh/system 2>/dev/null || return 0

  _ghostty_progress_resolve_tty() {
    emulate -L zsh
    local tty_id tty_key tty_device tty_hint="${TTY:-}" shell_pid="$sysparams[pid]"

    # $TTY 可被 wrapper 改写成通用 /dev/tty；ps 返回真正的控制终端标识。
    # 必须在进入命令替换前捕获 PID，否则 sysparams[pid] 会变成短命替换子进程自身。
    tty_id="$(LC_ALL=C /bin/ps -p "$shell_pid" -o tty= 2>/dev/null)" || tty_id=
    tty_id="${tty_id//[[:space:]]/}"
    if [[ -z "$tty_id" || "$tty_id" == '??' || "$tty_id" == -* || "$tty_id" == /* \
          || "$tty_id" == ./* || "$tty_id" == */./* || "$tty_id" == */. \
          || "$tty_id" == */ || "$tty_id" == *//* || "$tty_id" == *..* \
          || "$tty_id" == *[^[:alnum:]_./-]* \
          || ! -c "/dev/$tty_id" ]]; then
      # ps 瞬时不可用时只接受具体设备节点；永不把通用 /dev/tty 映射到共享目录。
      [[ "$tty_hint" == /dev/* && "$tty_hint" != /dev/tty && ! -L "$tty_hint" \
            && -c "$tty_hint" ]] || return 1
      tty_id="${tty_hint#/dev/}"
      [[ -n "$tty_id" && "$tty_id" != -* && "$tty_id" != /* && "$tty_id" != ./* \
            && "$tty_id" != */./* && "$tty_id" != */. && "$tty_id" != */ \
            && "$tty_id" != *//* && "$tty_id" != *..* \
            && "$tty_id" != *[^[:alnum:]_./-]* ]] || return 1
    fi
    tty_device="/dev/$tty_id"
    [[ -c "$tty_device" && ! -L "$tty_device" ]] || return 1
    # 百分号不在允许字符集中，因此 %2F 是无歧义的斜杠编码。
    tty_key="v5-${tty_id//\//%2F}"
    [[ -n "$tty_key" && "$tty_key" != */* ]] || return 1
    REPLY="$tty_key"
    REPLY2="$tty_device"
  }

  if ! _ghostty_progress_resolve_tty; then
    unfunction -m '_ghostty_progress_*' 2>/dev/null
    return 0
  fi
  typeset -g _GHOSTTY_PROGRESS_TTY_NAME="$REPLY"
  unfunction _ghostty_progress_resolve_tty 2>/dev/null

  _ghostty_progress_state_dir() {
    emulate -L zsh
    local root="/tmp/.ghostty-progress-${EUID}"
    local tty_name="${_GHOSTTY_PROGRESS_TTY_NAME:-}"
    local dir

    [[ -n "$tty_name" && "$tty_name" != . && "$tty_name" != .. && "$tty_name" != */* ]] || return 1
    dir="$root/$tty_name"
    [[ -d "$root" && ! -L "$root" && -O "$root" ]] || return 1
    [[ -f "$root/state.lock" && ! -L "$root/state.lock" && -O "$root/state.lock" ]] || return 1
    [[ -d "$dir" && ! -L "$dir" && -O "$dir" ]] || return 1
    [[ -f "$dir/output.lock" && ! -L "$dir/output.lock" && -O "$dir/output.lock" ]] || return 1
    [[ -f "$dir/sequence" && ! -L "$dir/sequence" && -O "$dir/sequence" ]] || return 1
    REPLY="$dir"
  }

  _ghostty_progress_owner_identity() {
    emulate -L zsh
    local owner="$1" identity

    [[ "$owner" == <1-> ]] || return 1
    # 启动时间之外再绑定进程组和控制终端，进一步压缩秒级 PID 复用窗口。
    identity="$(LC_ALL=C /bin/ps -p "$owner" -o lstart= -o pgid= -o tty= 2>/dev/null)" \
      || return 1
    [[ -n "${identity//[[:space:]]/}" ]] || return 1
    REPLY="$identity"
  }

  _ghostty_progress_owner_alive() {
    emulate -L zsh
    local owner="$1" expected_identity="$2" current_identity

    builtin kill -0 "$owner" 2>/dev/null || return 1
    # 新协议不接受空身份，避免永久退化为仅 PID 校验。
    [[ -n "$expected_identity" ]] || return 1
    if _ghostty_progress_owner_identity "$owner"; then
      current_identity="$REPLY"
      [[ "$current_identity" == "$expected_identity" ]]
    else
      # 扫描/清理路径遇到瞬时失败先保留 marker；worker 写入路径另有严格三态校验。
      return 0
    fi
  }

  _ghostty_progress_remove_stop() {
    emulate -L zsh
    local stop="$1"

    if [[ -d "$stop" && ! -L "$stop" ]]; then
      /bin/rmdir "$stop" 2>/dev/null
    else
      /bin/rm -f "$stop" 2>/dev/null
    fi
  }

  _ghostty_progress_remove_marker() {
    emulate -L zsh
    local marker="$1"
    local -i remove_status=0

    /bin/rm -f "$marker" 2>/dev/null || remove_status=1
    _ghostty_progress_remove_stop "$marker.stop" || remove_status=1
    return "$remove_status"
  }

  _ghostty_progress_prepare_dir() {
    emulate -L zsh
    local root="/tmp/.ghostty-progress-${EUID}"
    local tty_name="${_GHOSTTY_PROGRESS_TTY_NAME:-}"
    local dir marker stop owner identity
    local shell_pid="$sysparams[pid]"

    [[ -n "$tty_name" && "$tty_name" != . && "$tty_name" != .. && "$tty_name" != */* ]] || return 1
    # 先确认控制终端仍可用，避免已退出 worker 重新创建已死亡 PTY 的状态目录。
    { : </dev/tty } 2>/dev/null || return 1
    { : >/dev/tty } 2>/dev/null || return 1
    if [[ -e "$root" ]]; then
      [[ -d "$root" && ! -L "$root" && -O "$root" ]] || return 1
    else
      /bin/mkdir -m 700 "$root" 2>/dev/null || return 1
    fi
    /bin/chmod 700 "$root" 2>/dev/null || return 1

    if [[ ! -e "$root/state.lock" ]]; then
      ( setopt localoptions noclobber; : > "$root/state.lock" ) 2>/dev/null || :
    fi
    [[ -f "$root/state.lock" && ! -L "$root/state.lock" && -O "$root/state.lock" ]] || return 1
    /bin/chmod 600 "$root/state.lock" 2>/dev/null || return 1

    dir="$root/$tty_name"
    (
      zsystem flock -t 0.2 -i 0.01 "$root/state.lock" 2>/dev/null || exit 1
      if [[ -e "$dir" ]]; then
        [[ -d "$dir" && ! -L "$dir" && -O "$dir" ]] || exit 1
      else
        /bin/mkdir -m 700 "$dir" 2>/dev/null || exit 1
      fi
      /bin/chmod 700 "$dir" 2>/dev/null || exit 1

      if [[ -e "$dir/output.lock" ]]; then
        [[ -f "$dir/output.lock" && ! -L "$dir/output.lock" && -O "$dir/output.lock" ]] || exit 1
      else
        ( setopt localoptions noclobber; : > "$dir/output.lock" ) 2>/dev/null || exit 1
      fi
      /bin/chmod 600 "$dir/output.lock" 2>/dev/null || exit 1

      if [[ -e "$dir/sequence" ]]; then
        [[ -f "$dir/sequence" && ! -L "$dir/sequence" && -O "$dir/sequence" ]] || exit 1
      else
        ( setopt localoptions noclobber; print -r -- 0 > "$dir/sequence" ) 2>/dev/null || exit 1
      fi
      /bin/chmod 600 "$dir/sequence" 2>/dev/null || exit 1
    ) || return 1

    _ghostty_progress_state_dir || return 1
    dir="$REPLY"

    # 锁只存在于这个短命子进程；退出时由内核释放，从不按数字 FD 显式解锁。
    # 清理崩溃遗留的 marker；exec zsh 会保留 PID，因此也清理当前 shell 的旧项。
    (
      # 初始化清理是尽力而为；偶发争用交给后续 reconcile/worker 收尾，不阻塞 shell 启动。
      zsystem flock -t 0 "$dir/output.lock" 2>/dev/null || exit 1
      for marker in "$dir"/*.state(N); do
        if ! _ghostty_progress_marker_owner "$marker"; then
          _ghostty_progress_remove_marker "$marker"
          continue
        fi
        owner="$REPLY"
        identity="$REPLY2"
        if [[ "$owner" == "$shell_pid" ]] \
            || ! _ghostty_progress_owner_alive "$owner" "$identity"; then
          _ghostty_progress_remove_marker "$marker"
        fi
      done
      for stop in "$dir"/*.state.stop(N); do
        [[ -f "${stop%.stop}" ]] || _ghostty_progress_remove_stop "$stop"
      done
      exit 0
    ) || :
    REPLY="$dir"
  }

  _ghostty_progress_cleanup_state_dirs() {
    emulate -L zsh
    local root="/tmp/.ghostty-progress-${EUID}" current_dir="$1"
    local dir name tty_id tty_device

    [[ -d "$root" && ! -L "$root" && -O "$root" ]] || return 0
    [[ -f "$root/state.lock" && ! -L "$root/state.lock" && -O "$root/state.lock" ]] || return 0
    (
      # 历史目录回收完全是尽力而为；任何争用都立即跳过，不能拖慢新 shell 启动。
      zsystem flock -t 0 "$root/state.lock" 2>/dev/null || exit 0
      for dir in "$root"/*(/N); do
        [[ "$dir" != "$current_dir" && -d "$dir" && ! -L "$dir" && -O "$dir" ]] || continue
        name="${dir:t}"
        if [[ "$name" == v5-* ]]; then
          tty_id="${name#v5-}"
          tty_id="${tty_id//\%2F//}"
        elif [[ "$name" == ttys<-> ]]; then
          # 只回收能无歧义映射回设备的 macOS v3/v4 遗留目录。
          tty_id="$name"
        else
          continue
        fi
        [[ -n "$tty_id" && "$tty_id" != -* && "$tty_id" != /* && "$tty_id" != *..* \
              && "$tty_id" != *[^[:alnum:]_./-]* ]] || continue
        tty_device="/dev/$tty_id"
        # PTY 仍存在就可能有处于提示符的 shell；绝不回收其目录。
        [[ -c "$tty_device" ]] && continue
        # 每个目录单独用短命子进程持锁，避免扫描很多历史目录时累积锁 FD。
        (
          local marker stop entry base owner identity
          local -a entries
          local -i known=1 has_marker=0

          [[ -f "$dir/output.lock" && ! -L "$dir/output.lock" && -O "$dir/output.lock" ]] || exit 0
          [[ -f "$dir/sequence" && ! -L "$dir/sequence" && -O "$dir/sequence" ]] || exit 0
          zsystem flock -t 0 "$dir/output.lock" 2>/dev/null || exit 0
          [[ ! -c "$tty_device" ]] || exit 0

          # 死 PTY 中的无效或失去原进程身份的 marker 不应永久阻止目录回收。
          for marker in "$dir"/*.state(N); do
            if ! _ghostty_progress_marker_owner "$marker"; then
              _ghostty_progress_remove_marker "$marker"
              continue
            fi
            owner="$REPLY"
            identity="$REPLY2"
            if ! _ghostty_progress_owner_alive "$owner" "$identity"; then
              _ghostty_progress_remove_marker "$marker"
              continue
            fi
            has_marker=1
          done
          for stop in "$dir"/*.state.stop(N); do
            [[ -f "${stop%.stop}" ]] || _ghostty_progress_remove_stop "$stop"
          done
          (( has_marker )) && exit 0

          entries=("$dir"/*(DN))
          for entry in "${entries[@]}"; do
            base="${entry:t}"
            case "$base" in
              output.lock|sequence|worker-v<->.zsh|.worker-v<->.*|.marker-v5.*)
                [[ -f "$entry" && ! -L "$entry" && -O "$entry" ]] || known=0
                ;;
              *.state.stop)
                [[ ! -L "$entry" && -O "$entry" && ( -f "$entry" || -d "$entry" ) ]] || known=0
                ;;
              *)
                known=0
                ;;
            esac
            (( known )) || break
          done
          (( known )) || exit 0

          for entry in "${entries[@]}"; do
            case "${entry:t}" in
              *.state.stop)
                _ghostty_progress_remove_stop "$entry" || known=0
                ;;
              worker-v<->.zsh|.worker-v<->.*|.marker-v5.*)
                /bin/rm -f "$entry" 2>/dev/null || known=0
                ;;
            esac
          done
          (( known )) || exit 0
          entries=("$dir"/*(DN))
          for entry in "${entries[@]}"; do
            case "${entry:t}" in
              output.lock|sequence) ;;
              *) known=0 ;;
            esac
            (( known )) || break
          done
          (( known )) || exit 0
          /bin/rm -f "$dir/sequence" 2>/dev/null || exit 0
          /bin/rm -f "$dir/output.lock" 2>/dev/null || exit 0
          /bin/rmdir "$dir" 2>/dev/null
        )
      done
    ) || :
    return 0
  }

  _ghostty_progress_emit() {
    emulate -L zsh
    local payload tty_fd
    local -i written=0 write_status=1
    case "$1" in
      on)  payload=$'\e]9;4;3;0\a' ;;
      off) payload=$'\e]9;4;0\a' ;;
      *)   return 1 ;;
    esac
    # 每次动态取得专用、非阻塞且 close-on-exec 的 FD；不依赖可能已复用的缓存编号。
    sysopen -w -o cloexec,nonblock -u tty_fd /dev/tty 2>/dev/null || return 1
    syswrite -c written -o "$tty_fd" "$payload" 2>/dev/null
    write_status=$?
    exec {tty_fd}>&- 2>/dev/null
    (( write_status == 0 && written == ${#payload} ))
  }

  _ghostty_progress_is_tui() {
    emulate -L zsh
    local tty_state
    tty_state="$( { LC_ALL=C /bin/stty -a </dev/tty } 2>/dev/null )" || return 1
    [[ " $tty_state " == *[[:space:]]-icanon[[:space:]]* \
        || " $tty_state " == *[[:space:]]-echo[[:space:]]* ]]
  }

  _ghostty_progress_token_valid() {
    emulate -L zsh
    local token="$1" generation rest owner random digits

    generation="${token%%.*}"
    rest="${token#*.}"
    [[ "$rest" != "$token" ]] || return 1
    owner="${rest%%.*}"
    random="${rest#*.}"
    [[ "$random" != "$rest" && "$random" != *.* ]] || return 1
    if [[ "$generation" == g<0-> ]]; then
      digits="${generation#g}"
      [[ ${#digits} == 20 ]] || return 1
      # 后续会转成 zsh 的有符号整数；先拒绝会溢出的伪造/损坏 token。
      [[ "$digits" < 09223372036854775807 ]] || return 1
    else
      # 兼容热升级时仍在运行的旧时间戳 marker。
      [[ "$generation" == <0-> ]] || return 1
    fi
    [[ "$owner" == <1-> && "$random" == <0-> ]]
  }

  _ghostty_progress_marker_owner() {
    emulate -L zsh
    local marker="$1" name token rest token_owner owner identity mode

    [[ -f "$marker" && ! -L "$marker" && -O "$marker" ]] || return 1
    name="${marker:t}"
    [[ "$name" == *.state ]] || return 1
    token="${name%.state}"
    _ghostty_progress_token_valid "$token" || return 1
    rest="${token#*.}"
    token_owner="${rest%%.*}"
    owner=
    identity=
    mode=auto
    {
      IFS= read -r owner || return 1
      IFS= read -r identity || identity=
      # 旧 v5 marker 只有两行；第三行是向后兼容的进度所有权类型。
      IFS= read -r mode || mode=auto
    } < "$marker" 2>/dev/null
    [[ "$owner" == "$token_owner" ]] || return 1
    [[ -n "${identity//[[:space:]]/}" && ( "$mode" == auto || "$mode" == native ) ]] || return 1
    REPLY="$owner"
    REPLY2="$identity"
    REPLY3="$mode"
  }

  # 必须在持有 output.lock 时调用。返回序号最大的、未停止且 owner 存活的 marker。
  _ghostty_progress_current_marker_locked() {
    emulate -L zsh
    local dir="$1" marker stop token owner identity current_token= current_marker=
    local trusted_marker="${2:-}" trusted_owner="${3:-}" trusted_identity="${4:-}"

    for marker in "$dir"/*.state(N); do
      if ! _ghostty_progress_marker_owner "$marker"; then
        _ghostty_progress_remove_marker "$marker"
        continue
      fi
      owner="$REPLY"
      identity="$REPLY2"
      # worker 刚在同一轮完整校验过自己时复用结果，避免每秒为同一 PID fork 两次 ps。
      if [[ "$marker" == "$trusted_marker" && "$owner" == "$trusted_owner" \
            && "$identity" == "$trusted_identity" ]]; then
        :
      elif ! _ghostty_progress_owner_alive "$owner" "$identity"; then
        _ghostty_progress_remove_marker "$marker"
        continue
      fi
      [[ -e "$marker.stop" ]] && continue
      token="${${marker:t}%.state}"
      if [[ -z "$current_token" || "$token" > "$current_token" ]]; then
        current_token="$token"
        current_marker="$marker"
      fi
    done
    for stop in "$dir"/*.state.stop(N); do
      [[ -f "${stop%.stop}" ]] || _ghostty_progress_remove_stop "$stop"
    done
    REPLY="$current_marker"
    [[ -n "$current_marker" ]]
  }

  # 必须在持有 output.lock 时调用。序号只在锁内递增，避免时钟回拨和并发乱序。
  _ghostty_progress_next_token_locked() {
    emulate -L zsh
    local dir="$1" token_owner="$2" raw= generation digits padded marker token
    local -i sequence=0 candidate=0

    [[ "$token_owner" == <1-> ]] || return 1

    { IFS= read -r raw < "$dir/sequence" } 2>/dev/null
    if [[ "$raw" == <0-> && ( ${#raw} -lt 19 \
          || ( ${#raw} -eq 19 && "$raw" < 9223372036854775807 ) ) ]]; then
      (( sequence = 10#$raw ))
    fi
    for marker in "$dir"/g*.state(N.); do
      [[ -e "$marker.stop" ]] && continue
      # 兼容热升级前的最高代次 native 预约，不能污染正常命令的单调计数器。
      if _ghostty_progress_marker_owner "$marker" && [[ "$REPLY3" == native ]]; then
        continue
      fi
      token="${${marker:t}%.state}"
      _ghostty_progress_token_valid "$token" || continue
      generation="${token%%.*}"
      digits="${generation#g}"
      (( candidate = 10#$digits ))
      (( candidate > sequence )) && sequence=$candidate
    done
    (( sequence < 9223372036854775806 )) || return 1
    (( ++sequence ))
    printf -v padded '%020d' "$sequence" || return 1
    { builtin print -r -- "$sequence" >| "$dir/sequence" } 2>/dev/null || return 1
    REPLY="g${padded}.${token_owner}.${RANDOM}"
  }

  _ghostty_progress_request_stop() {
    emulate -L zsh
    local marker="$1" stop="$1.stop"

    [[ -f "$marker" && ! -L "$marker" && -O "$marker" ]] || return 0
    if [[ -e "$stop" ]]; then
      if [[ ! -L "$stop" && -O "$stop" && ( -d "$stop" || -f "$stop" ) ]]; then
        [[ -f "$marker" ]] || _ghostty_progress_remove_stop "$stop"
        return 0
      fi
      return 1
    fi
    if /bin/mkdir -m 700 "$stop" 2>/dev/null \
        || [[ -d "$stop" && ! -L "$stop" && -O "$stop" ]]; then
      [[ -f "$marker" ]] || _ghostty_progress_remove_stop "$stop"
      return 0
    fi
    return 1
  }

  _ghostty_progress_worker_active() {
    emulate -L zsh
    local marker="$1" owner="$2" identity="$3"
    local -i verify_identity="${4:-0}"
    [[ -f "$marker" && ! -e "$marker.stop" ]] || return 1
    _ghostty_progress_marker_owner "$marker" || return 1
    [[ "$REPLY" == "$owner" && "$REPLY2" == "$identity" && "$REPLY3" == auto ]] || return 1
    # owner 启动时间防止 PID 被复用后把无关进程误判为原 shell。
    if (( verify_identity )); then
      _ghostty_progress_owner_alive "$owner" "$identity"
    else
      builtin kill -0 "$owner" 2>/dev/null
    fi
  }

  _ghostty_progress_worker_identity() {
    emulate -L zsh
    local marker="$1" owner="$2" identity="$3" current_identity

    # 返回 0=身份匹配，1=已停止/不匹配，2=ps 暂时不可用；调用方不得把 2 当成可写。
    _ghostty_progress_worker_active "$marker" "$owner" "$identity" || return 1
    if _ghostty_progress_owner_identity "$owner"; then
      current_identity="$REPLY"
      [[ "$current_identity" == "$identity" ]]
    else
      return 2
    fi
  }

  _ghostty_progress_worker_finish() {
    emulate -L zsh
    setopt noerrexit nobgnice
    local marker="$1" shown="$2" dir="${1:h}"
    local -i finish_status=0 attempts=0
    local REPLY REPLY2 REPLY3

    # marker 已由 prompt 消费，说明清屏/交接已经完成；旧 worker 不能再写终端。
    if (( ! shown )) || [[ ! -f "$marker" ]]; then
      _ghostty_progress_remove_marker "$marker" || _ghostty_progress_request_stop "$marker"
      return 0
    fi

    # 所有失败共用 50 次上限，包括锁/写入/身份重查交替失败的情况。
    # 每次争锁至多 0.1s，重试间隔 0.1s；耗尽后仅清理自己的状态，不无锁清屏。
    for (( attempts = 0; attempts < 50; ++attempts )); do
      if ! _ghostty_progress_state_dir || [[ "$REPLY" != "$dir" ]]; then
        break
      fi
      (
        zsystem flock -t 0.1 -i 0.01 "$dir/output.lock" 2>/dev/null || exit 1
        # 等锁期间 prompt 可能已经完成交接，必须在锁内再次检查。
        [[ -f "$marker" ]] || exit 0
        _ghostty_progress_current_marker_locked "$dir"
        if [[ "$REPLY" == "$marker" ]]; then
          exit 3
        fi
        if [[ -n "$REPLY" ]]; then
          # native 预约同样占有进度；旧 worker 只能删除自己的 marker。
          _ghostty_progress_remove_marker "$marker" || _ghostty_progress_request_stop "$marker"
          exit 0
        fi
        if _ghostty_progress_emit off; then
          _ghostty_progress_remove_marker "$marker" || _ghostty_progress_request_stop "$marker"
          exit 0
        fi
        exit 2
      )
      finish_status=$?
      (( finish_status == 0 )) && return 0
      (( attempts < 49 )) && zselect -t 10 2>/dev/null
    done
    # 宁可让 Ghostty 的 15 秒超时收尾，也不能在无法确认所有权时覆盖其他程序。
    _ghostty_progress_remove_marker "$marker" || _ghostty_progress_request_stop "$marker"
    return 0
  }

  _ghostty_progress_worker() {
    emulate -L zsh
    setopt noerrexit nobgnice
    local marker="$1" dir="${1:h}" owner identity action current
    local action_state action_sequence action_current sequence_snapshot observed_sequence= blocked_marker=
    local -i shown=0 tui=0 sequence_changed=0 identity_tick=0 refresh_tick=0
    local -i blocked_active=0 blocked_ticks=0
    local -i action_status=0 identity_status=0 identity_failures=0
    local REPLY REPLY2 REPLY3

    # TOSTOP 不应暂停专用 OSC writer；其他终止信号仍保持默认行为。
    trap '' TTOU
    if ! _ghostty_progress_marker_owner "$marker"; then
      _ghostty_progress_remove_marker "$marker"
      return 0
    fi
    owner="$REPLY"
    identity="$REPLY2"
    # 启动时只做廉价一致性检查；真正显示前再做强校验，短命令不再额外 fork ps。
    if ! _ghostty_progress_worker_active "$marker" "$owner" "$identity"; then
      _ghostty_progress_remove_marker "$marker"
      return 0
    fi
    # 延迟期间不轮询；短命令的 marker 会由 precmd 删除，worker 醒来后一次检查即可退出。
    zselect -t 150 2>/dev/null
    if ! _ghostty_progress_worker_identity "$marker" "$owner" "$identity"; then
      _ghostty_progress_worker_finish "$marker" "$shown"
      return 0
    fi

    while true; do
      # 这里只是无写入的廉价停止检查；所有 OSC 写入前仍会严格验证完整进程身份。
      _ghostty_progress_worker_active "$marker" "$owner" "$identity" || break
      (( shown )) && (( ++refresh_tick ))
      tui=0
      _ghostty_progress_is_tui && tui=1
      if _ghostty_progress_state_dir; then
        dir="$REPLY"
        sequence_snapshot=invalid
        { IFS= read -r sequence_snapshot < "$dir/sequence" } 2>/dev/null \
          || sequence_snapshot=invalid
        [[ "$sequence_snapshot" == <0-> ]] || sequence_snapshot=invalid
        sequence_changed=0
        [[ "$sequence_snapshot" != "$observed_sequence" ]] && sequence_changed=1

        blocked_active=0
        if [[ -n "$blocked_marker" && -f "$blocked_marker" && ! -e "$blocked_marker.stop" ]] \
            && (( blocked_ticks < 9 )); then
          blocked_active=1
        fi
        # 稳态仅做 1Hz termios 探测；显示期间每 8 轮保活，退让中的 worker 每 10 轮复核 owner。
        if (( ! sequence_changed \
              && ( blocked_active || ( tui && ! shown ) || ( ! tui && shown && refresh_tick < 8 ) ) )); then
          (( ++identity_tick ))
          (( ++blocked_ticks ))
          # 稳态每 10 秒强校验一次；一旦 ps 瞬时失败则改为每秒重试并有界退出。
          if (( identity_failures || identity_tick >= 10 )); then
            identity_tick=0
            _ghostty_progress_worker_identity "$marker" "$owner" "$identity"
            identity_status=$?
            (( identity_status == 1 )) && break
            if (( identity_status == 2 )); then
              (( ++identity_failures ))
            else
              identity_failures=0
            fi
            (( identity_failures >= 10 )) && break
          fi
          zselect -t 100 2>/dev/null
          continue
        fi

        action="$(
          zsystem flock -t 0.05 -i 0.01 "$dir/output.lock" 2>/dev/null || exit 1
          # 每次写终端前做严格身份校验；ps 不可用时跳过本轮，绝不退化成仅 PID 校验。
          _ghostty_progress_worker_identity "$marker" "$owner" "$identity"
          identity_status=$?
          (( identity_status == 0 )) || exit "$(( identity_status + 1 ))"
          _ghostty_progress_current_marker_locked "$dir" "$marker" "$owner" "$identity"
          current="$REPLY"
          sequence_snapshot=invalid
          { IFS= read -r sequence_snapshot < "$dir/sequence" } 2>/dev/null \
            || sequence_snapshot=invalid
          [[ "$sequence_snapshot" == <0-> ]] || sequence_snapshot=invalid
          sequence_changed=0
          [[ "$sequence_snapshot" != "$observed_sequence" ]] && sequence_changed=1
          if [[ "$current" == "$marker" ]]; then
            if (( tui )); then
              if (( shown )) && _ghostty_progress_emit off; then
                action_state=hidden
              else
                action_state="$(( shown ? 1 : 0 ))"
              fi
            elif (( ! shown || sequence_changed || refresh_tick >= 8 )); then
              # stop 可在不持锁的 prompt 兜底路径创建；最后一刻再检查，避免命令结束后反向点亮。
              [[ ! -e "$marker.stop" ]] || exit 2
              if _ghostty_progress_emit on; then
                action_state=shown
              else
                action_state="$(( shown ? 1 : 0 ))"
              fi
            else
              action_state=1
            fi
          elif [[ -n "$current" ]]; then
            # 包括没有 worker 的 native 预约；缓存其 marker，避免退让期间每秒争锁/跑 ps。
            action_state=blocked
          else
            # stop/owner 退出可能恰好发生在两次检查之间；保留 shown 让 finish 清屏。
            action_state="$(( shown ? 1 : 0 ))"
          fi
          builtin print -r -- "${action_state}:${sequence_snapshot}:${current:t}"
        )"
        action_status=$?
        (( action_status == 2 )) && break
        if (( action_status == 0 )); then
          identity_failures=0
          identity_tick=0
        elif (( action_status == 1 )); then
          _ghostty_progress_worker_identity "$marker" "$owner" "$identity"
          identity_status=$?
          (( identity_status == 1 )) && break
          if (( identity_status == 2 )); then
            (( ++identity_failures ))
          else
            identity_failures=0
            identity_tick=0
          fi
        elif (( action_status == 3 )); then
          (( ++identity_failures ))
        fi
        # 连续 10 秒无法确认身份时停止写入并进入有界收尾，避免故障路径留下 worker。
        (( identity_failures >= 10 )) && break
        action_state="${action%%:*}"
        action_sequence="${action#*:}"
        action_current="${action_sequence#*:}"
        action_sequence="${action_sequence%%:*}"
        case "$action_state" in
          shown) shown=1; refresh_tick=0; blocked_marker=; blocked_ticks=0 ;;
          1) shown=1; blocked_marker= ;;
          hidden|0) shown=0; refresh_tick=0; blocked_marker= ;;
          blocked)
            shown=0
            refresh_tick=0
            blocked_marker="$dir/$action_current"
            blocked_ticks=0
            ;;
        esac
        if (( action_status == 0 )) \
            && [[ "$action" == *:* && ( "$action_sequence" == <0-> \
              || "$action_sequence" == invalid ) ]]; then
          observed_sequence="$action_sequence"
        fi
      else
        _ghostty_progress_worker_identity "$marker" "$owner" "$identity"
        identity_status=$?
        (( identity_status == 1 )) && break
        if (( identity_status == 2 )); then
          (( ++identity_failures ))
        else
          identity_failures=0
          identity_tick=0
        fi
        (( identity_failures >= 10 )) && break
      fi
      # 保活间隔低于 Ghostty macOS 的 15 秒超时；native 所有者存在时不会发送。
      zselect -t 100 2>/dev/null
    done

    _ghostty_progress_worker_finish "$marker" "$shown"
    return 0
  }

  _ghostty_progress_off() {
    emulate -L zsh
    setopt noerrexit
    local -a all_handles handles
    local handle token rest owner marker dir shell_pid
    local -i inherited=0
    local REPLY REPLY2 REPLY3

    shell_pid="$sysparams[pid]"
    [[ "${_GHOSTTY_PROGRESS_SUPPRESSED_PID:-}" == "$shell_pid" ]] \
      && unset _GHOSTTY_PROGRESS_SUPPRESSED_PID

    all_handles=("${(@k)functions[(I)_ghostty_progress_handle_*]}")
    for handle in "${all_handles[@]}"; do
      token="${handle#_ghostty_progress_handle_}"
      if ! _ghostty_progress_token_valid "$token"; then
        unfunction "$handle" 2>/dev/null
        continue
      fi
      rest="${token#*.}"
      owner="${rest%%.*}"
      if [[ "$owner" == "$shell_pid" ]]; then
        handles+=("$handle")
      else
        inherited=1
        unfunction "$handle" 2>/dev/null
      fi
    done
    # fork 子 shell 不能操作祖先的 marker。
    (( ${#handles} == 0 && inherited )) && return 0
    if (( ${#handles} == 0 )) \
        && [[ "${_GHOSTTY_PROGRESS_RECONCILE_PID:-}" != "$shell_pid" ]]; then
      return 0
    fi
    if ! _ghostty_progress_state_dir; then
      # 没有可信共享状态时不直接写终端；保留 reconcile，等待后续 prompt 恢复。
      _ghostty_progress_prepare_dir || return 0
    fi
    dir="$REPLY"

    if (
      local current current_mode
      local -a owned_markers
      local -i has_auto=0 owns_current=0 clear=0
      zsystem flock -t 0 "$dir/output.lock" 2>/dev/null || exit 1
      _ghostty_progress_current_marker_locked "$dir"
      current="$REPLY"
      for marker in "$dir"/*.state(N); do
        if _ghostty_progress_marker_owner "$marker" && [[ "$REPLY" == "$shell_pid" ]]; then
          owned_markers+=("$marker")
          [[ "$REPLY3" == auto ]] && has_auto=1
          if [[ "$marker" == "$current" ]]; then
            owns_current=1
            current_mode="$REPLY3"
          fi
        fi
      done
      if [[ -z "$current" ]]; then
        # 首次 prompt 的 reconcile 可以清除遗留状态；native 命令的收尾绝不清屏。
        (( has_auto || ${#owned_markers} == 0 )) && clear=1
      elif (( owns_current )) && [[ "$current_mode" == auto ]]; then
        clear=1
      fi
      # 必须先完成清屏，再消费 marker；失败时保留它供 worker 重试。
      if (( clear )); then
        _ghostty_progress_emit off || exit 2
      fi
      for marker in "${owned_markers[@]}"; do
        _ghostty_progress_remove_marker "$marker" || exit 3
      done
      exit 0
    ); then
      for handle in "${handles[@]}"; do unfunction "$handle" 2>/dev/null; done
      unset _GHOSTTY_PROGRESS_RECONCILE_PID
    else
      # prompt 不等锁；stop 让 worker 异步收尾，native 预约由后续 prompt/preexec 回收。
      for marker in "$dir"/*.state(N); do
        if _ghostty_progress_marker_owner "$marker" && [[ "$REPLY" == "$shell_pid" ]]; then
          _ghostty_progress_request_stop "$marker"
        fi
      done
      for handle in "${handles[@]}"; do
        token="${handle#_ghostty_progress_handle_}"
        if [[ ! -f "$dir/$token.state" || -e "$dir/$token.state.stop" ]]; then
          unfunction "$handle" 2>/dev/null
        fi
      done
    fi
    return 0
  }

  _ghostty_progress_env_split() {
    emulate -L zsh
    local input="$1" char next quote= word=
    local -i i=1 started=0
    reply=()
    # env -S 有自己的转义规则；不 eval，也不执行 shell/环境变量替换。
    while (( i <= ${#input} )); do
      char="${input[i++]}"
      if [[ "$char" == '\' ]]; then
        (( i <= ${#input} )) || return 1
        next="${input[i]}"
        if [[ "$quote" == "'" && "$next" != "'" && "$next" != '\' ]]; then
          word+="$char"
          started=1
          continue
        fi
        (( ++i ))
        case "$next" in
          c) [[ "$quote" != '"' ]] || return 1; break ;;
          _) if [[ -z "$quote" ]]; then
               (( started )) && reply+=("$word")
               word=; started=0; continue
             fi
             char=' ' ;;
          f) char=$'\f' ;; n) char=$'\n' ;; r) char=$'\r' ;;
          t) char=$'\t' ;; v) char=$'\v' ;;
          '#'|'$'|'"'|"'"|'\') char="$next" ;;
          *) return 1 ;;
        esac
      elif [[ -n "$quote" ]]; then
        if [[ "$char" == "$quote" ]]; then
          quote=
          continue
        fi
        # 动态引用保留为不透明文本，不展开；已确定的前置赋值仍可被识别。
      else
        case "$char" in
          "'"|'"') quote="$char"; started=1; continue ;;
          ' '|$'\t'|$'\n'|$'\r')
            (( started )) && reply+=("$word")
            word=; started=0; continue ;;
          '#') (( started )) || break ;;
        esac
      fi
      word+="$char"
      started=1
    done
    [[ -z "$quote" ]] || return 1
    (( started )) && reply+=("$word")
    return 0
  }

  _ghostty_progress_command_words() {
    emulate -L zsh
    setopt localoptions extendedglob
    local remaining="$1" word delimiter line
    local -a tokens delimiters tab_modes body_lines
    local -i expect_delimiter=0 strip_tabs=0 restart=0 i j consumed body_index
    reply=()
    if [[ "$remaining" != *'<<'* ]]; then
      reply=("${(Z+C+)remaining}")
      return 0
    fi
    # zsh 的 (z) 只做词法分割，不会跳过 heredoc。按原始换行消费正文后重新分词；
    # 带引号的多行参数仍是完整 token，正文中的引号、分号等从不参与命令扫描。
    while [[ -n "$remaining" ]]; do
      tokens=("${(Z+c+)remaining}")
      restart=0
      for word in "${tokens[@]}"; do
        while [[ "$remaining" == [' '$'\t'$'\r']* || "$remaining" == $'\\\n'* ]]; do
          if [[ "$remaining" == $'\\\n'* ]]; then
            remaining="${remaining[3,-1]}"
          else
            remaining="${remaining[2,-1]}"
          fi
        done
        if [[ "$word" == ';' && "$remaining" == $'\n'* ]]; then
          remaining="${remaining[2,-1]}"
          reply+=(';')
          if (( ${#delimiters} )); then
            # 一次分行，避免逐行截取整个剩余正文导致大 heredoc 二次方耗时。
            body_lines=("${(@f)remaining}")
            body_index=1
            for (( i = 1; i <= ${#delimiters}; ++i )); do
              delimiter="${delimiters[i]}"
              while true; do
                (( body_index <= ${#body_lines} )) || return 1
                line="${body_lines[body_index++]}"
                if (( tab_modes[i] )); then
                  line="${line##$'\t'#}"
                fi
                [[ "$line" == "$delimiter" ]] && break
              done
            done
            remaining="${(F)body_lines[body_index,-1]}"
            body_lines=(); delimiters=(); tab_modes=()
            restart=1
            break
          fi
          continue
        fi
        # 通常 token 与源文本逐字相同；兼容词法分析已移除的反斜杠换行。
        if [[ "$remaining" == "$word"* ]]; then
          consumed=${#word}
        else
          consumed=0
          for (( j = 1; j <= ${#word}; )); do
            (( ++consumed ))
            if [[ "${remaining[consumed]}" == "${word[j]}" ]]; then
              (( ++j ))
            elif [[ "${remaining[consumed,consumed+1]}" == $'\\\n' ]]; then
              (( ++consumed ))
            else
              return 1
            fi
          done
        fi
        remaining="${remaining[consumed+1,-1]}"
        [[ "$word" == '#'* ]] && continue
        if (( expect_delimiter )); then
          delimiters+=("${(Q)word}")
          tab_modes+=("$strip_tabs")
          expect_delimiter=0
        elif [[ "$word" == [0-9]#'<<' || "$word" == [0-9]#'<<-' ]]; then
          expect_delimiter=1
          strip_tabs=0
          [[ "$word" == *- ]] && strip_tabs=1
        else
          reply+=("$word")
        fi
      done
      (( restart )) || break
    done
    (( ! expect_delimiter && ${#delimiters} == 0 ))
  }

  _ghostty_progress_prefix_suppressed() {
    emulate -L zsh
    setopt localoptions extendedglob
    local mode="${GHOSTTY_PROGRESS_AUTO:-1}" raw_word word name value skip_arg=
    local -a words reply
    local -i env_phase=0 i=1 splits=0
    words=("$@")

    while (( i <= ${#words} )); do
      raw_word="${words[i++]}"
      word="${(Q)raw_word}"
      if [[ -n "$skip_arg" ]]; then
        if [[ "$skip_arg" == split ]]; then
          (( ++splits <= 16 )) && _ghostty_progress_env_split "$word" || break
          words=("${(@qqq)reply}" "${(@)words[i,-1]}")
          i=1
        elif [[ "$skip_arg" == unset && "$word" == GHOSTTY_PROGRESS_AUTO ]]; then
          mode=1
        fi
        skip_arg=
        continue
      fi
      # 前置重定向的目标是文件名，不能当成环境赋值。
      if [[ "$raw_word" == [0-9]#(\<|\>|\>\>|\<\>|\>\&|\<\&|\>\|) ]]; then
        skip_arg=redirect
        continue
      fi
      if (( env_phase == 1 )); then
        case "$word" in
          --) env_phase=2; continue ;;
          -i|--ignore-environment) mode=1; continue ;;
          -u) skip_arg=unset; continue ;;
          -u?*)
            [[ "${word#-u}" == GHOSTTY_PROGRESS_AUTO ]] && mode=1
            continue ;;
          -S) skip_arg=split; continue ;;
          -S?*)
            (( ++splits <= 16 )) && _ghostty_progress_env_split "${word#-S}" || break
            words=("${(@qqq)reply}" "${(@)words[i,-1]}")
            i=1
            continue ;;
          -C|-P) skip_arg=option; continue ;;
          -C?*|-P?*|-[0v]##) continue ;;
          -*) break ;;
        esac
      fi
      # shell 赋值只接受原始赋值词；env 则允许引号包裹整个 NAME=value。
      (( env_phase )) || word="$raw_word"
      if [[ "$word" == [[:alpha:]_][[:alnum:]_]#=* ]]; then
        name="${word%%=*}"
        value="${word#*=}"
        # env 的参数已完成一次去引号；不能再次剥掉属于实际值的引号。
        (( env_phase )) || value="${(Q)value}"
        [[ "$name" == GHOSTTY_PROGRESS_AUTO ]] && mode="$value"
        (( env_phase == 1 )) && env_phase=2
        continue
      fi
      word="${(Q)raw_word}"
      if (( ! env_phase )); then
        case "$word" in
          env|/usr/bin/env) env_phase=1; continue ;;
          command|builtin|exec|noglob|nocorrect|time|'!'|if|then|elif|else|while|until|do|'{'|'(')
            continue ;;
        esac
      fi
      # 已到命令名；后面的普通参数绝不作为开关读取。
      break
    done
    case "${mode:l}" in
      0|off|false|no) return 0 ;;
      *) return 1 ;;
    esac
  }

  _ghostty_progress_command_suppressed() {
    emulate -L zsh
    local command_line="$1" word
    local -a words segment reply
    # 只解析命令结构；不 eval，不执行变量/命令替换，heredoc 正文不作为命令。
    if ! _ghostty_progress_command_words "$command_line"; then
      _ghostty_progress_prefix_suppressed
      return $?
    fi
    words=("${reply[@]}")
    for word in "${words[@]}"; do
      case "$word" in
        ';'|'&&'|'||'|'|'|'|&'|'&'|'&!'|'&|'|$'\n')
          if (( ${#segment} )) && _ghostty_progress_prefix_suppressed "${segment[@]}"; then
            return 0
          fi
          segment=()
          ;;
        *) segment+=("$word") ;;
      esac
    done
    _ghostty_progress_prefix_suppressed "${segment[@]}"
  }


  _ghostty_progress_on() {
    emulate -L zsh
    setopt noerrexit nobgnice interactivecomments
    local -a pending_handles
    local dir token marker handle shell_pid owner_identity child_token child_marker
    # preexec 第三个参数包含完整的别名展开结果；手动调用时回退到第一个参数。
    local command_line="${3:-${1:-}}" mode=auto
    local worker_file
    local REPLY REPLY2 REPLY3

    shell_pid="$sysparams[pid]"
    [[ "${_GHOSTTY_PROGRESS_SUPPRESSED_PID:-}" == "$shell_pid" ]] \
      && unset _GHOSTTY_PROGRESS_SUPPRESSED_PID

    pending_handles=("${(@k)functions[(I)_ghostty_progress_handle_*]}")
    (( ${#pending_handles} )) && _ghostty_progress_off
    _ghostty_progress_command_suppressed "$command_line" && mode=native
    if ! _ghostty_progress_state_dir; then
      _ghostty_progress_prepare_dir || return 0
    fi
    dir="$REPLY"

    owner_identity=
    if [[ "$_GHOSTTY_PROGRESS_OWNER_PID" == "$shell_pid" \
          && -n "$_GHOSTTY_PROGRESS_OWNER_IDENTITY" ]]; then
      owner_identity="$_GHOSTTY_PROGRESS_OWNER_IDENTITY"
    elif _ghostty_progress_owner_identity "$shell_pid"; then
      owner_identity="$REPLY"
      typeset -g _GHOSTTY_PROGRESS_OWNER_PID="$shell_pid"
      typeset -g _GHOSTTY_PROGRESS_OWNER_IDENTITY="$owner_identity"
    else
      # 无法取得强身份时不创建 marker，避免退化成可能误认复用 PID 的路径。
      return 0
    fi

    # 从可能开始创建 marker 起记录待收尾状态；即使内存 handle 被删或中途失败也能在 prompt 修复。
    typeset -g _GHOSTTY_PROGRESS_RECONCILE_PID="$shell_pid"

    # 命令替换本身就是短命子进程；隐藏的锁 FD 随其退出自动释放。
    token="$(
      setopt localoptions noclobber noerrexit
      umask 077
      if [[ "$mode" == native ]]; then
        # 原生程序开始输出前，必须等已持锁的 writer 完成；无锁预约无法撤回在途写入。
        # 仅显式豁免命令等待交接，Ctrl+C 可取消；普通命令和空闲 prompt 仍不等待锁。
        zsystem flock "$dir/output.lock" 2>/dev/null || exit 1
      else
        zsystem flock -t 0 "$dir/output.lock" 2>/dev/null || exit 1
      fi
      # 无句柄但仍有同 PID marker 时，在已经持有的锁内修复，不再额外争锁一次。
      for child_marker in "$dir"/*.state(N); do
        if _ghostty_progress_marker_owner "$child_marker" \
            && [[ "$REPLY" == "$shell_pid" ]]; then
          _ghostty_progress_remove_marker "$child_marker" || exit 1
        fi
      done
      _ghostty_progress_next_token_locked "$dir" "$shell_pid" || exit 1
      child_token="$REPLY"
      child_marker="$dir/$child_token.state"
      {
        builtin print -r -- "$shell_pid"
        builtin print -r -- "$owner_identity"
        builtin print -r -- "$mode"
      } > "$child_marker" 2>/dev/null || exit 1
      _ghostty_progress_emit off
      builtin print -r -- "$child_token"
    )" || {
      _ghostty_progress_off
      return 0
    }
    if ! _ghostty_progress_token_valid "$token"; then
      _ghostty_progress_off
      return 0
    fi
    marker="$dir/$token.state"
    if ! _ghostty_progress_marker_owner "$marker" \
        || [[ "$REPLY" != "$shell_pid" || "$REPLY2" != "$owner_identity" ]]; then
      _ghostty_progress_off
      return 0
    fi
    handle="_ghostty_progress_handle_${token}"
    functions[$handle]=':'
    # native marker 参与同一套仲裁，但不创建自动进度 worker。
    [[ "$mode" == native ]] && return 0

    worker_file="${_GHOSTTY_PROGRESS_WORKER_FILE:-}"
    if [[ "$worker_file" != "$dir/worker-v5.zsh" \
          || ! -f "$worker_file" || -L "$worker_file" || ! -O "$worker_file" \
          || ! -r "$worker_file" ]]; then
      _ghostty_progress_off
      return 0
    fi

    # 外部 true 使交互 shell 不等待输出进程替换，也不会改写用户的 $!。
    # 启动子进程先清理继承资源再 exec；仅 exec 失败时 EXIT trap 才接管收尾。
    if ! { /usr/bin/true > >(
      exec </dev/null >/dev/null 2>&1
      emulate -L zsh
      setopt noerrexit nobgnice
      trap '' TTOU
      typeset -a _ghostty_launcher_inherited_fds
      typeset _ghostty_launcher_inherited_fd
      _ghostty_launcher_inherited_fds=(/dev/fd/<3->(N:t))
      for _ghostty_launcher_inherited_fd in "${_ghostty_launcher_inherited_fds[@]}"; do
        exec {_ghostty_launcher_inherited_fd}>&-
      done 2>/dev/null
      unset _ghostty_launcher_inherited_fd _ghostty_launcher_inherited_fds
      builtin cd / 2>/dev/null || exit 0
      trap '[[ ! -f "$marker" ]] || _ghostty_progress_worker_finish "$marker" 1' EXIT
      exec /bin/zsh -df "$worker_file" "$marker" "$_GHOSTTY_PROGRESS_TTY_NAME"
    ) } 2>/dev/null; then
      _ghostty_progress_off
      return 0
    fi
    return 0
  }

  _ghostty_progress_build_worker_program() {
    emulate -L zsh
    local -a worker_functions
    local name body program

    worker_functions=(
      _ghostty_progress_state_dir
      _ghostty_progress_prepare_dir
      _ghostty_progress_owner_identity
      _ghostty_progress_owner_alive
      _ghostty_progress_remove_stop
      _ghostty_progress_remove_marker
      _ghostty_progress_emit
      _ghostty_progress_is_tui
      _ghostty_progress_token_valid
      _ghostty_progress_marker_owner
      _ghostty_progress_current_marker_locked
      _ghostty_progress_request_stop
      _ghostty_progress_worker_active
      _ghostty_progress_worker_identity
      _ghostty_progress_worker_finish
      _ghostty_progress_worker
    )
    # 整个匿名函数先被完整解析，再清理用户环境继承的 FD；zsh 自有脚本 FD 不参与用户管道。
    program=$'() {\nemulate -L zsh\nsetopt noerrexit nobgnice\ntypeset -a _ghostty_worker_inherited_fds\ntypeset _ghostty_worker_inherited_fd\n_ghostty_worker_inherited_fds=(/dev/fd/<3->(N:t))\nfor _ghostty_worker_inherited_fd in "${_ghostty_worker_inherited_fds[@]}"; do\n  exec {_ghostty_worker_inherited_fd}>&-\ndone 2>/dev/null\nunset _ghostty_worker_inherited_fd _ghostty_worker_inherited_fds\nbuiltin cd / 2>/dev/null || exit 0\nzmodload zsh/zselect 2>/dev/null || exit 0\nzmodload zsh/system 2>/dev/null || exit 0\ntypeset -g _GHOSTTY_PROGRESS_TTY_NAME="$2"\n'
    for name in "${worker_functions[@]}"; do
      body="${functions[$name]}"
      [[ -n "$body" ]] || return 1
      program+=$'\n'"${name} () {"$'\n'"${body}"$'\n}'
    done
    program+=$'\n_ghostty_progress_worker "$1"\n} "$@"\n'
    # 不保留尾随换行，便于用 zsh 的内建文件读取做无 fork 的精确缓存比较。
    program="${program%$'\n'}"
    REPLY="$program"
  }

  _ghostty_progress_install_worker_program() {
    emulate -L zsh
    setopt noerrexit
    local dir="$1" program="$2" worker="$1/worker-v5.zsh" tmp= existing=
    local -i install_status=0

    [[ -d "$dir" && ! -L "$dir" && -O "$dir" ]] || return 1
    (
      umask 077
      zsystem flock -t 0.2 -i 0.01 "$dir/output.lock" 2>/dev/null || exit 1
      if [[ -e "$worker" \
            && ( ! -f "$worker" || -L "$worker" || ! -O "$worker" ) ]]; then
        exit 1
      fi
      if [[ -f "$worker" ]]; then
        existing="$(< "$worker")" || exit 1
        if [[ "$existing" == "$program" ]]; then
          /bin/chmod 600 "$worker" 2>/dev/null || exit 1
          exit 0
        fi
      fi
      tmp="$(/usr/bin/mktemp "$dir/.worker-v5.XXXXXX" 2>/dev/null)" || exit 1
      trap '[[ -z "$tmp" ]] || /bin/rm -f "$tmp" 2>/dev/null' EXIT
      { builtin print -rn -- "$program" >| "$tmp" } 2>/dev/null || exit 1
      /bin/chmod 600 "$tmp" 2>/dev/null || exit 1
      # 只校验尚未发布的新内容；完全相同的已发布 worker 不再为每个 shell 重写和复检。
      /bin/zsh -n "$tmp" </dev/null >/dev/null 2>&1 || exit 1
      /bin/mv -f "$tmp" "$worker" 2>/dev/null || exit 1
      tmp=
      exit 0
    )
    install_status=$?
    (( install_status == 0 )) || return 1
    [[ -f "$worker" && ! -L "$worker" && -O "$worker" && -r "$worker" ]] || return 1
    REPLY="$worker"
  }

  if ! _ghostty_progress_build_worker_program; then
    unset _GHOSTTY_PROGRESS_WORKER_PROGRAM _GHOSTTY_PROGRESS_WORKER_FILE
    unfunction -m '_ghostty_progress_*' 2>/dev/null
    return 0
  fi
  typeset -g _GHOSTTY_PROGRESS_WORKER_PROGRAM="$REPLY"
  unfunction _ghostty_progress_build_worker_program 2>/dev/null

  if ! _ghostty_progress_prepare_dir; then
    unset _GHOSTTY_PROGRESS_WORKER_PROGRAM _GHOSTTY_PROGRESS_WORKER_FILE
    unfunction -m '_ghostty_progress_*' 2>/dev/null
    return 0
  fi
  progress_dir="$REPLY"
  _ghostty_progress_cleanup_state_dirs "$progress_dir"
  unfunction _ghostty_progress_cleanup_state_dirs 2>/dev/null
  if ! _ghostty_progress_install_worker_program \
      "$progress_dir" "$_GHOSTTY_PROGRESS_WORKER_PROGRAM"; then
    unset _GHOSTTY_PROGRESS_WORKER_PROGRAM _GHOSTTY_PROGRESS_WORKER_FILE
    unfunction -m '_ghostty_progress_*' 2>/dev/null
    return 0
  fi
  typeset -g _GHOSTTY_PROGRESS_WORKER_FILE="$REPLY"
  unset _GHOSTTY_PROGRESS_WORKER_PROGRAM
  unfunction _ghostty_progress_install_worker_program 2>/dev/null
  typeset -g _GHOSTTY_PROGRESS_PROTOCOL_VERSION=5
  # 第一个 prompt 做一次幂等清屏，以修复上次异常退出后 Ghostty 中可能残留的视觉状态。
  typeset -g _GHOSTTY_PROGRESS_RECONCILE_PID="$sysparams[pid]"

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _ghostty_progress_on
  add-zsh-hook precmd _ghostty_progress_off
  add-zsh-hook zshexit _ghostty_progress_off
}
fi

# 个人环境变量、别名和其他已有配置保留在原 ~/.zshrc 中，不在这个托管区写入固定值。
# <<< ghostty-zsh-setup managed <<<
ZSHRC
install_managed_zsh_block "$HOME/.zshrc" "$GHOSTTY_ZSH_BLOCK"
ok "已保留原 ~/.zshrc，并更新 Ghostty 管理区"

# ------------------------------- 7. Starship + Ghostty ------------------------
if (( WITH_PERSONAL )); then
  step "${GHOSTTY_STEP}/${TOTAL_STEPS} Starship 预设 + Ghostty 配置"
fi
mkdir -p "$HOME/.config"
backup_file "$HOME/.config/starship.toml"
starship preset catppuccin-powerline -o "$HOME/.config/starship.toml"
ok "已生成 ~/.config/starship.toml (Catppuccin Powerline)"

}

if (( WITH_PERSONAL )); then
  configure_personal_environment
else
  info "Ghostty-only 模式：保留现有个人配置，跳过 ~/.zshrc、Starship、Oh My Zsh 和命令行工具。"
fi

# ------------------------------- 7. Ghostty ---------------------------------
if (( ! WITH_PERSONAL )); then
  step "2/${TOTAL_STEPS} Ghostty 主题"
fi
GHOSTTY_DIR="$HOME/.config/ghostty"
mkdir -p "$GHOSTTY_DIR"

# 自定义紫色主题 (独立文件, 升级 Ghostty 不受影响; 已存在则跳过)
THEME_FILE="$GHOSTTY_DIR/themes/Catppuccin Mocha Purple"
if [[ -f "$THEME_FILE" ]]; then
  ok "已存在自定义主题: Catppuccin Mocha Purple"
else
  mkdir -p "$GHOSTTY_DIR/themes"
  cat > "$THEME_FILE" <<'THEME'
# Catppuccin Mocha Purple — magenta 色位换为 Catppuccin 官方紫 mauve 系
palette = 0=#45475a
palette = 1=#f38ba8
palette = 2=#a6e3a1
palette = 3=#f9e2af
palette = 4=#89b4fa
palette = 5=#cba6f7
palette = 6=#94e2d5
palette = 7=#a6adc8
palette = 8=#585b70
palette = 9=#f37799
palette = 10=#89d88b
palette = 11=#ebd391
palette = 12=#74a8fc
palette = 13=#d8b4fe
palette = 14=#6bd7ca
palette = 15=#bac2de
background = #1e1e2e
foreground = #cdd6f4
cursor-color = #f5e0dc
cursor-text = #1e1e2e
selection-background = #585b70
selection-foreground = #cdd6f4
THEME
  ok "已创建自定义主题: Catppuccin Mocha Purple"
fi

backup_file "$GHOSTTY_DIR/config"
if (( ! WITH_PERSONAL )); then
  step "3/${TOTAL_STEPS} Ghostty 配置"
fi
cat > "$GHOSTTY_DIR/config" <<'GHOSTTY'
# ~/.config/ghostty/config
# 由 setup-ghostty-env.sh 生成，已通过 ghostty +validate-config 校验。
# 保存后 Ghostty 会自动热重载；也可手动按 Cmd+Shift+, 重载。

theme = "Catppuccin Mocha Purple"
background-opacity = 0.9
background-blur-radius = 24
window-padding-x = 12
window-padding-y = 12
font-family = "MesloLGS NF"
font-size = 14

# Option 键作为 Alt: opt+←/→ 跳单词、opt+⌫ 删单词、tmux 前缀键可用
macos-option-as-alt = true

# 非活跃分屏变暗程度 (0.0-1.0, 越低越暗; 0.7 即默认值)
unfocused-split-opacity = 0.7

# Quake 全局下拉终端 (需授予 macOS 辅助功能权限, 首次加载会弹窗)
keybind = global:alt+space=toggle_quick_terminal

# 退出时保存窗口布局 (位置/大小/标签页/分屏/cwd), 重启恢复
window-save-state = always

# ---- 备选写法 (按需取消注释) ----
# brew 的 font-meslo-lg-nerd-font 字体族名为 "MesloLGS Nerd Font"，与上面不同名:
# font-family = "MesloLGS Nerd Font"
# Ghostty 1.1+ 的新键名 (与 background-blur-radius 等效，二选一):
# background-blur = 24
GHOSTTY
ok "已写入 $GHOSTTY_DIR/config"

# 使用 Ghostty 自带校验器验证配置合法性
GHOSTTY_BIN="$(command -v ghostty || true)"
if [[ -z "$GHOSTTY_BIN" && -x "/Applications/Ghostty.app/Contents/MacOS/ghostty" ]]; then
  GHOSTTY_BIN="/Applications/Ghostty.app/Contents/MacOS/ghostty"
fi
if [[ -n "$GHOSTTY_BIN" ]]; then
  if "$GHOSTTY_BIN" +validate-config --config-file="$GHOSTTY_DIR/config" &>/dev/null; then
    ok "Ghostty 配置校验通过 ($("$GHOSTTY_BIN" +version | head -n1))"
  else
    warn "Ghostty 配置校验未通过，请检查 $GHOSTTY_DIR/config"
  fi
else
  warn "未找到 Ghostty，如需安装: brew install --cask ghostty"
fi

# ------------------------------- 8. 完成 -------------------------------------
step "${DONE_STEP}/${TOTAL_STEPS} 完成 🎉"
if [[ ${#BACKUPS[@]} -gt 0 ]]; then
  ok "本次生成的备份文件:"
  for b in "${BACKUPS[@]}"; do printf '     %s\n' "$b"; done
else
  ok "没有覆盖任何已有文件 (首次安装)"
fi

if (( WITH_PERSONAL )); then
  cat <<'NEXT'

后续步骤:
  1. 新开一个 Ghostty 窗口 (或在当前窗口按 Cmd+Shift+, 重载配置)
  2. 执行 exec zsh 让新 .zshrc 立即生效
  3. 试试看:
       z <目录片段>   # zoxide 智能跳转
       y              # yazi 文件管理器 (退出后跟随目录)
       lg             # lazygit
  4. 提示符带 powerline 箭头/图标依赖 Nerd Font，若显示乱码请确认 Ghostty 已生效字体

注意: Starship 仅在 Ghostty 中加载 (按 $TERM_PROGRAM == "ghostty" 判断)，
      在 Terminal / iTerm2 中将是 zsh 默认提示符 —— 这是预期行为。
NEXT
else
  cat <<'NEXT'

后续步骤:
  1. 新开一个 Ghostty 窗口，或在当前窗口按 Cmd+Shift+, 重载配置
  2. 当前已有的 ~/.zshrc 和个人命令行环境保持不变
  3. 如果字体没有立即显示，退出并重新打开 Ghostty，让 macOS 完成字体刷新
NEXT
fi
