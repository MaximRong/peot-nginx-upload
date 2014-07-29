-- need to replace with realworld stage path
local localMaps = {
    index = "/home/maxim/Documents/poet/index/",
    front = "/home/maxim/Documents/poet/front/",
    back = "/home/maxim/Documents/poet/back/",
};


local upload = require "resty.upload";
local method = ngx.var.request_method;
local resty_random = require "resty.random"
local str = require "resty.string"
local match = string.match
local cjson = require "cjson"

local _M = { _VERSION = '0.01' };
local mt = { __index = _M }



local uploadStandard = {
    size = 0,
    suffix = "*",
    localPath = localMaps.index
};


function uploadFileHandler(self, _res) 
    self.uploadFile:write(_res);
    self.uploadFileSize =  self.uploadFileSize +  string.byte(_res)
end;

function closeFileHandler(self)
    self.uploadFile:close()
    self.uploadFile = nil
end;

function parseUploadLimitInfo()
    -- TODO : Ð£Ñé
    local args = ngx.req.get_uri_args()
    for key, val in pairs(args) do
        if "size" == key then
            uploadStandard.size = val;
        elseif "suffix" == key then
            uploadStandard.suffix = val;
        elseif "localPath" == key then
            uploadStandard.localPath = localMaps.val;
        end;
    end

    ngx.log(ngx.DEBUG, "upload limit info is : ", cjson.encode(uploadStandard));
end;

function computeLimitSize()
    local limitSize;
    local match = ngx.re.match(uploadStandard.size, "^(\\d+)([A-Za-z])$");
    if match then
        -- ngx.log(ngx.ERR, "match ",  cjson.encode(match));
        local number, unit = match[1], match[2];
        if unit == "M" or unit == "m" then
            limitSize = number * 1024 * 1024
        elseif unit == "K" or unit == "k" then
            limitSize = number * 1024
        end
    else
        limitSize = uploadStandard.size
    end
    return limitSize;
end

function _M.overLimitSize(self)
    if 0 == uploadStandard.size then return false end;

    local limitSize = computeLimitSize();
    if limitSize < self.uploadFileSize then
        closeFile();
        os.remove(uploadStandard.stage .. self.fileName)
        ngx.log(ngx.ERR, "upload file size over the limit, the upload size is : ", self.uploadFileSize, " ; the limit size is : ", limitSize);
        return true;
    end

    return false;
end

function _M.allowUploadType(self)
    if "*" == uploadStandard.suffix then return true end;
    local pattern = ".+\\.(" .. uploadStandard.suffix .. ")$"
    ngx.log(ngx.DEBUG, "------allowed upload file type is : ------>", pattern)
    return ngx.re.match(self.fileName, pattern);
end

function exitWithErrorMsg(_msg, _err)
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    if _err then
        ngx.say(ngx.ERR, _msg, _err);
    else
        ngx.say(ngx.ERR, _msg);
    end
    ngx.log(ngx.ERR, _msg)
    ngx.exit(500);
end;

function createUploadForm()
    local chunk_size = 8192;
    local form, err = upload:new(chunk_size);
    if not form then
        exitWithErrorMsg("failed to get upload form: ", err)
    end;

    form:set_timeout(1000);
    
    return form;
end

function _M.createRandomFilename(self)
    local random = resty_random.bytes(16)
    local prefix, suffix = match(self.fileName, "^(.+)%.(.+)$") -- lua 原生match 正则转义用%
    return prefix .. str.to_hex(random) .. '.' .. suffix;
end

local function checkDirectoryExists(_sPath )
    return os.execute( "cd " .. _sPath ) == 0
end

function _M.handleRequestData(self, _form, _uploadResult) 
    while true do
        local typ, res, err = _form:read();
        if not typ then
            exitWithErrorMsg("failed to read typ: ", err)
        end
           
        if typ == "header" then
            
            if res[1] ~= "Content-Type" then
                local matchUpload = ngx.re.match(res[2], '(.+)filename="(.+)"(.*)')
                if matchUpload then                     
                    self.fileName = matchUpload[2];
                    ngx.log(ngx.DEBUG, "------start to handle upload file------>", self.fileName)
                    if not self:allowUploadType() then 
                        exitWithErrorMsg("upload file type is not allowed!! ", err)
                    end
                  
                    self.fileName = self:createRandomFilename()
                    ngx.log(ngx.DEBUG, "------random file name is ------>", self.fileName)

                    local directory = uploadStandard.localPath;
                    if not checkDirectoryExists(directory) then
                        ngx.log(ngx.DEBUG, "------directory path is exists, now create it ------>", directory)
                        os.execute( "mkdir -p " .. directory )
                    end;

                    self.uploadFile = io.open(directory .. self.fileName, "w+")                   
                    if not self.uploadFile then
                        exitWithErrorMsg("failed to open file :" .. self.fileName, err)
                    end
                    self.bodyHandler = uploadFileHandler;
                    self.endPartHandler = closeFileHandler;
                end;            
            end;

        elseif typ == "body" then
            if self.bodyHandler then
                self:bodyHandler(res);
                if self:overLimitSize() then  
                    exitWithErrorMsg("file size over limit :")
                end;
                
            end;

        elseif typ == "part_end" then
                bodyHandler = nil;
                if self.endPartHandler then
                    self:endPartHandler()
                    endPartHandler = nil;
                    table.insert(_uploadResult, {filename = self.fileName, fileSize = self.uploadFileSize})
                    self.fileName = nil;
                    self.uploadFileSize = 0;
                end

        elseif typ == "eof" then
            break;
        else

        end; 
    end;

end;

function _M.new()
    local self = {
        bodyHandler = nil, 
        endPartHandler = nil, 
        fileName = nil, 
        uploadFile = nil, 
        uploadFileSize = 0;
    }
    return setmetatable(self, mt);
end

function _M.upload(self)

    parseUploadLimitInfo();
    local uploadResult = {};
    local form = createUploadForm()
    self:handleRequestData(form, uploadResult)

    ngx.say(cjson.encode(uploadResult));   
    
end;


return _M;