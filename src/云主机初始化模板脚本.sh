#!/bin/bash
# 云主机初始化模板脚本
# 保存为模板，可用于批量创建相同配置的云主机

set -e

# 配置参数
VM_NAME="$1"
NETWORK="${2:-private}"
FLAVOR="${3:-m1.tiny}"
SECURITY_GROUP="${4:-minimal-sg}"
KEY_NAME="${5:-cloud-key}"

# 创建user-data文件
cat > /tmp/user-data-$$.txt << 'DATA_EOF'
#!/bin/bash
# 基础初始化脚本
echo "开始系统初始化..."

# 1. 软件包更新和安装
apk update
apk add curl wget vim htop

# 2. 创建应用目录
mkdir -p /opt/app/{config,logs,data}

# 3. 创建监控脚本
cat > /opt/health-check.sh << 'SCRIPT_EOF'
#!/bin/bash
echo "Health check at $(date)"
echo "CPU: $(top -bn1 | grep load)"
echo "Memory: $(free -m)"
echo "Disk: $(df -h /)"
SCRIPT_EOF
chmod +x /opt/health-check.sh

# 4. 配置定时任务
echo "*/5 * * * * /opt/health-check.sh >> /opt/app/logs/health.log" >> /etc/crontabs/root

# 5. 设置主机名
echo "${VM_NAME}" > /etc/hostname
hostname ${VM_NAME}

echo "初始化完成于 $(date)"
DATA_EOF

# 创建云主机
echo "创建云主机: $VM_NAME"
openstack server create \
  --image cirros \
  --flavor $FLAVOR \
  --network $NETWORK \
  --security-group $SECURITY_GROUP \
  --key-name $KEY_NAME \
  --user-data /tmp/user-data-$$.txt \
  $VM_NAME

# 清理临时文件
rm -f /tmp/user-data-$$.txt

echo "云主机 $VM_NAME 创建命令已执行"
echo "请等待云主机启动后分配浮动IP"
EOF