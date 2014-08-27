local upload = require "resty.upload";
local resty_random = require "resty.random"
local str = require "resty.string"
local match = string.match
local cjson = require "cjson"

local _M = { _VERSION = '0.01' };

function getFilesize(file)
    local current = file:seek()      -- get current position
    local size = file:seek("end")    -- get file size
    file:seek("set", current)        -- restore position
    return size
end

local function uploadFileHandler(self, res) 
    self.uploadFile:write(res);
   -- self.uploadFileSize = self.uploadFileSize +  string.byte(res)
    self.uploadFileSize = getFilesize(self.uploadFile);
end;

local function closeFileHandler(self)
    self.uploadFile:close();
    self.uploadFile = nil
end;

local function exitWithErrorMsg(msg)
    local ret = {
            error = 1,
            message = msg
    }
    ngx.say(cjson.encode(ret))
    ngx.log(ngx.ERR, cjson.encode(ret));
    ngx.exit(ngx.HTTP_OK);
end 

local function computeLimitSize(size)
    local limitSize;
    local match = ngx.re.match(size, "^(\\d+)([A-Za-z])$");
    if match then
        -- ngx.log(ngx.ERR, "match ",  cjson.encode(match));
        local number, unit = match[1], match[2];
        if unit == "M" or unit == "m" then
            limitSize = tonumber(number) * 1024 * 1024
        elseif unit == "K" or unit == "k" then
            limitSize = tonumber(number) * 1024
        elseif unit == "b" or unit == "B" then
            limitSize = tonumber(number);
        end
    elseif ngx.re.match(size, "^(\\d+)$") then
        limitSize = tonumber(size)
    else
        exitWithErrorMsg("size args is Illegal, must be number or with unit 'b'  'm' or 'k'!")
    end
    return limitSize;
end

local function parseUploadLimitInfo(self)
    self.size = computeLimitSize(self.maxSize);
    if not self.storePath then
        exitWithErrorMsg("storePath args must be set, please check!!!")
    end
    ngx.log(ngx.DEBUG, "upload limit info is : ", cjson.encode(self));
end;


local function overLimitSize(self)
    if 0 == self.size then return false end;

    if self.size < self.uploadFileSize then
        closeFileHandler(self);
        os.remove(self.storePath .. self.fileName)
        ngx.log(ngx.ERR, "upload file size over the limit, the upload size is : ", self.uploadFileSize, " bytes ; the limit size is : ", self.size);
        return true;
    end

    return false;
end

local function checkFileFuffix(self, fileName)
    if "*" == self.suffix then return true end;
    local pattern = ".+\\.(" .. self.suffix .. ")$"
    ngx.log(ngx.DEBUG, "------allowed upload file type is : ------>", pattern)
    return ngx.re.match(fileName, pattern);
end

local function allowUploadType(self, fileName)   
    if not checkFileFuffix(self, fileName) then 
        exitWithErrorMsg("upload file type is not allowed!! ")
    end
end

local function createUploadForm()
    local chunk_size = 8192;
    local form, err = upload:new(chunk_size);
    if not form then
        exitWithErrorMsg("failed to get upload form: " .. err)
    end;

    form:set_timeout(1000);
    return form;
end

local function createRandomFilename(self, originalFileName)
    local random = resty_random.bytes(16)
    local prefix, suffix = match(originalFileName, "^(.+)%.(.+)$") -- lua 原生match 正则转义用%
    return prefix .. str.to_hex(random) .. '.' .. suffix;
end

local function createFilename(self, originalFileName)
    self.fileName = self.randomName == "no" and originalFileName or createRandomFilename(self, originalFileName) ;
    ngx.log(ngx.DEBUG, "------random file name is ------>", self.fileName);
end

local function checkDirectoryExists(sPath )
    return os.execute( "cd " .. sPath ) == 0
end

local function isHeadNotContentType(headerKey)
    return headerKey ~= "Content-Type"
end

local function createDirectoryIfNotExist(self)
    local directory = self.storePath;
    if not checkDirectoryExists(directory) then
        ngx.log(ngx.DEBUG, "------directory path is exists, now create it ------>", directory)
        os.execute( "mkdir -p " .. directory )
    end;
end

local function openFileWithIoOperate(self)
    self.uploadFile = io.open(self.storePath .. self.fileName, "w+")
    if not self.uploadFile then
        exitWithErrorMsg("failed to open file :" .. self.fileName)
    end
end

local function bandingFileHandler(self)
    self.bodyHandler = uploadFileHandler;
    self.endPartHandler = closeFileHandler; 
end

local function headerResHandler(self, res)
    local matchUpload = ngx.re.match(res, '(.+)filename="(.+)"(.*)')
    if not matchUpload then return end;

    local originalFileName = matchUpload[2];
    ngx.log(ngx.DEBUG, "------start to handle upload file------>", originalFileName)

    allowUploadType(self, originalFileName)

    createFilename(self, originalFileName)
    
    createDirectoryIfNotExist(self)

    openFileWithIoOperate(self)
    
    bandingFileHandler(self) 
end

local function doBodyHandlerIfExists(self, res)
    if not self.bodyHandler then return end

    self:bodyHandler(res);
    if overLimitSize(self) then  
        exitWithErrorMsg("file size over limit.")
    end;
end

local function doEndHandlerIfExists(self, uploadResult)
    if not self.endPartHandler then return end
    
    self:endPartHandler()
    self.bodyHandler = nil;
    self.endPartHandler = nil;

    table.insert(uploadResult, {filename = self.fileName, fileSize = self.uploadFileSize .. "bytes"})
    self.fileName = nil;
    self.uploadFileSize = 0;
    
end

local function handleRequestData(self, form)
    local uploadResult = {};
    while true do
        local typ, res, err = form:read();
        if not typ then
            exitWithErrorMsg("failed to read typ: " .. err)
        end
           
        if typ == "header" then     
            if isHeadNotContentType(res[1]) then
                headerResHandler(self, res[2]); 
            end;

        elseif typ == "body" then
            doBodyHandlerIfExists(self, res)            

        elseif typ == "part_end" then
            doEndHandlerIfExists(self, uploadResult)

        elseif typ == "eof" then
            break;
        else
            -- nothing!
        end; 
    end;

    return uploadResult;
end;

local function contains()
    string.find(str, "tiger")
end

local function checkDomainLegal(domains)
    local referer =  ngx.var.http_referer;
    local legalDomain = false;
    for index, domain in ipairs(domains) do
        if string.find(string.lower(referer), domain) then
            legalDomain = true;
            break;
        end;
    end;
    if not legalDomain then
        exitWithErrorMsg("your domain not be allowed to be submit!!")
    end;
end

function _M.upload(domains)
    checkDomainLegal(domains);
    local self = {
        bodyHandler = nil, 
        endPartHandler = nil, 
        fileName = nil, 
        uploadFile = nil, 
        uploadFileSize = 0,

        size = 0,
        maxSize = ngx.var.arg_size or 0,
        suffix = ngx.var.arg_suffix or "*",
        storePath = ngx.var.arg_storePath,
        randomName = ngx.var.arg_randomName or "yes",
        callback = ngx.var.arg_callback or nil
    };

    parseUploadLimitInfo(self);
    local form = createUploadForm();
    local uploadResult = handleRequestData(self, form);
    local rep = {error = 0, message = uploadResult};
    if self.callback ~= nil then
        self.callback = self.callback .. "?param=" .. cjson.encode(rep);
        return ngx.redirect(self.callback);
    end;

    ngx.say(cjson.encode(rep));
end;


return _M;