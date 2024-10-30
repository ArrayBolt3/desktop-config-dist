#!/bin/bash

## Copyright (C) 2018 - 2023 ENCRYPTED SUPPORT LP <adrelanos@whonix.org>
## Copyright (C) 2018 Algernon <33966997+Algernon-01@users.noreply.github.com>
## See the file COPYING for copying conditions.

set -e
set -o errexit
set -o nounset
set -o errtrace
set -o pipefail

## 'true' versus 'echo':
## Using 'true' for output and not 'echo' because this script's output gets
## parsed by Xfce genmon, which gets confused by additional 'echo's.

## The following command lists the block devices:
## sudo /bin/lsblk
##
## Example output:
## NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
## sda      8:0    0  100G  1 disk
##
## RO (Read-Only) column:
## 1 indicates read-only
## 0 indicates read-write
##
## If any "0" appears, the system is not in live mode.

## Special case when using snapd:
##
## sudo /bin/lsblk
##
## Example output:
## NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
## loop0    7:0    0   55M  1 loop /snap/core18/1754
## loop1    7:1    0        0 loop
## loop2    7:2    0        0 loop
## loop3    7:3    0        0 loop
## loop4    7:4    0        0 loop
## loop5    7:5    0        0 loop
## loop6    7:6    0        0 loop
## loop7    7:7    0        0 loop
## sda      8:0    0  100G  0 disk
##   sda1   8:1    0  100G  0 part /
## sr0     11:0    1 1024M  0 rom

## Running:
##
## sudo /bin/lsblk --noheadings --raw --output RO
##
## Example output:
## 1
## 1
## 0
## 0
## 0
## 0
## 0
## 0
## 0
## 0
## 0

## The following method did not work properly with 'snapd':
## http://forums.whonix.org/t/wickr-me-gets-whonix-stuck-in-live-mode/9834/1
#if sudo --non-interactive /bin/lsblk --noheadings --raw --output RO | grep --invert-match --fixed-strings -- "0" ; then

output_function() {
   cat "${save_file}"
}

save_function() {
   if [ -e "${save_file}" ]; then
      1>&2 echo 'Something went wrong - save_function called when save file exists!'
      exit 1;
   fi
   mkdir -p "${save_dir}"
   [ -n "${img}" ] && append-once "${save_file}" "<img>${img}</img>"
   [ -n "${txt}" ] && append-once "${save_file}" "<txt>${txt}</txt>"
   [ -n "${tool}" ] && append-once "${save_file}" "<tool>${tool}</tool>"
   [ -n "${click}" ] && {
      ## TODO: fix append-once bug
      #append-once "${save_file}" "<click>${click}</click>"
      #append-once "${save_file}" "<txtclick>${click}</txtclick>"

      ## Workaround for above append-once bug.
      append-once "${save_file}" "\
<click>${click}</click>
<txtclick>${click}</txtclick>"
   }
}

save_dir="/run/user/${UID}/desktop-config-dist/livecheck"
save_file="${save_dir}/lastresult"

proc_cmdline_output=$(cat /proc/cmdline)

## Debugging.
#safe-rm -f "${save_file}"

## Test mode overrides
if [[ "${1:-}" == "test" ]]; then
   safe-rm -f "${save_file}"
   proc_cmdline_output="$2"
fi

if test -f "${save_file}" ; then
   output_function
   exit 0
fi

if test -f /usr/share/whonix/marker ; then
   homepage="https://www.whonix.org"
else
   homepage="https://www.kicksecure.com"
fi

missing_icon=""
icon_dir="/usr/share/icons/gnome-colors-common/32x32"

msg_cmd="/usr/libexec/msgcollector/generic_gui_message"

icon_error="${icon_dir}/status/dialog-error.png"
icon_persistent_mode="${icon_dir}/status/dialog-information.png"
icon_grub_live_without_read_only="${icon_dir}/status/user-online.png"
icon_iso="${icon_dir}/devices/media-optical.png"
icon_grub_live_with_read_only="${icon_dir}/actions/dialog-apply.png"

## If at least one icon is missing, set 'missing_icon=true'.
test -f "${icon_error}" || missing_icon=true
test -f "${icon_persistent_mode}" || missing_icon=true
test -f "${icon_grub_live_without_read_only}" || missing_icon=true
test -f "${icon_iso}" || missing_icon=true
test -f "${icon_grub_live_with_read_only}" || missing_icon=true

if [ "$missing_icon" = "true" ]; then
   bug_message="<br/><i>(Minor bug: Missing icons)</i><br/>"
else
   bug_message=""
fi

heading_line="<u><b>Live Check Result:</b></u>"

## We use `sudo` to run `lsblk` because `hide-hardware-info.service` makes it readable only by the `root` user.
## https://forums.whonix.org/t/restrict-hardware-information-to-root-testers-wanted/8618/13
##
## This has a sudoers exception in file:
## /etc/sudoers.d/desktop-config-dist
##
## Check if the lsblk command fails (e.g., due to insufficient sudo permissions)
if ! lsblk_output="$(sudo --non-interactive /bin/lsblk --noheadings --raw --output RO)" ; then
   # lsblk command failed with a non-zero exit code
   true "INFO: Running 'sudo --non-interactive /bin/lsblk --noheadings --raw --output RO' failed!"
   img="${icon_error}"
   txt="Error"
   title="Livecheck"
   link="<a href=\"${homepage}/wiki/Grub-live#Live_Check_Systray_Issues\">${homepage}/wiki/Grub-live#Live_Check_Systray_Issues</a>"
   msg="\
${heading_line}<br/><br/>
<b>Live Detection Test:</b> Minor issue. Do not panic.<br/>
<br/>
<i>Unable to determine if booted into live mode or persistent mode.</i> For assistance and to report this issue, please visit:<br/>
${link}.<br/><br/>
${bug_message}"
   click="${msg_cmd} error '${title}' '${msg}' '' ok"
   tool="<b>Live Detection Test:</b> Minor issue. Click on the icon for more information."
   save_function
   output_function
   exit 0
fi
## lsblk command succeeded

if [[ "${1:-}" == "test" ]]; then
   lsblk_output="$3"
fi

## Detect if the system was booted in live mode
## Check for 'rd.live.image' first, because both, ISO and grub-live come with 'boot=live' kernel parameter.
if echo "${proc_cmdline_output}" | grep --quiet --fixed-strings -e 'root=live' -e 'rd.live.image'; then
   live_mode_environment="ISO Live"
   status_word="ISO"
   live_status="true"
   maybe_iso_live_message="<br/><u>This message can be safely ignored if only using this ISO to install to the hard drive.</u><br/>"
elif echo "${proc_cmdline_output}" | grep --quiet --fixed-strings -e 'boot=live' -e 'rootovl' -e 'rd.live.overlay.overlayfs=1' ; then
   live_mode_environment="grub-live"
   status_word="Live"
   live_status="true"
   maybe_iso_live_message=""
else
   live_mode_environment="false"
   status_word="persistent"
   live_status="false"
   maybe_iso_live_message=""
fi

## Check if there are any read-write devices
if echo "$lsblk_output" | grep --quiet --fixed-strings -- "0" ; then
   true "INFO: At least one '0' found. Conclusion: not all devices are read-only; some are read-write."
   if [ "$live_status" = "true" ]; then
      true "INFO: Live mode (grub-live or ISO live) is enabled."
      if [ "$live_mode_environment" = "grub-live" ]; then
         img="${icon_grub_live_without_read_only}"
         msg_type="warning"
      elif [ "$live_mode_environment" = "ISO Live" ]; then
         img="${icon_iso}"
         msg_type="warning"
      else
         img="${icon_error}"
         msg_type="error"
      fi
      ## Show "Live" or "ISO" next to info symbol in systray.
      txt="${status_word}"
      title="Livecheck"
      link="<a href=\"${homepage}/wiki/Live_Mode\">${homepage}/wiki/Live_Mode</a>"
      msg="\
${heading_line}<br/><br/>
<b>Live Mode Active:</b> <b>Yes</b> (${live_mode_environment})<br/>
<b>Persistent Mode Active:</b> No<br/><br/>
No changes will be made to disk.
<ul>
   <li>For added security, consider <a href=\"${homepage}/wiki/Read-only\">setting your disk to read-only mode</a>.</li>
</ul>
${maybe_iso_live_message}<br/>
For more information, see: ${link}<br/><br/>
${bug_message}"
      click="${msg_cmd} ${msg_type} '${title}' '${msg}' '' ok"
      tool="<b>Live Mode Active (${live_mode_environment}):</b> No changes will be made to disk. Click on the icon for more information.${maybe_iso_live_message}${bug_message}"
   else
      true "INFO: Live mode (grub-live or ISO live) is disabled."
      img="${icon_persistent_mode}"
      ## Do not show "Persistent" next to info symbol in systray.
      #txt="${status_word}"
      txt=""
      title="Livecheck"
      link="<a href=\"${homepage}/wiki/Persistent_Mode\">${homepage}/wiki/Persistent_Mode</a>"
      msg="\
${heading_line}<br/><br/>
<b>Live Mode Active:</b> No<br/>
<b>Persistent Mode Active:</b> <b>Yes</b>
<ul>
   <li>All changes to the disk will be preserved after a reboot.</li>
   <li>If you prefer a temporary session where changes are not saved, consider switching to live mode.</li>
</ul>
For more information, see: ${link}<br/><br/>
${bug_message}"
      click="${msg_cmd} info '${title}' '${msg}' '' ok"
      tool="<b>Persistent Mode Active:</b> All changes to the disk will be preserved after a reboot. Click on the icon for more information.${bug_message}"
   fi
   save_function
   output_function
   exit 0
fi

true "INFO: No '0' found. Conclusion: All devices are read-only."

img="${icon_grub_live_with_read_only}"
## Show "read-only" next to info symbol in systray.
txt="read-only"
title="Livecheck"
link="<a href=\"${homepage}/wiki/Live_Mode\">${homepage}/wiki/Live_Mode</a>"
msg="\
${heading_line}<br/><br/>
<b>Live Mode Active:</b> <b>Yes</b> (${live_mode_environment})<br/>
<b>Persistent Mode Active:</b> No
<ul>
   <li>No changes will be made to disk.</li>
   <li>For more information, see the following link:</li>
</ul>
${link}<br/><br/>
${bug_message}"
click="${msg_cmd} warning '${title}' '${msg}' '' ok"
tool="<b>Live Mode Active (${live_mode_environment}):</b> No changes will be made to disk. Click on the icon for more information.${bug_message}"

save_function
output_function
exit 0
