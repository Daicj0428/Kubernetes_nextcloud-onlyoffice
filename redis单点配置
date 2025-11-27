# 备份配置文件
```bash
[root@master-0 nextcloud_redis]# kubectl exec -it -n nextcloud nextcloud-5df6cfd7d4-ffczr -- bash

root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# cp /var/www/html/config/config.php /var/www/html/config/config.php.backup
```


# 正确编辑config.php文件
```bash
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html#  cat > /tmp/fix_redis_config.php << 'EOF'
<?php
// 读取原配置文件
$configFile = '/var/www/html/config/config.php';
$configContent = file_get_contents($configFile);

// 找到配置结束的位置
$pos = strrpos($configContent, ');');

if ($pos !== false) {
    // 在结束前插入Redis配置
    $redisConfig = "\n  // Redis配置\n  'memcache.distributed' => '\\\\OC\\\\Memcache\\\\Redis',\n  'memcache.locking' => '\\\\OC\\\\Memcache\\\\Redis',\n  'redis' => array(\n    'host' => 'redis',\n    'port' => 6379,\n    'password' => 'password',\n    'timeout' => 1.5,\n    'dbindex' => 0,\n  ),";
    
    $newConfig = substr($configContent, 0, $pos) . $redisConfig . substr($configContent, $pos);
    file_put_contents($configFile, $newConfig);
    echo "Redis配置已成功添加到config.php\n";
} else {
    echo "无法找到配置结束位置\n";
}
EOF

# 执行修复脚本
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# php /tmp/fix_redis_config.php
Redis配置已成功添加到config.php
```

## 2. 验证修复后的配置
```bash
# 检查配置文件语法
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# php -l /var/www/html/config/config.php
No syntax errors detected in /var/www/html/config/config.php
# 查看Redis配置部分
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# cat /var/www/html/config/config.php | grep -A 15 -B 5 redis
  'installed' => true,

  // Redis配置
  'memcache.distributed' => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' => array(
    'host' => 'redis',
    'port' => 6379,
    'password' => 'password',
    'timeout' => 1.5,
    'dbindex' => 0,
  ),);
```
## 3. 重新测试Redis配置
```bash
# 创建新的测试脚本
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# cat > /tmp/test_redis_final.php << 'EOF'
<?php
require_once '/var/www/html/config/config.php';

echo "=== Redis最终配置测试 ===\n";

// 检查配置语法
if (php_sapi_name() === 'cli') {
    $result = shell_exec('php -l /var/www/html/config/config.php');
    if (strpos($result, 'No syntax errors') !== false) {
        echo "✓ config.php 语法正确\n";
    } else {
        echo "✗ config.php 语法错误: $result\n";
        exit(1);
    }
}

// 检查Redis配置
if (isset($CONFIG['memcache.distributed']) && $CONFIG['memcache.distributed'] === '\OC\Memcache\Redis') {
    echo "✓ Redis分布式缓存已配置\n";
} else {
    echo "✗ Redis分布式缓存未配置\n";
}

if (isset($CONFIG['memcache.locking']) && $CONFIG['memcache.locking'] === '\OC\Memcache\Redis') {
    echo "✓ Redis锁定缓存已配置\n";
} else {
    echo "✗ Redis锁定缓存未配置\n";
}

// 测试Redis连接
try {
    $redis = new Redis();
    $connected = $redis->connect('redis', 6379, 1.5);
    
    if ($connected) {
        $redis->auth('password');
        
        if ($redis->ping()) {
            echo "✓ Redis服务连接正常\n";
            
            // 测试Nextcloud风格的缓存键
            $testKey = 'oc_redis_test_' . uniqid();
            $testValue = 'Nextcloud Redis Integration Test - ' . date('Y-m-d H:i:s');
            
            if ($redis->set($testKey, $testValue, 30)) {
                $retrieved = $redis->get($testKey);
                if ($retrieved === $testValue) {
                    echo "✓ Redis缓存功能正常\n";
                    echo "  测试键: $testKey\n";
                    echo "  测试值: $retrieved\n";
                } else {
                    echo "✗ 读取的值不匹配\n";
                }
                $redis->del($testKey);
            } else {
                echo "✗ 无法设置缓存键\n";
            }
        } else {
            echo "✗ Redis ping失败\n";
        }
        $redis->close();
    } else {
        echo "✗ 无法连接到Redis\n";
    }
} catch (Exception $e) {
    echo "✗ Redis异常: " . $e->getMessage() . "\n";
}

echo "===================\n";
EOF

# 执行测试
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# php /tmp/test_redis_final.php
=== Redis最终配置测试 ===
✓ config.php 语法正确
✓ Redis分布式缓存已配置
✓ Redis锁定缓存已配置
✓ Redis服务连接正常
✓ Redis缓存功能正常
  测试键: oc_redis_test_692417d9b4d01
  测试值: Nextcloud Redis Integration Test - 2025-11-24 16:31:21
===================
```
## 4. 重启Web服务应用配置
```bash
# 重启Apache服务
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# service apache2 restart
Restarting Apache httpd web server: apache2Terminated
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# command terminated with exit code 137

# 等待服务重启

# 检查Apache状态
[root@master-0 nextcloud_redis]# kubectl exec -it -n nextcloud nextcloud-5df6cfd7d4-ffczr -- bash
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# service apache2 status
apache2 is 
```
## 5. 验证Nextcloud中的Redis使用
```bash
# 使用occ命令检查配置
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# su www-data -s /bin/bash -c "php /var/www/html/occ config:list | grep -A 10 -B 5 redis"
        "dbuser": "***REMOVED SENSITIVE VALUE***",
        "dbpassword": "***REMOVED SENSITIVE VALUE***",
        "installed": true,
        "memcache.distributed": "\\OC\\Memcache\\Redis",
        "memcache.locking": "\\OC\\Memcache\\Redis",
        "redis": {
            "host": "***REMOVED SENSITIVE VALUE***",
            "port": 6379,
            "password": "***REMOVED SENSITIVE VALUE***",
            "timeout": 1.5,
            "dbindex": 0
        }
    },
    "apps": {
        "accessibility": {
            "enabled": "yes",

# 检查系统信息
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# su www-data -s /bin/bash -c "php /var/www/html/occ status"
  - installed: true
  - version: 23.0.0.10
  - versionstring: 23.0.0
  - edition: 
  - maintenance: false
  - needsDbUpgrade: false
  - productname: Nextcloud
  - extendedSupport: false
```
## 6. 创建更完整的测试
```bash
# 创建完整的Nextcloud Redis功能测试
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# cat > /tmp/test_nextcloud_redis.php << 'EOF'
<?php
require_once '/var/www/html/config/config.php';

echo "=== Nextcloud Redis 完整功能测试 ===\n";

// 1. 检查配置文件
echo "1. 配置文件检查:\n";
if (file_exists('/var/www/html/config/config.php')) {
    echo "   ✓ config.php 存在\n";
    
    // 检查Redis配置
    $hasDistributed = isset($CONFIG['memcache.distributed']) && $CONFIG['memcache.distributed'] === '\OC\Memcache\Redis';
    $hasLocking = isset($CONFIG['memcache.locking']) && $CONFIG['memcache.locking'] === '\OC\Memcache\Redis';
    $hasRedisConfig = isset($CONFIG['redis']);
    
    echo "   " . ($hasDistributed ? '✓' : '✗') . " 分布式缓存配置\n";
    echo "   " . ($hasLocking ? '✓' : '✗') . " 锁定缓存配置\n";
    echo "   " . ($hasRedisConfig ? '✓' : '✗') . " Redis连接配置\n";
    
    if ($hasRedisConfig) {
        echo "   Redis连接详情:\n";
        echo "     Host: " . $CONFIG['redis']['host'] . "\n";
        echo "     Port: " . ($CONFIG['redis']['port'] ?? '6379') . "\n";
    }
} else {
    echo "   ✗ config.php 不存在\n";
}

// 2. 测试Redis连接
echo "\n2. Redis连接测试:\n";
try {
    $redis = new Redis();
    $host = $CONFIG['redis']['host'] ?? 'redis';
    $port = $CONFIG['redis']['port'] ?? 6379;
    $password = $CONFIG['redis']['password'] ?? 'password';
    $timeout = $CONFIG['redis']['timeout'] ?? 1.5;
    
    if ($redis->connect($host, $port, $timeout)) {
        $redis->auth($password);
        
        if ($redis->ping()) {
            echo "   ✓ Redis连接成功\n";
            
            // 测试Nextcloud相关功能
            echo "\n3. Nextcloud缓存模式测试:\n";
            
            // 测试分布式缓存模式
            $distributedKey = 'oc_distributed_test_' . uniqid();
            $redis->set($distributedKey, 'distributed_value', 60);
            if ($redis->get($distributedKey) === 'distributed_value') {
                echo "   ✓ 分布式缓存模式工作正常\n";
                $redis->del($distributedKey);
            }
            
            // 测试锁定缓存模式  
            $lockKey = 'oc_lock_test_' . uniqid();
            $redis->set($lockKey, 'lock_value', 10);
            if ($redis->get($lockKey) === 'lock_value') {
                echo "   ✓ 锁定缓存模式工作正常\n";
                $redis->del($lockKey);
            }
            
            // 查看现有Nextcloud键
            $ocKeys = $redis->keys('oc_*');
            echo "   现有的Nextcloud键数量: " . count($ocKeys) . "\n";
            if (count($ocKeys) > 0) {
                echo "   示例键: " . implode(', ', array_slice($ocKeys, 0, 5)) . "\n";
            }
            
        } else {
            echo "   ✗ Redis ping失败\n";
        }
        $redis->close();
    } else {
        echo "   ✗ 无法连接到Redis服务器\n";
    }
} catch (Exception $e) {
    echo "   ✗ Redis异常: " . $e->getMessage() . "\n";
}

echo "\n4. 性能测试:\n";
$start = microtime(true);
try {
    $redis = new Redis();
    $redis->connect($CONFIG['redis']['host'], $CONFIG['redis']['port'], 1.0);
    $redis->auth($CONFIG['redis']['password']);
    
    // 执行100次简单的set/get操作测试性能
    $iterations = 100;
    for ($i = 0; $i < $iterations; $i++) {
        $key = 'perf_test_' . $i;
        $value = 'value_' . $i;
        $redis->set($key, $value, 1);
        $redis->get($key);
    }
    $redis->close();
    
    $time = microtime(true) - $start;
    echo "   ✓ 性能测试完成: $iterations 次操作耗时 " . round($time * 1000, 2) . "ms\n";
    echo "   平均每次操作: " . round(($time / $iterations) * 1000, 2) . "ms\n";
} catch (Exception $e) {
    echo "   ✗ 性能测试失败: " . $e->getMessage() . "\n";
}

echo "\n=== 测试完成 ===\n";
EOF

# 执行完整测试
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# php /tmp/test_nextcloud_redis.php
=== Nextcloud Redis 完整功能测试 ===
1. 配置文件检查:
   ✓ config.php 存在
   ✓ 分布式缓存配置
   ✓ 锁定缓存配置
   ✓ Redis连接配置
   Redis连接详情:
     Host: redis
     Port: 6379

2. Redis连接测试:
   ✓ Redis连接成功

3. Nextcloud缓存模式测试:
   ✓ 分布式缓存模式工作正常
   ✓ 锁定缓存模式工作正常
   现有的Nextcloud键数量: 0

4. 性能测试:
   ✓ 性能测试完成: 100 次操作耗时 477.36ms
   平均每次操作: 4.77ms

=== 测试完成 ===
```
## 7. 清理临时文件
```bash
# 清理测试文件
root@nextcloud-5df6cfd7d4-ffczr:/var/www/html# rm -f /tmp/fix_redis_config.php /tmp/test_redis_final.php /tmp/test_nextcloud_redis.php
```
