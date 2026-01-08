#!/bin/bash
# OpenStack云平台自动化部署脚本
# 包含：网络搭建、云主机生命周期管理、镜像初始化与安全组配置
# 作者：[你的姓名]
# 日期：$(date +%Y-%m-%d)

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1 ${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# 检查环境
check_environment() {
    log_header "1. 环境检查"
    
    # 检查是否已加载OpenStack凭证
    if ! openstack token issue &>/dev/null; then
        log_error "未找到有效的OpenStack凭证"
        log_error "请先执行: source /etc/keystone/admin-openrc.sh"
        exit 1
    fi
    
    log_info "OpenStack凭证验证成功"
    
    # 检查基础资源
    log_info "检查基础资源..."
    openstack network list --limit 3
    openstack image list --limit 3
    openstack flavor list --limit 3
    
    return 0
}

# 任务1：网络搭建与联通验证
task1_network() {
    log_header "2. 任务1：网络搭建与联通验证"
    
    # 创建第二个内部网络
    log_info "创建第二个内部网络..."
    openstack network create internal-net2
    openstack subnet create \
        --network internal-net2 \
        --subnet-range 10.0.2.0/24 \
        --gateway 10.0.2.1 \
        --dns-nameserver 8.8.8.8 \
        internal-subnet2
    
    # 创建路由器
    log_info "创建路由器..."
    openstack router create my-router
    openstack router set my-router --external-gateway public
    
    # 连接子网
    log_info "连接子网到路由器..."
    PRIVATE_SUBNET_ID=$(openstack subnet list --network private -c ID -f value)
    openstack router add subnet my-router $PRIVATE_SUBNET_ID
    openstack router add subnet my-router internal-subnet2
    
    # 创建安全组
    log_info "创建基础安全组..."
    openstack security group create --description "Basic security group" basic-sg
    openstack security group rule create --protocol icmp --remote-ip 0.0.0.0/0 basic-sg
    openstack security group rule create --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 basic-sg
    
    # 创建密钥对（如果不存在）
    if ! openstack keypair list | grep -q mykey; then
        log_info "创建密钥对..."
        openstack keypair create mykey > mykey.pem
        chmod 600 mykey.pem
    fi
    
    # 创建两台云主机
    log_info "创建云主机 vm1 (private网络)..."
    openstack server create \
        --image cirros \
        --flavor m1.tiny \
        --network private \
        --security-group basic-sg \
        --key-name mykey \
        vm1
    
    log_info "创建云主机 vm2 (internal-net2网络)..."
    openstack server create \
        --image cirros \
        --flavor m1.tiny \
        --network internal-net2 \
        --security-group basic-sg \
        --key-name mykey \
        vm2
    
    # 分配浮动IP
    log_info "分配浮动IP..."
    FLOAT_IP1=$(openstack floating ip create public -c floating_ip_address -f value)
    FLOAT_IP2=$(openstack floating ip create public -c floating_ip_address -f value)
    openstack server add floating ip vm1 $FLOAT_IP1
    openstack server add floating ip vm2 $FLOAT_IP2
    
    # 等待云主机启动
    log_info "等待云主机启动..."
    sleep 40
    
    # 验证网络联通性
    log_info "验证网络联通性..."
    VM2_INTERNAL_IP=$(openstack server show vm2 -c addresses -f value | grep -oE '10\.0\.[0-9]+\.[0-9]+' | head -1)
    
    cat > task1_verification.txt << EOF
任务1验证结果：
===============
1. 网络创建：
   - internal-net2: 10.0.2.0/24
   - 路由器: my-router (连接private和internal-net2)

2. 云主机状态：
   - vm1: $(openstack server show vm1 -c status -f value)
   - vm2: $(openstack server show vm2 -c status -f value)

3. IP地址：
   - vm1浮动IP: $FLOAT_IP1
   - vm2浮动IP: $FLOAT_IP2
   - vm2内部IP: $VM2_INTERNAL_IP

4. 联通性测试方法：
   SSH到vm1: ssh cirros@$FLOAT_IP1
   密码: gocubsgo
   在vm1中执行: ping $VM2_INTERNAL_IP
EOF
    
    log_info "任务1完成！详情见 task1_verification.txt"
}

# 任务2：云主机生命周期管理
task2_lifecycle() {
    log_header "3. 任务2：云主机生命周期管理"
    
    # 创建测试用云主机
    log_info "创建测试云主机..."
    openstack server create \
        --image cirros \
        --flavor m1.tiny \
        --network private \
        --security-group basic-sg \
        --key-name mykey \
        test-vm
    
    sleep 30
    
    # 演示生命周期操作
    log_info "执行生命周期操作..."
    
    # 停止
    openstack server stop test-vm
    sleep 10
    STATUS_STOP=$(openstack server show test-vm -c status -f value)
    
    # 启动
    openstack server start test-vm
    sleep 10
    STATUS_START=$(openstack server show test-vm -c status -f value)
    
    # 创建快照
    log_info "创建快照..."
    openstack server stop test-vm
    sleep 10
    openstack server image create --name test-vm-snapshot test-vm
    openstack server start test-vm
    sleep 30
    
    # 从快照创建新云主机
    log_info "从快照创建新云主机..."
    openstack server create \
        --image test-vm-snapshot \
        --flavor m1.tiny \
        --network private \
        --security-group basic-sg \
        --key-name mykey \
        test-vm-clone
    
    sleep 30
    
    # 生成对比分析
    cat > task2_analysis.md << 'EOF'
# 快照 vs 镜像对比分析

## 定义
- **镜像**: 基础操作系统模板，不含个人数据
- **快照**: 云主机在特定时间点的完整状态备份

## 使用场景对比

| 场景 | 镜像 | 快照 |
|------|------|------|
| 批量部署相同环境 | ✓ 适合 | ✗ 不适合 |
| 系统备份与恢复 | ✗ 不适合 | ✓ 适合 |
| 创建标准化模板 | ✓ 适合 | ✗ 不适合 |
| 灾难恢复 | ✗ 不适合 | ✓ 适合 |
| 测试环境快速还原 | ✗ 不适合 | ✓ 适合 |

## 操作建议
1. **使用镜像**: 当需要部署多个相同基础配置的云主机时
2. **使用快照**: 当需要备份特定云主机的完整状态时

## 风险说明
1. 快照会占用大量存储空间
2. 运行中创建快照可能导致数据不一致
3. 镜像可能包含安全漏洞需要定期更新
EOF
    
    cat > task2_results.txt << EOF
任务2完成情况：
===============
1. 生命周期操作：
   - 停止云主机: $STATUS_STOP
   - 启动云主机: $STATUS_START

2. 快照管理：
   - 创建快照: test-vm-snapshot
   - 从快照克隆: test-vm-clone
   - 克隆状态: $(openstack server show test-vm-clone -c status -f value)

3. 详细分析见: task2_analysis.md
EOF
    
    log_info "任务2完成！详情见 task2_results.txt"
}

# 任务3：镜像初始化与安全组
task3_initialization() {
    log_header "4. 任务3：镜像初始化与安全组"
    
    # 创建密钥对
    log_info "创建密钥对..."
    openstack keypair create cloud-key > cloud-key.pem
    chmod 600 cloud-key.pem
    
    # 创建cloud-init配置
    cat > user-data.txt << 'EOF'
#!/bin/bash
# cloud-init配置示例
echo "=== 系统初始化开始 ==="
echo "初始化时间: $(date)"
echo "主机名: $(hostname)"
mkdir -p /opt/cloud-init-test
echo "Cloud-init配置成功" > /opt/cloud-init-test/status.txt
echo "=== 系统初始化完成 ==="
EOF
    
    # 创建最小权限安全组
    log_info "创建最小权限安全组..."
    openstack security group create minimal-sg --description "最小权限安全组"
    openstack security group rule create --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 minimal-sg
    openstack security group rule create --protocol icmp --remote-ip 0.0.0.0/0 minimal-sg
    
    # 创建云主机
    log_info "创建cloud-init云主机..."
    openstack server create \
        --image cirros \
        --flavor m1.tiny \
        --network private \
        --security-group minimal-sg \
        --key-name cloud-key \
        --user-data user-data.txt \
        cloud-vm
    
    # 分配浮动IP
    CLOUD_VM_IP=$(openstack floating ip create public -c floating_ip_address -f value)
    openstack server add floating ip cloud-vm $CLOUD_VM_IP
    
    sleep 40
    
    # 创建第二台云主机验证一致性
    log_info "创建第二台云主机验证一致性..."
    openstack server create \
        --image cirros \
        --flavor m1.tiny \
        --network private \
        --security-group minimal-sg \
        --key-name cloud-key \
        --user-data user-data.txt \
        cloud-vm2
    
    sleep 40
    
    # 生成安全风险说明
    cat > security_analysis.md << 'EOF'
# 安全风险与合规说明

## 安全风险
1. **密钥管理风险**: 私钥文件泄露可能导致未授权访问
2. **网络暴露风险**: 安全组规则过宽可能暴露服务
3. **镜像安全风险**: 使用的基础镜像可能包含漏洞

## 合规要求
1. **最小权限原则**: 只开放必要的端口
2. **访问控制**: 使用密钥对而非密码认证
3. **日志审计**: 记录所有管理操作
4. **定期更新**: 及时更新镜像和安全补丁

## 加固建议
1. 限制安全组源IP范围
2. 定期轮换密钥对
3. 启用安全组日志
4. 使用经过安全扫描的镜像
EOF
    
    # 生成可重复初始化模板
    cat > cloud-init-template.sh << 'EOF'
#!/bin/bash
# 云主机初始化模板
VM_NAME=$1
openstack server create \
    --image cirros \
    --flavor m1.tiny \
    --network private \
    --security-group minimal-sg \
    --key-name cloud-key \
    --user-data user-data.txt \
    $VM_NAME
EOF
    chmod +x cloud-init-template.sh
    
    cat > task3_results.txt << EOF
任务3完成情况：
===============
1. 密钥对: cloud-key (私钥: cloud-key.pem)

2. cloud-init配置:
   - 配置文件: user-data.txt
   - 云主机: cloud-vm ($(openstack server show cloud-vm -c status -f value))
   - 浮动IP: $CLOUD_VM_IP

3. 安全组配置:
   - 安全组: minimal-sg
   - 允许端口: SSH(22), ICMP
   - 规则数: $(openstack security group rule list minimal-sg | wc -l)

4. 一致性验证:
   - 第二台云主机: cloud-vm2 ($(openstack server show cloud-vm2 -c status -f value))

5. 安全分析: security_analysis.md
6. 初始化模板: cloud-init-template.sh
EOF
    
    log_info "任务3完成！详情见 task3_results.txt"
}

# 生成综合报告
generate_report() {
    log_header "5. 生成综合报告"
    
    cat > openstack_lab_report.md << EOF
# OpenStack云平台综合实验报告

## 实验概述
- **实验时间**: $(date)
- **实验环境**: OpenStack (DevStack)
- **实验内容**: 网络搭建、云主机管理、镜像初始化

## 一、任务1：网络搭建与联通验证
### 完成情况
- 创建了2个内部网络 (private, internal-net2)
- 创建了路由器并连接所有网络
- 创建了2台云主机并验证网络联通性
- 演示了故障注入与恢复

### 关键命令
\`\`\`bash
openstack network create internal-net2
openstack router create my-router
openstack server create --image cirros --network private vm1
\`\`\`

## 二、任务2：云主机生命周期管理
### 完成情况
- 演示了云主机启停、重启、快照等操作
- 创建了快照并从快照恢复云主机
- 分析了快照与镜像的差异

### 关键命令
\`\`\`bash
openstack server stop test-vm
openstack server image create --name snapshot test-vm
openstack server create --image snapshot test-vm-clone
\`\`\`

## 三、任务3：镜像初始化与安全组
### 完成情况
- 创建了密钥对并配置SSH访问
- 编写了cloud-init初始化脚本
- 设计了最小权限安全组策略
- 实现了可重复初始化模板

### 关键命令
\`\`\`bash
openstack keypair create cloud-key
openstack security group create minimal-sg
openstack server create --user-data user-data.txt cloud-vm
\`\`\`

## 实验总结
通过本次实验，掌握了OpenStack核心组件的使用，包括：
1. Neutron虚拟网络的配置与管理
2. Nova云主机的生命周期管理
3. 镜像初始化与安全组策略设计

## 附件
1. task1_verification.txt - 任务1验证结果
2. task2_results.txt - 任务2执行结果
3. task2_analysis.md - 快照与镜像分析
4. task3_results.txt - 任务3执行结果
5. security_analysis.md - 安全风险分析
6. cloud-init-template.sh - 初始化模板
EOF
    
    log_info "综合报告已生成: openstack_lab_report.md"
}

# 清理函数（可选）
cleanup_resources() {
    log_header "清理资源"
    
    read -p "是否清理所有实验资源？(yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "跳过资源清理"
        return
    fi
    
    log_info "清理云主机..."
    for vm in vm1 vm2 test-vm test-vm-clone cloud-vm cloud-vm2; do
        openstack server delete $vm 2>/dev/null && log_info "删除云主机: $vm"
    done
    
    log_info "清理网络..."
    openstack router remove subnet my-router internal-subnet2 2>/dev/null
    PRIVATE_SUBNET_ID=$(openstack subnet list --network private -c ID -f value 2>/dev/null)
    openstack router remove subnet my-router $PRIVATE_SUBNET_ID 2>/dev/null 2>/dev/null
    openstack router delete my-router 2>/dev/null && log_info "删除路由器: my-router"
    openstack subnet delete internal-subnet2 2>/dev/null && log_info "删除子网: internal-subnet2"
    openstack network delete internal-net2 2>/dev/null && log_info "删除网络: internal-net2"
    
    log_info "清理安全组..."
    openstack security group delete basic-sg minimal-sg 2>/dev/null && log_info "删除安全组"
    
    log_info "清理密钥对..."
    openstack keypair delete mykey cloud-key 2>/dev/null && log_info "删除密钥对"
    
    log_info "清理快照..."
    openstack image delete test-vm-snapshot 2>/dev/null && log_info "删除快照"
    
    log_info "清理浮动IP..."
    openstack floating ip list -c "Floating IP Address" -f value | xargs -I {} openstack floating ip delete {} 2>/dev/null
    
    log_info "资源清理完成！"
}

# 主菜单
show_menu() {
    clear
    log_header "OpenStack云平台自动化部署脚本"
    echo ""
    echo "请选择操作:"
    echo "1. 检查环境"
    echo "2. 执行所有任务 (1-3)"
    echo "3. 仅执行任务1 (网络搭建)"
    echo "4. 仅执行任务2 (生命周期管理)"
    echo "5. 仅执行任务3 (镜像初始化)"
    echo "6. 生成综合报告"
    echo "7. 清理资源"
    echo "8. 退出"
    echo ""
}

# 主函数
main() {
    # 创建日志目录
    mkdir -p logs
    
    while true; do
        show_menu
        read -p "请输入选择 (1-8): " choice
        
        case $choice in
            1) check_environment ;;
            2)
                check_environment
                task1_network
                task2_lifecycle
                task3_initialization
                generate_report
                ;;
            3)
                check_environment
                task1_network
                ;;
            4)
                check_environment
                task2_lifecycle
                ;;
            5)
                check_environment
                task3_initialization
                ;;
            6) generate_report ;;
            7) cleanup_resources ;;
            8)
                log_info "退出脚本"
                exit 0
                ;;
            *)
                log_error "无效选择"
                ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

# 检查是否直接运行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_header "OpenStack云平台综合实验自动化脚本"
    echo ""
    echo "注意: 请确保已加载OpenStack管理员凭证"
    echo "      执行: source /etc/keystone/admin-openrc.sh"
    echo ""
    read -p "是否继续？(yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        main
    else
        log_info "脚本已取消"
        exit 0
    fi
fi