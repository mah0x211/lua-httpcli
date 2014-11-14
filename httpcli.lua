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

 
  httpcli.lua
  lua-httpcli
  
  Created by Masatoshi Teruya on 14/11/13.
  
--]]
-- module
local typeof = require('util.typeof');
local flatten = require('util.table').flatten;
local parseURI = require('url').parse;
local encodeURI = require('url').encodeURI;
local encodeJSON = require('cjson.safe').encode;
local decodeJSON = require('cjson.safe').decode;
-- constants
local DEFAULT_TIMEOUT = 60;
local SCHEME = {
    http = true,
    https = true
};
local CONVERSION_TBL = { 
    ['-'] = '_'
};
local EINVAL = '%s must be %s';

-- private
local function setHeader( req, header )
    for k, v in pairs( header ) do
        req.header[k] = v;
    end
end


local function encodeFormURL( tbl )
    local etbl = {};
    local idx = 0;
    
    for k, v in pairs( flatten( tbl ) ) do
        idx = idx + 1;
        etbl[idx] = encodeURI( k ) .. '=' .. encodeURI( v );
    end
    
    return idx > 0 and table.concat( etbl, '&' ) or nil;
end


local function toFormUrlEncoded( req, body )
    req.body = encodeFormURL( body ) or '';
    setHeader( req, {
        ['Content-Type'] = 'application/x-www-form-urlencoded',
        ['Content-Length'] = #req.body
    });
end


local function toJSON( req, body )
    local err;
    
    req.body, err = encodeJSON( body );
    if not err then
        setHeader( req, {
            ['Content-Type'] = 'application/json',
            ['Content-Length'] = #req.body
        });
    end
    
    return err;
end

local BODYENCODER = {
    form = toFormUrlEncoded,
    json = toJSON
};


local function setOptBody( req, body, enctype )
    if body ~= nil then
        -- invalid body type
        if typeof.table( body ) then
            local encoder;
            
            -- default content-type: text/plain
            if enctype == nil then
                enctype = 'form';
            elseif not typeof.string( enctype ) then
                return EINVAL:format( 'opts.enctype', 'string' );
            -- encode table
            end
            
            encoder = BODYENCODER[enctype];
            -- unknown enctype
            if not encoder then
                return 'unsupported encoding type: ' .. enctype;
            end
            
            return encoder( req, body );
        -- set string body
        elseif typeof.string( body ) then
            -- default content-type: application/x-www-form-urlencoded
            if enctype == nil then
                enctype = 'application/x-www-form-urlencoded';
                req.body = encodeURI( body );
            -- invalid enctype
            elseif not typeof.string( enctype ) then
                return EINVAL:format( 'opts.enctype', 'string' );
            -- custom encoding type
            else
                req.body = body;
            end
            
            setHeader( req, {
                ['Content-Type'] = enctype,
                ['Content-Length'] = #req.body
            });
        -- unsupported body type
        else
            return EINVAL:format( 'opts.body', 'string or table' );
        end
    end
end


local function setOptHeader( req, header )
    if header == nil then
        return nil;
    elseif not typeof.table( header ) then
        return EINVAL:format( 'opts.header', 'table' );
    end
    
    setHeader( req, header );
end


local function setOptQuery( req, query )
    if query == nil then
        if req.query then
            req.uri = req.uri .. '?' .. req.query .. req.hash;
        else
            req.uri = req.uri .. req.hash;
        end
        return nil;
    elseif not typeof.table( query ) then
        return EINVAL:format( 'opts.query', 'table' );
    end
    
    query = encodeFormURL( query );
    -- append encoded query and hash fragment
    if query then
        if req.query then
            req.uri = req.uri .. '?' .. req.query .. '&' .. query .. req.hash;
        else
            req.uri = req.uri .. '?' .. query .. req.hash;
        end
    -- append has fragment
    else
        req.uri = req.uri .. req.hash;
    end
end


local function setURI( req, uri )
    local err, parsedURI;
    
    if not typeof.string( uri ) then
        return EINVAL:format( 'uri', 'string' );
    end
    
    -- parse uri
    parsedURI, err = parseURI( uri );
    
    if err then
        return ('invalid uri format: %q'):format( err );
    -- unsupported protocol
    elseif not SCHEME[parsedURI.scheme] then
        return ('unsupported protocol: %q'):format( parsedURI.scheme );
    end
    req.scheme = parsedURI.scheme;
    req.host = parsedURI.host;
    req.port = parsedURI.port;
    req.query = parsedURI.query;
    req.hash = parsedURI.fragment and '#' .. parsedURI.fragment or '';
    req.uri = table.concat({
        parsedURI.scheme,
        '://',
        parsedURI.userinfo and parsedURI.userinfo .. '@' or '',
        parsedURI.host,
        parsedURI.port and ':' .. parsedURI.port or '',
        parsedURI.path
    });
end


local function createRequest( method, uri, opts )
    local req = {
        method = method,
        header = {}
    };
    local err = setURI( req, uri );
    
    opts = opts or {};
    if err then
        return nil, err;
    elseif not typeof.table( opts ) then
        return nil, EINVAL:format( 'opts', 'table' );
    end
    
    err = setOptQuery( req, opts.query );
    if err then
        return nil, err;
    end
    err = setOptHeader( req, opts.header );
    if err then
        return nil, err;
    end
    err = setOptBody( req, opts.body, opts.enctype );
    if err then
        return nil, err;
    end
    
    return req;
end


-- class
local HttpCli = require('halo').class.HttpCli;


function HttpCli:__index( method )
    local own = protected( self );
    
    method = type( method ) == 'string' and own.methods[method] or nil;
    if method then
        return function( _, uri, opts, timeout )
            local err, req, entity, body;
            
            -- verify timeout
            if timeout == nil then
                timeout = own.timeout;
            elseif not typeof.uint( timeout ) then
                return nil, 'timeout must be unsigned integer number';
            end
            
            -- create request table
            req, err = createRequest( method, uri, opts );
            if err then
                return nil, err;
            end
            
            -- call request method
            -- entity:table, err:string = delegate:request( req:table )
            entity, err = own.delegate:request( req, timeout );
            if not err and entity.header then
                -- replace to uppercase header
                if own.ucHeader then
                    local header = {};
                    
                    -- convert to uppercase
                    for k, v in pairs( entity.header ) do
                        header[k:upper():gsub( '[- ]', CONVERSION_TBL )] = v;
                    end
                    entity.header = header;
                end
                
                if entity.body then
                    local ctype;
                    
                    -- lookup content-type header
                    if own.ucHeader then
                        ctype = entity.header.CONTENT_TYPE;
                    else
                        for _, name in ipairs({
                            'content-type', 'Content-Type'
                        }) do
                            ctype = entity.header[name];
                            if ctype then
                                break;
                            end
                        end
                    end
                    
                    -- decode json response
                    if ctype and ctype:find('^application/json') then
                        body, err = decodeJSON( entity.body );
                        if not err then
                            entity.body = body;
                        end
                    end
                end
            end
            
            return entity, err;
        end
    end
    
    return nil;
end


-- delegate: request handler
-- methods: table of method
-- timeout: default timeout sec
function HttpCli:init( delegate, methods, ucHeader, timeout )
    local own = protected( self );
    local index = getmetatable( self ).__index;
    
    if not typeof.table( delegate ) or not typeof.Function( delegate.request ) then
        return nil, 'delegate should implement request method';
    elseif not typeof.table( methods ) then
        return nil, 'methods must be table';
    elseif ucHeader ~= nil and not typeof.boolean( ucHeader ) then
        return nil, 'ucHeader must be boolean';
    elseif timeout == nil then
        timeout = DEFAULT_TIMEOUT;
    elseif not typeof.uint( timeout ) then
        return nil, 'timeout must be unsigned integer number';
    end
    
    own.delegate = delegate;
    own.methods = methods;
    own.timeout = timeout;
    own.ucHeader = ucHeader;
    
    -- remove unused methods
    for _, name in ipairs({ 'init', 'constructor' }) do
        index[name] = nil;
    end
    
    return self;
end


return HttpCli.exports;
