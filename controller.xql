xquery version "3.0";

declare namespace dbk="http://docbook.org/ns/docbook";

import module namespace login="http://exist-db.org/xquery/login" at "resource:org/exist/xquery/modules/persistentlogin/login.xql";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "modules/config.xqm";
import module namespace pages="http://www.tei-c.org/tei-simple/pages" at "modules/lib/pages.xql";
import module namespace tpu="http://www.tei-c.org/tei-publisher/util" at "modules/lib/util.xql";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

declare variable $logout := request:get-parameter("logout", ());
declare variable $login := request:get-parameter("user", ());

declare variable $allowOrigin := local:allowOriginDynamic(request:get-header("Origin"));

declare function local:allowOriginDynamic($origin as xs:string?) {
    let $origin := replace($origin, "^(\w+://[^/]+).*$", "$1")
    return
        if (local:checkOriginWhitelist($config:origin-whitelist, $origin)) then
            $origin
        else
            "*"
};

declare function local:checkOriginWhitelist($regexes, $origin) {
    if (empty($regexes)) then
        false()
    else if (matches($origin, head($regexes))) then
        true()
    else
        local:checkOriginWhitelist(tail($regexes), $origin)
};

declare function local:get-template($doc as xs:string) {
    let $template := request:get-parameter("template", ())
    return
        if ($template) then
            $template
        else
            let $document := pages:get-document($doc)
            where exists($document)
            let $config := tpu:parse-pi($document, request:get-parameter("view", ()))
            return
                $config?template
};


if ($exist:path eq '') then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{request:get-uri()}/"/>
    </dispatch>

else if ($exist:path eq "/") then
    (: forward root path to index.xql :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="index.html"/>
    </dispatch>

(:
 : Login a user via AJAX. Just returns a 401 if login fails.
 :)
else if ($exist:resource eq 'login') then (
    let $loggedIn := login:set-user($config:login-domain, (), false())
    let $user := request:get-attribute($config:login-domain || ".user")
    return (
        util:declare-option("exist:serialize", "method=json media-type=application/json"),
        response:set-header("Access-Control-Allow-Origin", $allowOrigin),
        if ($allowOrigin) then response:set-header("Access-Control-Allow-Credentials", "true") else (),
        try {
            <status xmlns:json="http://www.json.org">
                <user>{$user}</user>
                {
                    if ($user) then (
                        sm:get-user-groups($user) ! <groups json:array="true">{.}</groups>,
                        <dba>{sm:is-dba($user)}</dba>
                    ) else
                        ()
                }
            </status>
        } catch * {
            response:set-status-code(401),
            <status>{$err:description}</status>
        }
    )

) else if (contains($exist:path, "/$shared/")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="/shared-resources/{substring-after($exist:path, '/$shared/')}"/>
    </dispatch>

else if (contains($exist:path, "/node_modules/")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/node_modules/{substring-after($exist:path, '/node_modules/')}"/>
    </dispatch>

else if (matches($exist:path, "^.*/(resources|transform)/.*$")) then
    let $dir := replace($exist:path, "^.*/(resources|transform)/.*$", "$1")
    return
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
            <forward url="{$exist:controller}/{$dir}/{substring-after($exist:path, '/' || $dir || '/')}">
            {
                if ($dir = "transform") then
                    <set-header name="Cache-Control" value="no-cache"/>
                else (
                    <set-header name="Access-Control-Allow-Origin" value="{$allowOrigin}"/>,
                    if ($allowOrigin = "*") then () else <set-header name="Access-Control-Allow-Credentials" value="true"/>
                )
            }
            </forward>
        </dispatch>

else if (contains($exist:path, "/images/")) then
     <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/resources/images/{substring-after($exist:path, '/images/')}"/>
    </dispatch>

else if (ends-with($exist:resource, ".xql")) then (
    login:set-user($config:login-domain, (), false()),
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        {
            if (contains($exist:path, "/modules")) then
                <forward url="{$exist:controller}/modules/{substring-after($exist:path, '/modules/')}">
                    <set-header name="Access-Control-Allow-Origin" value="{$allowOrigin}"/>
                    { if ($allowOrigin = "*") then () else <set-header name="Access-Control-Allow-Credentials" value="true"/> }
                </forward>
            else
                <forward url="{$exist:controller}{$exist:path}">
                    <set-header name="Access-Control-Allow-Origin" value="{$allowOrigin}"/>
                    { if ($allowOrigin = "*") then () else <set-header name="Access-Control-Allow-Credentials" value="true"/> }
                </forward>
        }
        <cache-control cache="no"/>
    </dispatch>

)

else if ($logout or $login) then (
    login:set-user($config:login-domain, (), false()),
    (: redirect successful login attempts to the original page, but prevent redirection to non-local websites:)
    let $referer := request:get-header("Referer")
    let $this-servers-scheme-and-domain := request:get-scheme() || "://" || request:get-server-name()
    return
        if (starts-with($referer, $this-servers-scheme-and-domain)) then
            <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
                <redirect url="{request:get-header("Referer")}"/>
            </dispatch>
        else
            <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
                <redirect url="{replace(request:get-uri(), "^(.*)\?", "$1")}"/>
            </dispatch>

) else if (matches($exist:resource, "\.(png|jpg|jpeg|gif|tif|tiff|txt)$", "s")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
       <forward url="{$exist:controller}/data/{$exist:path}"/>
   </dispatch>

else if (starts-with($exist:path, "/api/dts")) then
    let $endpoint := tokenize(substring-after($exist:path, "/api/dts/"), "/")[last()]
    return
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
           <forward url="{$exist:controller}/modules/lib/dts.xql">
               <add-parameter name="endpoint" value="{$endpoint}"/>
           </forward>
       </dispatch>

else if (ends-with($exist:resource, ".html")) then (
    login:set-user($config:login-domain, (), false()),
    let $resource :=
        if (contains($exist:path, "/templates/")) then
            "templates/" || $exist:resource
        else
            $exist:resource
    return
        (: the html page is run through view.xql to expand templates :)
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
            <forward url="{$exist:controller}/{$resource}"/>
            <view>
                <forward url="{$exist:controller}/modules/view.xql">
                    <set-header name="Access-Control-Allow-Origin" value="{$allowOrigin}"/>
                    { if ($allowOrigin = "*") then () else <set-header name="Access-Control-Allow-Credentials" value="true"/> }
                    <set-header name="Access-Control-Expose-Headers" value="pb-start, pb-total"/>
                {
                    if ($exist:resource = ("search-results.html", "documents.html", "index.html")) then
                        <set-header name="Cache-Control" value="no-cache"/>
                    else
                        ()
                }
                </forward>
            </view>
            {
                if ($exist:resource = "index.html") then
            		<error-handler>
            			<forward url="{$exist:controller}/error-page.html" method="get"/>
            			<forward url="{$exist:controller}/modules/view.xql"/>
            		</error-handler>
                else
                    ()
            }
        </dispatch>

) else if (starts-with($exist:path, "/collection/")) then (
    login:set-user($config:login-domain, (), false()),
    let $path := substring-after($exist:path, "/collection/")
    let $templatePath := $config:data-root || "/" || $path || "collection.html"
    let $templateAvail := doc-available($templatePath) or util:binary-doc-available($templatePath)
    let $template := 
        if ($templateAvail) then 
            $templatePath
        else
            $config:app-root || "/templates/documents.html"
    return
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
            <forward url="{$exist:controller}/modules/view.xql">
                <add-parameter name="template" value="{$template}"/>
                <add-parameter name="root" value="{$path}"/>
                <set-header name="Cache-Control" value="no-cache"/>
                <set-header name="Access-Control-Allow-Origin" value="{$allowOrigin}"/>
                { if ($allowOrigin = "*") then () else <set-header name="Access-Control-Allow-Credentials" value="true"/> }
                <set-header name="Access-Control-Expose-Headers" value="pb-start, pb-total"/>
            </forward>
            <error-handler>
                <forward url="{$exist:controller}/error-page.html" method="get"/>
                <forward url="{$exist:controller}/modules/view.xql"/>
            </error-handler>
        </dispatch>

) else (
    login:set-user($config:login-domain, (), false()),
    (: let $id := replace(xmldb:decode($exist:resource), "^(.*)\..*$", "$1") :)
    let $id := xmldb:decode($exist:resource)
    let $path := replace($exist:path, "^/(.*?)[^/]*$", "$1")
    (: let $path := substring-before(substring-after($exist:path, "/works/"), $exist:resource) :)
    let $mode := request:get-parameter("mode", ())
    let $html :=
        if ($exist:resource = "") then
            "index.html"
        else if ($exist:resource = ("search.html", "toc.html")) then
            $exist:resource
        else
            ()
    return
        if (ends-with($exist:resource, ".epub")) then
            <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
                <forward url="{$exist:controller}/modules/lib/get-epub.xql">
                    <add-parameter name="id" value="{$path}{$id}"/>
                </forward>
                <error-handler>
                    <forward url="{$exist:controller}/error-page.html" method="get"/>
                    <forward url="{$exist:controller}/modules/view.xql"/>
                </error-handler>
            </dispatch>
        else if (ends-with($exist:resource, ".tex")) then
            <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
                <forward url="{$exist:controller}/modules/lib/latex.xql">
                    <add-parameter name="id" value="{$path}{$id}"/>
                </forward>
                <error-handler>
                    <forward url="{$exist:controller}/error-page.html" method="get"/>
                    <forward url="{$exist:controller}/modules/view.xql"/>
                </error-handler>
            </dispatch>
        else if (ends-with($exist:resource, ".pdf")) then
            <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
                <forward url="{$exist:controller}/modules/lib/pdf.xql">
                    <add-parameter name="doc" value="{$path}{$id}"/>
                </forward>
                <error-handler>
                    <forward url="{$exist:controller}/error-page.html" method="get"/>
                    <forward url="{$exist:controller}/modules/view.xql"/>
                </error-handler>
            </dispatch>
        else if ($mode = "plain") then
            <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
                <forward url="{$exist:controller}/modules/lib/transform.xql">
                    <add-parameter name="doc" value="{$path}{$id}"/>
                </forward>
                <error-handler>
                    <forward url="{$exist:controller}/error-page.html" method="get"/>
                    <forward url="{$exist:controller}/modules/view.xql"/>
                </error-handler>
            </dispatch>
        else if (matches($exist:resource, ".xml$", "i")) then
            let $docPath := $path || $id
            let $template :=
                if ($html) then $html else (local:get-template($docPath), $config:default-template)[1]
            return
                <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
                    <forward url="{$exist:controller}/templates/pages/{$template}"></forward>
                    <view>
                        <forward url="{$exist:controller}/modules/view.xql">
                        {
                            if (request:get-parameter("template", ())) then
                                ()
                            else
                                <add-parameter name="template" value="{$template}"/>
                        }
                        {
                            if ($exist:resource != "toc.html") then
                                <add-parameter name="doc" value="{$path}{$id}"/>
                            else
                                ()
                        }
                            <set-header name="Cache-Control" value="no-cache"/>
                        </forward>
                    </view>
                    <error-handler>
                        <forward url="{$exist:controller}/error-page.html" method="get"/>
                        <forward url="{$exist:controller}/modules/view.xql"/>
                    </error-handler>
                </dispatch>
        else
            <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
                <cache-control cache="yes"/>
            </dispatch>

)