(:~
 : This is the main XQuery which will (by default) be called by controller.xql
 : to process any URI ending with ".html". It receives the HTML from
 : the controller and passes it to the templating system.
 :)
xquery version "3.0";

import module namespace templates="http://exist-db.org/xquery/templates";

(:
 : The following modules provide functions which will be called by the
 : templating.
 :)
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace browse="http://www.tei-c.org/tei-simple/templates" at "lib/browse.xql";
import module namespace pages="http://www.tei-c.org/tei-simple/pages" at "lib/pages.xql";
import module namespace search="http://www.tei-c.org/tei-simple/search" at "lib/search.xql";
import module namespace app="teipublisher.com/app" at "app.xql";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";

declare option output:method "html5";
declare option output:media-type "text/html";

declare function local:report-error($data) {
    util:declare-option("exist:output", "method=xml"),
    try {
        let $error := parse-xml($data)
        return
            $error
    } catch * {
        $data
    }
};

let $config := map {
    $templates:CONFIG_APP_ROOT : $config:app-root,
    $templates:CONFIG_STOP_ON_ERROR : true()
}
(:
 : We have to provide a lookup function to templates:apply to help it
 : find functions in the imported application modules. The templates
 : module cannot see the application modules, but the inline function
 : below does see them.
 :)
let $lookup := function($functionName as xs:string, $arity as xs:int) {
    try {
        function-lookup(xs:QName($functionName), $arity)
    } catch * {
        ()
    }
}
(:
 : The HTML is passed in the request from the controller.
 : Run it through the templating system and return the result.
 :)
let $error := request:get-attribute("org.exist.forward.error")
return
    if ($error) then
        local:report-error($error)
    else
        let $template := request:get-parameter('template', ())
        let $content :=
            if ($template and doc-available($template)) then
                doc($template)
            else
                request:get-data()
        return
            templates:apply($content, $lookup, (), $config)