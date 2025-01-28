#!/bin/bash
#
# This is a very simple HTTP client talking to some server on STDIN/STDOUT
# and passing back the response via FD 3.
# It apparently works with Debian repositories.
#
# It needs some environment variables:
#
# MODE		informational	http or https
# Host		informational	hostname to connect to
# PORT		informational	PORT number to connect to
# URL		mandatory	The URL PATH without the host part
# HEADS		mandatory	all the headers, already correctly preformatted with \r\n in between
#				like with: printf -vHEADS '%s\r\n' "${HEADERS[@]}"
#				(because bash cannot pass arrays into subshells)
# TIMEOUT	default=60	Timeout in seconds
# PARENT	informational	$SOCKLINGER_NR of the parent (or something similar)
#
# This needs some of my own tools:
#
# https://github.com/hilbix/unbuffered
# https://github.com/hilbix/timeout

LONG_TIMEOUT=60
DOWNGRADE="/tmp/APT-CACHER-NG-PROXY.https.tmp"

STDOUT() { local a b; printf -va '[%s] %q' "${PARENT:-${SOCKLINGER_NR:-$PPID}}" "$1"; [ 1 -ge $# ] || printf -vb ' %q' "${@:2}"; printf '%s%s\n' "$a" "$b"; }
STDERR() { STDOUT "$@" >&2; }
OOPS() { STDERR OOPS: "$@"; exit 23; }
x() { "$@"; }
o() { x "$@" || OOPS fail $?: "$@"; }

# Downgrade https location header
# Remember the downgrade to upgrade to HTTPS later again
location()
{
  local dest

  STDERR location "$hd"
  case "$hd" in
  (https://*)	;;
  (*)		return;;
  esac
  hd="${hd#https://}"
  dest="${hd%%/*}"
  hd="http://$hd"
  h="$ht: $hd"

  STDERR DOWNGRADE "$dest"
  # Add the downgrade to the upgrade list
  x fgrep -svf "$DOWNGRADE" >> "$DOWNGRADE" <<< "$dest"
}

get-headers()
{
  HEADS=()
  CURLHEADS=()
  LAYER=normal
  while	read -rt${TIMEOUT:-10} h && h="${h%$'\r'}" && [ -n "$h" ]
  do
	ht="${h%%: *}"
	hd="${h#*: }"
	o test ".$h" = ".$ht: $hd"
	STDERR HEAD: "$ht:" "$hd"
	ht="${ht,,}"
	case "$ht:$hd" in
	(proxy-connection:*)	continue;;
	(connection:*)		continue;;
	(cache-control:*)	continue;;
	(content-length:*)	ContentLength="$hd";;
	(content-type:*)	ContentType="$hd";;
	(transfer-encoding:*chunked*)	LAYER=chunked;;		# JFROG uses this, sigh
	(transfer-encoding:*)	;;
	(location:*)		location;;

# request
#        (accept:*)		Accept="$hd";;
#        (host:*)		Host="$hd";;
#        (user-agent:*)		UserAgent="$hd";;
#        (accept-encoding:*)	;;
#        (range:*)		;;
#        (if-range:*)		;;
#        (referer:*)		;;
#        (accept-language:*)	;;

# response
	(upgrade:*)		continue;;
	(accept-ranges:*)	;;
	(date:*)		;;
	(expires:*)		;;
	(etag:*)		;;
	(content-range:*)	ContentRange="$hd";;
	(last-modified:*)	;;
	(server:*)		;;
	(age:*)			;;
	(via:*)			;;
	(vary:*)		;;
	(permissions-policy:*)	;;
	(referrer-policy:*)	;;
	(x-frame-options:*)	;;
	(x-xss-protection:*)	;;
	(content-disposition:*)	;;

# WTF?
	(x-content-type-options:*)	;;
	(x-clacks-overhead:*)	;;	# GNU Terry Pratchett
	(x-served-by:*)		;;
	(x-cache:*)		;;
	(x-cache-hits:*)	;;
	(x-timer:*)		;;

# JFROG
	(x-jfrog-version:*)	;;
	(x-artifactory-id:*)	;;
	(x-artifactory-node-id:*)	;;
	(x-request-id:*)	;;
	(x-checksum-sha1:*)	;;
	(x-checksum-sha256:*)	;;
	(x-checksum-md5:*)	;;
	(x-artifactory-filename:*)	;;

	(*)			STDERR head "$ht:" "$hd";;
	esac
	CURLHEADS+=(-H "$h")
	HEADS+=("$h")
  done
}

LAYER-normal()
{
  [ -n "$ContentLength" ] || OOPS missing ContentLength
  cnt="$(set -o pipefail; head -c "$ContentLength" | /usr/local/bin/timeout "$LONG_TIMEOUT" - | /usr/local/bin/unbuffered -o3 | wc -c)" || OOPS transfer failed
}

LAYER-chunked()
{
  [ -z "$ContentLength" ] || OOPS chunked with ContentLength
  while	read -rt "$LONG_TIMEOUT" -n30 n || OOPS unexpected EOF at $cnt
	n="${n%$'\r'}"

#	STDERR chunk "$cnt" "$n"
	printf '%s\r\n' "$n"
	[ 0 != "$n" ]
  do
	{ let cnt+=$[16#$n] && head -c "$[16#$n]" | /usr/local/bin/timeout "$LONG_TIMEOUT" -; } || OOPS transfer failed at $cnt

	read -rt "$LONG_TIMEOUT" -n2 t || OOPS unexpected EOF at $cnt
	[ -z "${t%$'\r'}" ] || OOPS unexpected 0x$n chunk at $cnt: "$t"
	printf '\r\n' || OOPS cannot write at $cnt
  done >&3
}

printf 'GET %s HTTP/1.1\r\n' "$URL"
printf 'connection: close\r\n'
printf '%s\r\n' "$HEADS"

read -rt${TIMEOUT:-10} HTTP CODE OK || OOPS no response: "$MODE" "$Host" "$PORT" "$URL"
OK="${OK%$'\r'}"

get-headers
STDERR GOT "$MODE" "$Host" "$PORT" "$URL" "$HTTP" "$CODE" "$OK" "$ContentType" "$ContentLength" "$ContentRange"
#STDERR "${HEADS[@]}"

# Now pass everything to the requestor
# Note that apt-cacher-ng fails if OK is an empty string

printf '%s %s %s\r\n' "$HTTP" "$CODE" "${OK:-OK}" >&3 || OOPS EOF
#printf 'connection: close\r\n'		# ignored by Apt-Cacher-NG?!?
#printf 'proxy-connection: close\r\n'	# ignored by Apt-Cacher-NG?!?
printf '%s\r\n' "${HEADS[@]}" '' >&3 || OOPS EOF

# Use `head` to restrict the number of incoming bytes.
# Because apparently some hosts seem to ignore "connection: close".
cnt=0
"LAYER-$LAYER"

# We probably should store the body above before passing it back
# such that we can test it for correctness before handing it to apt-cacher-ng

STDERR DONE "$cnt"
[ -z "$ContentLength" ] || [ "$cnt" = "$ContentLength" ] || OOPS content got "$cnt" length "$ContentLength" range "$ContentRange"

