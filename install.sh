#!/usr/bin/env bash
# v2node 一键安装(从公开分发仓库 arieeses/v2node-dist 拉预编译二进制;源码私有)。
#
# 用法一(直接带参数,非交互):
#   bash <(curl -Ls .../install.sh) <面板地址> <节点ID> <ApiKey>
# 用法二(不带参数):只装二进制+服务,并生成占位模板 /etc/v2node/config.yml,
#   你自己编辑后 `systemctl restart v2node`。不会弹向导、不会覆盖已存在的配置。
# 默认装最新正式版(releases/latest);可用 VERSION=vX.Y.Z 指定某个 tag。
set -e
green='\033[0;32m'; red='\033[0;31m'; yellow='\033[1;33m'; plain='\033[0m'

API_HOST="$1"; NODE_ID="$2"; API_KEY="$3"

# 架构检测
case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo -e "${red}暂不支持的架构: $(uname -m)${plain}"; exit 1 ;;
esac

echo -e "${green}[1/6] 安装依赖...${plain}"
if command -v apt >/dev/null 2>&1; then
  apt update -y && apt install -y wget curl unzip tar socat ca-certificates
elif command -v yum >/dev/null 2>&1; then
  yum install -y wget curl unzip tar socat ca-certificates
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache wget curl unzip tar socat ca-certificates
fi

# 下载地址:默认 releases/latest(正式版);VERSION 指定则按 tag 拉。
if [ -n "$VERSION" ]; then
  URL="https://github.com/arieeses/v2node-dist/releases/download/${VERSION}/v2node-linux-${ARCH}.zip"
  echo -e "${green}[2/6] 下载 v2node ${VERSION} (${ARCH})...${plain}"
else
  URL="https://github.com/arieeses/v2node-dist/releases/latest/download/v2node-linux-${ARCH}.zip"
  echo -e "${green}[2/6] 下载 v2node 最新正式版 (${ARCH})...${plain}"
fi
mkdir -p /usr/local/v2node && cd /usr/local/v2node
curl -L -o v2node-linux.zip "$URL"
if ! unzip -o v2node-linux.zip >/dev/null 2>&1; then
  echo -e "${red}下载/解压失败,请确认能访问 Github 且该版本有 ${ARCH} 包: ${URL}${plain}"; exit 1
fi
rm -f v2node-linux.zip && chmod +x v2node
[ -f /usr/local/v2node/v2node ] || { echo -e "${red}未找到 v2node 可执行文件${plain}"; exit 1; }

echo -e "${green}[3/6] geo 数据...${plain}"
mkdir -p /etc/v2node
[ -f /etc/v2node/geoip.dat ]   || curl -sL -o /etc/v2node/geoip.dat   https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat   || true
[ -f /etc/v2node/geosite.dat ] || curl -sL -o /etc/v2node/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat || true

# 配置:带齐 3 个参数就写入;否则——已存在则保留(升级场景),不存在则生成占位模板。
NEED_EDIT=0
echo -e "${green}[4/6] 处理配置 /etc/v2node/config.yml ...${plain}"
if [ -n "$API_HOST" ] && [ -n "$NODE_ID" ] && [ -n "$API_KEY" ]; then
  cat > /etc/v2node/config.yml <<EOF
Log:
  Level: warning
  Output: ""
  Access: none

Nodes:
  - ApiHost: "${API_HOST}"
    NodeID: ${NODE_ID}
    ApiKey: "${API_KEY}"
    Timeout: 30
EOF
  echo -e "  已按参数写入配置。"
elif [ -f /etc/v2node/config.yml ]; then
  echo -e "  已存在配置,保留不动(升级场景)。"
else
  cat > /etc/v2node/config.yml <<'EOF'
Log:
  Level: warning
  Output: ""
  Access: none

Nodes:
  - ApiHost: "https://你的面板地址"
    NodeID: 0
    ApiKey: "你的面板server_token"
    Timeout: 30
EOF
  NEED_EDIT=1
  echo -e "  ${yellow}已生成占位模板,需手动填写。${plain}"
fi

echo -e "${green}[5/6] 安装 systemd 服务...${plain}"
cat > /etc/systemd/system/v2node.service <<'EOF'
[Unit]
Description=v2node
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
Environment=GOGC=50
LimitNOFILE=999999
WorkingDirectory=/usr/local/v2node/
ExecStart=/usr/local/v2node/v2node server -c /etc/v2node/config.yml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable v2node >/dev/null 2>&1

# 安装 v2node 管理命令(curl 失败不影响服务)
if curl -Ls -o /usr/bin/v2node https://raw.githubusercontent.com/arieeses/v2node-dist/main/v2node.sh && [ -s /usr/bin/v2node ]; then
  chmod +x /usr/bin/v2node
  echo -e "${green}已安装管理命令: 输入 v2node 打开菜单${plain}"
else
  echo -e "${yellow}管理命令安装失败(不影响服务),可手动装:${plain}"
  echo -e "  ${green}curl -Ls -o /usr/bin/v2node https://raw.githubusercontent.com/arieeses/v2node-dist/main/v2node.sh && chmod +x /usr/bin/v2node${plain}"
fi

echo "------------------------------------------"
/usr/local/v2node/v2node version || true
if [ "$NEED_EDIT" = "1" ]; then
  echo -e "${yellow}[6/6] 配置还没填,未启动。请编辑配置后启动:${plain}"
  echo -e "  ${green}nano /etc/v2node/config.yml${plain}   # 填 ApiHost / NodeID / ApiKey"
  echo -e "  ${green}systemctl restart v2node${plain}      # 填好后启动"
else
  echo -e "${green}[6/6] 启动...${plain}"
  systemctl restart v2node; sleep 2
  systemctl is-active v2node >/dev/null 2>&1 && echo -e "${green}v2node 已运行 ✓${plain}" || echo -e "${red}未运行,看日志: journalctl -u v2node -n 50${plain}"
fi
echo -e "日志: ${green}journalctl -u v2node -f${plain}"
