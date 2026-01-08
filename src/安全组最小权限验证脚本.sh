#!/bin/bash
# 安全组最小权限验证脚本

FLOAT_IP=$1
if [ -z "$FLOAT_IP" ]; then
    echo "请提供云主机浮动IP"
    exit 1
fi

echo "=== 安全组最小权限验证 ==="
echo "测试目标: $FLOAT_IP"
echo ""

# 测试允许的端口
echo "1. 测试允许的端口:"
echo "   a) SSH (22端口):"
if nc -z -w 2 $FLOAT_IP 22; then
    echo "      允许 ✓"
else
    echo "      拒绝 ✗"
fi

echo ""
echo "   b) ICMP (ping):"
if ping -c 2 -W 1 $FLOAT_IP &> /dev/null; then
    echo "      允许 ✓"
else
    echo "      拒绝 ✗"
fi

echo ""
# 测试不允许的端口（应该被拒绝）
echo "2. 测试未允许的端口（应该被拒绝）:"
PORTS="80 443 3306 3389 8080"
for port in $PORTS; do
    if nc -z -w 2 $FLOAT_IP $port 2>/dev/null; then
        echo "  端口 $port: 允许 ✗ (安全漏洞!)"
    else
        echo "  端口 $port: 拒绝 ✓"
    fi
done

echo ""
echo "3. 安全组规则检查:"
openstack security group rule list minimal-sg -c "IP Protocol" -c "Port Range" -c "Remote IP Prefix"

echo ""
echo "=== 验证结果 ==="
echo "如果只有SSH(22)和ICMP被允许，其他端口都被拒绝，则符合最小权限原则。"
EOF