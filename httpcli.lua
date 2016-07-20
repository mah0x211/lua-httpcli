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
-- errors
local EINVAL = '%s must be %s';
local ENOSUP = 'unsupported %s: %q';
local EENCODE = 'failed to encode application/json content: %s';
local EDECODE = 'failed to decode application/json content: %s';
local EACCES = 'cannot access to %q';
-- mime types
local MIME_FORM_URLENCODED = 'application/x-www-form-urlencoded';
local MIME_JSON = 'application/json';


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
        etbl[idx] = encodeURI( k ) .. '=' .. encodeURI( tostring( v ) );
    end

    return idx > 0 and table.concat( etbl, '&' ) or nil;
end


local function toFormUrlEncoded( req, body )
    req.body = encodeFormURL( body ) or '';
    setHeader( req, {
        ['Content-Type'] = MIME_FORM_URLENCODED,
        ['Content-Length'] = #req.body
    });
end


local function toJSON( req, body )
    local err;

    req.body, err = encodeJSON( body );
    if err then
        return EENCODE:format( err );
    end

    setHeader( req, {
        ['Content-Type'] = MIME_JSON,
        ['Content-Length'] = #req.body
    });
end

local BODYENCODER = {
    [MIME_FORM_URLENCODED]  = toFormUrlEncoded,
    [MIME_JSON]             = toJSON
};


local function isValidHost( host )
    local port;

    -- check path-segment
    if host:find('/', 1, true ) then
        return false;
    end

    -- check port
    port = host:match(':(.*)$');
    if port then
        -- invalid port format
        if port:find('[^0-9]') then
            return false;
        end
        -- invalid port range
        port = tonumber( port );
        if not port or port < 0 or port > 65535 then
            return false;
        end
    end

    return true;
end


local function setOptFailover( req, failover )
    local err, scheme, host;

    if failover == nil then
        failover = {};
    elseif not typeof.table( failover ) then
        return EINVAL:format( 'opts.failover', 'table' );
    end

    -- parse failover addrs
    req.failover = {};
    for _, addr in ipairs( failover ) do
        if not typeof.string( addr ) then
            return EINVAL:format( 'opts.failover#' .. _, 'string' );
        end

        scheme, host = addr:match('^(.+)://(.+)$');
        if scheme then
            if not SCHEME[scheme] then
                return ENOSUP:format(
                    'opts.failover#' .. _ .. ': protocol', host[1]
                );
            elseif not isValidHost( host ) then
                return ('opts.failover#%d invalid host format'):format( _ );
            end
            req.failover[#req.failover+1] = {
                scheme = scheme,
                host = host,
                uri = table.concat({
                    addr,
                    req.path
                })
            };
        elseif not isValidHost( addr ) then
            return ('opts.failover#%d invalid host format'):format( _ );
        else
            req.failover[#req.failover+1] = {
                scheme = req.scheme,
                host = addr,
                uri = table.concat({
                    req.scheme, '://', addr, req.path
                })
            };
        end
    end
end


local function setOptRedirect( req, redirect )
    if redirect == nil then
        req.redirect = false;
    elseif not typeof.boolean( redirect ) then
        return EINVAL:format( 'opts.redirect', 'boolean' );
    else
        req.redirect = redirect;
    end
end


local function setOptBody( req, body, enctype )
    if body ~= nil then
        if typeof.table( body ) then
            local encoder;

            -- default content-type: text/plain
            if enctype == nil then
                enctype = MIME_FORM_URLENCODED;
            elseif not typeof.string( enctype ) then
                return EINVAL:format( 'opts.enctype', 'string' );
            end

            encoder = BODYENCODER[enctype];
            -- unknown enctype
            if not encoder then
                return ENOSUP:format( 'encoding type', enctype );
            end

            return encoder( req, body );
        -- set string body
        elseif typeof.string( body ) then
            -- default content-type: application/x-www-form-urlencoded
            if enctype == nil then
                enctype = MIME_FORM_URLENCODED;
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


local function setHostHeader( req )
    if req.port ~= 80 and req.port ~= 443 then
        setHeader( req, {
            ['Host'] = req.host .. ':' .. tostring( req.port )
        });
    else
        setHeader( req, {
            ['Host'] = req.host
        });
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
            req.uri = req.uri .. '?' .. req.query;
            req.path = req.path .. '?' .. req.query;
        end
    elseif not typeof.table( query ) then
        return EINVAL:format( 'opts.query', 'table' );
    else
        query = encodeFormURL( query );
        -- append encoded query and hash fragment
        if query then
            if req.query then
                req.uri = req.uri .. '?' .. req.query .. '&' .. query;
                req.path = req.path .. '?' .. req.query .. '&' .. query;
            else
                req.uri = req.uri .. '?' .. query;
                req.path = req.path .. '?' .. query;
            end
        end
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
        return ENOSUP:format( 'protocol', tostring( parsedURI.scheme ) );
    end

    req.scheme = parsedURI.scheme;
    req.host = parsedURI.host;
    req.userinfo = parsedURI.userinfo;
    req.port = parsedURI.port or req.scheme == 'https' and 443 or 80;
    req.path = parsedURI.path;
    req.query = parsedURI.query;
    req.hash = parsedURI.fragment and '#' .. parsedURI.fragment;
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
    local err;

    opts = opts or {};
    if not typeof.table( opts ) then
        return nil, EINVAL:format( 'opts', 'table' );
    end

    err = setURI( req, uri );
    if err then
        return nil, err;
    end

    err = setOptQuery( req, opts.query );
    if err then
        return nil, err;
    end
    err = setOptHeader( req, opts.header );
    if err then
        return nil, err;
    end
    -- append host header
    setHostHeader( req );

    err = setOptBody( req, opts.body, opts.enctype );
    if err then
        return nil, err;
    end

    err = setOptRedirect( req, opts.redirect );
    if err then
        return nil, err;
    end

    err = setOptFailover( req, opts.failover );
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
            local ok, err, req, entity, body;

            -- verify timeout
            if timeout == nil then
                timeout = own.timeout;
            elseif not typeof.uint( timeout ) then
                return nil, EINVAL:format( 'timeout', 'unsigned integer number' );
            end

            -- create request table
            req, err = createRequest( method, uri, opts );
            if err then
                return nil, err;
            end

            -- verify request uri
            if own.verifyURI then
                ok = own.verifyURI({
                    uri = req.uri,
                    host = req.host,
                    userinfo = req.userinfo,
                    port = req.port,
                    path = req.path,
                    query = req.query,
                    hash = req.hash
                });
                -- access denied
                if ok ~= true then
                    return nil, EACCES:format( uri );
                end
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

                -- if non-empty body
                if entity.body and not entity.body:find('^%s*$') then
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
                        if err then
                            err = EDECODE:format( err );
                        else
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
function HttpCli:init( delegate, methods, ucHeader, timeout, verifyURI )
    local own = protected( self );
    local index = getmetatable( self ).__index;

    -- check arguments
    if not typeof.table( delegate ) or not typeof.Function( delegate.request ) then
        return nil, 'delegate should implement request method';
    elseif not typeof.table( methods ) then
        return nil, EINVAL:format( 'methods', 'table' );
    elseif ucHeader ~= nil and not typeof.boolean( ucHeader ) then
        return nil, EINVAL:format( 'ucHeader', 'boolean' );
    elseif timeout ~= nil and not typeof.uint( timeout ) then
        return nil, EINVAL:format( 'timeout', 'unsigned integer number' );
    elseif verifyURI ~= nil and not typeof.Function( verifyURI ) then
        return nil, EINVAL:format( 'verifyURI', 'function' );
    end

    own.delegate = delegate;
    own.methods = methods;
    own.timeout = timeout or DEFAULT_TIMEOUT;
    own.ucHeader = ucHeader;
    own.verifyURI = verifyURI;

    -- remove unused methods
    for _, name in ipairs({ 'init', 'constructor' }) do
        index[name] = nil;
    end

    return self;
end


return HttpCli.exports;
