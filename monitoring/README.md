# Nextcloud 监控接入完整部署指南

> **日期**: 2026-06-06
> **命名空间**: `nextcloud`
> **Prometheus**: `monitoring` namespace，kube-prometheus-stack

---

## 架构概览

```
┌──────────────────────────────────────────────────────────────┐
│                     Prometheus (monitoring)                   │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ ServiceMonitor → Service → Pod (Exporter)               │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────────┐
│ mysql-exporter│   │ redis-exporter│   │ nextcloud-exporter│
│    :9104      │   │    :9121      │   │      :9205        │
│      │        │   │      │        │   │        │          │
│      ▼        │   │      ▼        │   │        ▼          │
│ mysql-master  │   │    redis      │   │  Nextcloud API    │
│    :3306      │   │    :6379      │   │  http://nextcloud │
└───────────────┘   └───────────────┘   └───────────────────┘
```

**三个 Exporter：**

| Exporter | 端口 | 采集对象 | 镜像 |
|----------|------|----------|------|
| MySQL Exporter | 9104 | `mysql-master:3306` | `prom/mysqld-exporter` |
| Redis Exporter | 9121 | `redis:6379` | `oliver006/redis_exporter` |
| Nextcloud Exporter | 9205 | `http://nextcloud` (API) | `xperimental/nextcloud-exporter` |

---

## 前置步骤

### 确认环境

```bash
# 连接到 K8s master 节点（.23）
ssh root@192.168.28.23

# 检查 nextcloud namespace 中的服务
kubectl get svc,pod -n nextcloud

# 确认 Prometheus Operator 已安装
kubectl get prometheus -n monitoring
kubectl get servicemonitors -n monitoring | grep kube-prometheus
```

### 确认 ServiceMonitor selector

Prometheus Operator 通过 `serviceMonitorSelector` 来发现 ServiceMonitor。需要确认 label：

```bash
kubectl get prometheus -n monitoring -o yaml | grep -A5 serviceMonitorSelector
```

常见的 selector 是 `release: kube-prometheus`，我们的 ServiceMonitor 必须带有此 label。

---

## 步骤 1: MySQL 监控数据库用户

在 mysql-master pod 中创建专用的监控用户：

```bash
kubectl exec -it mysql-master-0 -n nextcloud -- mysql -u root -p
```

```sql
-- 创建监控用户（只能读取，不能写入）
CREATE USER 'exporter'@'%' IDENTIFIED BY 'exporterpass';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
FLUSH PRIVILEGES;

-- 验证
SELECT user, host FROM mysql.user WHERE user='exporter';
```

> **注意**: 如果 MySQL 已经配置了 `exporter` 用户，可跳过此步骤。

---

## 步骤 2: 推送镜像到 Harbor

从公网拉取镜像并推送到私有镜像仓库（30 节点）：

```bash
# SSH 到 30 节点（有外网访问）
ssh root@192.168.28.30

# 拉取镜像
docker pull prom/mysqld-exporter:latest
docker pull oliver006/redis_exporter:latest
docker pull xperimental/nextcloud-exporter:latest

# 打标签
docker tag prom/mysqld-exporter:latest dai30.test.com/k8s/mysqld-exporter:latest
docker tag oliver006/redis_exporter:latest dai30.test.com/k8s/redis_exporter:latest
docker tag xperimental/nextcloud-exporter:latest dai30.test.com/k8s/nextcloud-exporter:latest

# 推送到 Harbor
docker push dai30.test.com/k8s/mysqld-exporter:latest
docker push dai30.test.com/k8s/redis_exporter:latest
docker push dai30.test.com/k8s/nextcloud-exporter:latest
```

> 如果 K8s 节点能直接访问公网，可以使用官方镜像，无需推送到 Harbor。
> 本文档中的 YAML 使用官方镜像名，部署时按需替换。

---

## 步骤 3: 部署 Exporter

将 `manifests/` 目录下的 YAML 文件上传到 master 节点，然后按顺序执行：

### 3.1 MySQL Exporter

```bash
kubectl apply -f manifests/01-mysql-exporter.yaml

# 验证
kubectl get pod,svc -n nextcloud -l app=mysql-exporter
kubectl logs -n nextcloud -l app=mysql-exporter
```

### 3.2 Redis Exporter

```bash
kubectl apply -f manifests/02-redis-exporter.yaml

# 如果 Redis 有密码，修改 YAML 中的 REDIS_PASSWORD 环境变量
# 当前集群 Redis 密码: password

# 验证
kubectl get pod,svc -n nextcloud -l app=redis-exporter
kubectl logs -n nextcloud -l app=redis-exporter
```

### 3.3 Nextcloud Exporter

```bash
kubectl apply -f manifests/03-nextcloud-exporter.yaml

# 修改 NEXTCLOUD_PASSWORD 为实际的 Nextcloud admin 密码
# 当前集群密码: admin123

# 验证
kubectl get pod,svc -n nextcloud -l app=nextcloud-exporter
kubectl logs -n nextcloud -l app=nextcloud-exporter
```

### 测试 metrics 端点

在集群内部测试：

```bash
# 找一个测试 pod 或者直接 exec 到 exporter
kubectl exec -n nextcloud deploy/mysql-exporter -- wget -qO- http://localhost:9104/metrics | head -20
kubectl exec -n nextcloud deploy/redis-exporter -- wget -qO- http://localhost:9121/metrics | head -20
kubectl exec -n nextcloud deploy/nextcloud-exporter -- wget -qO- http://localhost:9205/metrics | head -20
```

---

## 步骤 4: 配置 Service + ServiceMonitor

> 注意: Service 已在步骤 3 的 YAML 中创建，此步骤部署 ServiceMonitor。

```bash
kubectl apply -f manifests/04-servicemonitors.yaml

# 验证 ServiceMonitor 已创建
kubectl get servicemonitors -n nextcloud
```

### 确认 Prometheus 已发现 target

```bash
# 方法 1: 查看 Prometheus Targets 页面
# http://<prometheus-nodeport>:30900/targets

# 方法 2: 通过 API 检查
kubectl port-forward -n monitoring svc/prometheus-k8s 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.namespace=="nextcloud") | {labels: .labels, health: .health}'
```

预期看到 3 个 target，health 为 `"up"`。

---

## 步骤 5: 配置 RBAC 授权

> **为什么需要**: Prometheus 运行在 `monitoring` namespace，其 ServiceAccount `prometheus-k8s` 需要访问 `nextcloud` namespace 中的 Kubernetes API 来发现 ServiceMonitor 指定的 target（services, endpoints, pods）。

```bash
kubectl apply -f manifests/05-rbac.yaml

# 验证
kubectl get role,rolebinding -n nextcloud | grep prometheus
```

如果 Prometheus 日志中出现 `cannot list resource "services"` 或 `forbidden` 错误，说明 RBAC 未配置。

必要时重启 Prometheus 使其重新加载配置：

```bash
kubectl rollout restart statefulset/prometheus-k8s -n monitoring
kubectl rollout status statefulset/prometheus-k8s -n monitoring
```

---

## 步骤 6: 导入 Grafana 仪表板

### 方法 1: 通过 Grafana API 导入（推荐）

```bash
# 在 master 节点执行
curl -X POST \
  -H "Content-Type: application/json" \
  -u admin:admin123 \
  -d @grafana-dashboard.json \
  http://192.168.28.23:32000/api/dashboards/db
```

### 方法 2: 通过 Grafana Web UI 导入

1. 打开 `http://192.168.28.23:32000`
2. 登录 (admin / admin123)
3. Dashboards → New → Import
4. 上传 `grafana-dashboard.json` 或粘贴 JSON

### 仪表板内容

| 区域 | 面板 | 说明 |
|------|------|------|
| **MySQL** | 连接数 | Threads Connected / Running / Max |
| | QPS | SELECT / INSERT / UPDATE / DELETE rate |
| | Buffer Pool 命中率 | InnoDB Buffer Pool 缓存效率 |
| | 慢查询 | Slow Queries 计数器 |
| **Redis** | 内存使用 | Used Memory vs Max Memory |
| | 键数量 | db0 / db1 key 数量 |
| | 连接数 | Connected Clients / Blocked Clients |
| | 命令速率 | Commands Processed / s |
| **Nextcloud** | 状态 | API Up/Down (1=正常, 0=异常) |
| | 用户数 | 活跃用户总数 |
| | 存储使用 | 已用存储空间 |
| **概览** | 服务健康 | 3 个 target 全部 up 时显示 3 (绿灯) |

---

## 步骤 7: 验证

### 综合检查脚本

```bash
#!/bin/bash
echo "===== 1. Pods ====="
kubectl get pods -n nextcloud -l 'app in (mysql-exporter,redis-exporter,nextcloud-exporter)'

echo ""
echo "===== 2. Services ====="
kubectl get svc -n nextcloud -l 'app in (mysql-exporter,redis-exporter,nextcloud-exporter)'

echo ""
echo "===== 3. ServiceMonitors ====="
kubectl get servicemonitors -n nextcloud

echo ""
echo "===== 4. RBAC ====="
kubectl get role,rolebinding -n nextcloud | grep prometheus

echo ""
echo "===== 5. Prometheus Targets ====="
kubectl port-forward -n monitoring svc/prometheus-k8s 9090:9090 &
sleep 2
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    if t['labels'].get('namespace') == 'nextcloud':
        print(f\"  {t['labels']['app']:25s}  health={t['health']}\")
"
kill %1 2>/dev/null

echo ""
echo "===== 6. Grafana Dashboard ====="
echo "  http://192.168.28.23:32000/d/nextcloud-monitor"
```

### 期望结果

- ✅ 3 个 Exporter Pod 全部 `Running` (1/1)
- ✅ 3 个 Service 存在，ClusterIP 已分配
- ✅ 3 个 ServiceMonitor 存在
- ✅ Role + RoleBinding 存在
- ✅ Prometheus Targets 全部 `health=up`
- ✅ Grafana 仪表板 `Nextcloud 监控仪表盘` 可访问，面板有数据

---

## 常见问题排查

### 问题 1: ServiceMonitor 未被 Prometheus 识别

**现象**: Prometheus Targets 页面看不到 nextcloud exporter

**原因**: 
- ServiceMonitor label 与 Prometheus 的 `serviceMonitorSelector` 不匹配
- RBAC 未配置

**解决**:
```bash
# 检查 Prometheus 的 selector
kubectl get prometheus -n monitoring -o yaml | grep -A5 serviceMonitorSelector

# 检查 ServiceMonitor 的 labels
kubectl get servicemonitor -n nextcloud mysql-exporter -o yaml | grep -A5 labels

# 确保 labels 包含匹配的 key=value（如 release: kube-prometheus）
```

### 问题 2: Prometheus Target 显示 "down"

**现象**: target 存在但 health=down

**排查**:
```bash
# 1. 测试 Pod 内 metrics 端点
kubectl exec -n nextcloud deploy/mysql-exporter -- wget -qO- http://localhost:9104/metrics | head

# 2. 测试 Service 连通性
kubectl run test --rm -it --image=busybox -n nextcloud -- wget -qO- http://mysql-exporter:9104/metrics | head

# 3. 查看 Prometheus 日志
kubectl logs -n monitoring prometheus-k8s-0 | grep nextcloud
```

### 问题 3: Nextcloud Exporter 显示 nextcloud_up=0

**可能原因**:
- Nextcloud admin 密码不正确
- Nextcloud API 路径变更（某些版本使用 `/ocs/v2.php`）
- 网络不通

**排查**:
```bash
# 查看 exporter 日志
kubectl logs -n nextcloud -l app=nextcloud-exporter

# 测试 Nextcloud API
kubectl exec -n nextcloud deploy/nextcloud -- wget -qO- http://localhost/status.php | head
```

### 问题 4: Grafana 面板显示 No Data

**常见原因**:
- 时间范围选择过小（数据还未采集到）
- Prometheus 数据源配置错误
- 查询表达式写错

**解决**:
1. 将 Grafana 时间范围调整为 `Last 15 minutes`
2. 在 Prometheus Web UI 中手动测试查询表达式
3. 确认 Grafana 数据源 URL 指向正确的 Prometheus

---

## 文件清单

```
nextcloud-monitoring/
├── README.md                                # 本文档（部署指南）
├── grafana-dashboard.json                   # Grafana 仪表板 JSON
└── manifests/
    ├── 01-mysql-exporter.yaml               # MySQL Exporter Deployment + Service
    ├── 02-redis-exporter.yaml               # Redis Exporter Deployment + Service
    ├── 03-nextcloud-exporter.yaml           # Nextcloud Exporter Deployment + Service
    ├── 04-servicemonitors.yaml              # 3 个 ServiceMonitor
    └── 05-rbac.yaml                         # Role + RoleBinding for Prometheus
```

### 所需凭证汇总

| 服务        | 用户       | 密码           | 用途                   |
| --------- | -------- | ------------ | -------------------- |
| MySQL     | exporter | exporterpass | 监控采集                 |
| Redis     | default  | password     | 监控采集（当前集群 Redis 有密码） |
| Nextcloud | admin    | admin123     | API 状态采集             |
| Grafana   | admin    | admin123     | 管理仪表板                |

---

## 相关文档

- [[../diagrams/vm-k8s-architecture|集群架构图]]
- [K8s集群全量报告](../../reports/k8s-full-inspection-2026-06-05.md)
- [Grafana 9.5.3 渲染 Bug 记录](../../reports/grafana-953-rendering-bug.md)
- `manifests/` 目录下的 YAML 文件
