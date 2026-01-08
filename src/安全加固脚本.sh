#!/bin/bash
# 1. 禁用SSH密码认证
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# 2. 更改默认SSH端口
sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config

# 3. 配置fail2ban防止暴力破解
apk add fail2ban
systemctl enable fail2ban