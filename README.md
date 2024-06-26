> Warning!  This just is a (working!) quick hack.

# apt-cacher-ng-proxy

A shell based proxy for `apt-cacher-ng`.

So the path is `apt =Acquire::http::Proxy=> apt-cacher-ng =/etc/apt-cacher-ng/proxy.conf=> apt-cacher-ng-proxy =socat=> Internet`

> It probably lacks features, like reaching out to another Proxy etc.
>
> There is not much documentation yet on how to extend it.
> Read the source.  I did it as simple as I can.
>
> It should be easy to add missing features yourself, just look into the script [`./GET.sh`](GET.sh)

It upgrades `http` requests to `https` for certain destinations:

- apache.jfrog.io
- developer.download.nvidia.com
- (The list can be extended in `GET.sh`)

So no need to rewrite `https://` to `http:///HTTPS/`,
instead just replace `https:` with `http:` (hence remove the `s`).

> Not using `https` for Debian repositories still is secure
> as long as you use signatures.  Even Ubuntu downgraded from `https` to `http`


## Usage

Install following of my tools:

- <https://github.com/hilbix/unbuffered>
- <https://github.com/hilbix/timeout>

And if you want to use my tools for connection and autostart:

- <https://github.com/hilbix/socklinger>
- <https://github.com/hilbix/ptybuffer>
- <https://github.com/hilbix/watcher>
  - for `watcher.py /var/tmp/autostart/$USER/*.sock`

Then:

	git clone https://github.com/hilbix/apt-cacher-ng-proxy.git
	ln -s --relative apt-cacher-ng-proxy/autostart ~/autostart/proxy

Or without the `autostart.sh` script of `ptybuffer`:

	cd apt-cacher-ng-proxy
	socklinger -n-5 127.0.0.2:8080 ./proxy.sh

> In case you do not want to use `socklinger`:
>
>     socat tcp-listen:8080,bind=127.0.0.2,reuseaddr,fork exec:./proxy.sh
>
> is similar, however `socklinger` limits the number of parallel connects to 5 (see `-n`).
> You can use `inetd` or `xinetd` of course, too, to run `./proxy.sh`

To configure `apt-cacher-ng` to use the proxy on `127.0.0.2:8080`:

Create file `/etc/apt-cacher-ng/proxy.conf` with following contents:

	AllowUserPorts: 80 443
	Proxy: http://127.0.0.2:8080
	NoSSLChecks: 0

## TODO

The downloaded files should be verified for correctness before they are handed back to `apt-cacher-ng`,
because if `apt-cacher-ng` ever sees a single byte corruption, you will have a very hard time to get rid of this wrong byte.

> The only way I found out was to completely wipe directory `/var/cache/apt-cacher-ng` and restart `apt-cacher-ng` afterwards.
> All other ways trying to handle it with the `apt-cacher-ng` web frontend failed for me for unknown reason.
>
> YMMV if you grok it better than me.

There should be a standard way to talk to a `http(s)` type proxy in `proxy.sh` (look for `socat`).


## FAQ

WTF why?

- Because `apt-cacher-ng` suddenly refused to download `https` URLs from apache.jfrog.io
- Because I was unable to configure `apt-cacher-ng` to properly use `tinyproxy`
- Because `apt-cacher-ng` is not able to use HTTP/1.0 proxies which close the connection on each request

CONNECT?

- Not supported by purpose .. yet

License?

- This Works is placed under the terms of the Copyright Less License,  
  see file COPYRIGHT.CLL.  USE AT OWN RISK, ABSOLUTELY NO WARRANTY.
- Read: Free as free beer, free speech and free baby.

