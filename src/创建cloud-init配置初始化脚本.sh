# 创建cloud-init配置
cat > user-data.txt << 'EOF'
#!/bin/bash

# 基础系统配置
echo "=== 系统初始化开始 ==="

# 1. 创建用户（cirros镜像默认只有cirros用户）
sudo useradd -m -s /bin/bash admin
echo "admin:admin123" | sudo chpasswd
sudo usermod -aG sudo admin

# 2. 创建SSH目录并设置权限
sudo mkdir -p /home/admin/.ssh
sudo chmod 700 /home/admin/.ssh

# 3. 添加公钥（请替换为你的公钥）
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...你的公钥内容... user@host" | sudo tee /home/admin/.ssh/authorized_keys
sudo chmod 600 /home/admin/.ssh/authorized_keys
sudo chown -R admin:admin /home/admin/.ssh

# 4. 安装常用工具（cirros使用apk包管理器）
sudo apk update && sudo apk add curl wget vim

# 5. 创建测试文件
sudo mkdir -p /opt/cloud-init-test
echo "Cloud-init配置成功执行于: $(date)" | sudo tee /opt/cloud-init-test/status.txt
echo "主机名: $(hostname)" | sudo tee -a /opt/cloud-init-test/status.txt
echo "IP地址: $(hostname -I)" | sudo tee -a /opt/cloud-init-test/status.txt

# 6. 配置SSH服务（允许密码登录用于测试）
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication no/#PasswordAuthentication no/' /etc/ssh/sshd_config
sudo service sshd restart

echo "=== 系统初始化完成 ==="
EOF

echo "cloud-init配置已创建: user-data.txt"