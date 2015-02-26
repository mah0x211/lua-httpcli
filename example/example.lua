local inspect = require('util').inspect;
local HttpCli = require('httpcli.luasocket');

local function verifyURI( req )
    print( inspect( req ) );
    return true;
end

local myDefaultTimeout = 60; -- seconds
local uppercaseHeaderName = true; -- convert header names to uppercase
local cli, err = HttpCli.new( uppercaseHeaderName, myDefaultTimeout, verifyURI );

if err then
    print( err );
else
    local timeoutForThisRequest = 30;
    local res;
    
    res, err = cli:get( 'http://user:pswd@example.com/', { -- also, can be pass the https url
        -- query    = <table>,
        -- header   = <table>,
        -- body     = <string or table>,
        -- enctype  = <encoding-type string>,
        --            supported enctype:
        --              * 'application/json'
        --              * 'application/x-www-form-urlencoded'
        -- failover = <failover-address table>
        --            format: [scheme://]host[:port]
        --            scheme: http or https
        --            port: 0 - 65535
        --            e.g.: {
        --              'https://localhost',
        --              this format will inherit a scheme of url argument
        --              '127.0.0.1:8080'
        --            }
    }, timeoutForThisRequest );

    -- response table has the following fields;
    -- status: number (HTTP status code)
    -- header: <table or nil>
    -- body  : <string or table or nil>
    --
    -- NOTE-1: header and body will be nil if status is 408 408 Request Timeout
    -- NOTE-2: if content-type header is a 'application/json' then decode a 
    --         body strings on internally, and set an error strings to second 
    --         returns value on failure.
    print( inspect({ res, err }) );
end
