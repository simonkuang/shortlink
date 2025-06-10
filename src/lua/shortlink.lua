-- shortlink.lua - 短链接服务器主要逻辑
local json = require "cjson"
local http = require "resty.http"

local _M = {}

-- 全局变量存储短链接数据
local shortlink_data = {}
local last_load_time = 0
local config_file = "/usr/local/openresty/data/shortlinks.json"  -- 配置文件路径

-- 生成 JavaScript 代码用于复制请求
local function generate_redirect_js(target_url, method, headers, cookies)
    local js_headers = "{}"
    local js_cookies = ""

    -- 构建 headers 对象
    if headers and next(headers) then
        local header_pairs = {}
        for k, v in pairs(headers) do
            table.insert(header_pairs, string.format('"%s": "%s"', k, v))
        end
        js_headers = "{" .. table.concat(header_pairs, ", ") .. "}"
    end

    -- 构建 cookies 字符串
    if cookies and next(cookies) then
        local cookie_pairs = {}
        for k, v in pairs(cookies) do
            table.insert(cookie_pairs, string.format("%s=%s", k, v))
        end
        js_cookies = table.concat(cookie_pairs, "; ")
    end

    local js_code = string.format([[
<!DOCTYPE html>
<html>
<head>
    <title>Redirecting...</title>
    <script>
        function redirect() {
            var method = '%s';
            var url = '%s';
            var headers = %s;
            var cookies = '%s';
            
            // 设置 cookies
            if (cookies) {
                document.cookie = cookies;
            }
            
            if (method === 'GET') {
                // 对于 GET 请求，直接跳转
                window.location.href = url;
            } else {
                // 对于其他 HTTP 方法，使用 fetch API
                var fetchOptions = {
                    method: method,
                    headers: headers,
                    credentials: 'include'  // 包含 cookies
                };
                
                // 如果是 POST/PUT/PATCH 等需要 body 的方法，可以添加空 body
                if (['POST', 'PUT', 'PATCH'].includes(method.toUpperCase())) {
                    fetchOptions.body = '';
                }
                
                fetch(url, fetchOptions)
                    .then(function(response) {
                        if (response.redirected) {
                            window.location.href = response.url;
                        } else {
                            window.location.href = url;
                        }
                    })
                    .catch(function(error) {
                        console.error('Error:', error);
                        // 如果 fetch 失败，尝试直接跳转
                        window.location.href = url;
                    });
            }
        }
        
        // 页面加载后立即执行跳转
        window.onload = redirect;
        
        // 如果 3 秒后还没跳转，强制跳转
        setTimeout(function() {
            window.location.href = '%s';
        }, 3000);
    </script>
</head>
<body>
    <p>Redirecting to <a href="%s">%s</a>...</p>
    <p>If you are not redirected automatically, please click the link above.</p>
</body>
</html>
]], method, target_url, js_headers, js_cookies, target_url, target_url, target_url)

    return js_code
end

-- 加载短链接配置文件
local function load_shortlink_config()
    local file = io.open(config_file, "r")
    if not file then
        ngx.log(ngx.ERR, "Cannot open shortlink config file: " .. config_file)
        return false
    end

    local content = file:read("*all")
    file:close()

    if not content or content == "" then
        ngx.log(ngx.ERR, "Empty shortlink config file")
        return false
    end

    local success, data = pcall(json.decode, content)
    if not success then
        ngx.log(ngx.ERR, "Failed to parse JSON config: " .. tostring(data))
        return false
    end

    -- 验证数据结构
    if type(data) ~= "table" or not data.shortlinks then
        ngx.log(ngx.ERR, "Invalid config structure")
        return false
    end

    shortlink_data = data.shortlinks
    last_load_time = ngx.now()
    ngx.log(ngx.INFO, "Loaded " .. #shortlink_data .. " shortlinks")
    return true
end

-- 定时检查并重新加载配置
function _M.reload_config_if_needed()
    local current_time = ngx.now()
    local reload_interval = 10  -- 10秒检查一次

    if current_time - last_load_time > reload_interval then
        local success = load_shortlink_config()
        if not success then
            ngx.log(ngx.WARN, "Failed to reload config, using previous data")
        end
    end
end

-- 查找短链接
local function find_shortlink(short_code)
    for _, link in ipairs(shortlink_data) do
        if link.code == short_code then
            return link
        end
    end
    return nil
end

-- 处理短链接跳转
function _M.handle_redirect()
    -- 定时重新加载配置
    _M.reload_config_if_needed()

    -- 获取短链接代码
    local uri = ngx.var.uri
    local short_code = string.match(uri, "^/([^/]+)$")

    if not short_code then
        ngx.status = 404
        ngx.say("Invalid short link")
        return
    end

    -- 查找对应的链接配置
    local link_config = find_shortlink(short_code)
    if not link_config then
        ngx.status = 404
        ngx.say("Short link not found")
        return
    end

    -- 获取目标 URL 和配置
    local target_url = link_config.target_url
    local method = link_config.method or "GET"
    local headers = link_config.headers or {}
    local cookies = link_config.cookies or {}

    -- 记录访问日志
    ngx.log(ngx.INFO, string.format("Redirecting %s to %s via %s", short_code, target_url, method))

    -- 如果是简单的 GET 跳转且无特殊要求，直接重定向
    if method == "GET" and not next(headers) and not next(cookies) then
        return ngx.redirect(target_url, 302)
    end

    -- 生成带 JavaScript 的重定向页面
    local redirect_html = generate_redirect_js(target_url, method, headers, cookies)

    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(redirect_html)
end

-- 初始化加载配置
local function init()
    if not load_shortlink_config() then
        ngx.log(ngx.WARN, "Initial config load failed, service may not work properly")
    end
end

-- 在 Nginx 启动时初始化
init()

return _M
