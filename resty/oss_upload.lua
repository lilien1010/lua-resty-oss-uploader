--[[


            proxy_set_header Date $date;
            proxy_set_header Authorization $auth;
            proxy_set_header content-type $mime;
            proxy_set_header Content-MD5 '';

]]


-- local hmac = require "resty.hmac"
local http = require "resty.http"
local json = require "cjson"
  
local base64_decode	=	ngx.decode_base64 
local base64_encode	=	ngx.encode_base64

local ngx_log		=	ngx.log
local ngx_INFO		=	ngx.INFO

local ngx_http_time =	ngx.http_time 
local ngx_md5		=	ngx.md5
local ngx_md5_bin	=	ngx.md5_bin
local ngx_time		=	ngx.time 
local ngx_today		=	ngx.today
local string_len	=	string.len
local string_sub	=	string.sub
local sha1			=	ngx.hmac_sha1

local _M	=	{ 

	__accessKey	=	' ';
	__secretKey	=	" ";
	
	__storage_name	=	"oss";
	__service_name	=	"OSS";
	
	ACL_PRIVATE 			= 'private';
	ACL_PUBLIC_READ 		= 'public-read';	
	ACL_PUBLIC_READ_WRITE 	= 'public-read-write';	
	
}   

local allowd_types=	{
	['voice/htk']					=	'hta';
	['8bit']						=	'hta';
	['voice/hta']					=	'hta';
	['image/jpeg']					=	'jpg';
	['image/webp']					=	'webp';
	['image/png']					=	'png';  
	['image/gif']					=	'gif'; 
	['image/jpg']					=	'jpg'; 
	['image/bmp']					=	'bmp'; 
	['image/x-icon']				=	'ico'; 
	['image/tiff']					=	'tiff'; 
	['image/vnd.wap.wbmp']			=	'webp';  
	['image/vod']					=	'vod'; 
	['video/mp4']					=	'mp4'; 
	['application/htk']				=	'hta'; 
	['application/hta']				=	'hta'; 
	['application/octet-stream']	=	'hta'; 
}

_M.allowd_types		=	allowd_types

local mt 	= { __index = _M }

function _M:new(accessKey,secretKey,_bucket,timeout,region,alive)
	region	=	region or 's3.amazonaws.com'
	return setmetatable({
		__accessKey	=	accessKey;
		__secretKey	=	secretKey;
		_bucket		=	_bucket;
		timeout		=	timeout	or 30000;
		content_md5_bin		=	'';
		region		=	region;
		is_image	=	false;
		object_name	=	false;
		alive		=	alive;
	},mt)
	
end


function _M:__getSignature(str)  
    -- ngx.log(ngx.INFO,"data: ", self.__accessKey,',str=',str)
	
	local service =	_M.__service_name
	local key 	=	base64_encode(sha1(self.__secretKey,str))
	return service..' '.. self.__accessKey ..':'..key
end

 
function _M:build_auth_headers(content,acl,content_type,bucket,uri)

	local Date		=	ngx_http_time(ngx_time());
	acl				=	acl	or self.ACL_PUBLIC_READ
	
	local aclName 	=	"x-"..self.__storage_name.."-acl"
	
	local verb		=	'PUT'
	local MD5		=	base64_encode(self.content_md5_bin)
	content_type	=	content_type or  "application/octet-stream"
	local amz		=	"\n"..aclName..":"..acl
	local resource	=	'/'..bucket..'/'..uri;
	
	local CL 		=	string.char(10);
	
	local check_param	=	verb..CL..MD5..CL..content_type..CL..Date..amz..CL..resource
 
	-- ngx.log(ngx.INFO,'len =',string_len(check_param),' ,check_param=',check_param) 
	local out  =	{  
		['Date']			=	Date;  
		['Content-MD5']		=	MD5;  
		['Content-Type']	=	content_type;  
		['Authorization']	=	self:__getSignature(check_param);  
		['Connection']		=	'keep-alive'
	}
	
	out[aclName]		=	acl
	
	return out
end
 
function _M:get_obejct_name(content,content_type)
 
	local local_date	=	self:getDate()
    
	-- 加入时间因素 防止拷贝文件客户端冲突
	local md5 		=	ngx_md5(self.content_md5_bin .. ngx_time())
	local md5sum 	=	string_sub(md5,4,20)..'_'..string_sub(md5,28,32);
	local filename	=	local_date..'/'..md5sum..'.'..(allowd_types[content_type] or 'obj')
	return filename;
end 

function _M:upload(content, content_type, object_name )
	
	self.content_md5_bin	=	ngx_md5_bin(content)
	
	object_name		=	object_name or self:get_obejct_name(content,content_type)
	local s3_host			=	self.region
	local bucket_host		=	self._bucket .."."..s3_host 
    local host	 			= 	"http://"..bucket_host
    local final_url 		= 	host..'/'..object_name
      
	 local headers, err = self:build_auth_headers(content,self.ACL_PUBLIC_READ,content_type,self._bucket,object_name)
 
	
	 if not headers then return nil, err end
 
	 local httpc = http.new()
	
	headers['Host']	=	bucket_host
	 
	-- ngx.log(ngx.ERR,'headers=',json.encode(headers))
	
	httpc:set_timeout(self.timeout)
 	local res, err = httpc:request_uri(final_url, {
        method = "PUT",
        body = content,
        headers = headers
      })
	
	if self.alive then
		httpc:set_keepalive(self.alive.max_idle_timeout or 30000,self.alive.pool_size or 10)
	end
	
    if not res then 
		err	=	err 	or 	'' 
		return nil,self._bucket.. ' '..err
    end 
    
	-- local 	times, err = httpc:get_reused_times() 
	
	-- ngx_log(ngx_INFO,'times=',times,',err=',err,',con=',res.headers["Connection"])
	 
	-- local	body, err = res:read_body()
	
	if 	307 == res.status then
		ngx.log(ngx.ERR,' post redirect happen')
		if res.headers['Location'] then 
		
			local new_url 	=	res.headers['Location']
			 
			ngx.log(ngx.ERR,'307 new_url',new_url)
			
			local httpc = http.new()
			local res, err = httpc:request_uri(new_url, {
				method = "PUT",
				body = content,
				headers = headers
			  })
			       
			if not res then 
				err	=	err 	or 	'' 
				return nil,self._bucket.. ' '..err
			end 
			if 	200 ~= res.status then
				ngx.log(ngx.ERR,'307 s3_upload aws err',res.body)
				return nil,res.status..' code ,body='..res.body
			end
			return new_url,res.body
		else
			ngx.log(ngx.ERR,'307 but no Location')
		end
	 
	elseif 	200 ~= res.status then
		ngx.log(ngx.ERR,'s3_upload aws err',res.body)
		return nil,res.status..' code ,body='..res.body
	end
	
	   
	return 	final_url,object_name,res.body
		
end


return _M