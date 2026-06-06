# Nextcloud+Onlyoffice Kubernetes 集群部署

这是一个完整的 Nextcloud 云存储解决方案在 Kubernetes 集群上的部署配置，包含 MySQL 主从复制、Redis 缓存、NFS 存储支持和 ONLYOFFICE 在线文档编辑功能。

## 🚀 功能特性

- **完整的 Nextcloud 套件**: 包含 Web 应用、数据库和缓存层
- **高可用数据库**: MySQL 主从复制架构
- **性能优化**: Redis 缓存支持
- **在线文档编辑**: ONLYOFFICE Document Server 集成
- **持久化存储**: 基于 NFS 的动态存储供应
- **资源管理**: 资源配额和限制范围
- **健康检查**: 完整的应用健康监控
- **分步部署**: 支持检查点的可靠部署流程

## 整体架构
<img width="2189" height="1381" alt="image" src="https://github.com/user-attachments/assets/2ac04725-2ad6-4923-a7e1-bf458af1444f" />

## 📋 前置要求

### 系统要求

- Kubernetes 集群 (v1.19+)
- kubectl 配置和集群访问权限
- NFS 服务器 (192.168.28.30:/data/nfs-sc)
- Docker 镜像仓库访问
### 必需的基础组件

在部署本项目前，请确保您的 Kubernetes 集群已安装以下基础组件：
#### 1. NFS 客户端 Provisioner（可选但推荐）
如果您的集群没有可用的默认 StorageClass，本项目包含 NFS Provisioner 的部署配置：
```bash
# 项目已包含 NFS Provisioner 部署文件
kubectl apply -f 4-rbac.yaml
kubectl apply -f 5-deployment.yaml
kubectl apply -f 6-sc.yaml
```
#### 2. Ingress Controller（可选）

如需使用 Ingress 而非 NodePort 暴露服务，请预先安装 Ingress Controller：
**Nginx Ingress Controller:**

```bash
# 使用 Helm 安装
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace

# 或使用 kubectl 安装
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```
#### 3. 可用的 StorageClass

确保集群有可用的 StorageClass 用于动态存储供应：
```bash
# 检查现有 StorageClass
kubectl get storageclass

# 如果需要，设置默认 StorageClass
kubectl patch storageclass <your-storage-class> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

注意：如果使用项目内置的 NFS Provisioner，将自动创建名为 `nfs-client` 的 StorageClass。
```
### 网络要求

- 集群节点与 NFS 服务器之间的网络连通性
- 如使用 NodePort，确保防火墙允许访问 32048、32049 端口
- 集群内 DNS 服务正常运作（用于服务发现）
    
### 验证集群状态

在部署前，建议验证集群基础功能：

```bash
# 检查节点状态
kubectl get nodes

# 检查核心服务状态
kubectl get pods -n kube-system

# 检查网络连通性
kubectl run test-pod --rm -it --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local
```

### 资源要求

- CPU: 请求 4核，限制 6核
- 内存: 请求 6Gi，限制 12Gi
- 存储: 至少 31Gi NFS 存储空间
- ONLYOFFICE 额外需求: 16Gi 存储空间

## 🗂 项目结构

### 核心部署文件
```txt
.
├── 1-namespace.yaml              # 命名空间配置
├── 2-ResourceQuota.yaml          # 资源配额
├── 3-limitRange.yaml             # 限制范围
├── 4-rbac.yaml                   # NFS Provisioner RBAC
├── 5-deployment.yaml             # NFS Provisioner 部署
├── 6-sc.yaml                     # 存储类配置
├── 7-pvc.yaml                    # 持久卷声明
├── 8-1-mysql-master.yaml         # MySQL 主节点
├── 8-2-mysql-slave.yaml          # MySQL 从节点
├── 9-1-redis-config.yaml         # Redis 配置
├── 9-2-redis-deployment.yaml     # Redis 部署
├── 10-1-secrets.yaml             # 密钥配置
├── 10-2-nextcloud-cm.yaml        # Nextcloud 配置映射
├── 10-3-nextcloud-deployment.yaml # Nextcloud 部署
├── 10-4-nextcloud-php.yaml       # PHP 配置
├── 10-4-nextcloud-service.yaml   # Nextcloud 服务
├── deploy.sh                     # 自动化部署脚本
├── check-deploy-status.sh        # 部署状态检查脚本
├── reset-deploy.sh               # 重置部署脚本
└── redis单点配置.md              # Redis手动配置文档 
```


### ONLYOFFICE 集成文件
```txt
.
├── 11-1-onlyoffice-deployment.yaml     # ONLYOFFICE 部署
├── 11-2-onlyoffice-pvc.yaml            # ONLYOFFICE 存储
├── 11-3-onlyoffice-service.yaml        # ONLYOFFICE 内部服务
├── 11-4-onlyoffice-config.yaml         # ONLYOFFICE 配置
├── 11-5-onlyoffice-nodeport.yaml       # ONLYOFFICE 外部访问
└── 基于K8S Nextcloud部署onlyoffice.md  # 详细部署文档
```

## 🔧 配置说明

### 网络配置

- **Nextcloud Service**: NodePort 32048
- **MySQL Master**: Headless 服务，端口 3306
- **MySQL Slave**: Headless 服务，端口 3306
- **Redis**: 集群内部服务，端口 6379
- **ONLYOFFICE**: NodePort 32049

### 存储配置

- **StorageClass**: `nfs-client`
- **PVC 分配**:
    
    - MySQL Master: 10Gi
    - MySQL Slave: 10Gi
    - Nextcloud: 10Gi
    - Redis: 1Gi
    - ONLYOFFICE: 16Gi (5+2+5+2+2)

### 数据库配置

- **主从复制**: 自动配置
- **字符集**: utf8mb4
- **连接数**: 最大 100
- **缓冲池**: Master 512M, Slave 256M

## 🛠 部署步骤

### 快速部署
```bash
# 授予执行权限
chmod +x deploy.sh check-deploy-status.sh reset-deploy.sh

# 开始部署 Nextcloud 核心组件
./deploy.sh

# 部署 ONLYOFFICE（在 Nextcloud 部署完成后）
kubectl apply -f 11-*.yaml

# 强制重新部署（如需要）
./deploy.sh true
```

### 分步部署

#### 1. 部署 Nextcloud 核心组件

```bash
# 1. 创建命名空间和资源限制
kubectl apply -f 1-namespace.yaml
kubectl apply -f 2-ResourceQuota.yaml -f 3-limitRange.yaml

# 2. 部署存储基础设施
kubectl apply -f 4-rbac.yaml
kubectl apply -f 5-deployment.yaml
kubectl apply -f 6-sc.yaml

# 3. 创建持久化存储
kubectl apply -f 7-pvc.yaml

# 4. 部署数据库层
kubectl apply -f 8-1-mysql-master.yaml
kubectl apply -f 8-2-mysql-slave.yaml

# 5. 部署缓存层
kubectl apply -f 9-1-redis-config.yaml
kubectl apply -f 9-2-redis-deployment.yaml

# 6. 部署 Nextcloud 应用
kubectl apply -f 10-1-secrets.yaml
kubectl apply -f 10-2-nextcloud-cm.yaml
kubectl apply -f 10-3-nextcloud-deployment.yaml
kubectl apply -f 10-4-nextcloud-php.yaml
kubectl apply -f 10-4-nextcloud-service.yaml

# 部署nextcloud pod时，因应用初始化时间较久，未在yaml文件中设置相应的健康检查，待pod Running之后，可以根据一下命令对日志进行查看，待日志更新后代表初始化完成。
kubectl logs -f -l app=nextcloud -n nextcloud 
```
#### 2. 部署 ONLYOFFICE 文档服务器

```bash
# 部署 ONLYOFFICE 所有组件
kubectl apply -f 11-1-onlyoffice-deployment.yaml
kubectl apply -f 11-2-onlyoffice-pvc.yaml
kubectl apply -f 11-3-onlyoffice-service.yaml
kubectl apply -f 11-4-onlyoffice-config.yaml
kubectl apply -f 11-5-onlyoffice-nodeport.yaml
```

## ⚙️ ONLYOFFICE 配置

### 安装 ONLYOFFICE Nextcloud 应用

#### 自动安装（推荐）
```txt
在 Nextcloud 管理员界面：
	1. 点击右上角用户图标 → "应用"
	2. 搜索 "ONLYOFFICE"
	3. 点击 "下载并启用"
```

#### 手动安装（如自动安装失败）
```bash

# 进入 Nextcloud Pod
kubectl exec -n nextcloud -it <nextcloud-pod> -- bash

# 下载 ONLYOFFICE 应用
curl -L -o /tmp/onlyoffice.tar.gz \
  https://github.com/ONLYOFFICE/onlyoffice-nextcloud/releases/download/v7.4.8/onlyoffice.tar.gz

# 解压到应用目录
cd /var/www/html/apps
tar -xzf /tmp/onlyoffice.tar.gz

# 设置权限
chown -R www-data:www-data onlyoffice
chmod -R 755 onlyoffice

# 启用应用
su www-data -s /bin/sh -c "php occ app:enable onlyoffice"
```


### 配置 ONLYOFFICE 连接

#### 通过命令行配置
```bash
# 获取 Nextcloud Pod 名称
NEXTCLOUD_POD=$(kubectl get pods -n nextcloud -l app=nextcloud --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')

# 配置 Document Server 地址（使用 NodePort）
kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:app:set onlyoffice documentserver_url --value='http://<节点IP>:32049'"

# 设置 JWT 密钥
kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:app:set onlyoffice secret_key --value='onlyoffice-secret-key-2024'"

# 添加信任域名
kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:system:set trusted_domains 2 --value='onlyoffice-document-server'"
```
#### 通过界面配置

1. 进入 Nextcloud 管理员界面
2. 点击右上角用户图标 → "设置" → "ONLYOFFICE"
3. 配置以下参数：
    - **Document Editing Service address**: `http://<节点IP>:32049`
    - **Secret key**: `onlyoffice-secret-key-2024`
    - **内部地址**: `http://onlyoffice-document-server.nextcloud.svc.cluster.local`
    - **存储地址**: `http://<节点IP>:32048`

## 📊 监控和管理

### 检查部署状态
```bash
./check-deploy-status.sh
```
### 查看所有资源
```bash
kubectl get all -n nextcloud
```
### 查看 Pod 状态
```bash
kubectl get pods -n nextcloud -o wide
```
### 查看服务
```bash
kubectl get svc -n nextcloud
```
### 查看存储
```bash
kubectl get pvc -n nextcloud
kubectl get pv
```
### 查看日志
```bash
# Nextcloud 日志
kubectl logs -l app=nextcloud -n nextcloud --tail=50

# MySQL Master 日志
kubectl logs mysql-master-0 -n nextcloud --tail=50

# Redis 日志
kubectl logs -l app=redis -n nextcloud --tail=50

# ONLYOFFICE 日志
kubectl logs -l app=onlyoffice-document-server -n nextcloud --tail=50
```
## 🔄 故障排查

### 常见问题

1. **NFS Provisioner 无法启动**
    - 检查 NFS 服务器连通性
    - 验证 NFS 路径权限
2. **MySQL 主从复制失败**
    - 检查网络连通性
    - 验证复制用户权限
    - 查看 MySQL 错误日志
3. **Nextcloud 无法连接数据库**
    - 检查服务发现
    - 验证数据库凭据
    - 确认网络策略
4. **ONLYOFFICE 连接失败**
    - 验证 NodePort 服务状态
    - 检查 JWT 密钥匹配
    - 查看 ONLYOFFICE Pod 日志

### ONLYOFFICE 特定问题

#### 应用安装失败
```bash
# 手动安装 ONLYOFFICE 应用
kubectl exec -n nextcloud -it <nextcloud-pod> -- bash
cd /var/www/html/apps
curl -L -o onlyoffice.tar.gz https://github.com/ONLYOFFICE/onlyoffice-nextcloud/releases/download/v7.4.8/onlyoffice.tar.gz
tar -xzf onlyoffice.tar.gz
chown -R www-data:www-data onlyoffice
su www-data -s /bin/sh -c "php occ app:enable onlyoffice"
```
#### 文档服务器连接测试

```bash
# 测试 ONLYOFFICE 连接
kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ onlyoffice:documentserver --check"

# 检查 ONLYOFFICE 健康状态
kubectl exec -n nextcloud <onlyoffice-pod> -- curl http://localhost/healthcheck
```

### 重置部署

```bash
# 重置检查点
./reset-deploy.sh

# 完全重置（删除所有资源）
./reset-deploy.sh
# 然后选择选项 3

# 前往NFS节点手动对持久化数据删除
```

## 🌐 访问应用

### 访问方式

1. **NodePort 访问**
    - Nextcloud: `http://<节点IP>:32048`
    - ONLYOFFICE: `http://<节点IP>:32049`
2. **健康检查**
    - ONLYOFFICE: `http://<节点IP>:32049/healthcheck`

### 初始配置

首次访问时需要完成 Nextcloud 安装向导：

- **管理员账户**: 自定义用户名和密码
- **数据库配置**:
    - 数据库类型: MySQL/MariaDB
    - 数据库主机: `mysql-master`
    - 数据库名: `nextcloud`
    - 数据库用户: `nextcloud`
    - 数据库密码: `password`
        
- **可选 Redis 配置**（提升性能）:
    - 主机: `redis`
    - 端口: `6379`
    - 密码: `password`

**若nextcloud平台中无redis相关配置选项，可按照[redis单点配置.md]方式手动进行添加**

## 🔒 安全说明

- 所有敏感信息通过 Secret 管理
- 数据库使用独立密码
- Redis 配置了密码保护
- ONLYOFFICE 使用 JWT 认证
- 服务使用最小权限原则

## 📝 注意事项

1. **生产环境建议**:
    - 配置 TLS 证书
    - 设置合适的备份策略
    - 配置监控和告警
    - 使用企业级存储方案
2. **性能优化**:
    - 根据负载调整资源限制
    - 配置 PHP OPcache
    - 使用 Redis 进行会话和文件锁定
    - ONLYOFFICE 根据并发用户调整资源
3. **数据持久化**:
    - 定期备份 NFS 存储
    - 监控存储使用情况
    - 配置数据库备份
    - ONLYOFFICE 数据定期备份
4. **ONLYOFFICE 特定配置**    
    - 确保足够的存储空间（16Gi+）
    - 配置适当的内存限制（2Gi+）
    - 监控文档转换服务状态
    - 定期更新 ONLYOFFICE 版本

## 📞 支持

如遇到部署问题，请检查：

1. Kubernetes 集群状态
2. NFS 服务器连通性
3. 资源配额是否足够
4. 容器镜像可访问性
5. 网络策略配置
6. ONLYOFFICE 服务发现

查看详细日志获取具体错误信息。

## 🎯 功能验证

部署完成后，请验证以下功能：

### Nextcloud 核心功能

- 用户登录和管理
- 文件上传和下载
- 文件共享和协作
- 数据库连接正常
- Redis 缓存工作正常

### ONLYOFFICE 集成功能

- ONLYOFFICE 应用已启用
- 文档服务器连接正常
- 创建和编辑文档（.docx）
- 创建和编辑表格（.xlsx）
- 创建和编辑演示文稿（.pptx）
- 实时协作功能（如配置）

通过以上完整的部署和配置，您将获得一个功能齐全的 Nextcloud 云存储平台，集成了强大的 ONLYOFFICE 在线文档编辑功能。
