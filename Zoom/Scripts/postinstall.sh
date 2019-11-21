#!/bin/sh

# Dirty script built in the Zoom installer
# Barely updated by @ygini to act as a munki postinstall script
# Also updated by @bp88 and @homebysix for Catalina compatibility
# All UI related things have been removed
# But all other things are kept, even code that will never run.

# Bail out early if the target disk is not the startup disk.
if [ "$3" != "/" ]; then
    echo "[ERROR] Target disk is not the startup disk."
    exit 1
fi

app_path="/Applications/zoom.us.app"

kext_file="/System/Library/Extensions/ZoomAudioDevice.kext"
src_kext_file="$app_path/Contents/Plugins/ZoomAudioDevice.kext"
src_sig_kext_file="$app_path/Contents/Plugins/OS109/ZoomAudioDevice.kext"
LOG_PATH="/Library/Logs/zoomusinstall.log"
app_path="/Applications/zoom.us.app"

ver="$(/usr/bin/sw_vers -productVersion)"
majorver="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d "." -f 1)"
minorver="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d "." -f 2)"

echo "get version: $ver, $majorver, $minorver" >> "$LOG_PATH"

login_user="$(/usr/bin/stat -f '%Su' /dev/console)"
echo "user: $login_user" >> "$LOG_PATH"

need_unload=0
need_update=0
need_load=0
need_update_sig=0
use_sig_file=0

#################################
# use audio device plugin
AudioPluginPath="/Library/Audio/Plug-Ins/HAL"
audioPluginfile="$app_path/Contents/Plugins/ZoomAudioDevice.driver"
if [ "$minorver" -gt 9 ]; then
    echo "Install audio device drive" >> "$LOG_PATH"

    # unload device kernel if loaded
    st="$(/usr/sbin/kextstat -b zoom.us.ZoomAudioDevice | /usr/bin/grep zoom.us.ZoomAudioDevice 2>&1)"

    if echo "$st" | grep -q "zoom.us.ZoomAudioDevice"; then
        echo "audio device is loaded: ($st) skip driver" >> "$LOG_PATH"
    else
        #install audio driver
        if [ -d "$AudioPluginPath/ZoomAudioDevice.driver" ]; then
            /bin/rm -rf "$AudioPluginPath/ZoomAudioDevice.driver"
        fi

        /bin/cp -rf "$audioPluginfile" "$AudioPluginPath"
    fi
#################################
# use audio device kernel
else
    if [ "$minorver" -gt 9 ]; then
        vsig="$(/usr/bin/codesign -dv $kext_file 2>&1)"
        ret="$?"
        echo "verify signature:$vsig, $ret" >> "$LOG_PATH"
        if [ $ret -ne 0 ]; then
            echo "set update set to 1" >> "$LOG_PATH"
            need_update_sig=1
        fi

        use_sig_file=1
    fi

    if [ -d "$kext_file" ]; then
        v="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$kext_file/Contents/Info.plist")"
        echo "current version is $v" >> "$LOG_PATH"

        if [ $use_sig_file = 1 ]; then
            sv="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$src_sig_kext_file/Contents/Info.plist")"
        else
            sv="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$src_kext_file/Contents/Info.plist")"
        fi

        echo "new version is $sv" >> "$LOG_PATH"

        if [ "$v" = "$sv" ] && [ $need_update_sig = 0 ]; then
            echo "same version, no update" >> "$LOG_PATH"
        else
            need_update=1
        fi

        st="$(/usr/sbin/kextstat -b zoom.us.ZoomAudioDevice | /usr/bin/grep zoom.us.ZoomAudioDevice 2>&1)"
        if echo "$st" | grep -q "zoom.us.ZoomAudioDevice"; then
            echo "audio device is loaded: ($st)" >> "$LOG_PATH"
            if [ $need_update = 1 ]; then
                need_unload=1
            fi
        else
            echo "audio device is not loaded" >> "$LOG_PATH"
            need_load=1
        fi
    else
        need_update=1
    fi

    echo "install flag: $need_update, $need_load, $need_unload, $need_update_sig, $use_sig_file" >> "$LOG_PATH"
    echo "var $app_path" >>"$LOG_PATH"

    if [ $need_update = 0 ]; then
        echo "don't update" >> "$LOG_PATH"

        if [ $need_load = 1 ]; then
            l="$(/sbin/kextload -v 3 "$kext_file" 2>&1)"
            r="$?"
            echo "load ext: $l, $r" >> "$LOG_PATH"

            if [ $r -ne 0 ]; then
                kutil="$(/usr/bin/kextutil -v 4 "$kext_file" 2>&1)"
                echo "use kextutil: $kutil" >> "$LOG_PATH"
            fi

            state="$(/usr/sbin/kextstat -b zoom.us.ZoomAudioDevice 2>&1)"
            echo "ext stat: $state" >> "$LOG_PATH"
        fi
    else
        r=0
        if [ $need_unload = 1 ]; then
            s="$(sudo /sbin/kextunload -v 3 "$kext_file" 2>&1)"
            r="$?"

            echo "unload ext: ($s), ret=$r" >> "$LOG_PATH"
        fi

        unloaded=0
        if [ $r = 0 ]; then
            echo "unload ok" >> "$LOG_PATH"
            unloaded=1
        else
            echo "fail to unload kext" >> "$LOG_PATH"
            #try it again
            s="$(/usr/bin/sudo /sbin/kextunload -v 3 "$kext_file" 2>&1)"
            r="$?"

            echo "unload ext again: ($s), ret=$r" >> "$LOG_PATH"
            unloaded=1
        fi

        if [ $unloaded = 1 ]; then
            /bin/rm -rf "$kext_file"

            if [ $use_sig_file = 0 ]; then
                c="$(/bin/cp -af "$src_kext_file" "$kext_file" 2>&1)"
                r="$?"
            else
                c="$(/bin/cp -af "$src_sig_kext_file" "$kext_file" 2>&1)"
                r="$?"
            fi

            echo "copy kext:$c, $r" >> "$LOG_PATH"

            p="$(/usr/bin/printenv PATH)"
            echo "path: $p" >> "$LOG_PATH"
            echo "kext_file: $kext_file" >> "$LOG_PATH"
            #chown -R root:wheel "$kext_file"
            /bin/chmod -R 755 "$kext_file"
            /usr/bin/find "$kext_file" -type f -exec /bin/chmod 0644 {} ";"
        fi

        load="$(/sbin/kextload -v 3 "$kext_file" 2>&1)"
        r="$?"
        echo "load ext: $load, $r" >> "$LOG_PATH"

        if [ $r -ne 0 ]; then
            ku="$(/usr/bin/sudo /usr/bin/kextutil -b zoom.us.ZoomAudioDevice -v 2>&1)"
            echo "try kextutil: $ku" >> "$LOG_PATH"
        fi
    fi

    st="$(/usr/sbin/kextstat -b zoom.us.ZoomAudioDevice)"
    echo "ext stat: $st" >> "$LOG_PATH"
    echo "parent id: $PPID, $$" >> "$LOG_PATH"
fi
#################################
#audio device end

exit 0
