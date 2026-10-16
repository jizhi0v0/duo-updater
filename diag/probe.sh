#!/bin/bash
# Loops the CI fixtures' disk-image steps from job start; logs uptime per step.
set +e
DUR=${1:-480}
boot=$(sysctl -n kern.boottime | awk "{print \$4}" | tr -d ,)
up() { echo $(( $(date +%s) - boot )); }
echo "boot=$boot uptime_at_start=$(up)s"; sw_vers; uptime
end=$(( $(date +%s) + DUR ))
log() { # worker step rc output
  printf '%s %s %s %s rc=%s %s\n' "$(date -u +%H:%M:%S)" "$(up)" "$1" "$2" "$3" "$(echo "$4" | grep -v WARNING | tr '\n' '~' | cut -c1-300)" >> "$RUNNER_TEMP/probe-$1.log"
}
worker() {
  w=$1; i=0
  while [ $(date +%s) -lt $end ]; do
    i=$((i+1)); d=$(mktemp -d "$RUNNER_TEMP/w$w-XXXX")
    case $(( (i + w) % 4 )) in
    0) fs="MS-DOS";; 1) fs="APFS";; 2) fs="Case-sensitive APFS";; 3) fs="ExFAT";; esac
    o=$(hdiutil create -size 40m -type SPARSE -fs "$fs" -volname V "$d/a.sparseimage" 2>&1); r=$?; log $w "create-${fs// /_}" $r "$o"
    if [ $r = 0 ]; then
      mkdir "$d/m"; o=$(hdiutil attach -nobrowse -mountpoint "$d/m" "$d/a.sparseimage" 2>&1); r=$?; log $w "attach-${fs// /_}" $r "$o"
      [ $r = 0 ] && { o=$(hdiutil detach "$d/m" 2>&1); r=$?; log $w detach $r "$o"; [ $r = 0 ] || hdiutil detach -force "$d/m" >/dev/null 2>&1; }
    fi
    mkdir -p "$d/src" "$d/m2"; echo x > "$d/src/p"
    o=$(hdiutil makehybrid -quiet -hfs -hfs-volume-name Z -o "$d/h.dmg" "$d/src" 2>&1); r=$?; log $w makehybrid $r "$o"
    o=$(hdiutil attach -nobrowse -readonly -mountpoint "$d/m2" "$d/h.dmg" 2>&1); r=$?; log $w attach-hybrid $r "$o"
    if [ $r = 0 ]; then
      dev=$(echo "$o" | awk '/^\/dev\//{print $1; exit}')
      o=$(diskutil unmount "$d/m2" 2>&1); r=$?; log $w unmount $r "$o"
      o=$(hdiutil detach "$dev" 2>&1); r=$?; log $w detach-dev $r "$o"
    fi
    o=$(hdiutil create -quiet -size 40m -layout GPTSPUD -fs HFS+ -volname V1 "$d/two.dmg" 2>&1); r=$?; log $w create-gpt $r "$o"
    o=$(hdiutil attach -nomount "$d/two.dmg" 2>&1); r=$?; log $w attach-nomount $r "$o"
    dev=$(echo "$o" | awk '/^\/dev\//{print $1; exit}')
    if [ -n "$dev" ]; then
      ro=$(diskutil info -plist "$dev" | plutil -extract WritableMedia raw - 2>&1)
      log $w writable-media $([ "$ro" = true ] && echo 0 || echo 1) "WritableMedia=$ro dev=$dev"
      if [ "$ro" != true ]; then
        { echo "=== $(date -u +%H:%M:%S) read-only $dev $d/two.dmg"; lsof "$d/two.dmg" 2>&1; hdiutil info 2>&1 | grep -B2 -A12 "$d/two.dmg"; } >> "$RUNNER_TEMP/readonly.log"
      fi
      o=$(diskutil partitionDisk "$dev" GPT HFS+ V1 20M HFS+ V2 R 2>&1); r=$?; log $w partitionDisk $r "$o"
      o=$(hdiutil detach "$dev" 2>&1); r=$?; log $w detach-gpt $r "$o"; [ $r = 0 ] || hdiutil detach -force "$dev" >/dev/null 2>&1
    fi
    rm -rf "$d"
  done
}
( while [ $(date +%s) -lt $end ]; do echo "--- uptime $(up)s"; top -l 2 -n 6 -o cpu -stats pid,command,cpu | tail -7; sleep 20; done ) > "$RUNNER_TEMP/cpu.log" 2>&1 &
for w in $(seq 1 ${W:-3}); do worker $w & done
wait
echo "done at uptime $(up)s"
