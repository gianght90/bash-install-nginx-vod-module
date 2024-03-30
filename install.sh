#!/bin/bash
apt update && apt install -y build-essential git libpcre3-dev libssl-dev zlib1g-dev zip unzip libxml2-dev nfs-common cifs-utils snapd libavcodec-dev libswscale-dev libavfilter-dev
wget http://nginx.org/download/nginx-1.22.1.tar.gz
tar -zxvf nginx-1.22.1.tar.gz
rm -f nginx-1.22.1.tar.gz
wget https://github.com/kaltura/nginx-vod-module/archive/refs/tags/1.33.tar.gz
tar -zxvf 1.33.tar.gz
rm -f 1.33.tar.gz
wget https://github.com/kaltura/nginx-secure-token-module/archive/refs/tags/1.5.tar.gz
tar -zxvf 1.5.tar.gz
rm -f 1.5.tar.gz
wget https://github.com/kaltura/nginx-akamai-token-validate-module/archive/refs/tags/1.1.tar.gz
tar -zxvf 1.1.tar.gz
rm -f 1.1.tar.gz
cd nginx-1.22.1
sudo ./configure \
    --with-debug \
    --prefix=/etc/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/run/nginx.pid \
    --sbin-path=/usr/sbin/nginx \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-file-aio \
    --with-threads \
    --with-stream \
    --with-cc-opt="-O3 -mpopcnt" \
    --with-http_secure_link_module \
    --add-module=../nginx-vod-module-1.33 \
    --with-http_mp4_module \
    --with-http_slice_module \
    --add-module=../nginx-secure-token-module-1.5 \
	--add-module=../nginx-akamai-token-validate-module-1.1
sudo make
sudo make install
cat >"/lib/systemd/system/nginx.service" <<END
[Unit]
Description=Nginx VoD Server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
END
systemctl daemon-reload
cat >"/etc/nginx/nginx.conf" <<END
user root;
worker_processes auto;
pid /var/run/nginx.pid;
thread_pool open_file_pool threads=4;
events {
	use epoll;
}

http{
	include    mime.types;
    default_type  application/octet-stream;
	
    log_format  main  ' -  [] "" '
                '   "" "" "-" - '
                '"" ""   - '
                ' "" "" '
                '"" "" "" '
                ' ';
	
	access_log off;
	error_log /var/log/nginx/error.log crit;
	
	sendfile    on;
	tcp_nopush  on;
	tcp_nodelay on;
	
	#proxy;
	proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=nginx:100m inactive=1h max_size=10g use_temp_path=off;
	proxy_cache_valid 200 206 1d;
	proxy_cache_lock on;
	proxy_cache_min_uses 6;	
	
	vod_mode                           local;
	vod_metadata_cache                 metadata_cache 1600m;
	vod_response_cache                 response_cache 512m;
	vod_last_modified_types            *;
	vod_segment_duration               3000;
	vod_align_segments_to_key_frames   on;
	vod_dash_fragment_file_name_prefix "segment";
	vod_hls_segment_file_name_prefix   "segment";
	
	vod_manifest_segment_durations_mode accurate;
	
	open_file_cache          max=1000 inactive=5m;
	open_file_cache_valid    2m;
	open_file_cache_min_uses 1;
	open_file_cache_errors   on;

	aio on;
	
	server {
				listen *:80 ;
				server_name localhost;
				error_log /var/log/nginx/vod-error.log crit;
                keepalive_timeout 60;
                keepalive_requests 1000;
                client_header_timeout 20;
                client_body_timeout 20;
                reset_timedout_connection on;
                send_timeout 20;
													              							
				location /hls/ {
						alias /home/;
						vod hls;
						add_header Access-Control-Allow-Headers "*";
						add_header Access-Control-Expose-Headers "Server,range,Content-Length,Content-Range";
						add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS";
						add_header Access-Control-Allow-Origin "*";
				}
						
				location /vod_status {
					vod_status;
				}		
	}		
}
END
