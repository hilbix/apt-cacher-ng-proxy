#!/bin/bash
#
# Run this on a port and configure
#	apt-cacher-ng
# to use it for example in file
#	/etc/apt-cacher-ng/proxy.conf
# add:
#	AllowUserPorts: 80 443
#	Proxy: http://127.0.0.1:8080
#	NoSSLChecks: 0

TIMEOUT=10
DOWNGRADE=/tmp/APT-CACHER-NG-PROXY.https.tmp
UNKNOWN=/tmp/APT-CACHER-NG-PROXY.host.unknown.tmp

STDOUT() { local a b; printf -va '[%s] %q' "$SOCKLINGER_NR" "$1"; [ 1 -ge $# ] || printf -vb ' %q' "${@:2}"; printf '%s%s\n' "$a" "$b"; }
STDERR() { local e=$?; STDOUT "$@" >&2; return $e; }
FAIL()
{
  printf -v fail ' %q' "$@"
  printf 'HTTP/1.1 %03d FAIL\r\n' "$1"
  printf 'Connection: close\r\n'
  printf 'Content-Length: %d\r\n' $[8 + ${#fail}]
  printf 'Content-Type: text/plain\r\n'
  printf '\r\n'
  printf 'FAIL:%s\r\n' "$fail"
}
OOPS() { STDERR OOPS: "$@"; FAIL 500 "$@"; exit 23; }
x() { "$@"; }
o() { x "$@" || OOPS fail $?: "$@"; }

get-headers()
{
  HEADS=()
  CURLHEADS=()
  while	read -rt$TIMEOUT h && h="${h%$'\r'}" && [ -n "$h" ]
  do
        ht="${h%%: *}"
        hd="${h#*: }"
        o test ".$h" = ".$ht: $hd"
        ht="${ht,,}"
        case "$ht:$hd" in
        (proxy-connection:*)	continue;;
        (connection:*)		continue;;
        (cache-control:*)	continue;;
        (content-length:*)	ContentLength="$hd";;
        (content-type:*)	ContentType="$hd";;

        (accept:*)		Accept="$hd";;
        (host:*)		Host="$hd";;
        (user-agent:*)		UserAgent="$hd";;
        (accept-encoding:*)	;;
        (range:*)		;;
        (if-range:*)		;;
        (referer:*)		;;
        (accept-language:*)	;;

        (*)			STDERR head "$ht:" "$hd";;
        esac
        CURLHEADS+=(-H "$h")
        HEADS+=("$h")
  done
}

GET()
{
  local STDPORT SOCATMODE

  printf -vh '%s\r\n' "${HEADS[@]}"
  case "$MODE" in
  (http)	STDPORT=80;  SOCATMODE=tcp;;
  (https)	STDPORT=443; SOCATMODE=openssl;;
  esac
  MODE="$MODE" Host="$Host" PORT="${PORT:-$STDPORT}" URL="$URL" HEADS="$h" PARENT="$SOCKLINGER_NR" TIMEOUT="$TIMEOUT" o socat "$SOCATMODE:$Host:${PORT:-$STDPORT}" "exec:${0%/*}/GET.sh" 3>&1 >&2
}

getter()
{
  case "$URL" in
  (http://$Host/*)	URL="${URL#http://$Host}";;
  (*)			OOPS Host "$Host" does not match "$URL";;
  esac

  MODE=http
  case "$Host" in
# list of known hostnames to not log
# Debian
  (deb.debian.org)		;;
  (cdn-fastly.deb.debian.org)	;;

# Ubuntu
  (ppa.launchpadcontent.net)	;;
  (ppa.launchpad.net)		;;
  (security.ubuntu.com)		;;
  (ftp.tu-ilmenau.de)		;;
  (ftp.hosteurope.de)		;;
  (ddebs.ubuntu.com)		;;

# Raspbian
  (archive.raspberrypi.org)	;;

# Microsoft et al
  (packages.microsoft.com)	;;
  (dl.google.com)		;;

# list of hostnames to treat special
  (apache.jfrog.io)			MODE=https;;
  (developer.download.nvidia.com)	MODE=https;;

  (*)	fgrep -qsx "$Host" "$DOWNGRADE" && MODE=https ||	# Hack: Upgrade downgraded Location requests, see GET.sh
        STDERR Host "$Host" see "$UNKNOWN" ||			# Report unknown hosts
        fgrep -svf "$UNKNOWN" >> "$UNKNOWN" <<< "$Host"		# Record unknwon hosts
        ;;
  esac

  PORT=
  # Following heuristic probably fails for IPv6 IP based hosts:
  case "$Host" in
  (*:*)		PORT="${Host##*:}"; Host="${Host%:*}";;
  esac

  GET
}

# Use
#	DEBUG GET
# above to catch evidence.
# But you probably never need it:
DEBUG()
{
  local ret FILE=/tmp/PROXY-DEBUG.$$

  {
  printf '================\n'
  printf ' %q\n' "$MODE" "$Host" "$PORT" "$URL" 
  printf ' %s\n' "${HEADS[@]}"
  printf '================\n'
  } >> "$FILE"
  set -o pipefail
  "$@" | tee -a "$FILE"
  ret=$?
  printf '==== %q ====\n' "$ret" >> "$FILE"
  return $ret;
}

# This shitty Apt-Cacher-NG does not work properly with
# connection:close 
have=false
while	read -rt$TIMEOUT GET URL HTTP
do
        HTTP="${HTTP%$'\r'}"
        STDERR "$GET" "$URL" "$HTTP"
        get-headers
        have=:

        # We do not support CONNECT for a good reason:
        # At my side apt-cacher-ng fails to connect to SSL based hosts (IDKW)
        case "$GET" in
        (GET)	getter "$URL";;
        (*)	OOPS 503 wrong or unknown method: "$GET";;
        esac
done

$have || OOPS no input or timeout

