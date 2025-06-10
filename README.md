# OpenResty 短链接服务器部署指南

## 1. 系统要求

- OpenResty 1.15.8+ 
- Lua 5.1+
- lua-cjson 模块
- lua-resty-http 模块（可选，用于扩展功能）

## 2. 安装 OpenResty

### Ubuntu/Debian
```bash
# 添加 OpenResty 仓库
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"

# 安装 OpenResty
sudo apt-get update
sudo apt-get install openresty
```

### CentOS/RHEL
```bash
# 添加 OpenResty 仓库
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo

# 安装 OpenResty
sudo yum install openresty
```

## 3. 目录结构

```
/usr/local/openresty/
├── nginx/
│   ├── conf/
│   │   └── nginx.conf          # 主配置文件
│   └── logs/                   # 日志目录
├── lua/
│   └── shortlink.lua           # 短链接处理模块
└── data/
    └── shortlinks.json         # 短链接配置文件
```

## 4. 部署步骤

### 4.1 创建目录结构
```bash
sudo mkdir -p /usr/local/openresty/lua
sudo mkdir -p /usr/local/openresty/data
```

### 4.2 复制文件
```bash
# 复制 Lua 模块
sudo cp shortlink.lua /usr/local/openresty/lua/

# 复制配置文件
sudo cp shortlinks.json /usr/local/openresty/data/

# 复制 Nginx 配置
sudo cp nginx.conf /usr/local/openresty/nginx/conf/
```

### 4.3 修改配置文件路径
编辑 `/usr/local/openresty/lua/shortlink.lua`，修改配置文件路径：
```lua
local config_file = "/usr/local/openresty/data/shortlinks.json"
```

### 4.4 修改 Nginx 配置
编辑 `/usr/local/openresty/nginx/conf/nginx.conf`，确保：
```nginx
lua_package_path "/usr/local/openresty/lua/?.lua;;";
```

## 5. 启动服务

```bash
# 测试配置文件
sudo /usr/local/openresty/bin/openresty -t

# 启动服务
sudo /usr/local/openresty/bin/openresty

# 重新加载配置
sudo /usr/local/openresty/bin/openresty -s reload

# 停止服务
sudo /usr/local/openresty/bin/openresty -s stop
```

## 6. 数据结构说明

### 短链接配置格式
```json
{
  "shortlinks": [
    {
      "code": "短链接代码",
      "target_url": "目标URL",
      "method": "HTTP方法 (GET/POST/PUT/DELETE/PATCH等)",
      "headers": {
        "Header-Name": "Header-Value"
      },
      "cookies": {
        "cookie-name": "cookie-value"
      },
      "description": "描述信息（可选）"
    }
  ]
}
```

### 字段说明
- `code`: 短链接标识符，只能包含字母和数字
- `target_url`: 目标 URL，必须是完整的 URL
- `method`: HTTP 方法，默认为 GET
- `headers`: 自定义请求头（可选）
- `cookies`: 需要设置的 cookies（可选）
- `description`: 描述信息（可选）

## 7. 使用示例

### 7.1 简单跳转
```
http://your-domain.com/s/google
→ 跳转到 https://www.google.com
```

### 7.2 POST 请求跳转
```
http://your-domain.com/s/api1
→ 使用 POST 方法访问 API，并携带指定的 headers 和 cookies
```

### 7.3 带认证的跳转
```
http://your-domain.com/s/secure
→ 带特定 headers 和 cookies 访问安全页面
```

## 8. 管理功能

### 8.1 健康检查
```bash
curl http://your-domain.com/health
```

### 8.2 手动重新加载配置
```bash
curl http://your-domain.com/admin/reload
```

### 8.3 查看日志
```bash
# 访问日志
sudo tail -f /usr/local/openresty/nginx/logs/access.log

# 错误日志
sudo tail -f /usr/local/openresty/nginx/logs/error.log
```

## 9. 配置文件自动重载

服务器会每 60 秒自动检查配置文件是否需要重新加载：
- 如果加载成功，使用新配置
- 如果加载失败，继续使用之前的配置
- 加载状态会记录在错误日志中

## 10. 安全注意事项

1. **访问控制**: 建议对 `/admin/*` 路径添加访问限制
2. **HTTPS**: 生产环境建议启用 HTTPS
3. **配置文件权限**: 确保配置文件的读取权限合适
4. **日志监控**: 定期检查访问和错误日志

## 11. 故障排查

### 11.1 常见问题
- **404 错误**: 检查短链接代码是否存在于配置文件中
- **配置加载失败**: 检查 JSON 格式是否正确
- **JavaScript 跳转失败**: 检查目标 URL 是否支持跨域请求

### 11.2 调试模式
可以临时修改错误日志级别为 debug：
```nginx
error_log logs/error.log debug;
```

## 12. 性能优化

1. **内存缓存**: 配置数据完全加载在内存中，访问速度快
2. **定时重载**: 避免每次请求都检查文件，减少 I/O 开销
3. **直接重定向**: GET 请求无特殊要求时直接使用 HTTP 重定向
4. **连接池**: OpenResty 内置连接池，处理高并发访问

这个短链接服务器设计灵活，支持各种 HTTP 方法和自定义参数，适合在内网或生产环境中使用。