peot-nginx-upload
=================

peot-nginx-upload is an upload module for nginx, writed by lua.
and lua-resty-upload is the prototype of this module, you can see the detail with this link : https://github.com/openresty/lua-resty-upload

Status
======

This library is considered production ready.

Synopsis
========

nginx conf:

```
  location /upload {
      content_by_lua '
          -- need to replace with realworld stage path
          local localMaps = {
              defaultPath = "/upload/poet/index/",
              index = "/upload/poet/index/",
              front = "/upload/poet/front/",
              back = "/upload/poet/back/",
          };

          local localPath = localMaps.defaultPath;

          if not ngx.arg_localPath and ngx.arg_localPath ~= nil then  
              localPath =  localMaps[ngx.var.arg_localPath];
          end     

          local upload = require "poet.poet-upload";
          upload.upload(ngx.var.arg_size, ngx.var.arg_suffix, localPath);
      ';
  }
```

Description
===========

This Lua library is a upload module for the ngx_lua nginx module:

http://wiki.nginx.org/HttpLuaModule

This Lua library takes advantage of ngx_lua's cosocket API, which ensures 100% nonblocking behavior.

Note that at least ngx_lua 0.5.0rc29 or ngx_openresty 1.0.15.7 is required.


Methods
=======

upload
------
`up:upload();`

Attempts to upload file to server.
this module will rename your upload file, and return the new file name to client when upload finished.
Allow to upload multiple file an once, and server will return a json array to client.

Config
=======
There is one static config in nginx location config block. to config the storage of the upload file.
```
local localMaps = {
    defaultPath = "/upload/poet/index/",
    index = "/upload/poet/index/",
    front = "/upload/poet/front/",
    back = "/upload/poet/back/",
};
```
the default config is 'defaultPath', and must don not remove this key.
user must config this as needed, then when you upload a file, you must send the right key with 'upload argument' for the path.

Result
===========
If upload file with no error, the module will return a json data to client.
the result data's structure like below:
```
[
  {"filename":"uploadFileName","fileSize":uploadFileSize},
  {"filename":"uploadFileName","fileSize":uploadFileSize}
]
```

Exception
===========

If there is an exception occurs when upload file, the module will return the error message to client, and the httpstatus code is 500.

Client side
===========

there are three optional arguments for client side, the arguments may send to server by get arguments.

1. size : to limit upload file size, when the size of upload file over the limit, server will return httpstatus code 480.
          the size argument can be number, or unit with 'M'/'m' or 'K'/'k'. All of those arguments is legal : `300` `300M` `300m` `300K`.

2. suffix : to limit suffix of the upload file, when uplod file not match the limit, server will return httpstatus code 481.
          the format of the suffix argument is : suffix1|suffix2|suffix3, like : jpg|txt|gif
          
3. localPath : set the path of the upload file to storage, if server config path can't matched, server will return httpstatus code 482.
          the argument of this must match the server side config, or you will get an error!

the sample request url like below :
`http://uploadurl?size=300k&suffix=jpg|gif|txt&localPath=front`

