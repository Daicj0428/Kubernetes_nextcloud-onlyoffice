##### 1、查看nextcloud svc地址

```
[root@master-0 ~]# kubectl get svc -n nextcloud nextcloud
NAME        TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
nextcloud   NodePort   10.100.178.30   <none>        80:32048/TCP   3d19h
[root@master-0 ~]# 
```
##### 2、浏览器中访问，并使用管理员用户登录

##### 3、点击搜索，并选择‘下载并启用’按钮

###### 若出现报错：

`cURL error 56: OpenSSL SSL_read: Connection reset by peer, errno 104 (see https://curl.haxx.se/libcurl/c/libcurl-errors.html) for https://github.com/ONLYOFFICE/onlyoffice-nextcloud/releases/download/v7.4.8/onlyoffice.tar.gz` 尝试前往nextcloud pod中手动进行安装，步骤如下：
**手动进入nextcloud pod中下载安装onlyoffice**

```
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# curl -L -v -o /tmp/onlyoffice-test.tar.gz \
  https://github.com/ONLYOFFICE/onlyoffice-nextcloud/releases/download/v7.4.8/onlyoffice.tar.gz
  
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# ls /tmp/onlyoffice-test.tar.gz 
/tmp/onlyoffice-test.tar.gz
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# cd /var/www/html/apps
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html/apps# tar -xzf /tmp/onlyoffice-test.tar.gz
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html/apps# ls -la onlyoffice/
total 64
drwxrwxr-x 13 root     root   255 Nov  1  2022 .
drwxr-xr-x 49 www-data root  4096 Nov 25 11:10 ..
-rw-rw-r--  1 root     root   248 Nov  1  2022 3rd-Party.license
drwxrwxr-x  3 root     root    17 Nov  1  2022 3rdparty
-rw-rw-r--  1 root     root    64 Nov  1  2022 AUTHORS.md
-rw-rw-r--  1 root     root  8269 Nov  1  2022 CHANGELOG.md
-rw-rw-r--  1 root     root 11357 Nov  1  2022 LICENSE
-rw-rw-r--  1 root     root 14348 Nov  1  2022 README.md
drwxrwxr-x  2 root     root    85 Nov  1  2022 appinfo
drwxrwxr-x 31 root     root  4096 Nov  1  2022 assets
drwxrwxr-x  2 root     root   219 Nov  1  2022 controller
drwxrwxr-x  2 root     root   115 Nov  1  2022 css
drwxrwxr-x  2 root     root   171 Nov  1  2022 img
drwxrwxr-x  2 root     root   169 Nov  1  2022 js
drwxrwxr-x  2 root     root  4096 Nov  1  2022 l10n
drwxrwxr-x  5 root     root  4096 Nov  1  2022 lib
drwxrwxr-x  2 root     root   132 Nov  1  2022 screenshots
drwxrwxr-x  2 root     root   160 Nov  1  2022 templates
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html/apps# chown -R www-data:www-data onlyoffice
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html/apps# chmod -R 755 onlyoffice
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html/apps# cd
root@nextcloud-5df6cfd7d4-ffczr:~# cd /var/www/html/
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# su www-data -s /bin/sh -c "php occ app:enable onlyoffice"
onlyoffice 7.4.8 enabled
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# su www-data -s /bin/sh -c "php occ app:list | grep onlyoffice"
  - onlyoffice: 7.4.8
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# 
```

##### 4、部署onlyoffice
###### 1、编写yaml文件
**onlyoffice-deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: onlyoffice-document-server
  namespace: nextcloud
  labels:
    app: onlyoffice-document-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: onlyoffice-document-server
  template:
    metadata:
      labels:
        app: onlyoffice-document-server
    spec:
      containers:
      - name: onlyoffice-document-server
        image: onlyoffice/documentserver:7.4.1
        securityContext:
          runAsUser: 0
          runAsGroup: 0
        ports:
        - containerPort: 80
          name: http
        - containerPort: 443
          name: https
        env:
        - name: JWT_ENABLED
          value: "true"
        - name: JWT_SECRET
          value: "onlyoffice-secret-key-2024"
        - name: NODE_ENV
          value: "production"
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
        livenessProbe:
          httpGet:
            path: /healthcheck
            port: 80
          initialDelaySeconds: 180
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /healthcheck
            port: 80
          initialDelaySeconds: 120
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
        volumeMounts:
        - name: onlyoffice-data
          mountPath: /var/www/onlyoffice/Data
        - name: onlyoffice-logs
          mountPath: /var/log/onlyoffice
        - name: onlyoffice-db
          mountPath: /var/lib/postgresql
        - name: onlyoffice-rabbitmq
          mountPath: /var/lib/rabbitmq
        - name: onlyoffice-redis
          mountPath: /var/lib/redis
      volumes:
      - name: onlyoffice-data
        persistentVolumeClaim:
          claimName: onlyoffice-data-pvc
      - name: onlyoffice-logs
        persistentVolumeClaim:
          claimName: onlyoffice-logs-pvc
      - name: onlyoffice-db
        persistentVolumeClaim:
          claimName: onlyoffice-db-pvc
      - name: onlyoffice-rabbitmq
        persistentVolumeClaim:
          claimName: onlyoffice-rabbitmq-pvc
      - name: onlyoffice-redis
        persistentVolumeClaim:
          claimName: onlyoffice-redis-pvc
```

**onlyoffice-pvc.yaml**  持久化存储部署
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: onlyoffice-data-pvc
  namespace: nextcloud
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: nfs-client
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: onlyoffice-logs-pvc
  namespace: nextcloud
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: nfs-client
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: onlyoffice-db-pvc
  namespace: nextcloud
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: nfs-client
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: onlyoffice-rabbitmq-pvc
  namespace: nextcloud
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: nfs-client
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: onlyoffice-redis-pvc
  namespace: nextcloud
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: nfs-client
```

**onlyoffice-service.yaml** 集群内部访问
```yaml
apiVersion: v1
kind: Service
metadata:
  name: onlyoffice-document-server
  namespace: nextcloud
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
  - name: https
    port: 443
    targetPort: 443
    protocol: TCP
  selector:
    app: onlyoffice-document-server
```

**onlyoffice-nodeport.yaml** 浏览器访问路径
```yaml
apiVersion: v1
kind: Service
metadata:
  name: onlyoffice-document-server-external
  namespace: nextcloud
spec:
  type: NodePort
  selector:
    app: onlyoffice-document-server
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 32049
```

**onlyoffice-config.yaml** 
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onlyoffice-config
  namespace: nextcloud
data:
  onlyoffice.json: |
    {
      "stores": [
        {
          "onlyoffice": {
            "args": {
              "url": "http://onlyoffice-document-server",
              "verify_peer_off": true,
              "jwt_secret": "onlyoffice-secret-key-2024",
              "jwt_header": "Authorization",
              "timeout": 120,
              "conversionTimeout": 120,
              "max_download_size": 10485760,
              "max_upload_size": 10485760
            }
          }
        }
      ]
    }
```

###### 2、部署onlyoffice
```bash
[root@master-0 onlyoffice]# pwd
/root/sre/onlyoffice
[root@master-0 onlyoffice]# kubectl apply -f ./*



[root@master-0 onlyoffice]# kubectl get pod,pvc,svc -n nextcloud  | grep onlyoffice
NAME                                              READY   STATUS    RESTARTS       AGE
pod/onlyoffice-document-server-75f79df778-w6bgl   1/1     Running   2 (74m ago)    22h

NAME                                            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/onlyoffice-data-pvc       Bound    pvc-88e55374-7fa4-4046-8204-6c821b01998b   5Gi        RWO            nfs-client     27h
persistentvolumeclaim/onlyoffice-db-pvc         Bound    pvc-8c356d91-e53c-46cc-a105-4a2ced03af13   5Gi        RWO            nfs-client     27h
persistentvolumeclaim/onlyoffice-logs-pvc       Bound    pvc-76e8e9dc-ecc3-4c6d-a1b4-1dbfdc50d3b1   2Gi        RWO            nfs-client     27h
persistentvolumeclaim/onlyoffice-rabbitmq-pvc   Bound    pvc-a94f1381-f55c-4f9d-b042-8823f5e5bb5b   2Gi        RWO            nfs-client     27h
persistentvolumeclaim/onlyoffice-redis-pvc      Bound    pvc-b90f72ee-385d-4569-bf9f-9289e4bace10   2Gi        RWO            nfs-client     27h


NAME                                          TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
service/onlyoffice-document-server            ClusterIP   10.111.133.23    <none>        80/TCP,443/TCP   27h
service/onlyoffice-document-server-external   NodePort    10.108.193.223   <none>        80:32049/TCP     33m
[root@master-0 onlyoffice]# 
```

**查看是否能正常访问Onlyoffice**

###### 3、更新nextcloud配置

```
# 检查当前的 trusted_domains
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:system:get trusted_domains"
192.168.28.23:32048
7c260ff8.r20.cpolar.top

# 添加 OnlyOffice 和内部服务地址到 trusted_domains
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:system:set trusted_domains 2 --value='onlyoffice-document-server'"
System config value trusted_domains => 2 set to string onlyoffice-document-server
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:system:set trusted_domains 3 --value='nextcloud'"
System config value trusted_domains => 3 set to string nextcloud
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:system:set trusted_domains 4 --value='nextcloud.nextcloud.svc.cluster.local'"
System config value trusted_domains => 4 set to string nextcloud.nextcloud.svc.cluster.local
# 验证 trusted_domains
System config value trusted_domains => 7 set to string onlyoffice-document-server.nextcloud.svc.cluster.local
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:system:set trusted_domains 8 --value='nextcloud.nextcloud.svc.cluster.local'"
System config value trusted_domains => 8 set to string nextcloud.nextcloud.svc.cluster.local
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:system:set trusted_domains 5 --value='192.168.28.23'"
System config value trusted_domains => 5 set to string 192.168.28.23
[root@master-0 onlyoffice]# 
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:system:set trusted_domains 6 --value='192.168.28.23:32048'"
System config value trusted_domains => 6 set to string 192.168.28.23:32048
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:system:get trusted_domains"
192.168.28.23:32048
71058942.r20.cpolar.top
onlyoffice-document-server
nextcloud
nextcloud.nextcloud.svc.cluster.local
onlyoffice-document-server.nextcloud.svc.cluster.local
nextcloud.nextcloud.svc.cluster.local
192.168.28.23
192.168.28.23:32048
```

###### 4、配置Onlyoffice

```
# 配置 OnlyOffice（使用完整的内部地址）
# 获取新的 Pod 名称
[root@master-0 onlyoffice]# NEXTCLOUD_POD=$(kubectl get pods -n nextcloud -l app=nextcloud --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
[root@master-0 onlyoffice]# echo "新的 Nextcloud Pod: $NEXTCLOUD_POD"
新的 Nextcloud Pod: nextcloud-6d9568866d-fsj8p

[root@master-0 onlyoffice]# kubectl exec -n nextcloud nextcloud-6b4fcc694d-5ms9f -- su www-data -s /bin/bash -c "php occ config:app:set onlyof documentserver_url --value='http://192.168.28.23:32049/'"
Config value documentserver_url for app onlyoffice set to http://192.168.28.23:32049/

[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:app:set onlyoffice secret_key --value='onlyoffice-secret-key-2024'"
Config value secret_key for app onlyoffice set to onlyoffice-secret-key-2024

[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:app:set onlyoffice documentserver_internal --value='http://onlyoffice-document-server.nextcloud.svc.cluster.local'"
Config value documentserver_internal for app onlyoffice set to http://onlyoffice-document-server.nextcloud.svc.cluster.local

[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:app:set onlyoffice storage_url --value='http://nextcloud.nextcloud.svc.cluster.local'"
Config value storage_url for app onlyoffice set to http://nextcloud.nextcloud.svc.cluster.local

[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:app:get onlyoffice documentserver_url"
http://onlyoffice-document-server.nextcloud.svc.cluster.local

[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ config:app:get onlyoffice storage_url"
http://nextcloud.nextcloud.svc.cluster.local

# 验证配置
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $NEXTCLOUD_POD -- su www-data -s /bin/bash -c "php occ onlyoffice:documentserver --check"
Document server http://onlyoffice-document-server.nextcloud.svc.cluster.local/ version 7.4.1.36 is successfully connected
[root@master-0 onlyoffice]# ONLYOFFICE_POD=$(kubectl get pods -n nextcloud -l app=onlyoffice-document-server -o jsonpath='{.items[0].metadata.name}')
[root@master-0 onlyoffice]# kubectl exec -n nextcloud $ONLYOFFICE_POD -- curl -v "http://nextcloud.nextcloud.svc.cluster.local/status.php"
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0*   Trying 10.100.178.30:80...
* Connected to nextcloud.nextcloud.svc.cluster.local (10.100.178.30) port 80 (#0)
> GET /status.php HTTP/1.1
> Host: nextcloud.nextcloud.svc.cluster.local
> User-Agent: curl/7.81.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Date: Tue, 25 Nov 2025 08:31:58 GMT
< Server: Apache/2.4.51 (Debian)
< Referrer-Policy: no-referrer
< X-Content-Type-Options: nosniff
< X-Download-Options: noopen
< X-Frame-Options: SAMEORIGIN
< X-Permitted-Cross-Domain-Policies: none
< X-Robots-Tag: none
< X-XSS-Protection: 1; mode=block
< X-Powered-By: PHP/8.0.14
< Set-Cookie: oc6absrny84e=179bf6b6ccd94a18cb8ce3e515b3bf0f; path=/; HttpOnly; SameSite=Lax
< Expires: Thu, 19 Nov 1981 08:52:00 GMT
< Cache-Control: no-store, no-cache, must-revalidate
< Pragma: no-cache
< Set-Cookie: oc_sessionPassphrase=LDJ3Wapv3tDXSAkp8pou7TdDIETYWmDLwUblZ510ITdjrlrn3fWQOldZlRrj9dnvcdqWv4MPGLmc%2BjOy3H19H25Bl2FaPRGt0CxWsCKXuWdpgSernMErlU4xsluZqAwt; path=/; HttpOnly; SameSite=Lax
< Set-Cookie: oc6absrny84e=d2ba89165baae46f4ebe08d8e0a64e2b; path=/; HttpOnly; SameSite=Lax
< Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-eHVacnVKOU9aLzJicXk1SUM0VGh3N2tMSE13SUN4TVZWeGFiNFFMM2dvOD06dHJjR3pOaDVONmV1Mm04N1lNT1QrODFOZjRSR1IwbDBEVmpPZ21TWTJybz0='; style-src 'self' 'unsafe-inline'; frame-src *; img-src * data: blob:; font-src 'self' data:; media-src *; connect-src *; object-src 'none'; base-uri 'self';
< Set-Cookie: nc_sameSiteCookielax=true; path=/; httponly;expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=lax
< Set-Cookie: nc_sameSiteCookiestrict=true; path=/; httponly;expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=strict
< Access-Control-Allow-Origin: *
< Content-Length: 171
< Content-Type: application/json
< 
{ [171 bytes data]
100   171  100   171    0     0    102      0  0:00:01  0:00:01 --:--:--   102
* Connection #0 to host nextcloud.nextcloud.svc.cluster.local left intact
{"installed":true,"maintenance":false,"needsDbUpgrade":false,"version":"23.0.0.10","versionstring":"23.0.0","edition":"","productname":"Nextcloud","extendedSupport":false}


[root@master-0 onlyoffice]# kubectl rollout restart deployment/nextcloud -n nextcloud
deployment.apps/nextcloud restarted
[root@master-0 onlyoffice]# kubectl rollout restart deployment/onlyoffice-document-server -n nextcloud
deployment.apps/onlyoffice-document-server restarted
```

##### 5、UI界面手动添加Onlyoffice配置
    - **Document Editing Service address**: `http://<节点IP>:32049`
    - **Secret key**: `onlyoffice-secret-key-2024`
    - **内部地址**: `http://onlyoffice-document-server.nextcloud.svc.cluster.local`
    - **存储地址**: `http://<节点IP>:32048`

##### 6、新建DOC文档测试
