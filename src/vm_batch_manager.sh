#!/bin/bash

# 云主机批量管理脚本
# 支持：批量创建、启动、停止、删除、创建快照

set -e  # 遇到错误退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "命令 $1 不存在，请安装"
        exit 1
    fi
}

# 批量创建云主机
batch_create_vms() {
    local count=$1
    local name_prefix=$2
    
    log_info "开始批量创建 $count 台云主机，前缀: $name_prefix"
    
    for i in $(seq 1 $count); do
        local vm_name="${name_prefix}-${i}"
        
        log_info "创建云主机: $vm_name"
        
        # 尝试创建云主机
        if openstack server create \
            --image cirros \
            --flavor m1.tiny \
            --network private \
            --security-group basic-sg \
            --key-name mykey \
            $vm_name > /dev/null 2>&1; then
            
            log_info "成功创建: $vm_name"
            
            # 分配浮动IP
            local float_ip=$(openstack floating ip create public -c floating_ip_address -f value 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$float_ip" ]; then
                openstack server add floating ip $vm_name $float_ip
                log_info "分配浮动IP $float_ip 给 $vm_name"
            else
                log_warn "无法分配浮动IP给 $vm_name"
            fi
            
        else
            log_error "创建 $vm_name 失败"
            # 继续创建其他云主机
            continue
        fi
        
        # 避免创建过快
        sleep 2
    done
    
    log_info "批量创建完成"
}

# 批量操作云主机
batch_operation() {
    local operation=$1
    local name_prefix=$2
    
    log_info "批量$operation云主机，前缀: $name_prefix"
    
    # 获取匹配的云主机列表
    local vms=$(openstack server list --name "$name_prefix" -c Name -f value)
    
    if [ -z "$vms" ]; then
        log_warn "没有找到匹配的云主机"
        return
    fi
    
    for vm in $vms; do
        log_info "${operation}云主机: $vm"
        
        case $operation in
            "启动")
                openstack server start $vm || log_warn "启动 $vm 失败"
                ;;
            "停止")
                openstack server stop $vm || log_warn "停止 $vm 失败"
                ;;
            "删除")
                # 先释放浮动IP
                local float_ip=$(openstack floating ip list --port $(openstack port list --server $vm -c ID -f value 2>/dev/null) -c "Floating IP Address" -f value 2>/dev/null)
                if [ -n "$float_ip" ]; then
                    openstack floating ip delete $float_ip 2>/dev/null
                    log_info "释放浮动IP: $float_ip"
                fi
                
                # 删除云主机
                openstack server delete $vm || log_warn "删除 $vm 失败"
                ;;
            "创建快照")
                # 先停止云主机以保证一致性
                log_info "停止 $vm 以创建一致性快照"
                openstack server stop $vm
                sleep 10
                
                local snapshot_name="${vm}-snapshot-$(date +%Y%m%d-%H%M%S)"
                openstack server image create --name $snapshot_name $vm || log_warn "创建快照 $snapshot_name 失败"
                
                # 重新启动云主机
                openstack server start $vm
                ;;
            *)
                log_error "不支持的操作: $operation"
                return 1
                ;;
        esac
        
        sleep 1
    done
    
    log_info "批量${operation}完成"
}

# 清理所有测试资源
cleanup_test_resources() {
    log_warn "即将清理所有测试资源！"
    read -p "确认清理所有测试资源？(yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "取消清理操作"
        return
    fi
    
    # 清理云主机
    log_info "清理云主机..."
    for vm in $(openstack server list --name "test-" -c Name -f value); do
        log_info "删除云主机: $vm"
        # 释放浮动IP
        local float_ip=$(openstack floating ip list --port $(openstack port list --server $vm -c ID -f value 2>/dev/null) -c "Floating IP Address" -f value 2>/dev/null)
        if [ -n "$float_ip" ]; then
            openstack floating ip delete $float_ip 2>/dev/null
        fi
        openstack server delete $vm 2>/dev/null
    done
    
    # 清理快照
    log_info "清理快照..."
    for snapshot in $(openstack image list --name "test-" -c Name -f value); do
        log_info "删除快照: $snapshot"
        openstack image delete $snapshot 2>/dev/null
    done
    
    log_info "清理完成"
}

# 显示帮助
show_help() {
    cat << EOF
云主机批量管理脚本

用法: $0 [选项]

选项:
  create <数量> <前缀>     批量创建云主机
  start <前缀>            批量启动云主机
  stop <前缀>             批量停止云主机
  delete <前缀>           批量删除云主机
  snapshot <前缀>         批量创建快照
  cleanup                 清理所有测试资源
  help                    显示此帮助信息

示例:
  $0 create 5 test-vm    创建5台test-vm-1到test-vm-5
  $0 start test-vm       启动所有test-vm开头的云主机
  $0 cleanup             清理所有测试资源
EOF
}

# 主程序
main() {
    # 检查必要命令
    check_command openstack
    
    case $1 in
        create)
            if [ $# -ne 3 ]; then
                log_error "参数错误，用法: $0 create <数量> <前缀>"
                exit 1
            fi
            batch_create_vms $2 $3
            ;;
        start|stop|delete|snapshot)
            if [ $# -ne 2 ]; then
                log_error "参数错误，用法: $0 $1 <前缀>"
                exit 1
            fi
            batch_operation $1 $2
            ;;
        cleanup)
            cleanup_test_resources
            ;;
        help|*)
            show_help
            ;;
    esac
}