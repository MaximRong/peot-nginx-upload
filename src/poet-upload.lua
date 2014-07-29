local upload = require "resty.upload";
local resty_random = require "resty.random"
local str = require "resty.string"
local match = string.match
local cjson = require "cjson"

local _M = { _VERSION = '0.01' };

local function uploadFileHandler(self, _res) 
    self.uploadFile:write(_res);
    self.uploadFileSize = self.uploadFileSize +  string.byte(_res)
end;

local function closeFileHandler(self)
    self.uploadFile:close()
    self.uploadFile = nil
end;

local function exitWithClientErrorMsg(_msg, _httpCode, _err)
    ngx.status = _httpCode
    if _err then
        ngx.say(ngx.ERR, _msg, _err);
    else
        ngx.say(ngx.ERR, _msg);
    end
    ngx.log(ngx.ERR, _msg)
    ngx.exit(_httpCode);
end 

local function computeLimitSize(size)
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

local function parseUploadLimitInfo(_self)
    _self.size = computeLimitSize(_self.maxSize);
    if not _self.localPath then
        exitWithClientErrorMsg("localPath args is Illegal, please check!", 482)
    end
    ngx.log(ngx.DEBUG, "upload limit info is : ", cjson.encode(_self));
end;



local function overLimitSize(_self)
    if 0 == _self.size then return false end;

    if _self.size < _self.uploadFileSize then
        closeFileHandler(_self);
        os.remove(_self.localPath .. _self.fileName)
        ngx.log(ngx.ERR, "upload file size over the limit, the upload size is : ", _self.uploadFileSize, " ; the limit size is : ", _self.size);
        return true;
    end

    return false;
end

local function checkFileFuffix(_self, _fileName)
    if "*" == _self.suffix then return true end;
    local pattern = ".+\\.(" .. _self.suffix .. ")$"
    ngx.log(ngx.DEBUG, "------allowed upload file type is : ------>", pattern)
    return ngx.re.match(_fileName, pattern);
end

local function allowUploadType(_self, _fileName)   
    if not checkFileFuffix(_self, _fileName) then 
        exitWithClientErrorMsg("upload file type is not allowed!! ", 481, err)
    end
end



local function exitWithErrorMsg(_msg, _err)
    exitWithClientErrorMsg(_msg, 500, _err)
end;

local function createUploadForm()
    local chunk_size = 8192;
    local form, err = upload:new(chunk_size);
    if not form then
        exitWithErrorMsg("failed to get upload form: ", err)
    end;

    form:set_timeout(1000);
    return form;
end

local function createRandomFilename(_self, _originalFileName)
    local random = resty_random.bytes(16)
    local prefix, suffix = match(_originalFileName, "^(.+)%.(.+)$") -- lua 原生match 正则转义用%
    _self.fileName =  prefix .. str.to_hex(random) .. '.' .. suffix;
    ngx.log(ngx.DEBUG, "------random file name is ------>", _self.fileName)
end

local function checkDirectoryExists(_sPath )
    return os.execute( "cd " .. _sPath ) == 0
end

local function isHeadNotContentType(_headerKey)
    return _headerKey ~= "Content-Type"
end

local function createDirectoryIfNotExist(_self)
    local directory = _self.localPath;
    if not checkDirectoryExists(directory) then
        ngx.log(ngx.DEBUG, "------directory path is exists, now create it ------>", directory)
        os.execute( "mkdir -p " .. directory )
    end;
end

local function openFileWithIoOperate(_self)
    _self.uploadFile = io.open(_self.localPath .. _self.fileName, "w+")                   
    if not _self.uploadFile then
        exitWithErrorMsg("failed to open file :" .. _self.fileName)
    end
end

local function bandingFileHandler(_self)
    _self.bodyHandler = uploadFileHandler;
    _self.endPartHandler = closeFileHandler; 
end

local function headerResHandler(self, _res)
    local matchUpload = ngx.re.match(_res, '(.+)filename="(.+)"(.*)')
    if not matchUpload then return end;

    local originalFileName = matchUpload[2];
    ngx.log(ngx.DEBUG, "------start to handle upload file------>", originalFileName)

    allowUploadType(self, originalFileName) 

    createRandomFilename(self, originalFileName)
    
    createDirectoryIfNotExist(self)

    openFileWithIoOperate(self)
    
    bandingFileHandler(self) 
end

local function doBodyHandlerIfExists(_self, _res)
    if not _self.bodyHandler then return end

    _self:bodyHandler(_res);
    if overLimitSize(_self) then  
        exitWithClientErrorMsg("file size over limit :", 480)
    end;
end

local function doEndHandLerIfExists(_self, _uploadResult)
    if not _self.endPartHandler then return end
    
    _self:endPartHandler()
    _self.bodyHandler = nil;
    _self.endPartHandler = nil;

    table.insert(_uploadResult, {filename = _self.fileName, fileSize = _self.uploadFileSize})
    _self.fileName = nil;
    _self.uploadFileSize = 0;
    
end

local function handleRequestData(_self, _form, _uploadResult) 
    local uploadResult = {};
    while true do
        local typ, res, err = _form:read();
        if not typ then
            exitWithErrorMsg("failed to read typ: ", err)
        end
           
        if typ == "header" then     
            if isHeadNotContentType(res[1]) then
                headerResHandler(_self, res[2]); 
            end;

        elseif typ == "body" then
            doBodyHandlerIfExists(_self, res)            

        elseif typ == "part_end" then
            doEndHandLerIfExists(_self, uploadResult)

        elseif typ == "eof" then
            break;
        else
            -- nothing!
        end; 
    end;

    return uploadResult;
end;

function _M.upload(_maxSize, _suffix, _localPath)
    local self = {
        bodyHandler = nil, 
        endPartHandler = nil, 
        fileName = nil, 
        uploadFile = nil, 
        uploadFileSize = 0,

        size = 0,
        maxSize = _maxSize or 0,
        suffix = _suffix or "*",
        localPath = _localPath       
    };

    parseUploadLimitInfo(self);
    local form = createUploadForm()
    local uploadResult = handleRequestData(self, form, uploadResult)
    ngx.say(cjson.encode(uploadResult));       
end;


return _M;