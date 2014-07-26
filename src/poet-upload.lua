-- need to replace with realworld stage path
local localMaps = {
    index = "/home/maxim/Documents/poet/index/",
    front = "/home/maxim/Documents/poet/front/",
    back = "/home/maxim/Documents/poet/back/",
};

local _M = { _VERSION = '0.01' };
local upload = require "resty.upload";
local method = ngx.var.request_method;
local resty_random = require "resty.random"
local str = require "resty.string"
local match = string.match
local cjson = require "cjson"

local bodyHandler;
local endPartHandler;
local fileName;
local uploadFileSize = 0;
local uploadFile;

local uploadStandard = {
    size = 0,
    suffix = "*",
    localPath = localMaps.index
};


function uploadFileHandler(_res) 
    uploadFileSize = uploadFileSize +  string.byte(_res)
    uploadFile:write(_res);
end;

function closeFileHandler()
    uploadFile:close()
    uploadFile = nil
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

function overLimitSize()
    if 0 == uploadStandard.size then return false end;

    local limitSize = computeLimitSize();
    if limitSize < uploadFileSize then
        closeFile();
        os.remove(uploadStandard.stage .. fileName)
        ngx.log(ngx.ERR, "upload file size over the limit, the upload size is : ", uploadFileSize, " ; the limit size is : ", limitSize);
        return true;
    end

    return false;
end

function allowUploadType(_fileName)
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

function createRandomFilename(_fileName)
    local random = resty_random.bytes(16)
    local prefix, suffix = match(fileName, "^(.+)%.(.+)$") -- lua 原生match 正则转义用%
    return prefix .. str.to_hex(random) .. '.' .. suffix;
end

local function checkDirectoryExists(_sPath )
    return os.execute( "cd " .. _sPath ) == 0
end

function handleRequestData(_form) 
    while true do
        local typ, res, err = _form:read();
        if not typ then
            exitWithErrorMsg("failed to read typ: ", err)
        end
           
        if typ == "header" then
            
            if res[1] ~= "Content-Type" then
                matchUpload = ngx.re.match(res[2], '(.+)filename="(.+)"(.*)')
                if matchUpload then                     
                    fileName = matchUpload[2];
                    ngx.log(ngx.DEBUG, "------start to handle upload file------>", fileName)
                    if not allowUploadType(fileName) then 
                        exitWithErrorMsg("upload file type is not allowed!! ", err)
                    end
                  
                    fileName = createRandomFilename(fileName)
                    ngx.log(ngx.DEBUG, "------random file name is ------>", fileName)

                    local directory = uploadStandard.localPath;
                    if not checkDirectoryExists(directory) then
                        ngx.log(ngx.DEBUG, "------directory path is exists, now create it ------>", directory)
                        os.execute( "mkdir -p " .. directory )
                    end;

                    uploadFile = io.open(directory .. fileName, "w+")                   
                    if not uploadFile then
                        exitWithErrorMsg("failed to open file :" .. fileName, err)
                    end
                    bodyHandler = uploadFileHandler;
                    endPartHandler = closeFileHandler;
                end;            
            end;

        elseif typ == "body" then
            if bodyHandler then
                bodyHandler(res);
                if overLimitSize() then  
                    exitWithErrorMsg("file size over limit :")
                end;
                
            end;

        elseif typ == "part_end" then
                bodyHandler = nil;
                if endPartHandler then
                    endPartHandler()
                    endPartHandler = nil;
                end

        elseif typ == "eof" then
            break;
        else

        end; 
    end;

end;

function _M.upload()
    parseUploadLimitInfo();
    local form = createUploadForm()
    handleRequestData(form)

    ngx.say(cjson.encode({filename =  fileName, fileSize = uploadFileSize}));   
    
end;


return _M;