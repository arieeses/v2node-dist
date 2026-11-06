#!/usr/bin/env bash
# v2node 一键安装(从公开分发仓库 arieeses/v2node-dist 拉预编译二进制;源码私有)。
# 用法:
#   bash <(curl -Ls https://raw.githubusercontent.com/arieeses/v2node-dist/main/install.sh) <面板地址> <节点ID> <ApiKey>
# 省略参数则交互输入。可用环境变量 VERSION 指定版本(默认当前测试版)。
set -e
VERSION="${VERSION:-v1.0.22-lulutls-test}"
green='\033[0;32m'; red='\033[0;31m'; plain='\033[0m'

API_HOST="$1"; NODE_ID="$2"; API_KEY="$3"
[ -z "$API_HOST" ] && read -rp "面板地址 (如 https://test.knuu.top): " API_HOST
[ -z "$NODE_ID" ]  && read -rp "节点 ID: " NODE_ID
[ -z "$API_KEY" ]  && read -rp "面板 ApiKey (server_token): " API_KEY

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

echo -e "${green}[2/6] 下载 v2node ${VERSION} (${ARCH})...${plain}"
mkdir -p /usr/local/v2node && cd /usr/local/v2node
URL="https://github.com/arieeses/v2node-dist/releases/download/${VERSION}/v2node-linux-${ARCH}.zip"
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

echo -e "${green}[4/6] 写配置 /etc/v2node/config.yml ...${plain}"
cat > /etc/v2node/config.yml <<EOF
Log:
  Level: warning
  Output: ""
  Access: none

Nodes:
  - ApiHost: "${API_HOST}"
    NodeID: ${NODE_ID}
    ApiKey: "${API_KEY}"
    Timeout: 15
EOF

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

echo -e "${green}[6/6] 启动...${plain}"
systemctl daemon-reload && systemctl enable v2node >/dev/null 2>&1 && systemctl restart v2node
sleep 2
echo "------------------------------------------"
/usr/local/v2node/v2node version || true
systemctl is-active v2node >/dev/null 2>&1 && echo -e "${green}v2node 已运行 ✓${plain}" || echo -e "${red}未运行,看日志: journalctl -u v2node -n 50${plain}"
echo -e "日志: ${green}journalctl -u v2node -f${plain}"
