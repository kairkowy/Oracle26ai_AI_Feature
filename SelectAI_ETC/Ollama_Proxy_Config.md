### OLLAMA Proxy 설정 방법

이 문서는 OLLAMA-Oracle SelectAI 환경에 필요한 구성으로써, OLLAMA-Oracle 연계를 위하여 Nginx Proxy를 사용하여 OLLAMA 11434 포트 서비스를 80 포트 서비스로 전환하는 방법 다룬다.

Oracle SelectAI는 외부 LLM 특히 로컬 LLM 과의 연결을 위하여 OpenAI-Compitable API 방식을 사용하기 때문에 필요한 구성임.

OLLAMA 오프라인 서비스 구성 방법은 여기를 참도하세요.
https://github.com/kairkowy/handon-labs-for-vector-search/blob/main/Configuration/OLLAMA%20%EC%98%A4%ED%94%84%EB%9D%BC%EC%9D%B8%20%EC%84%A4%EC%B9%98%20%EB%B0%8F%20RPM%20%EC%84%A4%EC%B9%98%20%EB%B0%A9%EB%B2%95.md

1. ollama 서비스 수정

설치된 ollama.service 파일 수정
(예: vi etc/systemd/system/ollama.service)

```shell
vi etc/systemd/system/ollama.service

[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"

// Ollama 재기동

sudo systemctl daemon-reload
sudo systemctl restart ollama
sudo ss -lntp | grep 11434
```

ollama 서비스 확인

```shell
curl -sS http://127.0.0.1:11434/api/tags

{"models":[{"name":"llama3.2:latest","model":"llama3.2:latest","modified_at":"2026-01-06T23:12:15.326218844Z","size":2019393189,"digest":"a80c4f17acd55265feec403c7aef86be0c25983ab279d83f3bcd3abbcb5b8b72","details":{"parent_model":"","format":"gguf","family":"llama","families":["llama"],"parameter_size":"3.2B","quantization_level":"Q4_K_M"}}]}
```

2. Nginx 설치

Nginx 설치

여기서는 인터넷 환경에서 곧바로 Nginx 설치를 하는 방법으로 설명함. 인트라넷 환경에서는 Nginx 패키지를 인터넷 환경에서 패키지 다운로드 후 인트라넷 환경으로 이동하여 설치하는 방법이 필요함.
아래 링크에서 dnf download 부분을 참고하세요.
https://github.com/kairkowy/handon-labs-for-vector-search/blob/main/Configuration/Oracle%20%EB%B2%A1%ED%84%B0%EA%B2%80%EC%83%89%20%EC%98%A4%ED%94%84%EB%9D%BC%EC%9D%B8%20%ED%99%98%EA%B2%BD%20%EA%B5%AC%EC%84%B1-%EC%98%A8%EB%9D%BC%EC%9D%B8%EC%84%9C%EB%B2%84%20%EC%9E%91%EC%97%85.md


```shell
sudo dnf -y install nginx
sudo systemctl enable --now nginx

setsebool -P httpd_can_network_connect on   // SELinux 사전 처리(필수)
```

Nginx 환경 설정(11434->80)

/etc/nginx/nginx.conf 파일 수정

``` shell
vi /etc/nginx/nginx.conf

#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
map $http_authorization $auth_scheme {
  default "";
  "~*^Basic"  "Basic";
  "~*^Bearer" "Bearer";
}

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                     '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;
    log_format with_auth '$remote_addr - $remote_user [$time_local] '
                     '"$request" $status $body_bytes_sent '
                     'auth="$http_authorization"';

    access_log /var/log/nginx/ollama_access.log with_auth;


    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf; 

# 이후의 server 부분 모두 마킹 처리

```

Proxy 80 포트 설정 

// oracle select ai 에서 provicer_endpoint 파라미터 값에 포트번호 기술하면 에러가남(OPENAI compitable 조전)에 따라 80 포트 서비스가 필요함

**lua 패키지 설치 필요**

```shell
vi /etc/nginx/conf.d/ollama-proxy.conf

upstream ollama_upstream {
    server 127.0.0.1:11434;
    keepalive 32;
}

server {
    listen 80;
    server_name _;

    # (선택) 요청 크기 제한
    client_max_body_size 50m;

    # (선택) 특정 대역만 허용하고 싶으면 추가
    # allow 10.0.0.0/8;
    # allow 192.168.0.0/16;
    # deny  all;

    # (선택) 헬스체크는 인증 제외할지 여부
    # location = /health { return 200 "ok\n"; }

#    location / {
#        proxy_pass http://ollama_upstream;
#
#        # 기본 헤더
#        proxy_http_version 1.1;
#        proxy_set_header Host $host;
#        proxy_set_header X-Real-IP $remote_addr;
#        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#
#        # Ollama는 응답이 길어질 수 있음 (stream/SSE 포함)
#        proxy_read_timeout 3600;
#        proxy_send_timeout 3600;
#
#        # streaming 안정화(권장)
#        proxy_buffering off;
#
#        # keepalive
#        proxy_set_header Connection "";
#    }

  location /v1/chat/completions {

    proxy_http_version 1.1;

    # ===== 헤더 =====
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Connection "";

    # ===== 타임아웃 (Ollama 필수) =====
    proxy_read_timeout 3600;
    proxy_send_timeout 3600;

    # ===== streaming 안정화 =====
    proxy_buffering off;

    # ===== 요청(JSON) 수정 =====
    access_by_lua_block {
        ngx.req.read_body()
        local body = ngx.req.get_body_data()

        if body then
            local cjson = require "cjson.safe"
            local json = cjson.decode(body)

            if json then
                -- 기존 options 유지하면서 merge
                local options = json.options or {}

                options.num_ctx = 2048
                options.num_thread = 16
                options.num_predict = 384
                options.temperature = 0
                options.seed = 42

                json.options = options

                local new_body = cjson.encode(json)

                ngx.req.set_body_data(new_body)
                ngx.req.set_header("Content-Length", #new_body)
            end
        end
    }

    # ===== Ollama upstream =====
    proxy_pass http://ollama_upstream;
 }

```

Nginx proxy 적용

```
nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

systemctl reload nginx
```

방화벽(80 포트 오픈)

Oracle26AI 설치된 DB서버, Ollama 서비스의 서버 모두 서비스 포트 80을 개방 해주세요~


서비스 검증

ollama 서버에서

```shell
root@service-ollama conf.d]# curl -i http://localhost:11434/api/version
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Date: Tue, 03 Feb 2026 11:02:36 GMT
Content-Length: 20

==> 정상
```

DB서버에서

```shell
curl -s http://service-ollama/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.2","prompt":"오라클 26ai를 한 문장으로 설명","stream":false}'

{"model":"llama3.2","created_at":"2026-02-03T11:06:15.279940405Z","response":"오라클 26ai는 AI 기술을 incorporate한 오라클 DBMS(데이터베이스 관리 시스템)로, 오라클의 13대 CEO인 조 크루어(Cruder)가 이끄는 2022년부터 운영하는 version입니다.","done":true,"done_reason":"stop","context":[128006,9125,128007,271,38766,1303,33025,2696,25,6790,220,2366,18,271,128009,128006,882,128007,271,58368,51440,108661,220,1627,2192,18918,62398,54535,41953,43139,114942,128009,128006,78191,128007,271,58368,51440,108661,220,1627,2192,16969,15592,113094,18359,33435,24486,74177,51440,108661,6078,4931,7,167,51462,105010,107128,104019,117022,8,17835,11,74177,51440,108661,21028,220,1032,67945,12432,32428,66610,105411,102268,32179,3100,81,33719,8,20565,23955,104381,226,16969,220,2366,17,100392,103551,107065,44005,2373,80052,13],"total_duration":3529036370,"load_duration":92675399,"prompt_eval_count":37,"prompt_eval_duration":56672446,"eval_count":60,"eval_duration":3342991032}


curl -X POST http://service-ollama/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.2",    "messages": [{ "role": "user", "content": "오라클 26ai를 한 문장으로 설명" }],"stream": false}'

{"id":"chatcmpl-714","object":"chat.completion","created":1770116738,"model":"llama3.2","system_fingerprint":"fp_ollama","choices":[{"index":0,"message":{"role":"assistant","content":"오라클 26-AI는 고립된 지식로 인한 이에 대한 상처가 부드러워지는 AI 모del을 개발하여, 인간의 감정, 성격으로 주인공을 만든 시뮬레이션입니다."},"finish_reason":"stop"}],"usage":{"prompt_tokens":37,"completion_tokens":57,"total_tokens":94}}
```
----------------
end of document
