# lua aliyun OSS client[阿里云oss Lua 客户端，]

the HTTP client based on  https://github.com/pintsized/lua-resty-http


## useage

	指定上传文件到阿里云的某个OSS存储节点，

## example code
 ``` lua
	
	
local	oss_upload		=		require "resty.oss_upload"

local uploader   = 	oss_upload:new(access_key_id,access_key_secret,bucket,timeOut,region)
	
	local 	body 		=	'{}' 					-- [[这里可以是从其他地方获取的资源，url下载的文件，或者本地的文件，]]
	
	local 	mimeType	=	'text/json'				--资源类型
	
	local 	objectName 	=	'service_config.json'	-- 文件命名

	local	startcall 		= 	ngx_now()*1000 
	
	local url,err,upBody	=	uploader:upload(body,mimeType,objectName)
	 

	local	cost_time 		=	ngx_now()*1000-startcall

	ngx.log(ngx.INFO,',to=',bucket,',cost=',cost_time," OK  url=",objectName,',upBody=',upBody)
	
```