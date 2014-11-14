--[[
  
  Copyright (C) 2014 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
 
  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.
 
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.
   
  lib/luasocket.lua
  lua-httpcli
  
  Created by Masatoshi Teruya on 14/11/13.
  
--]]

-- module
local METHOD = require('httpconsts.method').consts;
local HttpCli = require('httpcli');
local ltn12 = require("ltn12");
local SCHEME = {
    http = require('socket.http'),
    https = require('ssl.https')
};
-- class
local LuaSocket = require('halo').class.LuaSocket;


function LuaSocket:init( ... )
    return HttpCli.new( self, METHOD, ... );
end


function LuaSocket:request( req, timeout )
    local sender = SCHEME[req.scheme];
    local body = {};
    local res, code, header;
    
    -- set timeout
    sender.TIMEOUT = timeout;
    -- send request
    res, code, header = SCHEME[req.scheme].request({
        method = req.method,
        url = req.uri,
        headers = req.header,
        source = req.body and ltn12.source.string( req.body ) or nil,
        sink = ltn12.sink.table( body )
    });
    
    -- success
    if type( code ) == 'number' then
        return {
            status = code,
            header = header,
            body = table.concat( body )
        };
    -- timeout: set 408 Request Timeout to status field
    elseif code == 'timeout' then
        return {
            status = 408
        };
    end
    
    -- failed to request
    return nil, code;
end


return LuaSocket.exports;
