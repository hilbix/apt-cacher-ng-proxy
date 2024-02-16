> Warning!  This just is a (working!) quick hack.

# apt-cacher-ng-proxy

A shell based proxy for `apt-cacher-ng`.

> It lacks many features, like reaching out to another Proxy etc.
> And there is no documentation.  Read the source.  I did it as simple as I can.
>
> However it should be easy to add missing features yourself, just look into the script `./GET.sh`

It upgrades `http` requests to `https` for certain destinations:

- apache.jfrog.io
- developer.download.nvidia.com

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

Or without `ptybuffer`:

	cd apt-cacher-ng-proxy
	socklinger -n-5 127.0.0.2:8080 ./proxy.sh

To configure `apt-cacher-ng` to use the proxy port:

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


## FAQ

WTF why?

- Because `apt-cacher-ng` suddenly refused to download `https` URLs from apache.jfrog.io
- Because I was unable to configure `apt-cacher-ng` to properly use `tinyproxy`
- Because `apt-cacher-ng` is not able to use HTTP/1.0 proxies which close the connection on each request

License?

- This Works is placed under the terms of the Copyright Less License,  
  see file COPYRIGHT.CLL.  USE AT OWN RISK, ABSOLUTELY NO WARRANTY.
- Read: Free as free beer, free speech and free baby.

