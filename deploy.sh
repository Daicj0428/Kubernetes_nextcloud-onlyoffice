#!/bin/bash

set -e

echo "开始部署Nextcloud集群..."

NAMESPACE="nextcloud"
CHECKPOINT_FILE="/tmp/nextcloud_deploy_checkpoint"
FORCE_RESTART=${1:-false}

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_debug() {
    echo -e "${CYAN}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# 检查点函数
checkpoint() {
    local step=$1
    echo "$step" > $CHECKPOINT_FILE
    log_info "检查点保存: $step"
}

get_current_checkpoint() {
    if [[ -f $CHECKPOINT_FILE ]]; then
        cat $CHECKPOINT_FILE
    else
        echo "start"
    fi
}

# 资源检查函数
check_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-$NAMESPACE}
    
    kubectl get $resource_type $resource_name -n $namespace > /dev/null 2>&1
    return $?
}

# 等待资源就绪函数
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-$NAMESPACE}
    local timeout=${4:-300}
    
    log_info "等待 $resource_type/$resource_name 就绪 (超时: ${timeout}s)..."
    
    if kubectl wait --for=condition=ready $resource_type/$resource_name -n $namespace --timeout=${timeout}s; then
        log_info "$resource_type/$resource_name 已就绪"
        return 0
    else
        log_error "$resource_type/$resource_name 就绪等待超时"
        return 1
    fi
}

# 检查Pod状态
check_pod_status() {
    local pod_name=$1
    local namespace=${2:-$NAMESPACE}
    
    kubectl get pod $pod_name -n $namespace -o jsonpath='{.status.phase}' 2>/dev/null
}

# 获取Pod日志
get_pod_logs() {
    local pod_name=$1
    local namespace=${2:-$NAMESPACE}
    local tail=${3:-20}
    
    log_info "获取Pod $pod_name 日志 (最后${tail}行):"
    kubectl logs $pod_name -n $namespace --tail=$tail || log_warn "无法获取Pod $pod_name 日志"
}

# 验证部署环境
validate_environment() {
    log_step "验证Kubernetes环境..."
    
    # 检查kubectl是否可用
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未找到，请安装kubectl"
        exit 1
    fi
    
    # 检查Kubernetes集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
    
    log_info "Kubernetes环境验证通过"
}

# 强制重启处理
if [[ "$FORCE_RESTART" == "true" ]]; then
    log_warn "强制重启模式，清除所有检查点"
    rm -f $CHECKPOINT_FILE
fi

# 验证环境
validate_environment

CURRENT_CHECKPOINT=$(get_current_checkpoint)
log_info "当前检查点: $CURRENT_CHECKPOINT"

# 步骤1: 创建命名空间
if [[ "$CURRENT_CHECKPOINT" == "start" ]]; then
    log_step "步骤1: 创建命名空间"
    kubectl apply -f 1-namespace.yaml
    checkpoint "namespace_created"
    CURRENT_CHECKPOINT="namespace_created"
fi

# 步骤2: 部署资源限制
if [[ "$CURRENT_CHECKPOINT" == "namespace_created" ]]; then
    log_step "步骤2: 部署资源限制"
    kubectl apply -f 2-ResourceQuota.yaml -f 3-limitRange.yaml
    checkpoint "resource_limits_applied"
    CURRENT_CHECKPOINT="resource_limits_applied"
fi

# 步骤3: 部署存储
if [[ "$CURRENT_CHECKPOINT" == "resource_limits_applied" ]]; then
    log_step "步骤3: 部署存储"
    
    # 检查并部署RBAC
    if ! check_resource serviceaccount nfs-client-provisioner; then
        log_info "部署NFS Provisioner RBAC..."
        kubectl apply -f 4-rbac.yaml
    else
        log_info "NFS Provisioner RBAC 已存在"
    fi
    
    # 检查并部署NFS Provisioner
    if ! check_resource deployment nfs-client-provisioner; then
        log_info "部署NFS Provisioner..."
        kubectl apply -f 5-deployment.yaml
    else
        log_info "NFS Provisioner 已存在"
    fi
    
    # 检查并部署StorageClass
    if ! check_resource storageclass nfs-client; then
        log_info "部署StorageClass..."
        kubectl apply -f 6-sc.yaml
    else
        log_info "StorageClass 已存在"
    fi
    
    checkpoint "storage_deployed"
    CURRENT_CHECKPOINT="storage_deployed"
fi

# 步骤4: 等待NFS provisioner启动
if [[ "$CURRENT_CHECKPOINT" == "storage_deployed" ]]; then
    log_step "步骤4: 等待NFS Provisioner启动..."
    
    # 等待Deployment创建Pod
    sleep 10
    
    # 获取Pod名称
    NFS_POD=$(kubectl get pod -n $NAMESPACE -l app=nfs-client-provisioner -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    
    if [[ -z "$NFS_POD" ]]; then
        log_error "未找到NFS Provisioner Pod"
        exit 1
    fi
    
    if wait_for_resource pod $NFS_POD $NAMESPACE 180; then
        log_info "NFS Provisioner 已就绪"
        checkpoint "nfs_provisioner_ready"
        CURRENT_CHECKPOINT="nfs_provisioner_ready"
    else
        log_error "NFS Provisioner 启动失败"
        get_pod_logs $NFS_POD
        exit 1
    fi
fi

# 步骤5: 创建PVC
if [[ "$CURRENT_CHECKPOINT" == "nfs_provisioner_ready" ]]; then
    log_step "步骤5: 创建PVC"
    
    # 检查并创建PVC
    for pvc in mysql-master-pvc mysql-slave-pvc nextcloud-pvc; do
        if ! check_resource pvc $pvc; then
            log_info "创建PVC: $pvc"
        else
            log_info "PVC $pvc 已存在"
        fi
    done
    
    kubectl apply -f 7-pvc.yaml
    
    # 检查PVC是否绑定
    log_info "检查PVC状态..."
    for pvc in mysql-master-pvc mysql-slave-pvc nextcloud-pvc; do
        max_wait=120
        wait_time=0
        
        while [[ $wait_time -lt $max_wait ]]; do
            pvc_phase=$(kubectl get pvc $pvc -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
            if [[ "$pvc_phase" == "Bound" ]]; then
                log_info "PVC $pvc 已绑定"
                break
            else
                log_debug "PVC $pvc 状态: $pvc_phase, 等待中... (${wait_time}s)"
                sleep 5
                ((wait_time+=5))
            fi
        done
        
        if [[ $wait_time -ge $max_wait ]]; then
            log_warn "PVC $pvc 绑定超时，状态: $pvc_phase"
            # 不退出，继续执行
        fi
    done
    
    checkpoint "pvc_created"
    CURRENT_CHECKPOINT="pvc_created"
fi

# 步骤6: 部署MySQL Master
if [[ "$CURRENT_CHECKPOINT" == "pvc_created" ]]; then
    log_step "步骤6: 部署MySQL Master"
    
    if ! check_resource statefulset mysql-master; then
        kubectl apply -f 8-1-mysql-master.yaml
        log_info "MySQL Master 已创建"
    else
        log_info "MySQL Master 已存在，跳过部署"
    fi
    
    checkpoint "mysql_master_deployed"
    CURRENT_CHECKPOINT="mysql_master_deployed"
fi

# 步骤7: 等待MySQL Master启动
if [[ "$CURRENT_CHECKPOINT" == "mysql_master_deployed" ]]; then
    log_step "步骤7: 等待MySQL Master启动..."
    
    if wait_for_resource pod mysql-master-0 $NAMESPACE 600; then
        log_info "MySQL Master 已就绪"
        
        # 额外等待确保MySQL服务完全启动
        sleep 30
        
        # 验证MySQL服务
        log_info "验证MySQL Master服务..."
        if kubectl exec -i -n $NAMESPACE mysql-master-0 -- mysql -uroot -ppassword -e "SELECT 1;" &> /dev/null; then
            log_info "MySQL Master 服务验证成功"
        else
            log_warn "MySQL Master 服务响应较慢，继续执行..."
        fi
        
        checkpoint "mysql_master_ready"
        CURRENT_CHECKPOINT="mysql_master_ready"
    else
        log_error "MySQL Master 启动失败"
        get_pod_logs mysql-master-0
        exit 1
    fi
fi

# 步骤8: 部署MySQL Slave
if [[ "$CURRENT_CHECKPOINT" == "mysql_master_ready" ]]; then
    log_step "步骤8: 部署MySQL Slave"
    
    if ! check_resource statefulset mysql-slave; then
        kubectl apply -f 8-2-mysql-slave.yaml
        log_info "MySQL Slave 已创建"
    else
        log_info "MySQL Slave 已存在，跳过部署"
    fi
    
    checkpoint "mysql_slave_deployed"
    CURRENT_CHECKPOINT="mysql_slave_deployed"
fi

# 步骤9: 等待MySQL Slave启动
if [[ "$CURRENT_CHECKPOINT" == "mysql_slave_deployed" ]]; then
    log_step "步骤9: 等待MySQL Slave启动..."
    
    if wait_for_resource pod mysql-slave-0 $NAMESPACE 600; then
        log_info "MySQL Slave 已就绪"
        
        # 额外等待确保MySQL服务完全启动
        sleep 30
        
        checkpoint "mysql_ready"
        CURRENT_CHECKPOINT="mysql_ready"
    else
        log_error "MySQL Slave 启动失败"
        get_pod_logs mysql-slave-0
        exit 1
    fi
fi

# 步骤10: 配置MySQL主从复制
if [[ "$CURRENT_CHECKPOINT" == "mysql_ready" ]]; then
    log_step "步骤10: 配置MySQL主从复制"
    
    # 确保Master完全就绪
    log_info "等待MySQL Master完全就绪..."
    sleep 30
    
    # 创建复制用户
    log_info "创建复制用户..."
    if kubectl exec -i -n $NAMESPACE mysql-master-0 -- mysql -uroot -ppassword << EOF
CREATE USER IF NOT EXISTS 'slave'@'%' IDENTIFIED BY '123456';
GRANT REPLICATION SLAVE ON *.* TO 'slave'@'%';
FLUSH PRIVILEGES;
FLUSH TABLES WITH READ LOCK;
EOF
    then
        log_info "复制用户创建成功"
    else
        log_error "复制用户创建失败"
        exit 1
    fi

    # 获取Master状态
    log_info "获取Master状态..."
    MASTER_STATUS=$(kubectl exec -i -n $NAMESPACE mysql-master-0 -- mysql -uroot -ppassword -e "SHOW MASTER STATUS\G")
    LOG_FILE=$(echo "$MASTER_STATUS" | grep "File:" | awk '{print $2}')
    LOG_POS=$(echo "$MASTER_STATUS" | grep "Position:" | awk '{print $2}')
    
    if [[ -z "$LOG_FILE" || -z "$LOG_POS" ]]; then
        log_error "无法获取Master状态"
        exit 1
    fi
    
    echo "Master Log File: $LOG_FILE"
    echo "Master Log Position: $LOG_POS"
    
    # 解锁Master表
    kubectl exec -i -n $NAMESPACE mysql-master-0 -- mysql -uroot -ppassword -e "UNLOCK TABLES;" || true
    
    # 配置Slave
    log_info "配置Slave复制..."
    if kubectl exec -i -n $NAMESPACE mysql-slave-0 -- mysql -uroot -ppassword << EOF
STOP SLAVE;
RESET SLAVE ALL;
CHANGE MASTER TO
    MASTER_HOST='mysql-master',
    MASTER_USER='slave',
    MASTER_PASSWORD='123456',
    MASTER_LOG_FILE='$LOG_FILE',
    MASTER_LOG_POS=$LOG_POS,
    MASTER_CONNECT_RETRY=10,
    MASTER_RETRY_COUNT=100;
START SLAVE;
EOF
    then
        log_info "Slave复制配置成功"
    else
        log_error "Slave复制配置失败"
        exit 1
    fi
    
    # 等待复制启动
    log_info "等待复制启动..."
    sleep 30
    
    # 验证复制状态
    log_info "验证MySQL复制状态..."
    max_retries=10
    retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        SLAVE_STATUS=$(kubectl exec -i -n $NAMESPACE mysql-slave-0 -- mysql -uroot -ppassword -e "SHOW SLAVE STATUS \G" 2>/dev/null || true)
        
        IO_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_IO_Running:" | awk '{print $2}' || echo "No")
        SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}' || echo "No")
        
        if [[ "$IO_RUNNING" == "Yes" ]] && [[ "$SQL_RUNNING" == "Yes" ]]; then
            log_info "MySQL 主从复制已配置成功"
            log_info "IO线程状态: $IO_RUNNING"
            log_info "SQL线程状态: $SQL_RUNNING"
            
            # 显示Seconds Behind Master
            SECONDS_BEHIND=$(echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master:" | awk '{print $2}' || echo "Unknown")
            log_info "复制延迟: $SECONDS_BEHIND 秒"
            
            checkpoint "mysql_replication_configured"
            CURRENT_CHECKPOINT="mysql_replication_configured"
            break
        else
            ((retry_count++))
            log_warn "复制状态检查失败 (尝试 $retry_count/$max_retries)"
            log_warn "IO线程状态: $IO_RUNNING"
            log_warn "SQL线程状态: $SQL_RUNNING"
            
            if [[ $retry_count -eq $max_retries ]]; then
                log_error "MySQL 主从复制配置失败"
                
                # 显示错误信息
                LAST_IO_ERROR=$(echo "$SLAVE_STATUS" | grep "Last_IO_Error:" | cut -d: -f2- | sed 's/^ *//' || echo "None")
                LAST_SQL_ERROR=$(echo "$SLAVE_STATUS" | grep "Last_SQL_Error:" | cut -d: -f2- | sed 's/^ *//' || echo "None")
                
                if [[ "$LAST_IO_ERROR" != "None" ]]; then
                    log_error "Last IO Error: $LAST_IO_ERROR"
                fi
                if [[ "$LAST_SQL_ERROR" != "None" ]]; then
                    log_error "Last SQL Error: $LAST_SQL_ERROR"
                fi
                
                exit 1
            fi
            
            sleep 10
        fi
    done
fi

# 步骤11: 部署Redis配置
if [[ "$CURRENT_CHECKPOINT" == "mysql_replication_configured" ]]; then
    log_step "步骤11: 部署Redis配置"
    kubectl apply -f 9-1-redis-config.yaml
    checkpoint "redis_config_applied"
    CURRENT_CHECKPOINT="redis_config_applied"
fi

# 步骤12: 部署Redis单节点
if [[ "$CURRENT_CHECKPOINT" == "redis_config_applied" ]]; then
    log_step "步骤12: 部署Redis单节点"
    
    if ! check_resource deployment redis; then
        kubectl apply -f 9-2-redis-deployment.yaml
        log_info "Redis单节点已创建"
    else
        log_info "Redis单节点已存在，跳过部署"
    fi
    
    checkpoint "redis_deployed"
    CURRENT_CHECKPOINT="redis_deployed"
fi

# 步骤13: 等待Redis启动
if [[ "$CURRENT_CHECKPOINT" == "redis_deployed" ]]; then
    log_step "步骤13: 等待Redis启动..."
    
    # 方法1: 等待Deployment就绪
    if wait_for_resource deployment redis $NAMESPACE 300; then
        log_info "Redis 已就绪"
        checkpoint "redis_ready"
        CURRENT_CHECKPOINT="redis_ready"
    else
        # 方法2: 如果等待Deployment失败，检查Pod状态
        log_warn "Deployment等待超时，检查Pod状态..."
        REDIS_POD=$(kubectl get pod -n $NAMESPACE -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        
        if [[ -n "$REDIS_POD" ]]; then
            pod_status=$(check_pod_status $REDIS_POD)
            if [[ "$pod_status" == "Running" ]]; then
                log_info "Redis Pod 正在运行，继续执行..."
                checkpoint "redis_ready"
                CURRENT_CHECKPOINT="redis_ready"
            else
                log_error "Redis Pod 状态为: $pod_status"
                get_pod_logs $REDIS_POD
                exit 1
            fi
        else
            log_error "未找到Redis Pod"
            exit 1
        fi
    fi
fi

# 步骤14: 部署Nextcloud配置
if [[ "$CURRENT_CHECKPOINT" == "redis_ready" ]]; then
    log_step "步骤14: 部署Nextcloud配置"
    
    # 部署ConfigMap
    kubectl apply -f 10-2-nextcloud-cm.yaml
    
    # 部署PHP配置
    if [[ -f "10-4-nextcloud-php.yaml" ]]; then
        kubectl apply -f 10-4-nextcloud-php.yaml
    fi
    
    # 部署Secrets（如果存在）
    if [[ -f "10-1-secrets.yaml" ]]; then
        kubectl apply -f 10-1-secrets.yaml
    fi
    
    checkpoint "nextcloud_config_applied"
    CURRENT_CHECKPOINT="nextcloud_config_applied"
fi

# 步骤15: 部署Nextcloud应用
if [[ "$CURRENT_CHECKPOINT" == "nextcloud_config_applied" ]]; then
    log_step "步骤15: 部署Nextcloud应用"
    
    log_info "部署Nextcloud..."
    kubectl apply -f 10-3-nextcloud-deployment.yaml -f 10-4-nextcloud-service.yaml
    
    # 部署Ingress（如果存在）
    if [[ -f "10-5-nextcloud-ingress.yaml" ]]; then
        kubectl apply -f 10-5-nextcloud-ingress.yaml
    fi
    
    checkpoint "nextcloud_app_deployed"
    CURRENT_CHECKPOINT="nextcloud_app_deployed"
fi

# 步骤16: 等待Nextcloud启动
if [[ "$CURRENT_CHECKPOINT" == "nextcloud_app_deployed" ]]; then
    log_step "步骤15: 等待Nextcloud Pod启动..."
    
    # 等待Deployment创建Pod
    sleep 20
    
    # 获取Nextcloud Pod名称
    NEXTCLOUD_POD=$(kubectl get pod -n $NAMESPACE -l app=nextcloud -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    
    if [[ -z "$NEXTCLOUD_POD" ]]; then
        log_warn "未找到Nextcloud Pod，请检查Deployment状态"
    else
        max_wait=300
        wait_time=0
        
        while [[ $wait_time -lt $max_wait ]]; do
            pod_status=$(check_pod_status $NEXTCLOUD_POD)
            
            if [[ "$pod_status" == "Running" ]]; then
                log_info "Nextcloud Pod 正在运行"
                break
            elif [[ "$pod_status" == "Pending" ]]; then
                log_debug "Nextcloud Pod 状态: Pending"
            elif [[ "$pod_status" == "Failed" ]]; then
                log_error "Nextcloud Pod 启动失败"
                get_pod_logs $NEXTCLOUD_POD
                break
            else
                log_debug "Nextcloud Pod 状态: $pod_status"
            fi
            
            sleep 10
            ((wait_time+=10))
        done
        
        if [[ $wait_time -ge $max_wait ]]; then
            log_warn "Nextcloud Pod 启动超时，请手动检查状态"
        fi
    fi
    
    # 显示部署完成信息
    echo ""
    echo "=================================================="
    echo "            Nextcloud 部署完成"
    echo "=================================================="
    echo ""
    echo "访问方式:"
    echo "1. 通过NodePort访问: http://<节点IP>:32048"
    echo "2. 端口转发临时访问:"
    echo "   kubectl port-forward svc/nextcloud 8080:80 -n nextcloud"
    echo "   然后访问: http://localhost:8080"
    echo ""
    echo "手动安装配置:"
    echo "  创建管理员账号:"
    echo "    用户名: 自定义"
    echo "    密码: 自定义"
    echo "  数据目录: /var/www/html/data"
    echo ""
    echo "数据库配置:"
    echo "  数据库类型: MySQL/MariaDB"
    echo "  数据库主机: mysql-master"
    echo "  数据库名: nextcloud"
    echo "  数据库用户: nextcloud"  
    echo "  数据库密码: password"
    echo ""
    echo "Redis配置 (可选，提升性能):"
    echo "  主机: redis"
    echo "  端口: 6379"
    echo "  密码: password"
    echo ""
    echo "故障排查命令:"
    echo "  kubectl get pods -n nextcloud"
    echo "  kubectl logs -l app=nextcloud -n nextcloud --tail=50"
    echo "  kubectl describe pod -l app=nextcloud -n nextcloud"
    echo "=================================================="

    checkpoint "deployment_completed"
    log_info "Nextcloud集群部署完成!"
fi

# 清理检查点文件（可选）
rm -f $CHECKPOINT_FILE
