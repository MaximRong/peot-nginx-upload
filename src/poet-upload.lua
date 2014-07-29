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
    local args = ngx.req.get_uri_args()
    for key, val in pairs(args) do
        if "size" == key then
            uploadStandard.size = computeLimitSize(val);
        elseif "suffix" == key then
            uploadStandard.suffix = val;
        elseif "localPath" == key then
            local path = localMaps[val]
            if not path then
                exitWithErrorMsg("localPath args is Illegal, please check!")
            end
            uploadStandard.localPath = path;
        end;
    end

    ngx.log(ngx.DEBUG, "upload limit info is : ", cjson.encode(uploadStandard));
end;

function computeLimitSize(size)
    local limitSize;
    local match = ngx.re.match(size, "^(\\d+)([A-Za-z])$");
    if match then
        -- ngx.log(ngx.ERR, "match ",  cjson.encode(match));
        local number, unit = match[1], match[2];
        if unit == "M" or unit == "m" then
            limitSize = number * 1024 * 1024
        elseif unit == "K" or unit == "k" then
            limitSize = number * 1024
        end
    elseif ngx.re.match(size, "^(\\d+)$") then
        limitSize = tonumber(size)
    else
        exitWithErrorMsg("size args is Illegal, must be number or with unit 'M' or 'k'!")
    end
    return limitSize;
end

function overLimitSize(_self)
    if 0 == uploadStandard.size then return false end;

    if uploadStandard.size < _self.uploadFileSize then
        closeFileHandler(_self);
        os.remove(uploadStandard.stage .. _self.fileName)
        ngx.log(ngx.ERR, "upload file size over the limit, the upload size is : ", _self.uploadFileSize, " ; the limit size is : ", uploadStandard.size);
        return true;
    end

    return false;
end

function allowUploadType(_fileName)   
    if not checkFileFuffix(_fileName) then 
        exitWithErrorMsg("upload file type is not allowed!! ", err)
    end
end

function checkFileFuffix(_fileName)
    if "*" == uploadStandard.suffix then return true end;
    local pattern = ".+\\.(" .. uploadStandard.suffix .. ")$"
    ngx.log(ngx.DEBUG, "------allowed upload file type is : ------>", pattern)
    return ngx.re.match(_fileName, pattern);
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

function createRandomFilename(_self, _originalFileName)
    local random = resty_random.bytes(16)
    local prefix, suffix = match(_originalFileName, "^(.+)%.(.+)$") -- lua 原生match 正则转义用%
    _self.fileName =  prefix .. str.to_hex(random) .. '.' .. suffix;
    ngx.log(ngx.DEBUG, "------random file name is ------>", _self.fileName)
end

function checkDirectoryExists(_sPath )
    return os.execute( "cd " .. _sPath ) == 0
end

function isHeadNotContentType(_headerKey)
    return _headerKey ~= "Content-Type"
end

function createDirectoryIfNotExist()
    local directory = uploadStandard.localPath;
    if not checkDirectoryExists(directory) then
        ngx.log(ngx.DEBUG, "------directory path is exists, now create it ------>", directory)
        os.execute( "mkdir -p " .. directory )
    end;
end

function openFileWithIoOperate(_self)
    _self.uploadFile = io.open(uploadStandard.localPath .. _self.fileName, "w+")                   
    if not _self.uploadFile then
        exitWithErrorMsg("failed to open file :" .. _self.fileName, err)
    end
end

function bandingFileHandler(_self)
    _self.bodyHandler = uploadFileHandler;
    _self.endPartHandler = closeFileHandler; 
end

function headerResHandler(self, _res)
    local matchUpload = ngx.re.match(_res, '(.+)filename="(.+)"(.*)')
    if not matchUpload then return end;

    local originalFileName = matchUpload[2];
    ngx.log(ngx.DEBUG, "------start to handle upload file------>", originalFileName)

    allowUploadType(originalFileName) 

    createRandomFilename(self, originalFileName)
    
    createDirectoryIfNotExist()

    openFileWithIoOperate(self)
    
    bandingFileHandler(self) 
end

function doBodyHandlerIfExists(_self, _res)
    if not _self.bodyHandler then return end

    _self:bodyHandler(_res);
    if overLimitSize(_self) then  
        exitWithErrorMsg("file size over limit :")
    end;
end

function doEndHandLerIfExists(_self, _uploadResult)
    if not _self.endPartHandler then return end
    
    _self:endPartHandler()
    _self.bodyHandler = nil;
    _self.endPartHandler = nil;

    table.insert(_uploadResult, {filename = _self.fileName, fileSize = _self.uploadFileSize})
    _self.fileName = nil;
    _self.uploadFileSize = 0;
    
end

function _M.handleRequestData(self, _form, _uploadResult) 
    local uploadResult = {};
    while true do
        local typ, res, err = _form:read();
        if not typ then
            exitWithErrorMsg("failed to read typ: ", err)
        end
           
        if typ == "header" then     
            if isHeadNotContentType(res[1]) then
                headerResHandler(self, res[2]); 
            end;

        elseif typ == "body" then
            doBodyHandlerIfExists(self, res)            

        elseif typ == "part_end" then
            doEndHandLerIfExists(self, uploadResult)

        elseif typ == "eof" then
            break;
        else
            -- nothing!
        end; 
    end;

    return uploadResult;
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
    local form = createUploadForm()
    local uploadResult = self:handleRequestData(form, uploadResult)
    ngx.say(cjson.encode(uploadResult));       
end;


return _M;