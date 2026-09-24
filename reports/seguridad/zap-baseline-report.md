# ZAP Scanning Report

ZAP by [Checkmarx](https://checkmarx.com/).


## Summary of Alerts

| Risk Level | Number of Alerts |
| --- | --- |
| High | 0 |
| Medium | 0 |
| Low | 3 |
| Informational | 3 |




## Insights

| Level | Reason | Site | Description | Statistic |
| --- | --- | --- | --- | --- |
| Info | Informational | https://bapqxqydqzopbpjrpnna.supabase.co | Percentage of responses with status code 4xx | 100 % |
| Info | Informational | https://bapqxqydqzopbpjrpnna.supabase.co | Percentage of endpoints with content type application/json | 100 % |
| Info | Informational | https://bapqxqydqzopbpjrpnna.supabase.co | Percentage of endpoints with method GET | 100 % |
| Info | Informational | https://bapqxqydqzopbpjrpnna.supabase.co | Count of total endpoints | 4    |







## Alerts

| Name | Risk Level | Number of Instances |
| --- | --- | --- |
| Cookie with SameSite Attribute None | Low | 3 |
| Cookie without SameSite Attribute | Low | 1 |
| Timestamp Disclosure - Unix | Low | 4 |
| Loosely Scoped Cookie | Informational | 3 |
| Non-Storable Content | Informational | 5 |
| Session Management Response Identified | Informational | 3 |




## Alert Detail



### [ Cookie with SameSite Attribute None ](https://www.zaproxy.org/docs/alerts/10054/)



##### Low (Medium)

### Description

A cookie has been set with its SameSite attribute set to "none", which means that the cookie can be sent as a result of a 'cross-site' request. The SameSite attribute is an effective counter measure to cross-site request forgery, cross-site script inclusion, and timing attacks.

* URL: https://bapqxqydqzopbpjrpnna.supabase.co
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co`
  * Method: `GET`
  * Parameter: `__cf_bm`
  * Attack: ``
  * Evidence: `set-cookie: __cf_bm`
  * Other Info: ``
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/`
  * Method: `GET`
  * Parameter: `__cf_bm`
  * Attack: ``
  * Evidence: `set-cookie: __cf_bm`
  * Other Info: ``
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/favicon.ico
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/favicon.ico`
  * Method: `GET`
  * Parameter: `__cf_bm`
  * Attack: ``
  * Evidence: `set-cookie: __cf_bm`
  * Other Info: ``


Instances: 3

### Solution

Ensure that the SameSite attribute is set to either 'lax' or ideally 'strict' for all cookies.

### Reference


* [ https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-cookie-same-site ](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-cookie-same-site)


#### CWE Id: [ 1275 ](https://cwe.mitre.org/data/definitions/1275.html)


#### WASC Id: 13

#### Source ID: 3

### [ Cookie without SameSite Attribute ](https://www.zaproxy.org/docs/alerts/10054/)



##### Low (Medium)

### Description

A cookie has been set without the SameSite attribute, which means that the cookie can be sent as a result of a 'cross-site' request. The SameSite attribute is an effective counter measure to cross-site request forgery, cross-site script inclusion, and timing attacks.

* URL: https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt`
  * Method: `GET`
  * Parameter: `__cf_bm`
  * Attack: ``
  * Evidence: `set-cookie: __cf_bm`
  * Other Info: ``


Instances: 1

### Solution

Ensure that the SameSite attribute is set to either 'lax' or ideally 'strict' for all cookies.

### Reference


* [ https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-cookie-same-site ](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-cookie-same-site)


#### CWE Id: [ 1275 ](https://cwe.mitre.org/data/definitions/1275.html)


#### WASC Id: 13

#### Source ID: 3

### [ Timestamp Disclosure - Unix ](https://www.zaproxy.org/docs/alerts/10096/)



##### Low (Low)

### Description

A timestamp was disclosed by the application/web server. - Unix

* URL: https://bapqxqydqzopbpjrpnna.supabase.co
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co`
  * Method: `GET`
  * Parameter: `set-cookie`
  * Attack: ``
  * Evidence: `1790230200`
  * Other Info: `1790230200, which evaluates to: 2026-09-24 06:10:00.`
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/`
  * Method: `GET`
  * Parameter: `set-cookie`
  * Attack: ``
  * Evidence: `1790230205`
  * Other Info: `1790230205, which evaluates to: 2026-09-24 06:10:05.`
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/favicon.ico
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/favicon.ico`
  * Method: `GET`
  * Parameter: `set-cookie`
  * Attack: ``
  * Evidence: `1790230205`
  * Other Info: `1790230205, which evaluates to: 2026-09-24 06:10:05.`
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt`
  * Method: `GET`
  * Parameter: `set-cookie`
  * Attack: ``
  * Evidence: `1790230200`
  * Other Info: `1790230200, which evaluates to: 2026-09-24 06:10:00.`


Instances: 4

### Solution

Manually confirm that the timestamp data is not sensitive, and that the data cannot be aggregated to disclose exploitable patterns.

### Reference


* [ https://cwe.mitre.org/data/definitions/200.html ](https://cwe.mitre.org/data/definitions/200.html)


#### CWE Id: [ 497 ](https://cwe.mitre.org/data/definitions/497.html)


#### WASC Id: 13

#### Source ID: 3

### [ Loosely Scoped Cookie ](https://www.zaproxy.org/docs/alerts/90033/)



##### Informational (Low)

### Description

Cookies can be scoped by domain or path. This check is only concerned with domain scope.The domain scope applied to a cookie determines which domains can access it. For example, a cookie can be scoped strictly to a subdomain e.g. www.nottrusted.com, or loosely scoped to a parent domain e.g. nottrusted.com. In the latter case, any subdomain of nottrusted.com can access the cookie. Loosely scoped cookies are common in mega-applications like google.com and live.com. Cookies set from a subdomain like app.foo.bar are transmitted only to that domain by the browser. However, cookies scoped to a parent-level domain may be transmitted to the parent, or any subdomain of the parent.

* URL: https://bapqxqydqzopbpjrpnna.supabase.co/
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `Domain=supabase.co`
  * Other Info: `The origin domain used for comparison was:
bapqxqydqzopbpjrpnna.supabase.co
Cookie name: __cf_bm
`
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/favicon.ico
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/favicon.ico`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `Domain=supabase.co`
  * Other Info: `The origin domain used for comparison was:
bapqxqydqzopbpjrpnna.supabase.co
Cookie name: __cf_bm
`
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `Domain=supabase.co`
  * Other Info: `The origin domain used for comparison was:
bapqxqydqzopbpjrpnna.supabase.co
Cookie name: __cf_bm
`


Instances: 3

### Solution

Always scope cookies to a FQDN (Fully Qualified Domain Name).

### Reference


* [ https://datatracker.ietf.org/doc/html/rfc6265#section-4.1 ](https://datatracker.ietf.org/doc/html/rfc6265#section-4.1)
* [ https://owasp.org/www-project-web-security-testing-guide/v41/4-Web_Application_Security_Testing/06-Session_Management_Testing/02-Testing_for_Cookies_Attributes.html ](https://owasp.org/www-project-web-security-testing-guide/v41/4-Web_Application_Security_Testing/06-Session_Management_Testing/02-Testing_for_Cookies_Attributes.html)
* [ https://code.google.com/archive/p/browsersec/wikis/Part2.wiki ](https://code.google.com/archive/p/browsersec/wikis/Part2.wiki)


#### CWE Id: [ 565 ](https://cwe.mitre.org/data/definitions/565.html)


#### WASC Id: 15

#### Source ID: 3

### [ Non-Storable Content ](https://www.zaproxy.org/docs/alerts/10049/)



##### Informational (Medium)

### Description

The response contents are not storable by caching components such as proxy servers. If the response does not contain sensitive, personal or user-specific information, it may benefit from being stored and cached, to improve performance.

* URL: https://bapqxqydqzopbpjrpnna.supabase.co
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `no-store`
  * Other Info: ``
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `no-store`
  * Other Info: ``
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/favicon.ico
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/favicon.ico`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `no-store`
  * Other Info: ``
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `no-store`
  * Other Info: ``
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/sitemap.xml
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/sitemap.xml`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `no-store`
  * Other Info: ``


Instances: 5

### Solution

The content may be marked as storable by ensuring that the following conditions are satisfied:
The request method must be understood by the cache and defined as being cacheable ("GET", "HEAD", and "POST" are currently defined as cacheable)
The response status code must be understood by the cache (one of the 1XX, 2XX, 3XX, 4XX, or 5XX response classes are generally understood)
The "no-store" cache directive must not appear in the request or response header fields
For caching by "shared" caches such as "proxy" caches, the "private" response directive must not appear in the response
For caching by "shared" caches such as "proxy" caches, the "Authorization" header field must not appear in the request, unless the response explicitly allows it (using one of the "must-revalidate", "public", or "s-maxage" Cache-Control response directives)
In addition to the conditions above, at least one of the following conditions must also be satisfied by the response:
It must contain an "Expires" header field
It must contain a "max-age" response directive
For "shared" caches such as "proxy" caches, it must contain a "s-maxage" response directive
It must contain a "Cache Control Extension" that allows it to be cached
It must have a status code that is defined as cacheable by default (200, 203, 204, 206, 300, 301, 404, 405, 410, 414, 501).

### Reference


* [ https://datatracker.ietf.org/doc/html/rfc7234 ](https://datatracker.ietf.org/doc/html/rfc7234)
* [ https://datatracker.ietf.org/doc/html/rfc7231 ](https://datatracker.ietf.org/doc/html/rfc7231)
* [ https://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html ](https://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html)


#### CWE Id: [ 524 ](https://cwe.mitre.org/data/definitions/524.html)


#### WASC Id: 13

#### Source ID: 3

### [ Session Management Response Identified ](https://www.zaproxy.org/docs/alerts/10112/)



##### Informational (High)

### Description

The given response has been identified as containing a session management token. The 'Other Info' field contains a set of header tokens that can be used in the Header Based Session Management Method. If the request is in a context which has a Session Management Method set to "Auto-Detect" then this rule will change the session management to use the tokens identified.

* URL: https://bapqxqydqzopbpjrpnna.supabase.co
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co`
  * Method: `GET`
  * Parameter: `__cf_bm`
  * Attack: ``
  * Evidence: `__cf_bm`
  * Other Info: `cookie:__cf_bm`
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt`
  * Method: `GET`
  * Parameter: `__cf_bm`
  * Attack: ``
  * Evidence: `__cf_bm`
  * Other Info: `cookie:__cf_bm`
* URL: https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt
  * Node Name: `https://bapqxqydqzopbpjrpnna.supabase.co/robots.txt`
  * Method: `GET`
  * Parameter: `__cf_bm`
  * Attack: ``
  * Evidence: `__cf_bm`
  * Other Info: `cookie:__cf_bm`


Instances: 3

### Solution

This is an informational alert rather than a vulnerability and so there is nothing to fix.

### Reference


* [ https://www.zaproxy.org/docs/desktop/addons/authentication-helper/session-mgmt-id/ ](https://www.zaproxy.org/docs/desktop/addons/authentication-helper/session-mgmt-id/)



#### Source ID: 3


